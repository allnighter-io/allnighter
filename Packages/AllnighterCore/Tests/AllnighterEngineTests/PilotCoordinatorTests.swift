import XCTest
import AllnighterCore
@testable import AllnighterCLI
@testable import AllnighterEngine

/// PL-S01/S02 works tests: Pilot (`docs/phases/Pilot_Relay.md`) is the SAME substrate
/// as the shipped PM Relay — `pmMode: .external`, a parked `awaitingPM` status between
/// rounds, and `RelayCoordinator.runExternalRound` standing in for a spawned PM turn.
/// Fixtures mirror `RelayCoordinatorTests` (real git repo, scripted dev CLI only — Pilot
/// never dispatches a PM seat at all).
final class PilotCoordinatorTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-pilot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Fixtures (mirrors RelayCoordinatorTests)

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
        devScripts: [MockCommandRunner.Script], runStore: RunStore, devDriverId: String = "dev_cli"
    ) -> (RunService, SequencedCommandRunner) {
        let devModel = Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: devDriverId, role: .both)
        let registry = DriverRegistry([TestSupport.headlessManifest(id: devDriverId, command: "dev_cli")])
        let runner = SequencedCommandRunner(queues: ["dev_cli": devScripts])
        let service = RunService(
            models: [devModel], registry: registry, runStore: runStore, commandRunner: runner,
            writeLock: RunWriteLockRegistry(), defaultSettings: { DefaultModelSettings() }, probeRecords: { [] }
        )
        return (service, runner)
    }

    private func verdictJSON(_ verdict: String, handover: String? = nil, note: String? = nil) -> String {
        var fields = ["\"verdict\": \"\(verdict)\""]
        if let handover { fields.append("\"handover\": \"\(handover)\"") }
        if let note { fields.append("\"note\": \"\(note)\"") }
        return "```json\n{\(fields.joined(separator: ", "))}\n```"
    }

    // MARK: - startPilot

    func testStartPilotCreatesParkedUnownedRelay() throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, _) = makeService(devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, idFactory: { "relay_pilot_1" })

        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "ignored", devWorkerId: "model_dev", maxRounds: 7
        )
        let result = coordinator.startPilot(config: config)
        guard case .success(let state) = result else { return XCTFail("expected success") }

        XCTAssertEqual(state.pmMode, .external)
        XCTAssertEqual(state.status, .awaitingPM)
        XCTAssertEqual(state.pmWorkerId, RelayState.externalPMWorkerId)
        XCTAssertEqual(state.devWorkerId, "model_dev")
        XCTAssertTrue(state.rounds.isEmpty)
        XCTAssertEqual(state.pilotMaxRounds, 7)

        // Durable: an awaitingPM save never writes an owner.pid marker.
        let ownerURL = stateStore.rootDirectory.appendingPathComponent("relay_pilot_1", isDirectory: true).appendingPathComponent("owner.pid")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownerURL.path))
    }

    func testStartPilotRejectsUntilAsUsageError() throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, _) = makeService(devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "ignored", devWorkerId: "model_dev", until: Date().addingTimeInterval(3600)
        )
        let result = coordinator.startPilot(config: config)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .untilNotSupported)
        XCTAssertEqual(stateStore.list().count, 0, "no relay is created on a rejected start")
    }

    // MARK: - runExternalRound: continue dispatches the dev turn only

    func testContinueDispatchesOneDevTurnAndParksBackToAwaitingPM() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, runner) = makeService(devScripts: [.init(stdout: "Implemented and committed.")], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, idFactory: { "relay_pilot_continue" })

        let started = coordinator.startPilot(config: .init(
            projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "model_dev"
        ))
        guard case .success = started else { return XCTFail("start failed") }

        let submission = "Reviewed the repo myself.\n\n" + verdictJSON("continue", handover: "Implement the thing.")
        let result = await coordinator.runExternalRound(relayId: "relay_pilot_continue", submission: submission)
        guard case .success(let payload) = result else { return XCTFail("expected success") }

        XCTAssertEqual(runner.callCount(for: "dev_cli"), 1)
        XCTAssertEqual(payload.state.status, .awaitingPM, "parks back between rounds — no clock")
        XCTAssertEqual(payload.state.rounds.count, 1)
        let round = try XCTUnwrap(payload.state.rounds.first)
        XCTAssertEqual(round.outcome, .continued)
        XCTAssertEqual(round.verdict?.verdict, .continueRelay)
        XCTAssertNil(round.pmRunId, "no PM turn ever dispatches in Pilot")
        XCTAssertNotNil(round.devRunId)
        XCTAssertNotNil(round.baselineHead)
        XCTAssertNotNil(round.headAfterDev)
        XCTAssertEqual(round.externalSubmission, submission, "run-truth stored verbatim, tail included")
        XCTAssertEqual(round.gate?.allowed, true)
        XCTAssertEqual(payload.devReport, "Implemented and committed.", "dev report returned verbatim in the same call")

        // Durable: the loaded on-disk state agrees.
        XCTAssertEqual(stateStore.load(id: "relay_pilot_continue")?.status, .awaitingPM)
    }

    // MARK: - PO-F7 dev-turn idle-timeout override (pilot)

    /// `pilot start --idle-timeout` is persisted onto `RelayState.pilotDevTurnIdleTimeoutSeconds`
    /// (Pilot has no long-lived process to re-supply `Config` at each later `pilot handoff`,
    /// same reasoning as `pilotMaxRounds`) and reaches `RunRequest.workerTimeoutSeconds` on
    /// the actual dev-turn dispatch.
    func testPilotStartIdleTimeoutPersistsAndReachesRunRequestOnHandoff() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let devModel = Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "dev_cli", role: .both)
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "dev_cli", command: "dev_cli")])
        let devSpy = TimeoutCapturingCommandRunner(
            inner: SequencedCommandRunner(queues: ["dev_cli": [.init(stdout: "Implemented and committed.")]])
        )
        let service = RunService(
            models: [devModel], registry: registry, runStore: runStore, commandRunner: devSpy,
            writeLock: RunWriteLockRegistry(), defaultSettings: { DefaultModelSettings() }, probeRecords: { [] }
        )
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, idFactory: { "relay_pilot_idle_timeout" })

        let started = coordinator.startPilot(config: .init(
            projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "model_dev",
            devTurnIdleTimeoutSeconds: 555
        ))
        guard case .success(let startedState) = started else { return XCTFail("start failed") }
        XCTAssertEqual(startedState.pilotDevTurnIdleTimeoutSeconds, 555, "persisted onto durable state at pilot start")

        let submission = "Reviewed the repo myself.\n\n" + verdictJSON("continue", handover: "Implement the thing.")
        let result = await coordinator.runExternalRound(relayId: "relay_pilot_idle_timeout", submission: submission)
        guard case .success = result else { return XCTFail("expected success") }

        XCTAssertEqual(
            devSpy.lastTimeout?.components.seconds, 555,
            "the durable pilotDevTurnIdleTimeoutSeconds must reach RunRequest.workerTimeoutSeconds on `pilot handoff`"
        )
    }

    /// P1: `--verdict continue --handover-file` delivers the order markdown byte-exact to
    /// the dev prompt through the real dispatch capture seam.
    func testHandoverFilePathDeliversHandoverByteExactToDev() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, runner) = makeService(devScripts: [.init(stdout: "Implemented and committed.")], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, idFactory: { "relay_pilot_handover_file" })

        _ = coordinator.startPilot(config: .init(
            projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "model_dev"
        ))

        let handover = """
        # PM Relay — round 1 (dev seat)

        Mention ```json fenced blocks in the handover prose.

        """
        let orderPath = tmp.appendingPathComponent("order.md")
        try handover.write(to: orderPath, atomically: true, encoding: .utf8)

        let submission = try PilotCLI.parseHandoffSubmission(Options([
            "--relay", "relay_pilot_handover_file", "--verdict", "continue",
            "--handover-file", orderPath.path,
        ]))
        let result = await coordinator.runExternalRound(relayId: "relay_pilot_handover_file", submission: submission)
        guard case .success = result else { return XCTFail("expected success") }

        XCTAssertEqual(runner.callCount(for: "dev_cli"), 1)
        let devArgs = runner.capturedArgs(for: "dev_cli").first ?? []
        let prompt: String
        if let index = devArgs.firstIndex(of: "-p"), index + 1 < devArgs.count {
            prompt = devArgs[index + 1]
        } else {
            prompt = devArgs.joined(separator: " ")
        }
        XCTAssertTrue(prompt.contains(handover), "dev prompt must carry the handover file text byte-exact")
    }

    func testDirtyTreeAtHandoffIsSnapshottedOnTheRound() async throws {
        let repo = try makeGitRepo()
        try "dirty".write(to: repo.appendingPathComponent("scratch.txt"), atomically: true, encoding: .utf8)
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, _) = makeService(devScripts: [.init(stdout: "Done.")], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, idFactory: { "relay_pilot_dirty" })
        _ = coordinator.startPilot(config: .init(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "model_dev"))

        let submission = "Go.\n\n" + verdictJSON("continue", handover: "Build it.")
        let result = await coordinator.runExternalRound(relayId: "relay_pilot_dirty", submission: submission)
        guard case .success(let payload) = result else { return XCTFail("expected success") }
        XCTAssertEqual(payload.state.rounds.first?.dirtyFiles, ["scratch.txt"])
    }

    // MARK: - runExternalRound: done / escalate settle immediately, no dev dispatch

    func testDoneSettlesRelayWithNoDevDispatch() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, runner) = makeService(devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, idFactory: { "relay_pilot_done" })
        _ = coordinator.startPilot(config: .init(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "model_dev"))

        let submission = "All acceptance criteria met.\n\n" + verdictJSON("done", note: "Shipped.")
        let result = await coordinator.runExternalRound(relayId: "relay_pilot_done", submission: submission)
        guard case .success(let payload) = result else { return XCTFail("expected success") }

        XCTAssertEqual(runner.callCount(for: "dev_cli"), 0)
        XCTAssertEqual(payload.state.status, .done)
        XCTAssertEqual(payload.state.note, "Shipped.")
        XCTAssertEqual(payload.state.rounds.count, 1)
        XCTAssertEqual(payload.state.rounds.first?.externalSubmission, submission)
        XCTAssertNil(payload.devReport)
    }

    func testEscalateParksRelayWithFounderQuestion() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, runner) = makeService(devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, idFactory: { "relay_pilot_escalate" })
        _ = coordinator.startPilot(config: .init(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "model_dev"))

        let submission = "Need to know which env.\n\n" + verdictJSON("escalate", note: "staging or prod?")
        let result = await coordinator.runExternalRound(relayId: "relay_pilot_escalate", submission: submission)
        guard case .success(let payload) = result else { return XCTFail("expected success") }

        XCTAssertEqual(runner.callCount(for: "dev_cli"), 0)
        XCTAssertEqual(payload.state.status, .escalated)
        XCTAssertEqual(payload.state.note, "staging or prod?")
    }

    // MARK: - runExternalRound: parse failure / gate block never create a round

    func testUnparseableSubmissionLeavesRelayAwaitingPMWithNoRound() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, runner) = makeService(devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, idFactory: { "relay_pilot_parse" })
        _ = coordinator.startPilot(config: .init(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "model_dev"))

        let result = await coordinator.runExternalRound(relayId: "relay_pilot_parse", submission: "No verdict tail here at all.")
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .verdictUnparseable(.noVerdictFound))
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 0)

        let reloaded = stateStore.load(id: "relay_pilot_parse")
        XCTAssertEqual(reloaded?.status, .awaitingPM, "no re-ask machinery — stays parked for the human to resubmit")
        XCTAssertTrue(reloaded?.rounds.isEmpty ?? false, "a parse failure never lands a round on the ledger")
    }

    func testGateBlockedHandoverLeavesRelayAwaitingPMWithNoRoundAndNoEscalation() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, runner) = makeService(devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, idFactory: { "relay_pilot_gate" })
        _ = coordinator.startPilot(config: .init(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "model_dev"))

        let dangerousHandover = "Run git reset --hard on main to clean this up."
        let submission = "Reviewed.\n\n" + verdictJSON("continue", handover: dangerousHandover)
        let result = await coordinator.runExternalRound(relayId: "relay_pilot_gate", submission: submission)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        guard case .handoverBlocked(let dangerClass, let code, _, let snippet) = error else { return XCTFail("wrong error case") }
        XCTAssertEqual(dangerClass, "destructiveGit")
        XCTAssertEqual(code, "RELAY_HANDOVER_UNSAFE")
        XCTAssertTrue(snippet.contains("reset --hard"))
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 0, "the dev turn must never dispatch on a blocked handover")

        let reloaded = stateStore.load(id: "relay_pilot_gate")
        XCTAssertEqual(reloaded?.status, .awaitingPM, "Pilot never escalates on a gate block — the PM is right there to rephrase")
        XCTAssertTrue(reloaded?.rounds.isEmpty ?? false)
    }

    // MARK: - runExternalRound: mutual exclusion / state guards

    func testRoundInFlightRefusesAConcurrentHandoff() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, _) = makeService(devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let running = RelayState(
            id: "relay_pilot_inflight", projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: RelayState.externalPMWorkerId, devWorkerId: "model_dev",
            status: .running, pmMode: .external, createdAt: Date()
        )
        try stateStore.save(running)

        let result = await coordinator.runExternalRound(relayId: "relay_pilot_inflight", submission: verdictJSON("done", note: "x"))
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .roundInFlight)
    }

    func testNotAwaitingPMRefusesADoneRelay() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, _) = makeService(devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let done = RelayState(
            id: "relay_pilot_done_already", projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: RelayState.externalPMWorkerId, devWorkerId: "model_dev",
            status: .done, pmMode: .external, createdAt: Date(), note: "Shipped."
        )
        try stateStore.save(done)

        let result = await coordinator.runExternalRound(relayId: "relay_pilot_done_already", submission: verdictJSON("done", note: "x"))
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notAwaitingPM(status: "done"))
    }

    func testNotFoundRelayReturnsRelayNotFound() async {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, _) = makeService(devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let result = await coordinator.runExternalRound(relayId: "relay_ghost", submission: verdictJSON("done", note: "x"))
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .relayNotFound)
    }

    func testSpawnedRelayRefusesRunExternalRound() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, _) = makeService(devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let spawned = RelayState(
            id: "relay_spawned_not_pilot", projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .escalated, createdAt: Date()
        )
        try stateStore.save(spawned)

        let result = await coordinator.runExternalRound(relayId: "relay_spawned_not_pilot", submission: verdictJSON("done", note: "x"))
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notPilotRelay)
    }

    // MARK: - Ceilings (honest stop, same as spawned)

    func testMaxRoundsStopsHonestlyOnTheHandoffThatWouldExceedIt() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, runner) = makeService(devScripts: [.init(stdout: "Round 1 done.")], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, idFactory: { "relay_pilot_ceiling" })
        _ = coordinator.startPilot(config: .init(
            projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "model_dev", maxRounds: 1
        ))

        let round1 = await coordinator.runExternalRound(
            relayId: "relay_pilot_ceiling", submission: "Go.\n\n" + verdictJSON("continue", handover: "Build round 1.")
        )
        guard case .success(let payload1) = round1 else { return XCTFail("round 1 should succeed") }
        XCTAssertEqual(payload1.state.status, .awaitingPM)

        let round2 = await coordinator.runExternalRound(
            relayId: "relay_pilot_ceiling", submission: "Go again.\n\n" + verdictJSON("continue", handover: "Build round 2.")
        )
        guard case .success(let payload2) = round2 else { return XCTFail("a ceiling stop is success(state), not an error") }
        XCTAssertEqual(payload2.state.status, .stopped)
        XCTAssertEqual(payload2.state.stoppedReason, "reached --max-rounds (1)")
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 1, "round 2 never dispatches — the ceiling fires before parsing even starts")
    }

    func testStagnationStopsAfterRepeatedNoChangeRounds() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        // The dev CLI is scripted and never touches git — the repo genuinely does not
        // change, exactly the deadlock signature stagnation exists to catch.
        let (service, runner) = makeService(devScripts: [.init(stdout: "Tried again, nothing changed.")], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, idFactory: { "relay_pilot_stagnation" })
        _ = coordinator.startPilot(config: .init(
            projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "model_dev",
            maxRounds: 20, stagnationRoundCap: 2
        ))

        for _ in 0..<2 {
            let result = await coordinator.runExternalRound(
                relayId: "relay_pilot_stagnation", submission: "Same flag again.\n\n" + verdictJSON("continue", handover: "Please fix the same thing.")
            )
            guard case .success = result else { return XCTFail("expected success") }
        }
        let third = await coordinator.runExternalRound(
            relayId: "relay_pilot_stagnation", submission: "Still same.\n\n" + verdictJSON("continue", handover: "Same again.")
        )
        guard case .success(let payload) = third else { return XCTFail("stagnation stop is success(state)") }
        XCTAssertEqual(payload.state.status, .stopped)
        XCTAssertTrue(payload.state.stoppedReason?.contains("stagnation") ?? false)
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 2, "the 3rd handoff never dispatches — stagnation fires before parsing")
    }

    // MARK: - Legacy decode (PL-S01)

    func testLegacyRelayJSONWithoutPMModeDecodesToSpawned() throws {
        let legacyJSON = """
        {
          "id": "relay_legacy", "projectRoot": "/repo", "docPath": "docs/spec.md",
          "pmWorkerId": "model_pm", "devWorkerId": "model_dev", "status": "done",
          "rounds": [], "createdAt": "2026-01-01T00:00:00Z"
        }
        """
        let decoded = try CoreJSON.decode(RelayState.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.pmMode, .spawned)
        XCTAssertNil(decoded.pilotMaxRounds)
        XCTAssertNil(decoded.pilotStagnationRoundCap)
    }

    // MARK: - Orphan reconciliation skips a parked awaitingPM relay (PL-S01)

    func testAwaitingPMRelaySurvivesOrphanReconcileSweep() throws {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let parked = RelayState(
            id: "relay_pilot_parked", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: RelayState.externalPMWorkerId, devWorkerId: "model_dev",
            status: .awaitingPM, pmMode: .external, createdAt: Date()
        )
        try stateStore.save(parked)
        // No owner.pid marker at all — a genuinely long-parked relay never had one,
        // which is exactly the case reconciliation must not misread as a dead owner.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: stateStore.rootDirectory.appendingPathComponent("relay_pilot_parked").appendingPathComponent("owner.pid").path))

        let reconciled = RelayCoordinator.reconcileOrphan(parked, stateStore: stateStore, threadProjector: nil, now: Date.init)
        XCTAssertEqual(reconciled.status, .awaitingPM, "reconcileOrphan only ever touches .running — a parked relay passes through untouched")
        XCTAssertEqual(stateStore.load(id: "relay_pilot_parked")?.status, .awaitingPM)
    }
}
