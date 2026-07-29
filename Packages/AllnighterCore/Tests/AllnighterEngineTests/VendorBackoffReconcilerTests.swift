import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class VendorBackoffReconcilerTests: HermeticSupportTestCase {
    private final class ScriptRunner: CommandRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var scripts: [MockCommandRunner.Script]
        private var calls: [[String]] = []

        init(_ scripts: [MockCommandRunner.Script]) {
            self.scripts = scripts
        }

        func run(
            command: String,
            args: [String],
            stdin: String?,
            env: [String: String],
            workingDirectory: String?,
            timeout: Duration
        ) async -> CommandResult {
            let script: MockCommandRunner.Script = lock.withLock {
                calls.append(args)
                let index = calls.count - 1
                return scripts.isEmpty ? .init() : scripts[min(index, scripts.count - 1)]
            }
            try? await Task.sleep(for: script.delay)
            if script.forcesTimeout { return CommandResult(timedOut: true) }
            if let launchError = script.launchError {
                return CommandResult(launchError: launchError)
            }
            return CommandResult(
                stdout: script.stdout,
                stderr: script.stderr,
                exitCode: script.exitCode
            )
        }

        var callCount: Int { lock.withLock { calls.count } }
        var capturedArgs: [[String]] { lock.withLock { calls } }
    }

    private struct Rig {
        var root: URL
        var repo: URL
        var store: RunStore
        var service: RunService
        var runner: ScriptRunner
        var lock: RunWriteLockRegistry
        var model: Model
    }

    private let limit = MockCommandRunner.Script(
        stderr: #"{"type":"error","error":{"type":"rate_limit_error","message":"You've been rate limited","retry_after":1}}"#,
        exitCode: 1
    )

    private func makeRig(scripts: [MockCommandRunner.Script]) throws -> Rig {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vendor-backoff-\(UUID().uuidString)", isDirectory: true)
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let store = RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true))
        let model = Model(
            id: "model_cursor_composer_25",
            displayName: "Opus",
            modelLabel: "opus",
            driverId: "agy",
            role: .both
        )
        var manifest = TestSupport.headlessManifest(id: "agy", command: "vendor")
        manifest.session = DriverManifest.Session(
            continuity: .vendorSession,
            acquire: .set,
            firstTurnArgs: ["-p", "{{prompt}}", "--session-id", "{{sessionId}}"],
            resumeArgs: ["-p", "{{prompt}}", "--resume", "{{sessionId}}"]
        )
        let runner = ScriptRunner(scripts)
        let lock = RunWriteLockRegistry()
        let settings = DefaultModelSettings(
            defaultTier: .frontier,
            allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: [model.id])
        )
        let probe = ToolProbeRecord(
            driverId: "agy",
            status: .ready(version: "1"),
            lastProbeAt: .distantPast
        )
        let service = RunService(
            models: [model],
            registry: DriverRegistry([manifest]),
            runStore: store,
            commandRunner: runner,
            writeLock: lock,
            invocations: ["vendor": .direct(path: "vendor")],
            defaultSettings: { settings },
            probeRecords: { [probe] },
            sessionStore: ExternalWorkerSessionStore(
                root: root.appendingPathComponent("threads", isDirectory: true)
            ),
            warmPool: WarmWorkerPool()
        )
        return Rig(
            root: root, repo: repo, store: store, service: service,
            runner: runner, lock: lock, model: model
        )
    }

    private func makeDue(_ runId: String, rig: Rig) throws {
        var run = try XCTUnwrap(rig.store.loadRaw(runId: runId))
        run.blocker?.wakeAfter = Date.distantPast
        run.blocker?.holderId = nil
        run.blocker?.holderKind = nil
        run.blocker?.holderAcquiredAt = nil
        try rig.store.save(run, models: [rig.model])
    }

    func testParkReleasesWriteLockThenWakeResumesSameRunAndSession() async throws {
        let rig = try makeRig(scripts: [limit, .init(stdout: "continued", exitCode: 0)])
        defer { try? FileManager.default.removeItem(at: rig.root) }

        let first = await rig.service.run(
            RunRequest(
                message: "continue this work",
                repoRoot: rig.repo.path,
                threadId: "thread-1",
                workerId: rig.model.id
            ),
            origin: .cli,
            runId: "same-run"
        )
        guard case .success(let parked) = first else {
            return XCTFail("initial run failed: \(first)")
        }
        XCTAssertEqual(parked.status, .queued)
        XCTAssertEqual(parked.phase, .waitingForVendor)
        XCTAssertEqual(parked.blocker?.resource, .vendorBackoff)
        XCTAssertEqual(parked.attempts.count, 1)
        XCTAssertEqual(parked.attempts.first?.capacityObservation?.kind, .accountRateLimit)
        let coolingSources = await rig.service.coolingSources()
        XCTAssertTrue(coolingSources.contains("agy"))
        let secondProcessView = try XCTUnwrap(rig.store.load(runId: parked.id))
        XCTAssertEqual(secondProcessView.status, .queued)
        XCTAssertEqual(secondProcessView.phase, .waitingForVendor)
        let ps = ProcessOwnershipSurface(
            runStore: rig.store,
            relayStore: RelayStateStore(
                rootDirectory: rig.root.appendingPathComponent("relays", isDirectory: true)
            )
        ).list(scopeRoot: rig.repo.path)
        let parkedRow = try XCTUnwrap(ps.processes.first {
            $0.kind == "run" && $0.id == parked.id
        })
        XCTAssertEqual(parkedRow.status, RunStatus.queued.rawValue)
        XCTAssertEqual(parkedRow.phase, RunPhase.waitingForVendor.rawValue)
        XCTAssertFalse(parkedRow.wouldReconcile)
        XCTAssertNil(parkedRow.progressStale)

        let key = RunWriteLock.key(repoRoot: rig.repo.path)
        let otherClaim = try XCTUnwrap(ExecutionLane.Claim.current(
            id: "intervening-run",
            kind: ExecutionLaneSite.mutatingRun.rawValue
        ))
        guard case .success(let interveningToken) = await rig.lock.tryAcquire(
            key, claim: otherClaim
        ) else {
            return XCTFail("parked run retained the repository write lock")
        }
        await rig.lock.release(key, token: interveningToken)

        try makeDue(parked.id, rig: rig)
        let reconciler = VendorBackoffReconciler(
            runStore: rig.store,
            runService: rig.service,
            coordinatorId: "serve-1"
        )
        let reconciledId = await reconciler.reconcileDueOnce()
        XCTAssertEqual(reconciledId, parked.id)

        let settled = try XCTUnwrap(rig.store.loadRaw(runId: parked.id))
        XCTAssertEqual(settled.id, parked.id)
        XCTAssertEqual(settled.status, .complete)
        XCTAssertNil(settled.phase)
        XCTAssertEqual(settled.attempts.count, 2)
        XCTAssertEqual(rig.runner.callCount, 2)

        let calls = rig.runner.capturedArgs
        guard calls.count == 2 else {
            return XCTFail("expected two claude invocations, got \(calls.count)")
        }
        let firstSessionIndex = try XCTUnwrap(calls[0].firstIndex(of: "--session-id"))
        let resumedIndex = try XCTUnwrap(calls[1].firstIndex(of: "--resume"))
        XCTAssertEqual(calls[1][resumedIndex + 1], calls[0][firstSessionIndex + 1])
    }

    func testRepeatedLimitsStopAtHardAttemptBound() async throws {
        let rig = try makeRig(
            scripts: Array(repeating: limit, count: VendorBackoffPolicy.maximumAttempts)
        )
        defer { try? FileManager.default.removeItem(at: rig.root) }

        let first = await rig.service.run(
            RunRequest(
                message: "bounded",
                repoRoot: rig.repo.path,
                threadId: "thread-bounded",
                workerId: rig.model.id
            ),
            origin: .cli,
            runId: "bounded-run"
        )
        guard case .success(let initial) = first else {
            return XCTFail("initial run failed: \(first)")
        }
        let reconciler = VendorBackoffReconciler(
            runStore: rig.store,
            runService: rig.service,
            coordinatorId: "serve-bounded"
        )
        for _ in 1..<VendorBackoffPolicy.maximumAttempts {
            try makeDue(initial.id, rig: rig)
            _ = await reconciler.reconcileDueOnce()
        }

        let failed = try XCTUnwrap(rig.store.loadRaw(runId: initial.id))
        XCTAssertEqual(failed.status, .failed)
        XCTAssertNil(failed.blocker)
        XCTAssertEqual(failed.attempts.count, VendorBackoffPolicy.maximumAttempts)
        XCTAssertEqual(
            rig.runner.callCount,
            VendorBackoffPolicy.maximumAttempts
        )
        XCTAssertTrue(failed.warnings.contains { $0.contains("human attention") })
    }

    func testRejectedStoredSessionGetsOneBoundedFreshHandoff() async throws {
        let rig = try makeRig(scripts: [
            limit,
            .init(stderr: "session not found", exitCode: 1),
            .init(stdout: "fresh continuation complete", exitCode: 0),
        ])
        defer { try? FileManager.default.removeItem(at: rig.root) }

        let first = await rig.service.run(
            RunRequest(
                message: "finish the original goal",
                repoRoot: rig.repo.path,
                threadId: "thread-fallback",
                workerId: rig.model.id
            ),
            origin: .cli,
            runId: "fresh-fallback"
        )
        guard case .success(let parked) = first else {
            return XCTFail("initial run failed: \(first)")
        }
        try makeDue(parked.id, rig: rig)
        let reconciler = VendorBackoffReconciler(
            runStore: rig.store,
            runService: rig.service,
            coordinatorId: "serve-fallback"
        )
        _ = await reconciler.reconcileDueOnce()

        let settled = try XCTUnwrap(rig.store.loadRaw(runId: parked.id))
        XCTAssertEqual(settled.status, .complete)
        XCTAssertEqual(settled.attempts.count, 2)
        XCTAssertEqual(rig.runner.callCount, 3)
        let calls = rig.runner.capturedArgs
        XCTAssertTrue(calls[1].contains("--resume"))
        XCTAssertTrue(calls[2].contains("--session-id"))
        XCTAssertFalse(calls[2].contains("--resume"))
        XCTAssertTrue(calls[2].joined(separator: " ").contains("Re-read the current repository state"))
    }

    func testPlannerNominatesOnlyOldestParkPerSourceAndLeaseIsExclusive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vendor-plan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RunStore(rootDirectory: root)
        let now = Date()
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "claude_code",
            sourceConfidence: .structured,
            rawSnippet: "limited",
            observedAt: now.addingTimeInterval(-60)
        )
        func parked(_ id: String, createdAt: Date) -> TeamRun {
            TeamRun(
                id: id,
                prompt: "work",
                status: .queued,
                phase: .waitingForVendor,
                workers: [Worker(
                    id: "worker-\(id)",
                    modelId: "model_opus",
                    instanceIndex: 0
                )],
                createdAt: createdAt,
                mutating: true,
                executionSourceId: "claude_code",
                repoRoot: root.path,
                blocker: RunBlocker(
                    resource: .vendorBackoff,
                    quotaScope: "claude_code",
                    wakeAfter: now.addingTimeInterval(-1),
                    capacityObservation: observation
                ),
                attempts: [RunAttempt(
                    attemptNumber: 1,
                    startedAt: createdAt,
                    endedAt: now.addingTimeInterval(-2),
                    capacityObservation: observation
                )]
            )
        }
        let oldest = parked("oldest", createdAt: now.addingTimeInterval(-100))
        let newer = parked("newer", createdAt: now.addingTimeInterval(-50))
        try store.save(newer, models: [])
        try store.save(oldest, models: [])

        let plan = VendorBackoffWakePlanner.plan(runs: store.list(), now: now)
        XCTAssertEqual(plan.dueRunId, oldest.id)
        XCTAssertNotNil(store.claimVendorWake(
            runId: oldest.id,
            coordinatorId: "serve-a",
            now: now
        ))
        XCTAssertNil(store.claimVendorWake(
            runId: oldest.id,
            coordinatorId: "serve-b",
            now: now.addingTimeInterval(1)
        ))
    }
}
