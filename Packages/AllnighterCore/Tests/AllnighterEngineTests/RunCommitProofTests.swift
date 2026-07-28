import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// FR12 commit-message fidelity + FR13 proof surfacing (Field_Reports_4.md).
final class RunCommitProofTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-commit-proof-\(UUID().uuidString)")
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

    private func makeService(
        repo: URL, commandRunner: CommandRunner, runStore: RunStore? = nil
    ) -> RunService {
        makeService(repo: repo, workerRunner: commandRunner, runStore: runStore)
    }

    private func makeService(
        repo: URL, workerRunner: CommandRunner, proofRunner: CommandRunner? = nil,
        runStore: RunStore? = nil
    ) -> RunService {
        let commandRunner = proofRunner.map { ProofDelegatingCommandRunner(worker: workerRunner, proof: $0) }
            ?? workerRunner
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

    // MARK: - FR12 prompt injection (exactly once, byte-exact blocks)

    func testCommitMessagePromptInjectedExactlyOnce() async throws {
        let repo = try makeGitRepo()
        let capture = PromptCapturingCommandRunner()
        let service = makeService(repo: repo, commandRunner: capture)
        let exact = "feat: ship FR12 verbatim"
        let result = await service.run(
            RunRequest(
                message: "Do the work", repoRoot: repo.path, workerId: "model_grok",
                commitMessage: exact),
            origin: .cli, runId: "fr12-prompt")
        guard case .success = result else { return XCTFail("run failed: \(result)") }
        let prompt = try XCTUnwrap(capture.lastPrompt(forCommand: "grok"))
        let block = ProvenanceConvention.commitMessageVerbatimBlock(message: exact)
        XCTAssertTrue(prompt.contains(block))
        XCTAssertEqual(prompt.components(separatedBy: block).count - 1, 1)
    }

    func testProofPromptInjectedExactlyOnce() async throws {
        let repo = try makeGitRepo()
        let capture = PromptCapturingCommandRunner()
        let service = makeService(repo: repo, commandRunner: capture)
        let proof = "swift test --filter Foo"
        let result = await service.run(
            RunRequest(
                message: "Do the work", repoRoot: repo.path, workerId: "model_grok",
                proofCommand: proof),
            origin: .cli, runId: "fr13-prompt")
        guard case .success = result else { return XCTFail("run failed: \(result)") }
        let prompt = try XCTUnwrap(capture.lastPrompt(forCommand: "grok"))
        let line = ProvenanceConvention.proofVerificationLine(command: proof)
        XCTAssertTrue(prompt.contains(line))
        XCTAssertEqual(prompt.components(separatedBy: line).count - 1, 1)
    }

    // MARK: - FR12 fidelity matched / mismatched

    func testCommitMessageMatchedWhenExact() async throws {
        let repo = try makeGitRepo()
        let exact = "relay: exact subject line"
        let service = makeService(
            repo: repo,
            commandRunner: ConfigurableCommittingCommandRunner(repoRoot: repo, commitMessage: exact))
        let result = await service.run(
            RunRequest(
                message: "Commit", repoRoot: repo.path, workerId: "model_grok",
                commitMessage: exact),
            origin: .cli, runId: "fr12-match")
        guard case .success(let run) = result else { return XCTFail("run failed") }
        let trj = TeamRunJSONMapper.map(
            run, models: [], manifests: [], context: .init(runJournalPath: "/tmp/run.json"))
        XCTAssertEqual(trj.outcome?.commitMessageMatched, true)
        XCTAssertFalse(trj.outcome?.headline.contains("commit message mismatch") ?? true)
    }

    func testCommitMessageMismatchWhenReworded() async throws {
        let repo = try makeGitRepo()
        let requested = "relay: exact subject line"
        let service = makeService(
            repo: repo,
            commandRunner: ConfigurableCommittingCommandRunner(
                repoRoot: repo, commitMessage: "relay: reworded subject line"))
        let result = await service.run(
            RunRequest(
                message: "Commit", repoRoot: repo.path, workerId: "model_grok",
                commitMessage: requested),
            origin: .cli, runId: "fr12-mismatch")
        guard case .success(let run) = result else { return XCTFail("run failed") }
        let trj = TeamRunJSONMapper.map(
            run, models: [], manifests: [], context: .init(runJournalPath: "/tmp/run.json"))
        XCTAssertEqual(trj.outcome?.commitMessageMatched, false)
        XCTAssertTrue(trj.outcome?.headline.contains("commit message mismatch") ?? false)
    }

    // MARK: - FR12 no-commit path

    func testNoCommitLeavesDirtyTreeAndHonestOutcome() async throws {
        let repo = try makeGitRepo()
        let baseline = GitObserver().observe(rootPath: repo.path).head
        let service = makeService(repo: repo, commandRunner: DirtyNoCommitCommandRunner(repoRoot: repo))
        let result = await service.run(
            RunRequest(message: "Edit only", repoRoot: repo.path, workerId: "model_grok", noCommit: true),
            origin: .cli, runId: "fr12-nocommit")
        guard case .success(let run) = result else { return XCTFail("run failed") }
        XCTAssertEqual(run.repoDelta?.baseline, baseline)
        XCTAssertEqual(run.repoDelta?.head, baseline)
        XCTAssertFalse(run.repoDelta?.changed ?? true)
        XCTAssertGreaterThan(run.uncommittedFileCount ?? 0, 0)
        let trj = TeamRunJSONMapper.map(
            run, models: [], manifests: [], context: .init(runJournalPath: "/tmp/run.json"))
        XCTAssertFalse(trj.outcome?.committed ?? true)
        XCTAssertTrue(trj.outcome?.headline.contains("left uncommitted for PM review (as ordered)") ?? false)
    }

    // MARK: - FR13 proof pass / fail / timeout

    func testProofPassSurfacesOnOutcome() async throws {
        let repo = try makeGitRepo()
        let service = makeService(
            repo: repo,
            workerRunner: MockCommandRunner(scripts: ["grok": .init(stdout: "ok", exitCode: 0)]),
            proofRunner: SubprocessCommandRunner())
        let result = await service.run(
            RunRequest(
                message: "noop", repoRoot: repo.path, workerId: "model_grok",
                proofCommand: "exit 0"),
            origin: .cli, runId: "fr13-pass")
        guard case .success(let run) = result else { return XCTFail("run failed") }
        XCTAssertEqual(run.proofResult?.passed, true)
        XCTAssertEqual(run.proofResult?.exitCode, 0)
        let trj = TeamRunJSONMapper.map(
            run, models: [], manifests: [], context: .init(runJournalPath: "/tmp/run.json"))
        XCTAssertEqual(trj.outcome?.proof?.passed, true)
        XCTAssertTrue(trj.outcome?.headline.contains("proof passed") ?? false)
    }

    func testProofFailSurfacesWithoutUndoingCommit() async throws {
        let repo = try makeGitRepo()
        let exact = "feat: keep this commit"
        let service = makeService(
            repo: repo,
            workerRunner: ConfigurableCommittingCommandRunner(repoRoot: repo, commitMessage: exact),
            proofRunner: SubprocessCommandRunner())
        let result = await service.run(
            RunRequest(
                message: "Commit", repoRoot: repo.path, workerId: "model_grok",
                commitMessage: exact, proofCommand: "exit 1"),
            origin: .cli, runId: "fr13-fail")
        guard case .success(let run) = result else { return XCTFail("run failed") }
        XCTAssertTrue(run.repoDelta?.changed ?? false)
        XCTAssertEqual(run.proofResult?.passed, false)
        XCTAssertEqual(run.proofResult?.exitCode, 1)
        let trj = TeamRunJSONMapper.map(
            run, models: [], manifests: [], context: .init(runJournalPath: "/tmp/run.json"))
        XCTAssertTrue(trj.outcome?.headline.contains("PROOF FAILED (exit 1)") ?? false)
        XCTAssertEqual(trj.outcome?.commitMessageMatched, true)
    }

    func testProofTimeoutWithHangingCommand() async throws {
        let repo = try makeGitRepo()
        let service = makeService(
            repo: repo,
            workerRunner: MockCommandRunner(scripts: ["grok": .init(stdout: "ok", exitCode: 0)]),
            proofRunner: SubprocessCommandRunner())
        let result = await service.run(
            RunRequest(
                message: "noop", repoRoot: repo.path, workerId: "model_grok",
                proofCommand: "sleep 10", proofTimeoutSeconds: 1),
            origin: .cli, runId: "fr13-timeout")
        guard case .success(let run) = result else { return XCTFail("run failed") }
        XCTAssertEqual(run.proofResult?.timedOut, true)
        XCTAssertFalse(run.proofResult?.passed ?? true)
        let trj = TeamRunJSONMapper.map(
            run, models: [], manifests: [], context: .init(runJournalPath: "/tmp/run.json"))
        XCTAssertTrue(trj.outcome?.headline.contains("PROOF FAILED (timeout)") ?? false)
    }

    // MARK: - Closed item: explicit --team names resolved team in footer

    func testExplicitTeamSurfacesInRunFooterNotDefaultTeam() async throws {
        let repo = try makeGitRepo()
        let capture = PromptCapturingCommandRunner()
        let service = makeService(repo: repo, commandRunner: capture)
        let result = await service.run(
            RunRequest(
                message: "Say done", repoRoot: repo.path,
                presetId: "build_slice", workerId: "model_grok", lane: .code),
            origin: .cli, runId: "closed-team-name")
        guard case .success(let run) = result else { return XCTFail("run failed") }
        XCTAssertEqual(run.teamDisplayName, "Build a Slice")
        XCTAssertFalse(RunIdentity.cliFooter(run).contains("Default Team ·"))
        XCTAssertTrue(RunIdentity.cliFooter(run).contains("Build a Slice"))
    }
}

