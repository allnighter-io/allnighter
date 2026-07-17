import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine

/// PO-S01 reconcile seam: interrupt ONLY when heartbeat is stale AND owner is dead.
final class ProcessOwnershipReconcileTests: XCTestCase {

    private func tempStore() -> (RunStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-s01-\(UUID().uuidString)", isDirectory: true)
        return (RunStore(rootDirectory: dir), dir)
    }

    private func nonTerminalRun(id: String) -> TeamRun {
        TeamRun(
            id: id, prompt: "p", status: .fanningOut,
            workers: [Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0)],
            workerAnswers: [TeamAnswer(
                memberId: "model_opus#0", modelId: "model_opus", role: "answer",
                result: WorkerRunResult(status: .queued)
            )],
            createdAt: Date()
        )
    }

    private func writeJournal(_ run: TeamRun, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try CoreJSON.encode(run).write(to: directory.appendingPathComponent("run.json"), options: .atomic)
    }

    private func setHeartbeatAge(in directory: URL, ageSeconds: TimeInterval) throws {
        try ProcessOwnership.touchHeartbeat(in: directory)
        let url = ProcessOwnership.heartbeatURL(in: directory)
        let past = Date().addingTimeInterval(-ageSeconds)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
    }

    // MARK: - Seam: fresh heartbeat + dead owner → NOT interrupted

    func testFreshHeartbeatAndDeadOwnerIsNotInterrupted() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let runDir = try store.runDirectory(forRunId: "fresh-hb")
        try writeJournal(nonTerminalRun(id: "fresh-hb"), in: runDir)
        // Dead owner pid
        try ProcessOwnership.writeOwnerPID(2_000_000, in: runDir)
        // Fresh heartbeat (just touched)
        try ProcessOwnership.touchHeartbeat(in: runDir)

        let loaded = store.load(runId: "fresh-hb")
        XCTAssertEqual(loaded?.status, .fanningOut,
                       "fresh heartbeat must never be overridden by a dead-owner pid check")
        XCTAssertNil(loaded?.endReason)
    }

    // MARK: - Seam: stale heartbeat + dead owner → interrupted + endReason

    func testStaleHeartbeatAndDeadOwnerReconcilesToInterrupted() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let runDir = try store.runDirectory(forRunId: "stale-orphan")
        try writeJournal(nonTerminalRun(id: "stale-orphan"), in: runDir)
        try ProcessOwnership.writeOwnerPID(2_000_000, in: runDir)
        try setHeartbeatAge(in: runDir, ageSeconds: ProcessOwnership.heartbeatStaleAfterSeconds + 5)

        let loaded = try XCTUnwrap(store.load(runId: "stale-orphan"))
        XCTAssertEqual(loaded.status, .interrupted)
        XCTAssertEqual(loaded.endReason, .reconciledOrphan)

        // Write-back is durable — second load stays terminal with endReason.
        let again = try XCTUnwrap(store.load(runId: "stale-orphan"))
        XCTAssertEqual(again.status, .interrupted)
        XCTAssertEqual(again.endReason, .reconciledOrphan)
    }

    // MARK: - Live owner keeps running even if heartbeat looks stale

    func testLiveOwnerIsNotInterruptedEvenWithStaleHeartbeat() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try store.save(nonTerminalRun(id: "live-owner"), models: [])
        let runDir = try store.runDirectory(forRunId: "live-owner")
        // Force stale heartbeat while this process is still the live owner.
        try setHeartbeatAge(in: runDir, ageSeconds: ProcessOwnership.heartbeatStaleAfterSeconds + 30)

        let loaded = store.load(runId: "live-owner")
        XCTAssertEqual(loaded?.status, .fanningOut,
                       "owner exit alone is death only with a stale heartbeat — live owner must not be reaped")
    }

    // MARK: - Missing heartbeat + dead owner (legacy crash) still reaps

    func testMissingHeartbeatAndDeadOwnerIsInterrupted() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let runDir = try store.runDirectory(forRunId: "no-hb")
        try writeJournal(nonTerminalRun(id: "no-hb"), in: runDir)
        try ProcessOwnership.writeOwnerPID(2_000_000, in: runDir)
        // No heartbeat file → stale by definition.

        let loaded = try XCTUnwrap(store.load(runId: "no-hb"))
        XCTAssertEqual(loaded.status, .interrupted)
        XCTAssertEqual(loaded.endReason, .reconciledOrphan)
    }

    // MARK: - endReason stamped on terminal saves

    func testTerminalSaveStampsEndReasonWhenMissing() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var run = nonTerminalRun(id: "done-1")
        run.status = .complete
        // endReason deliberately nil — save must infer.
        try store.save(run, models: [])
        let loaded = try XCTUnwrap(store.load(runId: "done-1"))
        XCTAssertEqual(loaded.status, .complete)
        XCTAssertEqual(loaded.endReason, .completed)
    }

    func testCancelEndReasonViaAsyncService() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-cancel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let team = TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan, defaultEffort: .low,
            isDefaultForLane: true,
            workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"),
            builtIn: true
        )
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "# Plan\nOk.", delay: .seconds(2))])
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ALLNIGHTER_TEAM_DEPTH")
        let service = AsyncTeamService(
            models: [opus],
            registry: registry,
            teams: [team],
            config: ToolConfig(maxConcurrentTeamRuns: 2, maxTeamRunDepth: 1),
            runStore: RunStore(rootDirectory: root.appendingPathComponent("Runs")),
            commandRunner: mock,
            governor: TeamGovernor(directory: root.appendingPathComponent("gov"), capacity: 2),
            idempotency: IdempotencyStore(fileURL: root.appendingPathComponent("idempotency.json")),
            environment: env,
            idFactory: { "run-cancel-end" }
        )
        guard case .success = await service.start(
            AsyncTeamStartRequest(question: "x", lane: .code, teamPresetId: "code_test", effort: .low),
            origin: .cli,
            readyModels: [opus]
        ) else {
            return XCTFail("expected start success")
        }
        _ = await service.cancel(runId: "run-cancel-end")
        let loaded = try XCTUnwrap(
            RunStore(rootDirectory: root.appendingPathComponent("Runs")).load(runId: "run-cancel-end")
        )
        XCTAssertEqual(loaded.status, .cancelled)
        XCTAssertEqual(loaded.endReason, .cancelled)
    }

    // MARK: - Heartbeat helpers

    func testHeartbeatTouchUpdatesMtime() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hb-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try ProcessOwnership.touchHeartbeat(in: dir)
        XCTAssertFalse(ProcessOwnership.isHeartbeatStale(in: dir))

        try setHeartbeatAge(in: dir, ageSeconds: 120)
        XCTAssertTrue(ProcessOwnership.isHeartbeatStale(in: dir))
    }

    func testProcessAliveDetectsSelfAndRejectsDead() {
        XCTAssertTrue(ProcessOwnership.processAlive(ProcessInfo.processInfo.processIdentifier))
        XCTAssertFalse(ProcessOwnership.processAlive(2_000_000))
        XCTAssertFalse(ProcessOwnership.processAlive(0))
    }

    // MARK: - TeamRunJSON endReason projection

    func testTeamRunJSONExposesEndReason() throws {
        var run = nonTerminalRun(id: "json-end")
        run.status = .interrupted
        run.endReason = .reconciledOrphan
        let trj = TeamRunJSONMapper.map(
            run, models: [], manifests: [],
            context: .init(runJournalPath: "/tmp/run.json")
        )
        XCTAssertEqual(trj.teamRun.endReason, "reconciledOrphan")
        XCTAssertEqual(trj.teamRun.status, .interrupted)
    }

    func testStatusResponseExposesEndReason() {
        var run = nonTerminalRun(id: "status-end")
        run.status = .failed
        run.endReason = .failed
        let status = AsyncTeamStatusMapper.statusResponse(for: run)
        XCTAssertEqual(status.endReason, "failed")
        XCTAssertEqual(status.status, .failed)
    }
}
