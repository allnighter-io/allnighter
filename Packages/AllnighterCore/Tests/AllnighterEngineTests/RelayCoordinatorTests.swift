import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// R-S04 works test: the RelayCoordinator loop against a real git repo and a scripted
/// (never-real-network) worker CLI, mirroring PairCoordinatorTests' seam — a custom
/// `CommandRunner` double keyed by command name, here extended to (a) return a DIFFERENT
/// scripted answer on each successive call to the same command (a relay's PM seat is
/// called more than once per relay) and (b) capture the args each call received so tests
/// can assert on the ACTUAL prompt text a turn was given (e.g. that a resumed relay's
/// founder note really reached the PM prompt).
final class RelayCoordinatorTests: XCTestCase {
    private var tmp: URL!

    /// `CoreJSON` encodes dates as ISO-8601 without fractional seconds, so a raw
    /// `Date()` fixture never round-trips byte-for-byte through disk. Tests that assert
    /// on a reloaded `RelayState` equalling the in-memory one inject this instead of
    /// `Date.init` so both sides already carry whole-second precision.
    private static func flooredNow() -> Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Fixtures

    private func runGit(_ args: [String], cwd: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd.path] + args
        p.standardOutput = Pipe(); p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    @discardableResult
    private func makeGitRepo() throws -> URL {
        let dir = tmp.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for a in [["init", "-q"], ["config", "user.email", "t@t.dev"], ["config", "user.name", "T"],
                  ["config", "commit.gpgsign", "false"]] { runGit(a, cwd: dir) }
        try "spec".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        runGit(["add", "."], cwd: dir)
        runGit(["commit", "-q", "-m", "c1"], cwd: dir)
        return dir
    }

