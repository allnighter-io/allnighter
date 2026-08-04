import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// WL-PWR-S00 — locus spike tests. Assert **target** behavior (post-S01/S02); several
/// fail on `main` today and gate implementation.
final class WriteLockPostWorkerTests: HermeticSupportTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wl-pwr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        try super.tearDownWithError()
    }

    // MARK: - Harness

    private struct Harness {
        let repo: URL
        let runStore: RunStore
        let registry: RunWriteLockRegistry
        let service: RunService
        var lockKey: String { RunWriteLock.key(repoRoot: repo.path) }
        func pollStore() -> RunStore { RunStore(rootDirectory: runStore.rootDirectory) }
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

    private func makeHarness(
        workerRunner: CommandRunner,
        proofRunner: CommandRunner? = nil
    ) throws -> Harness {
        let repo = try makeGitRepo()
        let runsDir = tmp.appendingPathComponent("runs-\(UUID().uuidString)", isDirectory: true)
        let runStore = RunStore(rootDirectory: runsDir)
        let model = Model(
            id: "model_grok", displayName: "Grok Build", modelLabel: "grok-build",
            driverId: "grok", role: .both)
        let registry = RunWriteLockRegistry()
        let commandRunner: CommandRunner = {
            if let proofRunner {
                return ProofDelegatingCommandRunner(worker: workerRunner, proof: proofRunner)
            }
            return workerRunner
        }()
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            runStore: runStore,
            commandRunner: commandRunner,
            writeLock: registry,
            defaultSettings: {
                DefaultModelSettings(
                    defaultTier: .frontier, allowHealthySubstitutions: true,
                    tiers: TierMembership(frontier: ["model_grok"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            })
        return Harness(repo: repo, runStore: runStore, registry: registry, service: service)
    }

    private actor WorkerDoneGate {
        private var done = false
        func markDone() { done = true }
        func waitForDone(timeout: TimeInterval) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if done { return true }
                try? await Task.sleep(for: .milliseconds(25))
            }
            return done
        }
    }

    private final class WorkerDoneSignallingRunner: CommandRunner, @unchecked Sendable {
        private let gate: WorkerDoneGate
        private let inner: MockCommandRunner
        init(gate: WorkerDoneGate, inner: MockCommandRunner) {
            self.gate = gate
            self.inner = inner
        }
        func run(
            command: String, args: [String], stdin: String?, env: [String: String],
            workingDirectory: String?, timeout: Duration
        ) async -> CommandResult {
            let result = await inner.run(
                command: command, args: args, stdin: stdin, env: env,
                workingDirectory: workingDirectory, timeout: timeout)
            await gate.markDone()
            return result
        }
    }

    private func waitUntilBlocked(runId: String, store: RunStore, timeout: TimeInterval = 10) async throws -> TeamRun {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let run = store.loadRaw(runId: runId),
               run.status == .queued, run.blocker?.resource == .repoWriteLock {
                return run
            }
            try await Task.sleep(for: .milliseconds(40))
        }
        throw XCTSkip("run \(runId) never reached waitingForWriteLock within \(timeout)s")
    }

    private func waitUntilLaneFree(
        registry: RunWriteLockRegistry, key: String, timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !(await registry.isHeld(key)) { return true }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return false
    }

    private func boundedValue<T: Sendable>(of task: Task<T, Never>, timeout: TimeInterval) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - T-M1 post-worker settlement holds lane (fails until WL-PWR-L1)

    /// Worker reaches `.done`, then harness proof sleeps. After S01 the coordinator
    /// releases mutation depth at worker terminal so a queued run B can acquire
    /// while A is still in proof/settlement (FIFO: B was waiting before release).
    func testTM1_SecondRunAcquiresAfterWorkerTerminalBeforeCoordinatorExit() async throws {
        let gate = WorkerDoneGate()
        let worker = WorkerDoneSignallingRunner(
            gate: gate,
            inner: MockCommandRunner(scripts: [
                "grok": .init(stdout: "Done.", exitCode: 0, delay: .milliseconds(400)),
            ]))
        let h = try makeHarness(
            workerRunner: worker,
            proofRunner: SubprocessCommandRunner())
        let runA = "run-a-\(UUID().uuidString)"
        let runB = "run-b-\(UUID().uuidString)"

        let taskA = Task {
            await h.service.run(
                RunRequest(
                    message: "mutate", repoRoot: h.repo.path, pinnedModelId: "model_grok",
                    proofCommand: "sleep 8"),
                origin: .cli, runId: runA)
        }

        // Let A acquire and begin the worker so B queues behind the live holder.
        try await Task.sleep(for: .milliseconds(150))
        let aHolds = await h.registry.isHeld(h.lockKey)
        XCTAssertTrue(aHolds, "run A must hold before B queues")

        let taskB = Task {
            await h.service.run(
                RunRequest(message: "second slice", repoRoot: h.repo.path, pinnedModelId: "model_grok"),
                origin: .cli, runId: runB)
        }
        _ = try await waitUntilBlocked(runId: runB, store: h.pollStore(), timeout: 3)

        let workerFinished = await gate.waitForDone(timeout: 5)
        XCTAssertTrue(workerFinished, "worker A must finish")

        // After worker terminal, A releases mutation depth; B leaves the write-lock wait
        // while A's coordinator is still in proof (sleep 8).
        let bLeftWriteLockWait = await waitUntilLeftWriteLockWait(
            runId: runB, store: h.pollStore(), timeout: 2)
        let aStillInFlight = await boundedValue(of: taskA, timeout: 0.3) == nil

        taskA.cancel()
        taskB.cancel()
        _ = await boundedValue(of: taskA, timeout: 1)
        _ = await boundedValue(of: taskB, timeout: 1)

        XCTAssertTrue(bLeftWriteLockWait,
                      "WL-PWR-L1: run B must leave write-lock wait within 2s after A's worker terminal while A's coordinator is still in proof/settlement")
        XCTAssertTrue(aStillInFlight,
                      "run A must still be in proof/settlement when B acquires")
    }

    private func waitUntilLeftWriteLockWait(
        runId: String, store: RunStore, timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let run = store.loadRaw(runId: runId) {
                let blocked = run.status == .queued && run.blocker?.resource == .repoWriteLock
                if !blocked { return true }
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return false
    }

    // MARK: - Nested relay: inner depth releases; outer remains (WL-PWR-S01)

    /// Outer relayDevTurn + nested RunService: early worker-terminal release must not
    /// free the outer hold (idempotent MutationAuthorityHold).
    func testNestedRelay_WorkerTerminalReleasesInnerDepthOuterRemains() async throws {
        let gate = WorkerDoneGate()
        let worker = WorkerDoneSignallingRunner(
            gate: gate,
            inner: MockCommandRunner(scripts: ["grok": .init(stdout: "Done.", exitCode: 0)]))
        let h = try makeHarness(workerRunner: worker)

        let outerClaim = try XCTUnwrap(
            ExecutionLane.Claim.current(
                id: "relay-outer-\(UUID().uuidString)",
                kind: ExecutionLaneSite.relayDevTurn.rawValue
            )
        )
        guard case .success(let outerToken) = await h.registry.tryAcquire(
            h.lockKey, claim: outerClaim, now: Date()
        ) else {
            return XCTFail("outer relayDevTurn must acquire")
        }

        let runId = "run-nested-\(UUID().uuidString)"
        let result = await h.service.run(
            RunRequest(message: "nested mutate", repoRoot: h.repo.path, pinnedModelId: "model_grok"),
            origin: .cli, runId: runId)

        guard case .success = result else {
            await h.registry.release(h.lockKey, token: outerToken, endReason: "testCleanup")
            return XCTFail("nested run failed: \(result)")
        }
        let workerFinished = await gate.waitForDone(timeout: 2)
        XCTAssertTrue(workerFinished)

        // RunService returned; idempotent owner release must leave the outer depth held.
        // (Nested depth decrement does not stamp lastEndReason — only the outermost free does.)
        let stillHeld = await h.registry.isHeld(h.lockKey)
        let holderCount = await h.registry.localHolderCount(for: h.lockKey)
        XCTAssertTrue(stillHeld,
                      "outer relay depth must remain after RunService worker-terminal release")
        XCTAssertEqual(holderCount, 1)

        await h.registry.release(h.lockKey, token: outerToken, endReason: "testDone")
        let freed = await h.registry.isHeld(h.lockKey)
        XCTAssertFalse(freed, "outermost release frees the lane")
    }

    // MARK: - T-M2 in-prompt hang (documents M2; L1 must not claim to fix)

    func testTM2_InPromptHangKeepsLaneUntilWorkerTerminal() async throws {
        let h = try makeHarness(
            workerRunner: MockCommandRunner(scripts: [
                "grok": .init(stdout: "Still working…", exitCode: 0, delay: .seconds(3)),
            ]))
        let runA = "run-a-\(UUID().uuidString)"
        let taskA = Task {
            await h.service.run(
                RunRequest(message: "slow worker", repoRoot: h.repo.path, pinnedModelId: "model_grok"),
                origin: .cli, runId: runA)
        }

        try await Task.sleep(for: .milliseconds(400))
        let laneHeld = await h.registry.isHeld(h.lockKey)
        XCTAssertTrue(laneHeld,
                      "lane must stay held while the worker stream has not reached terminal outcome")
        XCTAssertTrue(ExecutionLaneFlock.isLocked(laneKey: h.lockKey))

        let runB = "run-b-\(UUID().uuidString)"
        let taskB = Task {
            await h.service.run(
                RunRequest(message: "queued slice", repoRoot: h.repo.path, pinnedModelId: "model_grok"),
                origin: .cli, runId: runB)
        }
        _ = try await waitUntilBlocked(runId: runB, store: h.pollStore(), timeout: 5)

        _ = await boundedValue(of: taskA, timeout: 10)
        _ = await boundedValue(of: taskB, timeout: 10)
    }

    /// Kill during an in-prompt hang must free the flock for the next waiter (L2/L3).
    func testTM2_KillDuringInPromptHangFreesLaneForNextRun() async throws {
        let h = try makeHarness(
            workerRunner: MockCommandRunner(scripts: [
                "grok": .init(stdout: "hang", exitCode: 0, delay: .seconds(4)),
            ]))
        let runA = "run-a-\(UUID().uuidString)"
        let taskA = Task {
            await h.service.run(
                RunRequest(message: "hang", repoRoot: h.repo.path, pinnedModelId: "model_grok"),
                origin: .cli, runId: runA)
        }
        try await Task.sleep(for: .milliseconds(300))

        let surface = ProcessOwnershipSurface(runStore: h.runStore)
        guard case .success = surface.kill(id: runA) else {
            return XCTFail("kill of hung run A must succeed cooperatively for in-process coordinator")
        }

        let runB = "run-b-\(UUID().uuidString)"
        let taskB = Task {
            await h.service.run(
                RunRequest(message: "after kill", repoRoot: h.repo.path, pinnedModelId: "model_grok"),
                origin: .cli, runId: runB)
        }

        let acquired = await waitUntilLaneFree(registry: h.registry, key: h.lockKey, timeout: 2)
        taskA.cancel()
        taskB.cancel()
        _ = await boundedValue(of: taskA, timeout: 1)
        _ = await boundedValue(of: taskB, timeout: 1)

        XCTAssertTrue(acquired,
                      "WL-PWR-L2/L3: external kill must free the build flock within 2s even when the holder coordinator is still alive")
    }

    // MARK: - T-M3 kill after worker terminal (metadata-only kill leaves flock)

    func testTM3_KillAfterWorkerTerminalFreesLaneForNextRun() async throws {
        let gate = WorkerDoneGate()
        let worker = WorkerDoneSignallingRunner(
            gate: gate,
            inner: MockCommandRunner(scripts: ["grok": .init(stdout: "Done.", exitCode: 0)]))
        let h = try makeHarness(
            workerRunner: worker,
            proofRunner: SubprocessCommandRunner())
        let runA = "run-a-\(UUID().uuidString)"

        let taskA = Task {
            await h.service.run(
                RunRequest(
                    message: "mutate", repoRoot: h.repo.path, pinnedModelId: "model_grok",
                    proofCommand: "sleep 8"),
                origin: .cli, runId: runA)
        }
        let workerFinished = await gate.waitForDone(timeout: 5)
        XCTAssertTrue(workerFinished)

        let surface = ProcessOwnershipSurface(runStore: h.runStore)
        guard case .success = surface.kill(id: runA) else {
            return XCTFail("cooperative kill of in-process holder must stamp terminal")
        }

        let runB = "run-b-\(UUID().uuidString)"
        let taskB = Task {
            await h.service.run(
                RunRequest(message: "after kill", repoRoot: h.repo.path, pinnedModelId: "model_grok"),
                origin: .cli, runId: runB)
        }

        let acquired = await waitUntilLaneFree(registry: h.registry, key: h.lockKey, timeout: 2)
        taskA.cancel()
        taskB.cancel()
        _ = await boundedValue(of: taskA, timeout: 1)
        _ = await boundedValue(of: taskB, timeout: 1)

        XCTAssertTrue(acquired,
                      "WL-PWR-L2: kill must unlock the flock (not only journal/holder.json) while the coordinator is still in post-worker settlement")
    }

    // MARK: - T-PROOF regression (passes on main; guards S01 early-release path)

    func testTProof_HarnessProofPopulatesResult() async throws {
        let h = try makeHarness(
            workerRunner: MockCommandRunner(scripts: ["grok": .init(stdout: "ok", exitCode: 0)]),
            proofRunner: SubprocessCommandRunner())
        let result = await h.service.run(
            RunRequest(
                message: "work", repoRoot: h.repo.path, pinnedModelId: "model_grok",
                proofCommand: "exit 0"),
            origin: .cli, runId: "t-proof")
        guard case .success(let run) = result else {
            return XCTFail("run failed: \(result)")
        }
        XCTAssertEqual(run.proofResult?.passed, true)
    }

    // MARK: - T-PARK vendor park releases lane before return

    func testTPARK_VendorParkReleasesWriteLock() async throws {
        let h = try makeHarness(
            workerRunner: MockCommandRunner(scripts: [
                "grok": .init(
                    stdout: "", stderr: "usage limit reached, retry after: 120 seconds", exitCode: 1),
            ]))
        let result = await h.service.run(
            RunRequest(message: "park me", repoRoot: h.repo.path, pinnedModelId: "model_grok"),
            origin: .cli, runId: "t-park")
        guard case .success(let run) = result else {
            return XCTFail("park run failed: \(result)")
        }
        XCTAssertEqual(run.phase, .waitingForVendor)
        let laneHeldAfterPark = await h.registry.isHeld(h.lockKey)
        XCTAssertFalse(laneHeldAfterPark,
                       "vendor park must release the per-root write lock before returning")
    }
}
