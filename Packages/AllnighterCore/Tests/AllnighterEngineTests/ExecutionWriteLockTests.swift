import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// CR-S02 proof wall: one mutating owner per canonical root; a research
/// (read-only) run takes no write lock. Uses real git fixtures + injected
/// RunStore/RunWriteLockRegistry so nothing touches the live user catalog.
final class ExecutionWriteLockTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-exec-lock-\(UUID().uuidString)")
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
        try "spec".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        runGit(["add", "."], cwd: dir)
        runGit(["commit", "-q", "-m", "c1"], cwd: dir)
        return dir
    }

    private func mutatingModel() -> Model {
        Model(id: "model_grok", displayName: "Grok Build", modelLabel: "grok-build",
              driverId: "grok", role: .both)
    }

    private func mutatingService(repo: URL, registry: RunWriteLockRegistry, runner: CommandRunner) -> RunService {
        RunService(
            models: [mutatingModel()],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs-\(UUID().uuidString)")),
            commandRunner: runner,
            writeLock: registry,
            defaultSettings: {
                DefaultModelSettings(defaultTier: .frontier, allowHealthySubstitutions: true,
                                     tiers: TierMembership(frontier: ["model_grok"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            })
    }

    private func researchService(repo: URL, registry: RunWriteLockRegistry, runner: CommandRunner) -> RunService {
        let team = TeamPreset(
            id: "research_lock", displayName: "Research", lane: .code, outputKind: .plan,
            mutating: false,
            workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer",
                                         purpose: .answer, preferredModelId: "model_opus")],
            lead: TeamLeadSpec(skillId: "plan_writer_build"))
        return RunService(
            models: [Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                           driverId: "claude_code", role: .both)],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            teams: [team],
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs-\(UUID().uuidString)")),
            commandRunner: runner,
            writeLock: registry,
            defaultSettings: {
                DefaultModelSettings(defaultTier: .frontier, allowHealthySubstitutions: true,
                                     tiers: TierMembership(frontier: ["model_opus"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            })
    }

    /// A read-only research run must complete even while the per-root write lock is
    /// externally held — it never waits on or takes the lock.
    func testResearchRunTakesNoWriteLock() async throws {
        let repo = try makeGitRepo()
        let registry = RunWriteLockRegistry()
        let key = RunWriteLock.key(repoRoot: repo.path)
        let externalToken = await registry.acquire(key)
        XCTAssertNotNil(externalToken, "external holder should own the lock")

        let service = researchService(
            repo: repo, registry: registry,
            runner: MockCommandRunner(scripts: ["claude": .init(stdout: "# Answer\nresearch ok", exitCode: 0)]))
        let result = await service.run(
            RunRequest(message: "research only", repoRoot: repo.path, presetId: "research_lock"),
            origin: .cli, runId: "research-nolock")

        guard case .success(let run) = result else { return XCTFail("research run failed: \(result)") }
        XCTAssertFalse(run.mutating, "research run is read-only")
        // Completed despite the held lock → it neither waited nor acquired it.
        let heldByExternal = await registry.isHeld(key)
        XCTAssertTrue(heldByExternal, "only the external holder holds the lock")
        await registry.release(key, token: externalToken!)
        let heldAfterRelease = await registry.isHeld(key)
        XCTAssertFalse(heldAfterRelease, "research took no lock, so release drops the last holder")
    }

    /// A mutating run requires the single per-root write lock: while it is held, the
    /// run blocks (no worker spawn); once released, the run acquires it, runs, and
    /// releases it. Proves exactly one mutating owner per canonical root.
    func testMutatingRunRequiresSingleWriteLock() async throws {
        let repo = try makeGitRepo()
        let registry = RunWriteLockRegistry()
        let key = RunWriteLock.key(repoRoot: repo.path)
        let externalToken = await registry.acquire(key)
        XCTAssertNotNil(externalToken)

        let done = DoneFlag()
        let service = mutatingService(
            repo: repo, registry: registry,
            runner: MockCommandRunner(scripts: ["grok": .init(stdout: "Done.", exitCode: 0)]))
        let task = Task { () -> Result<TeamRun, RunServiceError> in
            let r = await service.run(
                RunRequest(message: "make a change", repoRoot: repo.path, workerId: "model_grok"),
                origin: .cli, runId: "mutating-lock")
            await done.mark()
            return r
        }

        try await Task.sleep(for: .milliseconds(600))
        let finishedWhileHeld = await done.value
        XCTAssertFalse(finishedWhileHeld,
                       "mutating run must block on the single per-root write lock while it is held")

        await registry.release(key, token: externalToken!)
        let result = await task.value
        guard case .success(let run) = result else { return XCTFail("mutating run failed: \(result)") }
        XCTAssertTrue(run.mutating)
        XCTAssertEqual(run.status, .complete)
        let heldAfterRun = await registry.isHeld(key)
        XCTAssertFalse(heldAfterRun, "the mutating run released the lock at terminal settlement")
    }

    private actor DoneFlag {
        private(set) var value = false
        func mark() { value = true }
    }
}
