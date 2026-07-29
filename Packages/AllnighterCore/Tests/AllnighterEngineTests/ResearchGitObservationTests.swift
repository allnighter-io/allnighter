import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// CR-S02 proof wall: bounded pre/post Git observation for research (read-only)
/// runs. Clean-unchanged / pre-existing-dirty-unchanged / new-tracked-change /
/// new-untracked-path / violation-surfaced-with-files-preserved. Real git in a
/// disposable fixture + injected RunStore so nothing touches the live catalog.
final class ResearchGitObservationTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-research-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func runGit(_ args: [String], cwd: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd.path] + args
        p.standardOutput = Pipe(); p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    private func makeGitRepo() throws -> URL {
        let dir = tmp.appendingPathComponent("repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for a in [["init", "-q"], ["config", "user.email", "t@t.dev"], ["config", "user.name", "T"],
                  ["config", "commit.gpgsign", "false"]] { runGit(a, cwd: dir) }
        try "sentinel v1\n".write(to: dir.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)
        runGit(["add", "."], cwd: dir)
        runGit(["commit", "-q", "-m", "c1"], cwd: dir)
        return dir
    }

    private func researchService(repo: URL, runner: CommandRunner) -> RunService {
        let team = TeamPreset(
            id: "research_obs", displayName: "Research", lane: .code, outputKind: .plan,
            mutating: false,
            workerSpecs: [TeamAgentSpec(id: "r1", skillId: "bug_reproducer",
                                         purpose: .answer, preferredModelId: "model_opus")],
            lead: TeamLeadSpec(skillId: "plan_writer_build"))
        return RunService(
            models: [Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                           driverId: "claude_code", role: .both)],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            teams: [team],
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

    private func runResearch(repo: URL, runner: CommandRunner, id: String) async throws -> TeamRun {
        let result = await researchService(repo: repo, runner: runner).run(
            RunRequest(message: "research only", repoRoot: repo.path, presetId: "research_obs"),
            origin: .cli, runId: id)
        guard case .success(let run) = result else {
            XCTFail("research run failed: \(result)"); throw TestError.runFailed
        }
        return run
    }

    private enum TestError: Error { case runFailed }

    // MARK: - Clean unchanged

    func testCleanUnchangedRepoHasNoViolation() async throws {
        let repo = try makeGitRepo()
        let head = GitObserver().observe(rootPath: repo.path).head
        let run = try await runResearch(
            repo: repo,
            runner: MockCommandRunner(scripts: ["claude": .init(stdout: "# Answer\nclean", exitCode: 0)]),
            id: "obs-clean")

        let obs = try XCTUnwrap(run.researchGitObservation)
        XCTAssertFalse(obs.changed)
        XCTAssertEqual(obs.baselineHead, head)
        XCTAssertEqual(obs.head, head)
        XCTAssertTrue(obs.changedPaths.isEmpty)
        XCTAssertFalse(run.warnings.contains { $0.contains("research-write violation") })

        // Surfaced in the canonical projection (research runs carry the observation,
        // never repoDelta).
        let trj = TeamRunJSONMapper.map(run, models: [], manifests: [],
                                        context: .init(runJournalPath: "/tmp/run.json"))
        XCTAssertEqual(trj.researchGitObservation, obs)
        XCTAssertNil(trj.repoDelta)
    }

    // MARK: - Pre-existing dirty, unchanged by the run

    func testPreExistingDirtyRepoUnchangedIsNotViolation() async throws {
        let repo = try makeGitRepo()
        // Dirty the repo BEFORE the run (tracked edit + untracked file). The worker
        // does nothing, so the observation must NOT flag a violation.
        try "sentinel dirtied\n".write(to: repo.appendingPathComponent("sentinel.txt"),
                                       atomically: true, encoding: .utf8)
        try "scratch".write(to: repo.appendingPathComponent("preexisting.tmp"),
                            atomically: true, encoding: .utf8)

        let run = try await runResearch(
            repo: repo,
            runner: MockCommandRunner(scripts: ["claude": .init(stdout: "# Answer\nnoted", exitCode: 0)]),
            id: "obs-preexisting-dirty")

        let obs = try XCTUnwrap(run.researchGitObservation)
        XCTAssertFalse(obs.changed, "a repo already dirty before the run is not a violation")
        XCTAssertFalse(run.warnings.contains { $0.contains("research-write violation") })
    }

    // MARK: - New tracked change

    func testNewTrackedChangeIsSurfacedAndPreserved() async throws {
        let repo = try makeGitRepo()
        let run = try await runResearch(
            repo: repo,
            runner: FileEditingCommandRunner(target: repo.appendingPathComponent("sentinel.txt"),
                                             contents: "sentinel MUTATED by research\n"),
            id: "obs-tracked")

        let obs = try XCTUnwrap(run.researchGitObservation)
        XCTAssertTrue(obs.changed, "a read-only run that edits a tracked file is a violation")
        XCTAssertTrue(obs.changedPaths.contains("sentinel.txt"), "got \(obs.changedPaths)")
        XCTAssertTrue(run.warnings.contains { $0.contains("research-write violation") })

        // Files are preserved — Allnighter never resets/repairs the tree.
        let onDisk = try String(contentsOf: repo.appendingPathComponent("sentinel.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, "sentinel MUTATED by research\n")
    }

    // MARK: - New untracked path

    func testNewUntrackedPathIsSurfacedAndPreserved() async throws {
        let repo = try makeGitRepo()
        let run = try await runResearch(
            repo: repo,
            runner: FileEditingCommandRunner(target: repo.appendingPathComponent("leaked.txt"),
                                             contents: "leaked by research\n"),
            id: "obs-untracked")

        let obs = try XCTUnwrap(run.researchGitObservation)
        XCTAssertTrue(obs.changed)
        XCTAssertTrue(obs.changedPaths.contains("leaked.txt"), "got \(obs.changedPaths)")
        XCTAssertTrue(run.warnings.contains { $0.contains("research-write violation") })

        // The unexpected file is preserved, not deleted.
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.appendingPathComponent("leaked.txt").path))
    }
}

/// Fake read-only worker that (mis)behaves by writing a file in the repo, so the
/// research Git observation has a real change to detect. Does no git commit.
private final class FileEditingCommandRunner: CommandRunner, @unchecked Sendable {
    private let target: URL
    private let contents: String

    init(target: URL, contents: String) {
        self.target = target
        self.contents = contents
    }

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        try? contents.write(to: target, atomically: true, encoding: .utf8)
        return CommandResult(stdout: "# Answer\nI looked around.", stderr: "", exitCode: 0)
    }
}
