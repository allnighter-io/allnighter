import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine

/// Concurrent Invocation Isolation F2 — the staged lease → owned identity →
/// terminal liveness contract. A run within its readiness/stage lease is NEVER
/// reaped (positive dead-proof required, not missing⇒dead); a written-then-dead
/// owner is reclaimable; an unowned run is reclaimable only past the lease.
final class ProcessOwnershipStageLeaseTests: XCTestCase {

    private func tempStore() -> (RunStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-f2-\(UUID().uuidString)", isDirectory: true)
        return (RunStore(rootDirectory: dir), dir)
    }

    private func nonTerminalRun(id: String, createdAt: Date = Date()) -> TeamRun {
        TeamRun(
            id: id, prompt: "p", status: .fanningOut,
            workers: [Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0)],
            workerAnswers: [TeamAnswer(
                memberId: "model_opus#0", modelId: "model_opus", role: "answer",
                result: WorkerRunResult(status: .queued)
            )],
            createdAt: createdAt
        )
    }

    private func writeJournal(_ run: TeamRun, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try CoreJSON.encode(run).write(to: directory.appendingPathComponent("run.json"), options: .atomic)
    }

    private func writeLease(runId: String, in directory: URL, expired: Bool) throws {
        let stagedAt = expired
            ? Date().addingTimeInterval(-ProcessOwnership.stageLeaseSeconds - 10)
            : Date()
        try ProcessOwnership.writeStageLease(
            ProcessOwnership.StageLease(
                runId: runId, stagedAt: stagedAt,
                expiresAt: stagedAt.addingTimeInterval(ProcessOwnership.stageLeaseSeconds)
            ),
            in: directory
        )
    }

    private func liveSelfIdentity(kind: ProcessOwnership.OwnerKind = .detachedRunner) throws
        -> ProcessOwnership.OwnerIdentity {
        let pid = ProcessInfo.processInfo.processIdentifier
        let ticks = try XCTUnwrap(ProcessOwnership.processStartTimeTicks(pid))
        return ProcessOwnership.OwnerIdentity(pid: pid, pgid: kind.isProcessGroupKillable ? pid : nil,
                                              startTimeTicks: ticks, kind: kind)
    }

    private let deadDetached = ProcessOwnership.OwnerIdentity(
        pid: 2_000_000, pgid: 2_000_000, startTimeTicks: 1, kind: .detachedRunner
    )

    // MARK: - Unexpired lease: never reaped, whatever the owner file says

    func testUnexpiredLeaseNoOwnerIsNeverReaped() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let runDir = try store.runDirectory(forRunId: "staged-no-owner")
        try writeJournal(nonTerminalRun(id: "staged-no-owner"), in: runDir)
        try writeLease(runId: "staged-no-owner", in: runDir, expired: false)

        XCTAssertEqual(
            ProcessOwnership.livenessVerdict(in: runDir, runCreatedAt: Date()), .staged)
        XCTAssertFalse(store.wouldReconcile(runId: "staged-no-owner"))
        // Read-only projection must NOT orphan a staged run.
        let projected = try XCTUnwrap(store.load(runId: "staged-no-owner"))
        XCTAssertEqual(projected.status, .fanningOut)
        XCTAssertNil(projected.endReason)

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        defer { ProcessOwnership.terminateSignalHook = nil }

        let detail = try XCTUnwrap(store.reconcileRunDetailed(runId: "staged-no-owner"))
        XCTAssertFalse(detail.reaped, "a run inside its stage lease is never reaped")
        XCTAssertEqual(detail.run.status, .fanningOut)
        XCTAssertTrue(signals.isEmpty)
    }

    func testUnexpiredLeaseProtectsDeadLauncherOwnerDuringHandoff() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        // Crash-mid-handshake: the staged owner record is the dead launcher,
        // but the runner may still be coming up to claim. Never reap.
        let runDir = try store.runDirectory(forRunId: "staged-dead-launcher")
        try writeJournal(nonTerminalRun(id: "staged-dead-launcher"), in: runDir)
        try writeLease(runId: "staged-dead-launcher", in: runDir, expired: false)
        try ProcessOwnership.writeOwnerIdentity(deadDetached, in: runDir)

        XCTAssertEqual(
            ProcessOwnership.livenessVerdict(in: runDir, runCreatedAt: Date()), .staged)

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        defer { ProcessOwnership.terminateSignalHook = nil }

        let detail = try XCTUnwrap(store.reconcileRunDetailed(runId: "staged-dead-launcher"))
        XCTAssertFalse(detail.reaped,
                       "written-then-dead owner is NOT positive dead-proof inside the stage lease")
        XCTAssertTrue(signals.isEmpty, "a staged run's recorded group is never signalled")
    }

    // MARK: - Expired lease: positive dead-proof required, then reclaimable

    func testExpiredLeaseWithNoOwnerIsReaped() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let runDir = try store.runDirectory(forRunId: "expired-no-owner")
        try writeJournal(nonTerminalRun(id: "expired-no-owner"), in: runDir)
        try writeLease(runId: "expired-no-owner", in: runDir, expired: true)

        XCTAssertEqual(
            ProcessOwnership.livenessVerdict(in: runDir, runCreatedAt: Date()),
            .unownedReclaimable)
        XCTAssertTrue(store.wouldReconcile(runId: "expired-no-owner"))

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        defer { ProcessOwnership.terminateSignalHook = nil }

        let detail = try XCTUnwrap(store.reconcileRunDetailed(runId: "expired-no-owner"))
        XCTAssertTrue(detail.reaped, "expired stage lease with no owner claim is reclaimable")
        XCTAssertEqual(detail.run.status, .interrupted)
        XCTAssertEqual(detail.run.endReason, .reconciledOrphan)
        XCTAssertTrue(signals.isEmpty, "no recorded owner → nothing to signal")
    }

    func testExpiredLeaseWithLiveOwnerIsNeverReaped() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        // A stale lease file must not condemn a run whose owner is verifiably live.
        let runDir = try store.runDirectory(forRunId: "expired-live-owner")
        try writeJournal(nonTerminalRun(id: "expired-live-owner"), in: runDir)
        try writeLease(runId: "expired-live-owner", in: runDir, expired: true)
        try ProcessOwnership.writeOwnerIdentity(try liveSelfIdentity(), in: runDir)

        XCTAssertEqual(
            ProcessOwnership.livenessVerdict(in: runDir, runCreatedAt: Date()), .ownedLive)
        let detail = try XCTUnwrap(store.reconcileRunDetailed(runId: "expired-live-owner"))
        XCTAssertFalse(detail.reaped)
    }

    func testExpiredLeaseWithDeadOwnerIsReaped() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let runDir = try store.runDirectory(forRunId: "expired-dead-owner")
        try writeJournal(nonTerminalRun(id: "expired-dead-owner"), in: runDir)
        try writeLease(runId: "expired-dead-owner", in: runDir, expired: true)
        try ProcessOwnership.writeOwnerIdentity(deadDetached, in: runDir)

        XCTAssertEqual(
            ProcessOwnership.livenessVerdict(in: runDir, runCreatedAt: Date()), .ownerDead)

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        defer { ProcessOwnership.terminateSignalHook = nil }

        let detail = try XCTUnwrap(store.reconcileRunDetailed(runId: "expired-dead-owner"))
        XCTAssertTrue(detail.reaped, "written-then-dead owner past the lease is reclaimable")
        XCTAssertEqual(detail.run.endReason, .reconciledOrphan)
        XCTAssertEqual(signals, [2_000_000], "recorded pgid is group-killed once")
    }

    // MARK: - No lease file: createdAt window decides (legacy + lease-write failure)

    func testNoLeaseYoungRunMissingOwnerIsProtectedAsStaging() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let runDir = try store.runDirectory(forRunId: "young-no-owner")
        try writeJournal(nonTerminalRun(id: "young-no-owner"), in: runDir)

        XCTAssertEqual(
            ProcessOwnership.livenessVerdict(in: runDir, runCreatedAt: Date()), .staged)
        let detail = try XCTUnwrap(store.reconcileRunDetailed(runId: "young-no-owner"))
        XCTAssertFalse(detail.reaped,
                       "a run younger than the staging window with no owner may still be staging")
    }

    func testNoLeaseOldRunMissingOwnerIsReaped() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let old = Date().addingTimeInterval(-ProcessOwnership.stageLeaseSeconds - 60)
        let runDir = try store.runDirectory(forRunId: "old-no-owner")
        try writeJournal(nonTerminalRun(id: "old-no-owner", createdAt: old), in: runDir)

        XCTAssertEqual(
            ProcessOwnership.livenessVerdict(in: runDir, runCreatedAt: old),
            .unownedReclaimable)
        let detail = try XCTUnwrap(store.reconcileRunDetailed(runId: "old-no-owner"))
        XCTAssertTrue(detail.reaped, "legacy unowned orphans past the window stay collectable")
        XCTAssertEqual(detail.run.endReason, .reconciledOrphan)
    }

    // MARK: - Claim clears the lease; terminal save drops the marker

    func testClaimedRunWithDeadOwnerIsReapedAfterLeaseCleared() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let runDir = try store.runDirectory(forRunId: "claimed-then-died")
        try writeJournal(nonTerminalRun(id: "claimed-then-died"), in: runDir)
        try writeLease(runId: "claimed-then-died", in: runDir, expired: false)
        try ProcessOwnership.writeOwnerIdentity(deadDetached, in: runDir)
        // Runner claims ownership → handoff complete → lease dropped.
        ProcessOwnership.clearStageLease(in: runDir)
        XCTAssertNil(ProcessOwnership.readStageLease(in: runDir))

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        defer { ProcessOwnership.terminateSignalHook = nil }

        let detail = try XCTUnwrap(store.reconcileRunDetailed(runId: "claimed-then-died"))
        XCTAssertTrue(detail.reaped,
                      "once the runner claimed and then died, the written-dead owner is reclaimable")
        XCTAssertEqual(signals, [2_000_000])
    }

    func testTerminalSaveDropsStageLeaseMarker() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let runDir = try store.runDirectory(forRunId: "terminal-lease")
        try writeJournal(nonTerminalRun(id: "terminal-lease"), in: runDir)
        try writeLease(runId: "terminal-lease", in: runDir, expired: false)

        var run = nonTerminalRun(id: "terminal-lease")
        run.status = .complete
        run.endReason = .completed
        try store.save(run, models: [])

        XCTAssertNil(ProcessOwnership.readStageLease(in: runDir),
                     "terminal save must not leave a staging marker behind")
    }

    // MARK: - Lease I/O round trip

    func testStageLeaseRoundTripAndExpiry() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-f2-io-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let stagedAt = Date(timeIntervalSince1970: 1_752_000_000)
        let lease = ProcessOwnership.StageLease(
            runId: "r1", stagedAt: stagedAt,
            expiresAt: stagedAt.addingTimeInterval(ProcessOwnership.stageLeaseSeconds)
        )
        try ProcessOwnership.writeStageLease(lease, in: dir)
        let read = try XCTUnwrap(ProcessOwnership.readStageLease(in: dir))
        XCTAssertEqual(read.runId, lease.runId)
        XCTAssertEqual(read.stagedAt.timeIntervalSince1970, lease.stagedAt.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(read.expiresAt.timeIntervalSince1970, lease.expiresAt.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertFalse(read.isExpired(at: stagedAt))
        XCTAssertTrue(read.isExpired(at: lease.expiresAt))
        XCTAssertTrue(ProcessOwnership.readStageLease(in: dir.appendingPathComponent("nope")) == nil)
    }
}