    private func makeService(
        pmScripts: [MockCommandRunner.Script],
        devScripts: [MockCommandRunner.Script],
        runStore: RunStore
    ) -> (RunService, SequencedCommandRunner) {
        let pmModel = Model(id: "model_pm", displayName: "PM", modelLabel: "pm", driverId: "pm_cli", role: .both)
        let devModel = Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "dev_cli", role: .both)
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: "pm_cli", command: "pm_cli"),
            TestSupport.headlessManifest(id: "dev_cli", command: "dev_cli"),
        ])
        let runner = SequencedCommandRunner(queues: ["pm_cli": pmScripts, "dev_cli": devScripts])
        let service = RunService(
            models: [pmModel, devModel],
            registry: registry,
            runStore: runStore,
            commandRunner: runner,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { DefaultModelSettings() },
            probeRecords: { [] }
        )
        return (service, runner)
    }

    private func verdictJSON(_ verdict: String, handover: String? = nil, note: String? = nil) -> String {
        var fields = ["\"verdict\": \"\(verdict)\""]
        if let handover { fields.append("\"handover\": \"\(handover)\"") }
        if let note { fields.append("\"note\": \"\(note)\"") }
        return "```json\n{\(fields.joined(separator: ", "))}\n```"
    }

    // MARK: - Happy path

    func testHappyTwoRoundRelayEndsInDone() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1 review.\n\n" + verdictJSON("continue", handover: "Implement the thing.")),
            .init(stdout: "Round 2 review, dev delivered.\n\n" + verdictJSON("done", note: "All criteria met.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Implemented and committed. Verified with `true`."),
        ]
        let (service, _) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", maxRounds: 5
        )
        let state = await coordinator.run(config: config)

        XCTAssertEqual(state.status, .done)
        XCTAssertEqual(state.note, "All criteria met.")
        XCTAssertEqual(state.rounds.count, 2)
        XCTAssertEqual(state.rounds[0].outcome, .continued)
        XCTAssertEqual(state.rounds[0].verdict?.verdict, .continueRelay)
        XCTAssertNotNil(state.rounds[0].pmRunId)
        XCTAssertNotNil(state.rounds[0].devRunId)
        XCTAssertNotNil(state.rounds[0].baselineHead)
        XCTAssertEqual(state.rounds[1].outcome, .done)
        XCTAssertEqual(state.rounds[1].verdict?.verdict, .done)
        // Round 2's PM prompt should have threaded round 1's dev report + head range —
        // verified indirectly: round 2 dispatched at all (there'd be no second PM call
        // otherwise) and the relay reached `done` only via round 2's verdict.
    }

    // MARK: - Verdict re-ask

    func testContinueWithoutHandoverTriggersReaskThenContinues() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "No verdict tail here at all."),
            .init(stdout: "Recovered.\n\n" + verdictJSON("continue", handover: "Do the thing.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [.init(stdout: "Done, committed.")]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", maxRounds: 1
        )
        let state = await coordinator.run(config: config)

        XCTAssertEqual(runner.callCount(for: "pm_cli"), 2, "first attempt + one re-ask")
        XCTAssertEqual(state.rounds.count, 1)
        XCTAssertEqual(state.rounds[0].outcome, .continued)
        XCTAssertEqual(state.rounds[0].verdict?.verdict, .continueRelay)
        XCTAssertNotNil(state.rounds[0].devRunId)
        // maxRounds: 1 means round 2 never starts — the relay stops on the ceiling right
        // after the successful re-ask round, proving the re-ask path itself works.
        XCTAssertEqual(state.status, .stopped)
        XCTAssertEqual(state.stoppedReason, "reached --max-rounds (1)")
    }

    func testReaskFailsEscalates() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "No verdict at all."),
            .init(stdout: "Still no verdict tail."),
        ]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev"
        )
        let state = await coordinator.run(config: config)

        XCTAssertEqual(runner.callCount(for: "pm_cli"), 2)
        XCTAssertEqual(state.status, .escalated)
        XCTAssertEqual(state.rounds.count, 1)
        XCTAssertEqual(state.rounds[0].outcome, .escalated)
        XCTAssertTrue(state.note?.contains("re-ask") ?? false)
    }

    // MARK: - HandoverGate

    func testGateBlockedHandoverEscalatesWithDangerClassInNote() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let dangerousHandover = "Run git reset --hard on main to clean this up."
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Reviewed.\n\n" + verdictJSON("continue", handover: dangerousHandover)),
        ]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev"
        )
        let state = await coordinator.run(config: config)

        XCTAssertEqual(runner.callCount(for: "dev_cli"), 0, "the dev turn must never dispatch on a blocked handover")
        XCTAssertEqual(state.status, .escalated)
        XCTAssertEqual(state.rounds[0].gate?.allowed, false)
        XCTAssertEqual(state.rounds[0].gate?.dangerClass, "destructiveGit")
        XCTAssertTrue(state.note?.contains("destructiveGit") ?? false)
        XCTAssertTrue(state.note?.contains("RELAY_HANDOVER_UNSAFE") ?? false)
    }

    // MARK: - Ceilings

    func testMaxRoundsStops() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Keep going.\n\n" + verdictJSON("continue", handover: "Keep building.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [.init(stdout: "Some progress, no commit this time.")]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev",
            maxRounds: 2, stagnationRoundCap: 10
        )
        let state = await coordinator.run(config: config)

        XCTAssertEqual(state.status, .stopped)
        XCTAssertEqual(state.stoppedReason, "reached --max-rounds (2)")
        XCTAssertEqual(state.rounds.count, 2)
        XCTAssertEqual(runner.callCount(for: "pm_cli"), 2)
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 2)
    }

    func testStagnationStops() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Same flag again.\n\n" + verdictJSON("continue", handover: "Please fix the same thing.")),
        ]
        // The dev CLI is scripted, never touches git — the repo genuinely does not change,
        // which is exactly the deadlock signature stagnation exists to catch.
        let devScripts: [MockCommandRunner.Script] = [.init(stdout: "I tried again but nothing changed.")]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev",
            maxRounds: 20, stagnationRoundCap: 2
        )
        let state = await coordinator.run(config: config)

        XCTAssertEqual(state.status, .stopped)
        XCTAssertTrue(state.stoppedReason?.contains("stagnation") ?? false)
        XCTAssertEqual(state.rounds.count, 2, "stops right after the 2nd consecutive no-change round")
        XCTAssertEqual(runner.callCount(for: "pm_cli"), 2)
    }

    // MARK: - Resume

    func testResumeAfterEscalateInjectsFounderNoteIntoNextPMTurn() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "I need to know which env.\n\n" + verdictJSON("escalate", note: "staging or prod?")),
        ]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            idFactory: { "relay_resume_test" }
        )
        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev"
        )
        let escalated = await coordinator.run(config: config)
        XCTAssertEqual(escalated.status, .escalated)
        XCTAssertEqual(escalated.id, "relay_resume_test")

        // Resume: the PM now delivers `done`. Assert the founder's answer actually reached
        // the PM prompt text for the resumed round (not just that the loop continued).
        runner.enqueue(command: "pm_cli", .init(stdout: "Using staging.\n\n" + verdictJSON("done", note: "Shipped to staging.")))
        let resumedConfig = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", maxRounds: 5
        )
        let resumed = await coordinator.resume(relayId: "relay_resume_test", founderAnswer: "use staging", config: resumedConfig)

        XCTAssertEqual(resumed?.status, .done)
        XCTAssertEqual(resumed?.rounds.count, 2)
        XCTAssertNil(resumed?.founderNote, "consumed after the first post-resume PM turn")

        let secondCallArgs = runner.capturedArgs(for: "pm_cli").last ?? []
        XCTAssertTrue(secondCallArgs.joined(separator: " ").contains("use staging"), "founder note must reach the PM prompt verbatim")
    }

    func testResumeOnNonEscalatedRelayReturnsNil() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let pmScripts: [MockCommandRunner.Script] = [.init(stdout: "Done.\n\n" + verdictJSON("done", note: "ok"))]
        let (service, _) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            idFactory: { "relay_done_test" }
        )
        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "model_pm", devWorkerId: "model_dev"
        )
        let done = await coordinator.run(config: config)
        XCTAssertEqual(done.status, .done)

        let result = await coordinator.resume(relayId: "relay_done_test", founderAnswer: "irrelevant", config: config)
        XCTAssertNil(result)
    }

    // MARK: - Durability

    func testStatePersistedAfterEachRoundNotOnlyAtTheEnd() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Build it.")),
            .init(stdout: "Round 2, done.\n\n" + verdictJSON("done", note: "Shipped.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [.init(stdout: "Built and committed.")]
        let (service, _) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = RelayCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            now: Self.flooredNow, idFactory: { "relay_durability_test" }
        )
        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", maxRounds: 5
        )

        let midRelayRoundCount = LockedBox<Int?>(nil)
        let final = await coordinator.run(config: config) { event in
            if case .devTurnFinished(let round) = event, round == 1 {
                // The relay is still mid-flight (round 2 hasn't started) — the loaded
                // on-disk state must already reflect round 1's completed dev turn.
                midRelayRoundCount.value = stateStore.load(id: "relay_durability_test")?.rounds.count
            }
        }

        XCTAssertEqual(midRelayRoundCount.value, 1)
        XCTAssertEqual(final.status, .done)

        let reloaded = stateStore.load(id: "relay_durability_test")
        XCTAssertEqual(reloaded, final)
    }

    // MARK: - Orphan reconciliation (works-test hazard #1)

    /// Simulates `RelayCoordinator.run()`'s own bootstrap up through the exact durable
    /// checkpoint a real relay leaves on disk the instant it dispatches round 1's PM turn —
    /// `started` (creates the thread), append the round, `save` (records THIS test
    /// process's pid as owner) — then overwrites the marker with a pid that cannot
    /// possibly be alive (mirrors `RunStoreJournalTests.testOrphanWithDeadPidResolvesToInterrupted`)
    /// to stand in for "the process was killed mid-round."
    @discardableResult
    private func makeOrphanedRunningRelay(
        id: String, projectRoot: String, stateStore: RelayStateStore, projector: RelayThreadProjector
    ) throws -> RelayState {
        var state = RelayState(
            id: id, projectRoot: projectRoot, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running, createdAt: Self.flooredNow()
        )
        projector.started(state: state, projectId: nil)
        state.rounds.append(RelayRound(roundNumber: 1, baselineHead: "abc123", startedAt: Self.flooredNow()))
        try stateStore.save(state)
        projector.sync(state: state, now: Self.flooredNow())

        let ownerURL = stateStore.rootDirectory.appendingPathComponent(id, isDirectory: true).appendingPathComponent("owner.pid")
        try Data("2000000".utf8).write(to: ownerURL)
        return state
    }

    func testStatusReconcilesDeadOwnerRunningRelayAndSettlesTheThread() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let threadStore = ThreadStore(rootDirectory: tmp.appendingPathComponent("threads"))
        let projector = RelayThreadProjector(store: threadStore, runStore: runStore)
        try makeOrphanedRunningRelay(id: "relay_orphan_status", projectRoot: tmp.path, stateStore: stateStore, projector: projector)

        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, threadProjector: projector)

        let reconciled = coordinator.status(relayId: "relay_orphan_status")
        XCTAssertEqual(reconciled?.status, .stopped)
        XCTAssertEqual(reconciled?.stoppedReason, RelayState.orphanReconciledReason)
        XCTAssertEqual(reconciled?.rounds.last?.outcome, .stopped)

        // Durable: a fresh read (a different process re-opening the same file) sees the
        // SAME reconciled result, not just an in-memory view.
        XCTAssertEqual(stateStore.load(id: "relay_orphan_status")?.status, .stopped)

        // Thread projection settled: the open PM turn closes, and a stopped system event lands.
        let thread = threadStore.get("relay_orphan_status")
        XCTAssertEqual(thread?.turn(id: "relay_orphan_status_pm1")?.status, .cancelled)
        let stopped = thread?.turn(id: "relay_orphan_status_stopped")
        XCTAssertNotNil(stopped)
        XCTAssertEqual(stopped?.text, RelayState.orphanReconciledReason)
    }

    func testResumeAfterOrphanReconciliationContinuesFromLastDurableRound() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let threadStore = ThreadStore(rootDirectory: tmp.appendingPathComponent("threads"))
        let projector = RelayThreadProjector(store: threadStore, runStore: runStore)
        try makeOrphanedRunningRelay(id: "relay_resume_after_kill", projectRoot: repo.path, stateStore: stateStore, projector: projector)

        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Recovered after kill.\n\n" + verdictJSON("done", note: "Finished after resume.")),
        ]
        let (service, _) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, threadProjector: projector)

        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", maxRounds: 5
        )
        let resumed = await coordinator.resume(relayId: "relay_resume_after_kill", founderAnswer: "continue please", config: config)

        XCTAssertEqual(resumed?.status, .done)
        // The killed round stays recorded as stopped — reconciliation never silently
        // erases it, it settles it — and the resumed attempt is a NEW round after it.
        XCTAssertEqual(resumed?.rounds.count, 2)
        XCTAssertEqual(resumed?.rounds.first?.outcome, .stopped)
        XCTAssertEqual(resumed?.rounds.last?.outcome, .done)
    }

    func testResumeNeverAcceptsADoneRelayEvenThoughReconciliationOnlyTouchesRunning() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let state = RelayState(
            id: "relay_done_never_resumable", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .done, createdAt: Date(), note: "Shipped."
        )
        try stateStore.save(state)

        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = RelayCoordinator.Config(
            projectRoot: "/repo", docPath: "docs/spec.md", pmWorkerId: "model_pm", devWorkerId: "model_dev"
        )
        let result = await coordinator.resume(relayId: "relay_done_never_resumable", founderAnswer: "anything", config: config)
        XCTAssertNil(result)
        XCTAssertEqual(stateStore.load(id: "relay_done_never_resumable")?.status, .done, "never mutated")
    }

    /// A ceiling-fired `.stopped` relay (`--max-rounds`/`--until`/stagnation) is a
    /// deliberate stop, not an orphan — `reconcileOrphan`'s `.running`-only guard means it
    /// is never mistaken for one, and `relay-resume` must keep refusing it.
    func testCeilingStoppedRelayIsNeitherReconciledNorResumable() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let state = RelayState(
            id: "relay_ceiling_stopped", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .stopped, createdAt: Date(),
            stoppedReason: "reached --max-rounds (5)"
        )
        try stateStore.save(state)

        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        XCTAssertEqual(coordinator.status(relayId: "relay_ceiling_stopped")?.stoppedReason, "reached --max-rounds (5)", "untouched by reconciliation")

        let config = RelayCoordinator.Config(
            projectRoot: "/repo", docPath: "docs/spec.md", pmWorkerId: "model_pm", devWorkerId: "model_dev"
        )
        let result = await coordinator.resume(relayId: "relay_ceiling_stopped", founderAnswer: "anything", config: config)
        XCTAssertNil(result)
    }
}

