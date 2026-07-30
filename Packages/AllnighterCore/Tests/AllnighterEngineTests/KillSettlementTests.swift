import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// RLR-S04b — the ONE identity-checked settlement (`KillSettlement`) and the two
/// operator verbs (`ProcessOwnershipSurface.killRun`, `AsyncTeamService.cancel`)
/// routed through it. Drives each `KillOutcome` with recorded identities and the
/// `terminateSignalHook` spy so no real signals are sent (liveness is decided by
/// the chosen recorded identity, not by reaping a real process).
final class KillSettlementTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ProcessOwnership.terminateSignalHook = nil
    }
    override func tearDown() {
        ProcessOwnership.terminateSignalHook = nil
        super.tearDown()
    }

    // MARK: - Harness

    private func tempStore() throws -> (support: URL, runs: RunStore) {
        let support = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("kill-settle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return (support, RunStore(rootDirectory: support.appendingPathComponent("Runs", isDirectory: true)))
    }

    private func run(id: String, status: RunStatus, blocked: Bool = false) -> TeamRun {
        var r = TeamRun(id: id, prompt: "p", status: status, createdAt: Date(), repoRoot: "/tmp/repo")
        if blocked {
            r.blocker = RunBlocker(resource: .repoWriteLock, scopeRoot: "/tmp/repo", holderId: "h", holderKind: "run")
        }
        return r
    }

    /// A recorded worker owner keyed by `workerId` in the run dir.
    private func writeWorker(_ identity: ProcessOwnership.OwnerIdentity, workerId: String, runs: RunStore, runId: String) throws {
        let dir = try runs.runDirectory(forRunId: runId)
        try ProcessOwnership.writeWorkerOwner(.init(workerId: workerId, record: identity.asRecord()), in: dir)
    }

    private func deadWorker(pgid: Int32) -> ProcessOwnership.OwnerIdentity {
        .init(pid: 2_100_099, pgid: pgid, startTimeTicks: 1, kind: .devTurn)
    }
    private func liveSelfWorker() throws -> ProcessOwnership.OwnerIdentity {
        // This process, recorded as a devTurn worker — genuinely identity-alive.
        let pid = ProcessInfo.processInfo.processIdentifier
        let ticks = try XCTUnwrap(ProcessOwnership.processStartTimeTicks(pid))
        return .init(pid: pid, pgid: pid, startTimeTicks: ticks, kind: .devTurn)
    }
    private func mismatchWorker() throws -> ProcessOwnership.OwnerIdentity {
        // Live pid, WRONG start time — recycled; must never be signalled.
        let pid = ProcessInfo.processInfo.processIdentifier
        let ticks = try XCTUnwrap(ProcessOwnership.processStartTimeTicks(pid))
        return .init(pid: pid, pgid: 9_099, startTimeTicks: ticks &- 99, kind: .devTurn)
    }

    // MARK: - KillOutcome coverage

    func testStoppedWhenEveryRecordedMemberDead() throws {
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }
        let r = run(id: "s1", status: .running)
        try runs.save(r, models: [])
        try writeWorker(deadWorker(pgid: 9_101), workerId: "r1", runs: runs, runId: "s1")

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { signals.append($0) }
        let dir = try runs.runDirectory(forRunId: "s1")
        let result = KillSettlement.settle(runDirectory: dir, mode: .kill, run: r)
        XCTAssertEqual(result.outcome, .stopped)
        XCTAssertTrue(result.signalled)
        XCTAssertEqual(signals, [9_101], "the dead worker's recorded group is best-effort signalled")
    }

    func testPartialWhenRecordedWorkerStillAlive() throws {
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }
        let r = run(id: "p1", status: .running)
        try runs.save(r, models: [])
        try writeWorker(try liveSelfWorker(), workerId: "r1", runs: runs, runId: "p1")

        // Hook suppresses the real signal so this process (the recorded worker)
        // stays identity-alive → the verify sees a live recorded member.
        ProcessOwnership.terminateSignalHook = { _ in }
        let dir = try runs.runDirectory(forRunId: "p1")
        let result = KillSettlement.settle(runDirectory: dir, mode: .kill, run: r)
        XCTAssertEqual(result.outcome, .partial)
        XCTAssertEqual(result.survivors, ["r1"])
    }

    func testRefusedWhenAllRecordedMembersMismatch() throws {
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }
        let r = run(id: "rf1", status: .running)
        try runs.save(r, models: [])
        try writeWorker(try mismatchWorker(), workerId: "r1", runs: runs, runId: "rf1")

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { signals.append($0) }
        let dir = try runs.runDirectory(forRunId: "rf1")
        let result = KillSettlement.settle(runDirectory: dir, mode: .kill, run: r)
        XCTAssertEqual(result.outcome, .refused)
        XCTAssertFalse(result.signalled)
        XCTAssertTrue(signals.isEmpty, "a recycled (mismatched) pid is never signalled")
    }

    func testVerificationUnavailableWhenExecutingWithNoRecordedWorker() throws {
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }
        // Executing (running) but no recorded worker runtimeOwnership (warm/legacy).
        let r = run(id: "vu1", status: .running)
        try runs.save(r, models: [])
        let dir = try runs.runDirectory(forRunId: "vu1")
        // Drop the inProcess coordinator owner that save() stamps, to model a warm
        // run that recorded nothing killable.
        try? FileManager.default.removeItem(at: ProcessOwnership.ownerURL(in: dir))
        let result = KillSettlement.settle(runDirectory: dir, mode: .kill, run: r)
        XCTAssertEqual(result.outcome, .verificationUnavailable)
    }

    func testNeverExecutedBlockedRunSettlesStopped() throws {
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }
        let r = run(id: "ne1", status: .queued, blocked: true)
        try runs.save(r, models: [])
        let dir = try runs.runDirectory(forRunId: "ne1")
        try? FileManager.default.removeItem(at: ProcessOwnership.ownerURL(in: dir))
        let result = KillSettlement.settle(runDirectory: dir, mode: .kill, run: r)
        XCTAssertEqual(result.outcome, .stopped, "a blocked run never spawned a worker — nothing survives")
    }

    // MARK: - killRun (surface) end-to-end verdicts

    func testKillRunStampsTerminalOnlyOnStopped() throws {
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }
        let surface = ProcessOwnershipSurface(runStore: runs)

        // Dead recorded worker → stopped → terminal killed.
        let dead = run(id: "kr-dead", status: .running)
        try runs.save(dead, models: [])
        try writeWorker(deadWorker(pgid: 9_201), workerId: "r1", runs: runs, runId: "kr-dead")
        ProcessOwnership.terminateSignalHook = { _ in }
        let row = try surface.kill(id: "kr-dead").get()
        XCTAssertEqual(row.killOutcome, KillOutcome.stopped.rawValue)
        XCTAssertEqual(row.endReason, "killed")
        let after = try XCTUnwrap(runs.loadRaw(runId: "kr-dead"))
        XCTAssertEqual(after.status, .cancelled)
        XCTAssertEqual(after.endReason, .killed)
        XCTAssertEqual(after.killOutcome, .stopped)
    }

    func testKillRunPartialLeavesLifecycleNonTerminal() throws {
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }
        let surface = ProcessOwnershipSurface(runStore: runs)

        let live = run(id: "kr-live", status: .running)
        try runs.save(live, models: [])
        try writeWorker(try liveSelfWorker(), workerId: "r1", runs: runs, runId: "kr-live")
        ProcessOwnership.terminateSignalHook = { _ in }
        let row = try surface.kill(id: "kr-live").get()
        XCTAssertEqual(row.killOutcome, KillOutcome.partial.rawValue)
        XCTAssertNil(row.endReason, "partial stamps no terminal endReason")

        let after = try XCTUnwrap(runs.loadRaw(runId: "kr-live"))
        XCTAssertFalse(after.status.isTerminal, "partial leaves the lifecycle non-terminal")
        XCTAssertEqual(after.killOutcome, .partial)
        XCTAssertNil(after.endReason)

        // Survivor visible in `ps` as a recorded, identity-alive worker row.
        let ps = surface.list()
        XCTAssertTrue(ps.processes.contains { $0.kind == "worker" && $0.identityAlive })
    }

    func testConcurrentKillersIdempotentNoDoubleTerminal() throws {
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }
        let surface = ProcessOwnershipSurface(runStore: runs)
        let r = run(id: "cc1", status: .running)
        try runs.save(r, models: [])
        try writeWorker(deadWorker(pgid: 9_301), workerId: "r1", runs: runs, runId: "cc1")
        ProcessOwnership.terminateSignalHook = { _ in }

        let first = try surface.kill(id: "cc1").get()
        XCTAssertEqual(first.killOutcome, KillOutcome.stopped.rawValue)

        // A second killer sees the already-terminal run under the flock and refuses
        // — it never writes a second terminal revision.
        guard case .failure(.alreadyTerminal(let id, let end)) = surface.kill(id: "cc1") else {
            return XCTFail("second concurrent killer must see alreadyTerminal, not re-stamp")
        }
        XCTAssertEqual(id, "cc1")
        XCTAssertEqual(end, "killed")
    }

    // MARK: - Coordinator-clobber guard (RISK #1)

    func testCoordinatorDoesNotClobberOperatorPartialWhileWorkerAlive() throws {
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }

        // Operator kill left the run non-terminal with killOutcome partial…
        var r = run(id: "cl1", status: .running)
        r.killOutcome = .partial
        try runs.save(r, models: [])
        // …and a recorded worker is still identity-alive.
        try writeWorker(try liveSelfWorker(), workerId: "r1", runs: runs, runId: "cl1")

        // A coordinator finishing normally tries to stamp terminal complete —
        // the guard must DROP it (preserve the operator's partial).
        var finishing = r
        finishing.status = .complete
        finishing.endReason = .completed
        finishing.killOutcome = nil
        _ = try runs.save(finishing, models: [])

        let onDisk = try XCTUnwrap(runs.loadRaw(runId: "cl1"))
        XCTAssertFalse(onDisk.status.isTerminal, "coordinator must not clobber a partial with a terminal while a worker is alive")
        XCTAssertEqual(onDisk.killOutcome, .partial)

        // Once the recorded worker is identity-DEAD, the coordinator may finish.
        let dir = try runs.runDirectory(forRunId: "cl1")
        try ProcessOwnership.writeWorkerOwner(.init(workerId: "r1", record: deadWorker(pgid: 9_401).asRecord()), in: dir)
        _ = try runs.save(finishing, models: [])
        let done = try XCTUnwrap(runs.loadRaw(runId: "cl1"))
        XCTAssertTrue(done.status.isTerminal, "with the worker dead, the legitimate terminal write proceeds")
        XCTAssertEqual(done.endReason, .completed)
    }

    // MARK: - RLR-S04c contradiction surface + warm honesty

    func testWarmKillReturnsVerificationUnavailable() throws {
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }
        let surface = ProcessOwnershipSurface(runStore: runs)

        // Simulated warm: executing, no recorded worker runtimeOwnership.
        let r = run(id: "warm1", status: .running)
        try runs.save(r, models: [])
        let dir = try runs.runDirectory(forRunId: "warm1")
        try? FileManager.default.removeItem(at: ProcessOwnership.ownerURL(in: dir))

        let row = try surface.kill(id: "warm1").get()
        XCTAssertEqual(row.killOutcome, KillOutcome.verificationUnavailable.rawValue)
        XCTAssertNil(row.endReason, "warm kill never stamps a terminal endReason")

        let after = try XCTUnwrap(runs.loadRaw(runId: "warm1"))
        XCTAssertFalse(after.status.isTerminal, "verificationUnavailable leaves lifecycle non-terminal")
        XCTAssertEqual(after.killOutcome, .verificationUnavailable)
        XCTAssertNotEqual(after.endReason, .killed, "never a terminal killed lie over unverifiable warm work")
    }

    func testContradictionSurfacesAfterClockKilledWithSurvivor() throws {
        // Shape of Works Test 6 contradiction leg (clock itself is S05): a
        // terminal timedOut stamp coexists with a live recorded worker →
        // `ps` reports `contradiction: terminalWithLiveOwnership`.
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }
        let surface = ProcessOwnershipSurface(runStore: runs)

        var r = run(id: "clk1", status: .running)
        try runs.save(r, models: [])
        try writeWorker(try liveSelfWorker(), workerId: "r1", runs: runs, runId: "clk1")
        // Clock fires via RunClockEnforcer: stamp timedOut terminal while the
        // recorded worker is still identity-alive (operator-vs-clock asymmetry).
        r.status = .timedOut
        r.endReason = .timedOut
        r.killOutcome = .partial
        try runs.save(r, models: [])

        // Receipts retained after terminal (S04c).
        let dir = try runs.runDirectory(forRunId: "clk1")
        XCTAssertFalse(
            ProcessOwnership.readWorkerOwners(inRunDirectory: dir).isEmpty,
            "worker receipts must survive the terminal save")
        XCTAssertNotNil(
            ProcessOwnership.readOwnerIdentity(in: dir),
            "coordinator owner.json is retained after terminal (S04c)")

        let ps = surface.list()
        let row = try XCTUnwrap(ps.processes.first { $0.id == "clk1" && $0.kind == "run" })
        XCTAssertEqual(row.killOutcome, KillOutcome.partial.rawValue)
        XCTAssertEqual(
            row.contradiction, RunContradiction.terminalWithLiveOwnership.rawValue,
            "terminal + live recorded worker must name the contradiction")
        // Status wire uses the same `RunContradictionSurface` derivation (proven
        // pure in RunContradictionTests; populated in AsyncTeamService.status).
    }

    func testContradictionAbsentWhenTerminalAndAllDead() throws {
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }
        let surface = ProcessOwnershipSurface(runStore: runs)

        var r = run(id: "ok1", status: .cancelled)
        r.endReason = .killed
        r.killOutcome = .stopped
        try runs.save(r, models: [])
        try writeWorker(deadWorker(pgid: 9_501), workerId: "r1", runs: runs, runId: "ok1")

        // Terminal + all-dead is history (CLP-S03 hides it from the default floor);
        // opt in to inspect the contradiction derivation on the museum row.
        let row = try XCTUnwrap(surface.list(includeHistory: true).processes.first { $0.id == "ok1" && $0.kind == "run" })
        XCTAssertNil(row.contradiction, "clean verified stop must not invent a contradiction")
        XCTAssertEqual(row.killOutcome, KillOutcome.stopped.rawValue)
    }

    // MARK: - Cancel lie (END=cancelled + ALIVE=yes)

    func testWouldReconcileTrueWhenTerminalWithLiveWorker() throws {
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }

        var r = run(id: "lie1", status: .cancelled)
        r.endReason = .cancelled
        r.killOutcome = .stopped // journal claimed verified stop
        try runs.save(r, models: [])
        try writeWorker(try liveSelfWorker(), workerId: "r1", runs: runs, runId: "lie1")

        XCTAssertTrue(
            runs.wouldReconcile(runId: "lie1"),
            "cancelled + live ownership must be would-reap (cancel lie recovery)")
        XCTAssertTrue(
            ProcessOwnership.anyRecordedMemberIdentityAlive(
                in: try runs.runDirectory(forRunId: "lie1")),
            "fixture worker must be identity-alive")
    }

    func testReconcileForceKillsTerminalWithLiveOwnership() throws {
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }

        var r = run(id: "lie2", status: .cancelled)
        r.endReason = .cancelled
        try runs.save(r, models: [])
        try writeWorker(try liveSelfWorker(), workerId: "r1", runs: runs, runId: "lie2")

        var signalled: [Int32] = []
        ProcessOwnership.terminateSignalHook = { signalled.append($0) }

        let detail = try XCTUnwrap(runs.reconcileRunDetailed(
            runId: "lie2", recoverTerminalLiveOwnership: true))
        // Hook suppresses real death; reaped is false while still "alive" under hook.
        // Signal path must still fire (force terminate attempted).
        XCTAssertFalse(signalled.isEmpty, "reconcile must signal recorded live members on cancel lie")
        XCTAssertEqual(detail.run.status, .cancelled, "must not clobber terminal status")
        XCTAssertNotNil(detail.run.killOutcome)
    }

    func testReconcileOnReadNeverSignalsTerminalWithLiveOwnership() throws {
        // `ps` reconciles on read and is contractually read-only ("ps never
        // kills"). Cancel-lie recovery is opt-in, so the default sweep must
        // report the contradiction without signalling. Regression: recovery-by-
        // default made a bare `alln ps` TERM→SIGKILL every terminal run's
        // recorded pgid — including the caller's own group.
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }
        let surface = ProcessOwnershipSurface(runStore: runs)

        var r = run(id: "ro1", status: .cancelled)
        r.endReason = .cancelled
        r.killOutcome = .stopped
        try runs.save(r, models: [])
        try writeWorker(try liveSelfWorker(), workerId: "r1", runs: runs, runId: "ro1")

        var signalled: [Int32] = []
        ProcessOwnership.terminateSignalHook = { signalled.append($0) }

        let row = try XCTUnwrap(surface.list(includeHistory: true).processes.first {
            $0.id == "ro1" && $0.kind == "run"
        })
        XCTAssertTrue(signalled.isEmpty, "ps reconcile-on-read must never signal a recorded tree")
        XCTAssertEqual(
            row.contradiction, RunContradiction.terminalWithLiveOwnership.rawValue,
            "ps still names the cancel lie it refuses to act on")
        XCTAssertTrue(row.wouldReconcile, "read-only WOULD_REAP report stays yes")
        // Sweep must not rewrite the journal either.
        let after = try XCTUnwrap(runs.loadRaw(runId: "ro1"))
        XCTAssertEqual(after.killOutcome, .stopped, "read path must not restamp killOutcome")
    }

    func testInProcessCoordinatorIsNotLiveOwnership() throws {
        // An `inProcess` coordinator is the reader itself. Counting it as live
        // ownership makes every completed in-process run a permanent cancel lie:
        // WOULD_REAP forever, and cancel stamps `.partial` over a stopped tree.
        // Must match `RunContradictionSurface.contradiction`'s documented rule.
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }

        var r = run(id: "ip1", status: .complete)
        r.killOutcome = .stopped
        try runs.save(r, models: [])
        let dir = try runs.runDirectory(forRunId: "ip1")
        let selfPid = ProcessInfo.processInfo.processIdentifier
        let ticks = try XCTUnwrap(ProcessOwnership.processStartTimeTicks(selfPid))
        try ProcessOwnership.writeOwnerIdentity(
            .init(pid: selfPid, pgid: nil, startTimeTicks: ticks, kind: .inProcess), in: dir)

        XCTAssertFalse(
            ProcessOwnership.anyRecordedMemberIdentityAlive(in: dir),
            "the reading process is not a live worker tree")
        XCTAssertFalse(
            runs.wouldReconcile(runId: "ip1"),
            "a completed in-process run is not reapeable")
    }

    func testCancelDoesNotStampCancelledWhenWorkerSurvives() async throws {
        // KillSettlement path (no inProcess shortcut): live worker + TERM suppressed
        // → partial, lifecycle stays non-terminal. Never END=cancelled + ALIVE=yes.
        let (support, runs) = try tempStore(); defer { try? FileManager.default.removeItem(at: support) }
        let registry = DriverRegistry([])
        let service = AsyncTeamService(
            models: [],
            registry: registry,
            teams: [],
            runStore: runs,
            now: { Date() }
        )
        let r = run(id: "cx1", status: .running)
        try runs.save(r, models: [])
        try writeWorker(try liveSelfWorker(), workerId: "r1", runs: runs, runId: "cx1")
        ProcessOwnership.terminateSignalHook = { _ in }

        let response = await service.cancel(runId: "cx1")
        XCTAssertNotNil(response)
        let after = try XCTUnwrap(runs.loadRaw(runId: "cx1"))
        XCTAssertFalse(
            after.status.isTerminal,
            "cancel must not stamp cancelled while a recorded worker is identity-alive")
        XCTAssertEqual(after.killOutcome, .partial)
        // Response mirrors journal — not a fake cancelled lifecycle.
        XCTAssertNotEqual(after.endReason, .cancelled)
    }
}
