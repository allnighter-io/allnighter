import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine

/// PO-S01 v2 reconcile seam: identity-dead → reaped immediately; identity-alive
/// never reaped; recycled pid never signalled; in-process never signalled.
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

    private func setProgressAge(in directory: URL, ageSeconds: TimeInterval, phase: String = "fanning_out") throws {
        let past = Date().addingTimeInterval(-ageSeconds)
        let hb = ProcessOwnership.ProgressHeartbeat(
            sequence: 1, phase: phase, lastProgressAt: past, touchedAt: past
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try CoreJSON.encode(hb).write(to: ProcessOwnership.heartbeatURL(in: directory), options: .atomic)
    }

    // MARK: - Identity-alive → never reaped at any heartbeat age

    func testIdentityAliveNeverReapedRegardlessOfHeartbeatAge() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try store.save(nonTerminalRun(id: "alive-stale-progress"), models: [])
        let runDir = try store.runDirectory(forRunId: "alive-stale-progress")
        // Force very stale progress while this process is still the live in-process owner.
        try setProgressAge(in: runDir, ageSeconds: 86_400)

        let projected = store.load(runId: "alive-stale-progress")
        XCTAssertEqual(projected?.status, .fanningOut,
                       "identity-alive must never be reaped regardless of progress age")

        let after = store.reconcileRun(runId: "alive-stale-progress")
        XCTAssertEqual(after?.status, .fanningOut)
        XCTAssertNil(after?.endReason)
    }

    // MARK: - Identity-dead → reaped immediately, reconciledOrphan, one atomic write

    func testIdentityDeadReapedImmediatelyOnExplicitReconcile() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let runDir = try store.runDirectory(forRunId: "dead-now")
        try writeJournal(nonTerminalRun(id: "dead-now"), in: runDir)
        // Detached identity with dead pid.
        let dead = ProcessOwnership.OwnerIdentity(
            pid: 2_000_000, pgid: 2_000_000, startTimeTicks: 1, kind: .detachedRunner
        )
        try ProcessOwnership.writeOwnerIdentity(dead, in: runDir)
        try ProcessOwnership.recordProgress(in: runDir, phase: "fanning_out")

        // Load projects read-only (no write-back).
        let projected = try XCTUnwrap(store.load(runId: "dead-now"))
        XCTAssertEqual(projected.status, .interrupted)
        XCTAssertEqual(projected.endReason, .reconciledOrphan)
        // Raw journal still non-terminal until explicit reconcile.
        XCTAssertEqual(store.loadRaw(runId: "dead-now")?.status, .fanningOut)

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        defer { ProcessOwnership.terminateSignalHook = nil }

        let reaped = try XCTUnwrap(store.reconcileRunDetailed(runId: "dead-now"))
        XCTAssertTrue(reaped.reaped)
        XCTAssertEqual(reaped.run.status, .interrupted)
        XCTAssertEqual(reaped.run.endReason, .reconciledOrphan)
        XCTAssertEqual(signals, [2_000_000], "detached dead owner with recorded pgid is PG-killed once")

        // Second reconcile is a no-op (never clobber terminal).
        signals.removeAll()
        let again = try XCTUnwrap(store.reconcileRunDetailed(runId: "dead-now"))
        XCTAssertFalse(again.reaped)
        XCTAssertEqual(again.run.status, .interrupted)
        XCTAssertTrue(signals.isEmpty)
    }

    // MARK: - Recycled pid: same pid, different startTime → dead, NO signal

    func testRecycledPidIsDeadAndNeverSignalled() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let livePid = ProcessInfo.processInfo.processIdentifier
        guard let liveTicks = ProcessOwnership.processStartTimeTicks(livePid) else {
            return XCTFail("could not read self start time")
        }
        // Same pid as this process, but a different start time → recycled identity.
        let recycled = ProcessOwnership.OwnerIdentity(
            pid: livePid,
            pgid: livePid,
            startTimeTicks: liveTicks &- 999_999,
            kind: .detachedRunner
        )
        let runDir = try store.runDirectory(forRunId: "recycled")
        try writeJournal(nonTerminalRun(id: "recycled"), in: runDir)
        try ProcessOwnership.writeOwnerIdentity(recycled, in: runDir)

        XCTAssertTrue(ProcessOwnership.isOwnerIdentityDead(in: runDir))
        XCTAssertFalse(ProcessOwnership.isIdentityAlive(recycled))

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        defer { ProcessOwnership.terminateSignalHook = nil }

        let reaped = try XCTUnwrap(store.reconcileRunDetailed(runId: "recycled"))
        XCTAssertFalse(reaped.reaped, "recycled pid must not be reconciled — identity mismatch")
        XCTAssertNil(reaped.run.endReason)
        XCTAssertTrue(signals.isEmpty,
                      "recycled pid (alive but wrong startTime) must NEVER be signalled")
    }

    // MARK: - Progress save must not demote a live detached runner

    func testSavePreservesAliveDetachedRunnerIdentity() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let runDir = try store.runDirectory(forRunId: "detach-keep")
        try writeJournal(nonTerminalRun(id: "detach-keep"), in: runDir)
        let livePid = ProcessInfo.processInfo.processIdentifier
        let liveTicks = try XCTUnwrap(ProcessOwnership.processStartTimeTicks(livePid))
        let detached = ProcessOwnership.OwnerIdentity(
            pid: livePid, pgid: livePid, startTimeTicks: liveTicks, kind: .detachedRunner
        )
        try ProcessOwnership.writeOwnerIdentity(detached, in: runDir)

        // Progress save (same shape as the runner's coordinator persist).
        try store.save(nonTerminalRun(id: "detach-keep"), models: [])
        let after = try XCTUnwrap(ProcessOwnership.readOwnerIdentity(in: runDir))
        XCTAssertEqual(after.kind, .detachedRunner)
        XCTAssertEqual(after.pgid, livePid)
        XCTAssertEqual(after.startTimeTicks, liveTicks)
        XCTAssertTrue(ProcessOwnership.isIdentityAlive(after))
    }

    // MARK: - In-process owner → never signalled

    func testInProcessOwnerNeverSignalledOnReconcile() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        // Save writes kind=inProcess, no pgid.
        try store.save(nonTerminalRun(id: "in-proc"), models: [])
        let runDir = try store.runDirectory(forRunId: "in-proc")
        let identity = try XCTUnwrap(ProcessOwnership.readOwnerIdentity(in: runDir))
        XCTAssertEqual(identity.kind, .inProcess)
        XCTAssertNil(identity.pgid)

        // Force identity-dead by overwriting with dead in-process record.
        let deadInProcess = ProcessOwnership.OwnerIdentity(
            pid: 2_000_000, pgid: nil, startTimeTicks: 1, kind: .inProcess
        )
        try ProcessOwnership.writeOwnerIdentity(deadInProcess, in: runDir)

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        defer { ProcessOwnership.terminateSignalHook = nil }

        let reaped = try XCTUnwrap(store.reconcileRunDetailed(runId: "in-proc"))
        XCTAssertTrue(reaped.reaped)
        XCTAssertEqual(reaped.run.endReason, .reconciledOrphan)
        XCTAssertTrue(signals.isEmpty, "in-process owners must never be PG-killed")
    }

    // MARK: - Reads never kill

    func testLoadAndListNeverSignalOrWrite() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let runDir = try store.runDirectory(forRunId: "read-only")
        try writeJournal(nonTerminalRun(id: "read-only"), in: runDir)
        try ProcessOwnership.writeOwnerIdentity(
            .init(pid: 2_000_000, pgid: 2_000_000, startTimeTicks: 1, kind: .detachedRunner),
            in: runDir
        )

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        defer { ProcessOwnership.terminateSignalHook = nil }

        _ = store.load(runId: "read-only")
        _ = store.list()
        XCTAssertTrue(signals.isEmpty, "load/list must never signal")
        XCTAssertEqual(store.loadRaw(runId: "read-only")?.status, .fanningOut,
                       "load must not write terminal status")
    }

    // MARK: - endReason never inferred on save

    func testTerminalSaveDoesNotInferEndReason() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var run = nonTerminalRun(id: "done-1")
        run.status = .complete
        // endReason deliberately nil — save must NOT invent one.
        try store.save(run, models: [])
        let loaded = try XCTUnwrap(store.load(runId: "done-1"))
        XCTAssertEqual(loaded.status, .complete)
        XCTAssertNil(loaded.endReason)
    }

    func testCancelEndReasonViaAsyncService() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-cancel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let team = TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan, defaultEffort: .low,
            isDefaultForLane: true,
            workerSpecs: [TeamAgentSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
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

    // MARK: - Heartbeat / identity helpers

    func testProgressHeartbeatSequenceAndStaleFlag() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hb-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try ProcessOwnership.recordProgress(in: dir, phase: "accepted")
        let first = try XCTUnwrap(ProcessOwnership.readProgressHeartbeat(in: dir))
        XCTAssertEqual(first.sequence, 1)
        XCTAssertFalse(ProcessOwnership.isProgressStale(in: dir))

        try setProgressAge(in: dir, ageSeconds: 120)
        XCTAssertTrue(ProcessOwnership.isProgressStale(in: dir))
    }

    func testProcessAliveAndStartTimeSelf() {
        let pid = ProcessInfo.processInfo.processIdentifier
        XCTAssertTrue(ProcessOwnership.processAlive(pid))
        XCTAssertFalse(ProcessOwnership.processAlive(2_000_000))
        XCTAssertFalse(ProcessOwnership.processAlive(0))
        XCTAssertNotNil(ProcessOwnership.processStartTimeTicks(pid))
        XCTAssertNotNil(ProcessOwnership.currentExecutablePath())
    }

    // MARK: - TeamRunJSON / status endReason projection (never inferred)

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

    func testStatusResponseDoesNotInferEndReason() {
        var run = nonTerminalRun(id: "status-end")
        run.status = .failed
        // nil endReason must stay nil (never inferred).
        let status = AsyncTeamStatusMapper.statusResponse(for: run)
        XCTAssertNil(status.endReason)
        XCTAssertEqual(status.status, .failed)

        run.endReason = .failed
        let stamped = AsyncTeamStatusMapper.statusResponse(for: run)
        XCTAssertEqual(stamped.endReason, "failed")
    }

    func testUnknownEndReasonIsHonest() {
        XCTAssertTrue(RunEndReason.allCases.contains(.unknown))
        XCTAssertEqual(RunEndReason.unknown.rawValue, "unknown")
    }
}