// MARK: - RelayStateStore

final class RelayStateStoreTests: XCTestCase {
    func testSaveLoadRoundTripAndList() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relaystore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = RelayStateStore(rootDirectory: tmp)
        let fixedNow = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        var round = RelayRound(roundNumber: 1, baselineHead: "abc123", startedAt: fixedNow)
        round.verdict = RelayVerdict(verdict: .continueRelay, handover: "do it")
        round.gate = RelayGateSummary(allowed: true)
        var state = RelayState(
            id: "relay_roundtrip", projectRoot: "/tmp/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running,
            rounds: [round], createdAt: fixedNow
        )
        try store.save(state)

        let loaded = store.load(id: "relay_roundtrip")
        XCTAssertEqual(loaded, state)

        state.status = .done
        state.note = "closing"
        try store.save(state)
        XCTAssertEqual(store.load(id: "relay_roundtrip")?.note, "closing")

        XCTAssertEqual(store.list().map(\.id), ["relay_roundtrip"])
    }

    func testLoadMissingReturnsNil() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relaystore-missing-\(UUID().uuidString)")
        let store = RelayStateStore(rootDirectory: tmp)
        XCTAssertNil(store.load(id: "does_not_exist"))
        XCTAssertEqual(store.list(), [])
    }

    // MARK: - owner.pid liveness marker (works-test hazard #1; mirrors RunStore)

    func testRunningSaveWritesOwnerPidThenTerminalSaveClearsIt() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relaystore-owner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = RelayStateStore(rootDirectory: tmp)
        let ownerURL = tmp.appendingPathComponent("relay_owner").appendingPathComponent("owner.pid")
        var state = RelayState(
            id: "relay_owner", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running, createdAt: Date()
        )
        try store.save(state)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownerURL.path), "a running relay records its owner pid")
        XCTAssertEqual(String(decoding: (try? Data(contentsOf: ownerURL)) ?? Data(), as: UTF8.self),
                       "\(ProcessInfo.processInfo.processIdentifier)")

        state.status = .done
        try store.save(state)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownerURL.path), "a terminal save clears the marker")
    }

    func testIsOwnerDeadTrueWhenMarkerMissingOrDeadFalseWhenAlive() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relaystore-dead-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = RelayStateStore(rootDirectory: tmp)

        // No relay folder at all — missing counts as dead (never assumed alive without proof).
        XCTAssertTrue(store.isOwnerDead(id: "relay_never_saved"))

        // A live owner (this test process) is not dead.
        let live = RelayState(
            id: "relay_live", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running, createdAt: Date()
        )
        try store.save(live)
        XCTAssertFalse(store.isOwnerDead(id: "relay_live"))

        // A marker naming a pid well above macOS's max — dead (mirrors
        // RunStoreJournalTests' `testOrphanWithDeadPidResolvesToInterrupted`).
        try Data("2000000".utf8).write(to: tmp.appendingPathComponent("relay_live").appendingPathComponent("owner.pid"))
        XCTAssertTrue(store.isOwnerDead(id: "relay_live"))
    }
}

