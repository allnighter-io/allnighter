import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// FR3 — repo delta in run truth: observed via `GitObserver`, captured on mutating
/// `RunService` runs (relay/pilot dev turns inherit this path with no relay-specific code).
final class RunRepoDeltaTests: HermeticSupportTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-repo-delta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        try super.tearDownWithError()
    }

    private func runGit(_ args: [String], cwd: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd.path] + args
        p.standardOutput = Pipe(); p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    @discardableResult
    private func makeGitRepo() throws -> URL {
        let dir = tmp.appendingPathComponent("repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for a in [["init", "-q"], ["config", "user.email", "t@t.dev"], ["config", "user.name", "T"],
                  ["config", "commit.gpgsign", "false"]] { runGit(a, cwd: dir) }
        try "spec".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        runGit(["add", "."], cwd: dir)
        runGit(["commit", "-q", "-m", "c1"], cwd: dir)
        return dir
    }

    private func makeMutatingService(
        repo: URL, commandRunner: CommandRunner, runStore: RunStore? = nil
    ) -> RunService {
        let model = Model(
            id: "model_grok", displayName: "Grok Build", modelLabel: "grok-build",
            driverId: "grok", role: .both)
        return RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            runStore: runStore ?? RunStore(rootDirectory: tmp.appendingPathComponent("runs-\(UUID().uuidString)")),
            commandRunner: commandRunner,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(
                    defaultTier: .frontier, allowHealthySubstitutions: true,
                    tiers: TierMembership(frontier: ["model_grok"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            }
        )
    }

    func testMutatingRunCapturesRepoDeltaWhenWorkerCommits() async throws {
        let repo = try makeGitRepo()
        let baselineHead = GitObserver().observe(rootPath: repo.path).head
        let service = makeMutatingService(repo: repo, commandRunner: CommittingCommandRunner(repoRoot: repo))

        let result = await service.run(
            RunRequest(message: "Make a change", repoRoot: repo.path, workerId: "model_grok", lane: .code),
            origin: .cli, runId: "repo-delta-commit")

        guard case .success(let run) = result else { return XCTFail("run failed: \(result)") }
        let delta = try XCTUnwrap(run.repoDelta)
        XCTAssertTrue(delta.changed)
        XCTAssertEqual(delta.baseline, baselineHead)
        XCTAssertNotEqual(delta.head, baselineHead)
        XCTAssertEqual(delta.commits.count, 1)
        XCTAssertEqual(delta.filesChanged, 1)
        XCTAssertFalse(delta.truncated)

        let trj = TeamRunJSONMapper.map(
            run, models: [], manifests: [], context: .init(runJournalPath: "/tmp/run.json"))
        XCTAssertEqual(trj.repoDelta, delta)

        let encoded = try CoreJSON.encode(trj.repoDelta!)
        let roundTripped = try CoreJSON.decode(RepoDelta.self, from: encoded)
        XCTAssertTrue(roundTripped.changed)
        XCTAssertEqual(roundTripped.filesChanged, 1)

        XCTAssertEqual(
            RunIdentity.repoDeltaSummary(delta),
            "committed \(String(delta.head!.prefix(7))): 1 file")
        XCTAssertTrue(RunIdentity.cliFooter(run).contains("committed"))

        let outcome = try XCTUnwrap(trj.outcome)
        XCTAssertEqual(outcome.status, .completed)
        XCTAssertTrue(outcome.committed)
        // SH-S08 (a8fddec1) appends observed single-seat timing (queue/duration/wall)
        // to the headline. This run is executed live, so those clocks are measured and
        // non-deterministic — assert the identity prefix exactly, then that the timing
        // summary is appended, rather than freezing measured milliseconds into a golden.
        let identityPrefix =
            "worker model_grok · lane code (context — --team routes) · mutating · committed \(String(delta.head!.prefix(7))): 1 file"
        XCTAssertTrue(outcome.headline.hasPrefix(identityPrefix),
                      "headline must start with the run identity; got: \(outcome.headline)")
        XCTAssertTrue(outcome.headline.contains("wall") && outcome.headline.contains("ms"),
                      "SH-S08 observed timing must be appended to the headline; got: \(outcome.headline)")
        // The human footer recomputes its own headline (with its own measured timing
        // clocks), so it need not be byte-identical to the JSON outcome headline —
        // assert it carries the same run identity.
        XCTAssertTrue(RunIdentity.cliFooter(run).contains(identityPrefix))
    }

    func testMutatingRunReportsNoChangeHonestly() async throws {
        let repo = try makeGitRepo()
        let service = makeMutatingService(
            repo: repo,
            commandRunner: MockCommandRunner(scripts: ["grok": .init(stdout: "Done.", exitCode: 0)]))

        let result = await service.run(
            RunRequest(message: "Say done", repoRoot: repo.path, workerId: "model_grok"),
            origin: .cli, runId: "repo-delta-none")

        guard case .success(let run) = result else { return XCTFail("run failed: \(result)") }
        let delta = try XCTUnwrap(run.repoDelta)
        XCTAssertFalse(delta.changed)
        XCTAssertEqual(delta.commits, [])
        XCTAssertEqual(delta.filesChanged, 0)

        let encoded = try CoreJSON.encode(delta)
        let roundTripped = try CoreJSON.decode(RepoDelta.self, from: encoded)
        XCTAssertFalse(roundTripped.changed)

        XCTAssertEqual(RunIdentity.repoDeltaSummary(delta), "no repo change")
    }

    func testNonMutatingRunOmitsRepoDeltaFromProjection() {
        let delta = RepoDelta(changed: true, baseline: "a", head: "b", commits: [], filesChanged: 1, files: ["x.swift"])
        let run = TeamRun(
            id: "r1", prompt: "p", status: .complete, createdAt: Date(), mutating: false, repoDelta: delta)
        let trj = TeamRunJSONMapper.map(run, models: [], manifests: [], context: .init(runJournalPath: "/tmp/run.json"))
        XCTAssertNil(trj.repoDelta)
    }

    func testRelayStyleDevDispatchInheritsRepoDeltaThroughRunService() async throws {
        let repo = try makeGitRepo()
        let service = makeMutatingService(repo: repo, commandRunner: CommittingCommandRunner(repoRoot: repo))
        let result = await service.run(
            RunRequest(
                message: RelayDevPrompt.assemble(context: .init(
                    handover: "Commit a file.", docPath: "docs/spec.md", roundNumber: 1,
                    workerDisplayName: "Dev Seat")),
                repoRoot: repo.path, presetId: "build_slice", workerId: "model_grok"),
            origin: .cli, runId: "relay-dev-inherit")
        guard case .success(let run) = result else { return XCTFail("relay-path run failed") }
        XCTAssertTrue(try XCTUnwrap(run.repoDelta).changed,
                      "relay/pilot dev turns dispatch through RunService — no relay-specific repoDelta code")
    }
}

/// Fake mutating worker that makes a real git commit in `repoRoot` before returning.
final class CommittingCommandRunner: CommandRunner, @unchecked Sendable {
    private let repoRoot: URL
    private let stdout: String

    init(repoRoot: URL, stdout: String = "Done.") {
        self.repoRoot = repoRoot
        self.stdout = stdout
    }

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        let file = repoRoot.appendingPathComponent("worker-change.txt")
        try? "worker change".write(to: file, atomically: true, encoding: .utf8)
        runGit(["add", "worker-change.txt"], cwd: repoRoot)
        runGit(["commit", "-q", "-m", "worker: test change"], cwd: repoRoot)
        return CommandResult(stdout: stdout, stderr: "", exitCode: 0)
    }

    private func runGit(_ args: [String], cwd: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd.path] + args
        p.standardOutput = Pipe(); p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }
}