// MARK: - TOCTOU / idempotency detached seams

final class ProcessOwnershipStartSeamTests: XCTestCase {

    /// Governor full → typed error synchronously, no accepted run dir, no runner.
    func testGovernorBusyRefusesWithoutAcceptedRunDir() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-toctou-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let team = TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan, defaultEffort: .low,
            isDefaultForLane: true,
            workerSpecs: [TeamAgentSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"),
            builtIn: true
        )
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "# Plan\nOk.", delay: .seconds(30))])
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ALLNIGHTER_TEAM_DEPTH")

        let govDir = root.appendingPathComponent("gov")
        let governor = TeamGovernor(directory: govDir, capacity: 1)
        // Exhaust the only slot so availability() is busy.
        guard case .acquired(let holder) = governor.acquireDetailed() else {
            return XCTFail("expected to hold the single governor slot")
        }
        defer { _ = holder }

        let runsDir = root.appendingPathComponent("Runs")
        let service = AsyncTeamService(
            models: [opus],
            registry: registry,
            teams: [team],
            config: ToolConfig(maxConcurrentTeamRuns: 1, maxTeamRunDepth: 1),
            runStore: RunStore(rootDirectory: runsDir),
            commandRunner: mock,
            governor: TeamGovernor(directory: govDir, capacity: 1),
            idempotency: IdempotencyStore(fileURL: root.appendingPathComponent("idempotency.json")),
            environment: env,
            idFactory: { "should-not-exist" }
        )

        // Start still consults availability before minting anything.
        let outcome = await service.start(
            AsyncTeamStartRequest(question: "x", lane: .code, teamPresetId: "code_test", effort: .low),
            origin: .cli,
            readyModels: [opus]
        )
        guard case .failure(let refusal) = outcome else {
            return XCTFail("expected TEAM_GOVERNOR_BUSY, got success")
        }
        XCTAssertEqual(refusal.code, "TEAM_GOVERNOR_BUSY")

        let entries = (try? FileManager.default.contentsOfDirectory(atPath: runsDir.path)) ?? []
        XCTAssertTrue(entries.filter { $0.hasPrefix("run_") }.isEmpty,
                      "no run dir left in accepted state when governor is busy")
    }

    /// Same start submitted twice → one run id, one runner identity (idempotency).
    func testIdempotentStartReturnsSameRunId() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-idem-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let team = TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan, defaultEffort: .low,
            isDefaultForLane: true,
            workerSpecs: [TeamAgentSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"),
            builtIn: true
        )
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "# Plan\nOk.", delay: .seconds(2))])
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ALLNIGHTER_TEAM_DEPTH")
        let idem = IdempotencyStore(fileURL: root.appendingPathComponent("idempotency.json"))
        final class IdCounter: @unchecked Sendable {
            private var n = 0
            private let lock = NSLock()
            func next() -> String {
                lock.lock(); defer { lock.unlock() }
                n += 1
                return "run-idem-\(n)"
            }
        }
        let ids = IdCounter()
        let service = AsyncTeamService(
            models: [opus],
            registry: registry,
            teams: [team],
            config: ToolConfig(maxConcurrentTeamRuns: 2, maxTeamRunDepth: 1),
            runStore: RunStore(rootDirectory: root.appendingPathComponent("Runs")),
            commandRunner: mock,
            governor: TeamGovernor(directory: root.appendingPathComponent("gov"), capacity: 2),
            idempotency: idem,
            environment: env,
            idFactory: { ids.next() }
        )
        let req = AsyncTeamStartRequest(
            question: "same", lane: .code, teamPresetId: "code_test",
            effort: .low, idempotencyKey: "key-po-s01"
        )
        let first = await service.start(req, origin: .cli, readyModels: [opus])
        let second = await service.start(req, origin: .cli, readyModels: [opus])
        guard case .success(let a) = first, case .success(let b) = second else {
            return XCTFail("expected both starts to succeed")
        }
        XCTAssertEqual(a.runId, b.runId)
        XCTAssertEqual(a.runId, "run-idem-1")
        let runs = (try? FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent("Runs").path
        )) ?? []
        XCTAssertEqual(runs.filter { $0.hasPrefix("run_") }.count, 1,
                       "double-submit must not mint a second run directory")
        _ = await service.cancel(runId: a.runId)
    }
}
