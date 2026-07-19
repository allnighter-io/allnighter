import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine

/// Journal0: incremental durability + orphan recovery. A non-terminal run whose
/// owning process is gone must read back as `interrupted` — never absent, never
/// falsely `running`.
final class RunStoreJournalTests: XCTestCase {

    private func tempStore() -> (RunStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("journal-\(UUID().uuidString)")
        return (RunStore(rootDirectory: dir), dir)
    }

    private func run(_ id: String, status: RunStatus) -> TeamRun {
        TeamRun(id: id, prompt: "p", status: status,
                workers: [Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0)],
                workerAnswers: [TeamAnswer(memberId: "model_opus#0", modelId: "model_opus", role: "answer",
                                           result: WorkerRunResult(status: status.isTerminal ? .done : .running))],
                createdAt: Date())
    }

    // MARK: - interrupted is terminal (TeamRun lifecycle)

    func testInterruptedIsTerminal() {
        XCTAssertTrue(RunStatus.interrupted.isTerminal)
        XCTAssertTrue(RunStatus.interrupted.allowedTransitions().isEmpty)
        // Any active state may transition to interrupted (orphan recovery).
        XCTAssertTrue(run("r", status: .fanningOut).canTransition(to: .interrupted))
        XCTAssertTrue(run("r", status: .planning).canTransition(to: .interrupted))
    }

    // MARK: - incremental durability + liveness marker

    func testNonTerminalSaveWritesLivenessMarkerThenTerminalClearsIt() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let runDir = try store.runDirectory(forRunId: "r1")
        let owner = ProcessOwnership.ownerURL(in: runDir)

        // Durable before workers finish: a non-terminal save persists run.json + identity.
        try store.save(run("r1", status: .fanningOut), models: [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDir.appendingPathComponent("run.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: owner.path), "non-terminal run records owner identity")
        let identity = try XCTUnwrap(ProcessOwnership.readOwnerIdentity(in: runDir))
        XCTAssertEqual(identity.pid, ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(identity.kind, .inProcess)
        XCTAssertNil(identity.pgid, "in-process owners never record a pgid")

        // Terminal save clears the marker (clean run leaves no stale liveness).
        try store.save(run("r1", status: .complete), models: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: owner.path))
    }

    // MARK: - orphan recovery on read

    func testOrphanWithNoMarkerResolvesToInterrupted() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Simulate a crash LONG AFTER staging (F2 liveness lease): non-terminal
        // state, no owner, no stage lease, createdAt past the staging window —
        // the legacy orphan, which stays reclaimable ("missing ⇒ dead" holds
        // only once the run can no longer be mid-handoff).
        let runDir = try store.runDirectory(forRunId: "orphan")
        var crashed = run("orphan", status: .planning)
        crashed.createdAt = Date().addingTimeInterval(-(ProcessOwnership.stageLeaseSeconds + 60))
        try CoreJSON.encode(crashed).write(to: runDir.appendingPathComponent("run.json"))

        // Reload: never absent, never falsely running — resolves to interrupted.
        XCTAssertEqual(store.load(runId: "orphan")?.status, .interrupted)
        XCTAssertEqual(store.list().first(where: { $0.id == "orphan" })?.status, .interrupted)
    }

    /// F2 liveness lease: a no-marker run INSIDE the staging window is not an
    /// orphan — its ownership handoff may still be in flight, so reads keep its
    /// own status and reconcile stays away (never "missing ⇒ dead").
    func testYoungNoMarkerRunReadsAsStagingNotInterrupted() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let runDir = try store.runDirectory(forRunId: "staging")
        try CoreJSON.encode(run("staging", status: .planning)).write(to: runDir.appendingPathComponent("run.json"))

        XCTAssertEqual(store.load(runId: "staging")?.status, .planning)
        XCTAssertFalse(store.wouldReconcile(runId: "staging"))
    }

    func testOrphanWithDeadPidResolvesToInterrupted() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let runDir = try store.runDirectory(forRunId: "crashed")
        try CoreJSON.encode(run("crashed", status: .answersIn)).write(to: runDir.appendingPathComponent("run.json"))
        // Identity pointing at a pid that is not alive (well above macOS max pid).
        try ProcessOwnership.writeOwnerIdentity(
            .init(pid: 2_000_000, pgid: 2_000_000, startTimeTicks: 1, kind: .detachedRunner),
            in: runDir
        )

        XCTAssertEqual(store.load(runId: "crashed")?.status, .interrupted)
    }

    func testLiveNonTerminalRunIsNotInterrupted() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // A non-terminal run owned by THIS (alive) process must NOT be interrupted.
        try store.save(run("live", status: .fanningOut), models: [])
        XCTAssertEqual(store.load(runId: "live")?.status, .fanningOut)
    }

    func testTerminalRunReadsBackUnchanged() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.save(run("done", status: .complete), models: [])
        XCTAssertEqual(store.load(runId: "done")?.status, .complete)
        XCTAssertNil(store.load(runId: "missing"))
    }

    func testProcessAliveDetectsSelfAndRejectsDead() {
        XCTAssertTrue(RunStore.processAlive(ProcessInfo.processInfo.processIdentifier))
        XCTAssertFalse(RunStore.processAlive(2_000_000))
        XCTAssertFalse(RunStore.processAlive(0))
        XCTAssertFalse(RunStore.processAlive(-1))
    }

    // MARK: - incremental persistence ordering (durable before workers run)

    final class StatusLog: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(RunStatus, Int)] = []
        func add(_ status: RunStatus, answered: Int) { lock.withLock { entries.append((status, answered)) } }
        var all: [(RunStatus, Int)] { lock.withLock { entries } }
    }

    func testCoordinatorPersistsBeforeWorkersAndOnEachTransition() async {
        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "# Plan\nDo it.", exitCode: 0)])
        let team = TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan, defaultEffort: .low,
            workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"))
        let resolved = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .low, readyModels: [opus])
        XCTAssertTrue(resolved.isRunnable)

        let log = StatusLog()
        let coordinator = CatalogRunCoordinator(workerRunner: DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(mock)), registry: registry)
        _ = await coordinator.run(resolved: resolved, prompt: "p", models: [opus]) { run in
            log.add(run.status, answered: run.answeredWorkers.count)
        }

        let entries = log.all
        XCTAssertGreaterThanOrEqual(entries.count, 3, "expected running + post-answer + terminal persists")
        // First write is durable BEFORE any worker produced an answer. RLR-L3:
        // `code_test` is a one-worker fan-out, so it opens at `running`, not `fanning_out`.
        XCTAssertEqual(entries.first?.0, .running)
        XCTAssertEqual(entries.first?.1, 0)
        // A later write reflects settled workers.
        XCTAssertTrue(entries.contains { $0.1 > 0 })
        // The final write is terminal.
        XCTAssertEqual(entries.last?.0, .complete)
        XCTAssertTrue(entries.last!.0.isTerminal)
    }

    func testCoordinatorPersistsRunningWorkersBeforeAnswersSettle() async throws {
        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "# Plan\nDo it.", delay: .milliseconds(400))])
        let team = TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan, defaultEffort: .low,
            workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"))
        let resolved = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .low, readyModels: [opus])
        let store = RunStore(rootDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-running-\(UUID().uuidString)", isDirectory: true))
        try FileManager.default.createDirectory(at: store.rootDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: store.rootDirectory) }

        final class RunningFlag: @unchecked Sendable {
            private let lock = NSLock()
            private var value = false
            func set() { lock.withLock { value = true } }
            var get: Bool { lock.withLock { value } }
        }
        let sawRunningPersist = RunningFlag()
        let coordinator = CatalogRunCoordinator(workerRunner: DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(mock)), registry: registry)
        let run = await coordinator.run(
            resolved: resolved, prompt: "p", models: [opus], runId: "status-live",
            persist: { saved in
                _ = try? store.save(saved, models: [opus])
                if saved.workerAnswers.contains(where: { $0.result.status == .running }) {
                    sawRunningPersist.set()
                    let status = AsyncTeamStatusMapper.statusResponse(for: saved)
                    XCTAssertEqual(status.status, .running)
                    XCTAssertEqual(status.workers.first?.status, "running")
                }
            })
        XCTAssertTrue(sawRunningPersist.get, "team_status must observe running workers during fan-out")
        XCTAssertEqual(run.status, .complete)
    }

    func testCoordinatorSnapshotsResolvedWorkerPrompts() async throws {
        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "# Plan\nDo it.", exitCode: 0)])
        let team = TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan, defaultEffort: .low,
            workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"))
        let resolved = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .low, readyModels: [opus])
        let coordinator = CatalogRunCoordinator(workerRunner: DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(mock)), registry: registry)
        let run = await coordinator.run(resolved: resolved, prompt: "founder prompt", models: [opus])
        let answerWorker = run.workers.first { $0.skillId == "bug_reproducer" }
        XCTAssertNotNil(answerWorker?.resolvedWorkerPromptSnapshot)
        XCTAssertTrue(answerWorker?.resolvedWorkerPromptSnapshot?.contains("founder prompt") == true)
        XCTAssertTrue(answerWorker?.resolvedWorkerPromptSnapshot?.contains("smallest reproducible") == true)
    }

    func testRunSnapshotSurvivesSkillEdit() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let teamsRoot = base.appendingPathComponent("teams", isDirectory: true)
        let skillsRoot = base.appendingPathComponent("skills", isDirectory: true)
        CatalogRoots.overrideForTesting(teams: teamsRoot, skills: skillsRoot)
        defer {
            CatalogRoots.resetTestingOverrides()
            try? FileManager.default.removeItem(at: base)
        }

        var skill = try SkillCatalog.duplicateBuiltIn("contrarian_reviewer", name: "WT Code Contrarian")
        skill.template = "WT Code Contrarian: challenge every assumption."
        try SkillCatalog.saveCustom(skill)

        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "# Plan\nDone.", exitCode: 0)])
        var team = try TeamCatalog.duplicateBuiltIn("code_plan", name: "Snapshot Team")
        team.workerSpecs = [TeamWorkerSpec(id: "row1", skillId: skill.id, purpose: .answer)]
        team.lead = TeamLeadSpec(skillId: "plan_writer_build")
        try TeamCatalog.saveCustom(team)

        let resolved = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .low, readyModels: [opus])
        let coordinator = CatalogRunCoordinator(workerRunner: DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(mock)), registry: registry)
        let run = await coordinator.run(resolved: resolved, prompt: "question", models: [opus])
        let snapshot = run.workers.first { $0.skillId == skill.id }?.resolvedWorkerPromptSnapshot
        XCTAssertTrue(snapshot?.contains("WT Code Contrarian") == true)

        var edited = skill
        edited.template = "Completely different template after edit."
        try SkillCatalog.saveCustom(edited)
        XCTAssertEqual(SkillCatalog.get(skill.id)?.template, "Completely different template after edit.")

        let full = TeamRunJSONMapper.map(
            run, models: [opus], manifests: registry.all,
            context: .init(runJournalPath: "/tmp/run.json", includeWorkerPromptSnapshots: true))
        let worker = full.workers.first { $0.skillId == skill.id }
        XCTAssertTrue(worker?.resolvedWorkerPromptSnapshot?.contains("WT Code Contrarian") == true)
        XCTAssertFalse(worker?.resolvedWorkerPromptSnapshot?.contains("Completely different") == true)
    }

    func testOrphanAsyncRunResolvesToInterrupted() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let runDir = try store.runDirectory(forRunId: "async-orphan")
        try CoreJSON.encode(TeamRun(
            id: "async-orphan", prompt: "p", status: .fanningOut,
            workers: [Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0)],
            workerAnswers: [TeamAnswer(memberId: "model_opus#0", modelId: "model_opus", role: "answer",
                                       result: WorkerRunResult(status: .running))],
            createdAt: Date()
        )).write(to: runDir.appendingPathComponent("run.json"))
        try ProcessOwnership.writeOwnerIdentity(
            .init(pid: 2_000_000, pgid: 2_000_000, startTimeTicks: 1, kind: .detachedRunner),
            in: runDir
        )
        XCTAssertEqual(store.load(runId: "async-orphan")?.status, .interrupted)
    }
}
