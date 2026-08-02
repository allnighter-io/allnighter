import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// CR-S04 proof wall: execution means execution. A mutating Team resolves to
/// EXACTLY ONE selected worker, that worker edits the canonical registered
/// repository, the returned change matches the fixture's real Git state, and an
/// execution request is never silently downgraded to research or to a dry run.
///
/// The write-lock invariant itself lives in `ExecutionWriteLockTests` (CR-S02) and
/// is not restated here. The live twin is
/// `scripts/code_red_works_test.sh live-direct`'s execution gesture.
/// See docs/archive/phases/CODE_RED_Core_Infrastructure_Repair.md.
final class ExecutionProofTests: XCTestCase {
    private static let proofLine = "CODE_RED_EXECUTION_PROOF"
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-exec-proof-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        setenv("ALLNIGHTER_SUPPORT_DIR", tmp.appendingPathComponent("support").path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("ALLNIGHTER_SUPPORT_DIR")
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Fixture

    @discardableResult
    private func git(_ args: [String], cwd: URL) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd.path] + args
        let out = Pipe()
        p.standardOutput = out; p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        try? p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeGitRepo() throws -> URL {
        let dir = tmp.appendingPathComponent("repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for a in [["init", "-q"], ["config", "user.email", "t@t.dev"], ["config", "user.name", "T"],
                  ["config", "commit.gpgsign", "false"]] { git(a, cwd: dir) }
        try "CODE_RED_SENTINEL\n".write(to: dir.appendingPathComponent("sentinel.txt"),
                                        atomically: true, encoding: .utf8)
        git(["add", "."], cwd: dir)
        git(["commit", "-q", "-m", "c1"], cwd: dir)
        return dir
    }

    /// Counts spawns and answers; optionally performs the requested edit + commit in
    /// the working directory it was actually handed (never a path it invented).
    private final class ExecutingRunner: CommandRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var spawnCount = 0
        private var directories: [String?] = []
        private let edits: Bool

        init(edits: Bool) { self.edits = edits }

        func run(
            command: String, args: [String], stdin: String?, env: [String: String],
            workingDirectory: String?, timeout: Duration
        ) async -> CommandResult {
            note(workingDirectory)
            guard edits, let cwd = workingDirectory else {
                return CommandResult(stdout: "Done.", stderr: "", exitCode: 0)
            }
            let root = URL(fileURLWithPath: cwd)
            let sentinel = root.appendingPathComponent("sentinel.txt")
            let existing = (try? String(contentsOf: sentinel, encoding: .utf8)) ?? ""
            try? (existing + ExecutionProofTests.proofLine + "\n")
                .write(to: sentinel, atomically: true, encoding: .utf8)
            for a in [["add", "."], ["commit", "-q", "-m", "code red execution proof"]] {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                p.arguments = ["-C", cwd] + a
                p.standardOutput = Pipe(); p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
                try? p.run(); p.waitUntilExit()
            }
            return CommandResult(stdout: "Appended \(ExecutionProofTests.proofLine).", stderr: "", exitCode: 0)
        }