// MARK: - RelayTurnClassifier

final class RelayTurnClassifierTests: XCTestCase {
    func testDeliveredOnDoneWithOutput() {
        let outcome = WorkerRunOutcome(status: .done, output: "the answer")
        XCTAssertEqual(RelayTurnClassifier.classify(.init(outcome: outcome)), .delivered(output: "the answer"))
    }

    func testEmptyResultOnDoneWithBlankOutput() {
        let outcome = WorkerRunOutcome(status: .done, output: "   \n")
        XCTAssertEqual(RelayTurnClassifier.classify(.init(outcome: outcome)), .emptyResult)
    }

    func testCompactionNeverClassifiedAsStalled() {
        let outcome = WorkerRunOutcome(status: .failed, output: "context compaction in progress, please retry")
        XCTAssertEqual(RelayTurnClassifier.classify(.init(outcome: outcome)), .compacting)
    }

    func testCompactionMarkerInReasoningAlsoWins() {
        let outcome = WorkerRunOutcome(status: .timedOut, reasoning: "running compaction now")
        XCTAssertEqual(RelayTurnClassifier.classify(.init(outcome: outcome)), .compacting)
    }

    func testInfraBackoffFromStructuredCapacityFact() {
        let observation = CapacityObservation(
            kind: .accountRateLimit, source: "pm_cli", sourceConfidence: .structured,
            rawSnippet: "rate limited", observedAt: Date())
        let outcome = WorkerRunOutcome(status: .failed, capacityObservation: observation)
        XCTAssertEqual(RelayTurnClassifier.classify(.init(outcome: outcome)), .infraBackoff)
    }