/// Fake worker that commits with a configurable subject line.
final class ConfigurableCommittingCommandRunner: CommandRunner, @unchecked Sendable {
    private let repoRoot: URL
    private let commitMessage: String
    private let stdout: String

    init(repoRoot: URL, commitMessage: String, stdout: String = "Done.") {
        self.repoRoot = repoRoot
        self.commitMessage = commitMessage
        self.stdout = stdout
    }

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        let file = repoRoot.appendingPathComponent("worker-change.txt")
        try? "worker change".write(to: file, atomically: true, encoding: .utf8)
        runGit(["add", "worker-change.txt"], cwd: repoRoot)
        runGit(["commit", "-q", "-m", commitMessage], cwd: repoRoot)
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

/// Routes worker CLI fakes and real `/bin/sh` proof subprocesses through one seam.
final class ProofDelegatingCommandRunner: CommandRunner, @unchecked Sendable {
    private let worker: CommandRunner
    private let proof: CommandRunner

    init(worker: CommandRunner, proof: CommandRunner) {
        self.worker = worker
        self.proof = proof
    }

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        let name = URL(fileURLWithPath: command).lastPathComponent
        if name == "sh" { return await proof.run(command: command, args: args, stdin: stdin, env: env, workingDirectory: workingDirectory, timeout: timeout) }
        return await worker.run(command: command, args: args, stdin: stdin, env: env, workingDirectory: workingDirectory, timeout: timeout)
    }
}

/// Fake worker that dirties the tree without committing.
final class DirtyNoCommitCommandRunner: CommandRunner, @unchecked Sendable {
    private let repoRoot: URL

    init(repoRoot: URL) { self.repoRoot = repoRoot }

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        let file = repoRoot.appendingPathComponent("pm-review.txt")
        try? "pm will commit".write(to: file, atomically: true, encoding: .utf8)
        return CommandResult(stdout: "Left dirty.", stderr: "", exitCode: 0)
    }
}