        private func note(_ dir: String?) {
            lock.lock(); spawnCount += 1; directories.append(dir); lock.unlock()
        }
        var spawns: Int { lock.lock(); defer { lock.unlock() }; return spawnCount }
        var cwds: [String?] { lock.lock(); defer { lock.unlock() }; return directories }
    }

    /// A source-scoped mutating Team that DECLARES two seats. Execution must still
    /// resolve to exactly one worker — the seat count is not the spawn count.
    private func executionTeam() -> TeamPreset {
        TeamPreset(
            id: "code_red_execution", displayName: "Code Red Execution", lane: .code,
            outputKind: .plan, mutating: true, executionSourceId: "claude_code",
            agentSpecs: [TeamAgentSpec(id: "exec", skillId: "execution_playbook",
                                         purpose: .answer, preferredModelId: "model_opus")],
            lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: "model_opus"))
    }

    private func service(runner: CommandRunner) -> RunService {
        RunService(
            models: [Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                           driverId: "claude_code", role: .both)],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            teams: [executionTeam()],
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs-\(UUID().uuidString)")),
            commandRunner: runner,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(defaultTier: .frontier, allowHealthySubstitutions: true,
                                     tiers: TierMembership(frontier: ["model_opus"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            })
    }

    private func execute(_ service: RunService, repo: URL, id: String) async throws -> TeamRun {
        let result = await service.run(
            RunRequest(message: "Append the exact line \(Self.proofLine) to sentinel.txt, then show the git diff.",
                       repoRoot: repo.path, presetId: "code_red_execution"),
            origin: .cli, runId: id)
        guard case .success(let run) = result else {
            XCTFail("execution run failed: \(result)"); throw TestError.runFailed
        }
        return run
    }

    private enum TestError: Error { case runFailed }

    // MARK: - Exactly one worker

    /// The law is one WORKER, not one vendor turn: live, the same single worker
    /// also produces the plan stage, so `usage.cliCalls` is 2 with one seat. Assert
    /// the roster and the ownership of every turn, never the turn count.
    ///
    /// Divergence worth knowing: `CatalogRunCoordinator` re-reads the preset from
    /// the global `TeamCatalog`, which cannot see this injected team, so the plan
    /// stage does not run here. The live gesture in
    /// `scripts/code_red_works_test.sh` is what proves the stage-owner half.
    func testMutatingTeamResolvesToExactlyOneWorker() async throws {
        let repo = try makeGitRepo()
        let runner = ExecutingRunner(edits: false)
        let run = try await execute(service(runner: runner), repo: repo, id: "cr-s04-single-worker")

        XCTAssertEqual(run.workers.count, 1,
                       "a mutating Team resolves to exactly one worker, whatever its declared seat count")
        XCTAssertEqual(run.answers.count, 1, "one answer from the one executor")
        let owners = Set(run.stages.compactMap(\.producedByAgentId))
        XCTAssertTrue(owners.isSubset(of: Set(run.workers.map(\.id))),
                      "every stage belongs to the single selected worker; got \(owners)")
        XCTAssertTrue(run.mutating, "the run must keep its mutating shape")
        XCTAssertEqual(run.executionSourceId, "claude_code",
                       "the single CLI that owns execution is recorded on the run")
        let canonical = RunWriteLock.normalize(repo.path) ?? repo.path
        XCTAssertEqual(RunWriteLock.normalize(runner.cwds.compactMap { $0 }.first ?? ""), canonical,
                       "the executor runs in the canonical registered root")
    }

    // MARK: - The edit lands once, in the real repository

    func testExecutionEditLandsExactlyOnceAndMatchesTheFixturesRealGitState() async throws {
        let repo = try makeGitRepo()
        let baseline = git(["rev-parse", "HEAD"], cwd: repo)
        let runner = ExecutingRunner(edits: true)
        let run = try await execute(service(runner: runner), repo: repo, id: "cr-s04-edit")

        // The change exists exactly once, in the fixture's real working tree.
        let onDisk = try String(contentsOf: repo.appendingPathComponent("sentinel.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk.components(separatedBy: Self.proofLine).count - 1, 1,
                       "the proof line must exist exactly once; got: \(onDisk)")

        // The returned delta is the fixture's real Git truth, not a worker's prose.
        let delta = try XCTUnwrap(run.repoDelta, "a mutating run must report the real repo delta")
        XCTAssertTrue(delta.changed)
        XCTAssertEqual(delta.baseline, baseline)
        XCTAssertEqual(delta.head, git(["rev-parse", "HEAD"], cwd: repo),
                       "the reported head must be the fixture's actual HEAD")
        XCTAssertNotEqual(delta.head, baseline)
        XCTAssertEqual(delta.filesChanged, 1)
        XCTAssertEqual(delta.files, ["sentinel.txt"],
                       "the reported changed path must be the real changed path")
        XCTAssertEqual(git(["show", "--name-only", "--format=", "HEAD"], cwd: repo), "sentinel.txt",
                       "git agrees exactly one tracked file changed")

        // Execution reports a repo delta; research observation belongs to read-only runs.
        XCTAssertNil(run.researchGitObservation,
                     "an execution run reports repoDelta, never the research observation")
        let trj = TeamRunJSONMapper.map(run, models: [], manifests: [],
                                        context: .init())
        XCTAssertEqual(trj.repoDelta, delta)
        XCTAssertNil(trj.researchGitObservation)
        XCTAssertEqual(trj.teamRun.writePolicy, "mutating")
    }

    // MARK: - Never downgraded

    func testExecutionRequestIsNeverDowngradedToResearch() async throws {
        let repo = try makeGitRepo()
        let runner = ExecutingRunner(edits: true)
        let run = try await execute(service(runner: runner), repo: repo, id: "cr-s04-no-downgrade")

        // A downgrade would look like: no spawn, no lock, read-only policy, or a
        // research observation in place of a real diff. None of those may happen.
        XCTAssertEqual(runner.spawns, 1, "the executor actually ran")
        XCTAssertTrue(run.mutating)
        XCTAssertEqual(RunIdentity.writePolicyLabel(mutating: run.mutating), "mutating")
        XCTAssertEqual(run.status, .complete)
        XCTAssertTrue(try XCTUnwrap(run.repoDelta).changed,
                      "the requested change really happened in the registered repository")
    }

    /// `--dry-run` is the ONLY thing that turns an execution request into a
    /// projection, and it must spawn nothing at all.
    func testDryRunResolvesTheSameExecutionWithoutSpawningAnything() async throws {
        let repo = try makeGitRepo()
        let runner = ExecutingRunner(edits: true)
        let svc = service(runner: runner)

        let projection = await svc.dryRun(
            RunRequest(message: "Append the exact line \(Self.proofLine) to sentinel.txt, then show the git diff.",
                       repoRoot: repo.path, presetId: "code_red_execution"),
            readyModels: [Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                                driverId: "claude_code", role: .both)])

        XCTAssertEqual(runner.spawns, 0, "a dry run must never spawn a vendor process")
        XCTAssertEqual(projection.writePolicy, "mutating",
                       "the projection reports the request's real write policy — it does not soften it")
        XCTAssertEqual(projection.teamPresetId, "code_red_execution")

        // And the fixture is untouched: no edit, no commit.
        let onDisk = try String(contentsOf: repo.appendingPathComponent("sentinel.txt"), encoding: .utf8)
        XCTAssertFalse(onDisk.contains(Self.proofLine), "a dry run must not change the repository")
        XCTAssertEqual(git(["status", "--porcelain"], cwd: repo), "",
                       "a dry run leaves the fixture clean")
    }
}