    func testInfraBackoffFromTextSniff() {
        let outcome = WorkerRunOutcome(status: .failed, errorReason: "429 rate limit exceeded")
        XCTAssertEqual(RelayTurnClassifier.classify(.init(outcome: outcome)), .infraBackoff)
    }

    func testStalledOnNotDoneWithoutInfraOrCompactionMarker() {
        let outcome = WorkerRunOutcome(status: .failed, errorReason: "unexpected exit")
        XCTAssertEqual(RelayTurnClassifier.classify(.init(outcome: outcome)), .stalled)
    }
}

/// Trivial `Sendable` mutable box for capturing a value inside an `@Sendable` events
/// closure (the events sink runs synchronously on whatever task calls it, but the
/// compiler can't see that without a lock).
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ initial: T) { stored = initial }
    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

// MARK: - Test double

/// A `CommandRunner` double keyed by command name, extending `MockCommandRunner`'s shape
/// (reuses its `Script`) with two things a relay's multi-turn-per-command loop needs that
/// a single static script can't express: (1) a DIFFERENT scripted answer per successive
/// call to the same command (`queues[command]` is consumed in order, repeating the last
/// entry once exhausted — mirrors `PairCoordinatorTests`' bespoke counting runners), and
/// (2) captured args per call, so a test can assert on the ACTUAL prompt text a turn
/// received (e.g. a resumed relay's founder note reaching the PM prompt).
final class SequencedCommandRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [String: [MockCommandRunner.Script]]
    private var counts: [String: Int] = [:]
    private var captured: [String: [[String]]] = [:]

    init(queues: [String: [MockCommandRunner.Script]]) {
        self.queues = queues
    }

    func enqueue(command: String, _ script: MockCommandRunner.Script) {
        lock.withLock { queues[command, default: []].append(script) }
    }

    func callCount(for command: String) -> Int {
        lock.withLock { counts[command, default: 0] }
    }

    func capturedArgs(for command: String) -> [[String]] {
        lock.withLock { captured[command, default: []] }
    }

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        let script: MockCommandRunner.Script = lock.withLock {
            let index = counts[command, default: 0]
            counts[command] = index + 1
            captured[command, default: []].append(args)
            let scripts = queues[command] ?? []
            return scripts.isEmpty ? MockCommandRunner.Script() : scripts[min(index, scripts.count - 1)]
        }

        if let launchError = script.launchError {
            return CommandResult(launchError: launchError)
        }
        try? await Task.sleep(for: script.delay)
        if script.forcesTimeout { return CommandResult(timedOut: true) }
        return CommandResult(stdout: script.stdout, stderr: script.stderr, exitCode: script.exitCode)
    }
}
