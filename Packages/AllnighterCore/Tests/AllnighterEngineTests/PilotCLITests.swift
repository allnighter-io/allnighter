import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

/// `alln pair pilot start|handoff|status|watch` flag parsing + validation
/// (`docs/phases/Pilot_Relay.md` PL-S03). Mirrors `RelayCLITests`: the exit-free
/// `parse*`/`errorEnvelope` helpers are the unit-testable surface; the thin `run*`
/// entry points that call `exit()` are not, matching the house pattern.
final class PilotCLITests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-pilot-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeProjectStore() -> ProjectStore {
        ProjectStore(rootDirectory: tmp.appendingPathComponent("projects"))
    }

    @discardableResult
    private func addProject(_ store: ProjectStore, path: String = "repo") throws -> Project {
        let dir = tmp.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try store.add(path: dir.path, name: nil)
    }

    func testStatusEmbedsPersistedPMTurnAtParkedBoundary() throws {
        let relayStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let state = RelayState(
            id: "relay_pm_turn", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .awaitingPM, createdAt: Date()
        )
        let turnStore = PMTurnStore(relaysRootDirectory: relayStore.rootDirectory)
        let turn = PMTurnJSON(
            kind: .relay, subjectId: state.id, sequence: 1, createdAt: Date(),
            reason: "awaitingPM", lifecycleStatus: "awaitingPM", report: "Settled report.",
            nextCommands: ["alln pair pilot handoff --relay relay_pm_turn --verdict continue --handover-file order.md --json"]
        )
        try turnStore.save(turn)

        let json = PilotCLI.makeStatusJSON(
            state: state, recovery: .none, stateStore: relayStore, runStore: runStore,
            pmTurnStore: turnStore
        )

        XCTAssertEqual(json.pmTurn?.subjectId, turn.subjectId)
        XCTAssertEqual(json.pmTurn?.report, turn.report)
        XCTAssertEqual(json.relay.pmTurn?.sequence, turn.sequence)
        XCTAssertTrue(json.notes.isEmpty)
        XCTAssertTrue(json.relay.notes.isEmpty)
    }

    func testStatusWaitMatchEncodesPMTurnAndOutcome() throws {
        let relayStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let state = RelayState(
            id: "relay_wait_match", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .awaitingPM, createdAt: Date()
        )
        let turnStore = PMTurnStore(relaysRootDirectory: relayStore.rootDirectory)
        try turnStore.save(PMTurnJSON(
            kind: .relay, subjectId: state.id, sequence: 1, createdAt: Date(),
            reason: "awaitingPM", lifecycleStatus: "awaitingPM", report: "Ready for PM.",
            nextCommands: ["alln pair pilot handoff --relay relay_wait_match --verdict continue --handover-file order.md --json"]
        ))

        var status = PilotCLI.makeStatusJSON(
            state: state, recovery: .none, stateStore: relayStore, pmTurnStore: turnStore
        )
        status.waitOutcome = PMTurnStatusWait.Outcome.matched.rawValue
        status.relay.waitOutcome = PMTurnStatusWait.Outcome.matched.rawValue

        let data = try JSONEncoder().encode(status)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["waitOutcome"] as? String, "matched")
        XCTAssertEqual((json["relay"] as? [String: Any])?["waitOutcome"] as? String, "matched")
        XCTAssertEqual((json["pmTurn"] as? [String: Any])?["report"] as? String, "Ready for PM.")
    }

    func testStatusMarksMissingPMTurnAtParkedBoundary() throws {
        let relayStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let state = RelayState(
            id: "relay_missing_turn", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .awaitingPM, createdAt: Date()
        )

        let json = PilotCLI.makeStatusJSON(
            state: state, recovery: .none, stateStore: relayStore,
            pmTurnStore: PMTurnStore(relaysRootDirectory: relayStore.rootDirectory)
        )

        XCTAssertNil(json.pmTurn)
        XCTAssertEqual(json.notes, ["pm_turn_missing"])
    }

    // MARK: - parseStartConfig

    func testParseStartConfigMissingDocThrows() {
        XCTAssertThrowsError(try PilotCLI.parseStartConfig(["--project", "x", "--dev-model", "b"])) { error in
            XCTAssertEqual(error as? PilotCLI.PilotCLIError, .missingRequired("--doc <path>"))
        }
    }

    func testParseStartConfigMissingProjectThrows() {
        XCTAssertThrowsError(try PilotCLI.parseStartConfig(["--doc", "docs/spec.md", "--dev-model", "b"])) { error in
            XCTAssertEqual(error as? PilotCLI.PilotCLIError, .missingRequired("--project <id|path>"))
        }
    }

    func testParseStartConfigUnknownProjectThrowsProjectNotFound() throws {
        let store = makeProjectStore()
        XCTAssertThrowsError(try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "does_not_exist", "--dev-model", "model_dev"],
            projectStore: store,
            models: [Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "claude_code", role: .both)]
        )) { error in
            XCTAssertEqual(error as? PilotCLI.PilotCLIError, .projectNotFound("does_not_exist"))
        }
    }

    func testParseStartConfigInvalidMaxRoundsThrows() throws {
        let store = makeProjectStore()
        try addProject(store)
        XCTAssertThrowsError(try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "repo", "--dev-model", "model_dev", "--max-rounds", "0"],
            projectStore: store,
            models: [Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "claude_code", role: .both)]
        )) { error in
            XCTAssertEqual(error as? PilotCLI.PilotCLIError, .invalidMaxRounds("0"))
        }
    }

    func testParseStartConfigMissingDevWorkerThrowsWhenNoneRemembered() throws {
        let store = makeProjectStore()
        try addProject(store)
        let models = [
            Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "claude_code", role: .both),
        ]
        XCTAssertThrowsError(try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "repo"],
            projectStore: store,
            models: models,
            probeRecords: [],
            devSeatStore: PilotDevSeatStore(rootDirectory: tmp.appendingPathComponent("readiness"))
        )) { error in
            XCTAssertEqual(
                error as? PilotCLI.PilotCLIError,
                .missingDevWorker(readySeats: PilotSeatResolver.formatReadySeats([]))
            )
        }
    }

    func testParseStartConfigRecallsRememberedDevWorker() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let seatStore = PilotDevSeatStore(rootDirectory: tmp.appendingPathComponent("readiness"))
        try seatStore.save(projectId: project.id, devModelId: "model_dev")
        let request = try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id],
            projectStore: store,
            models: [Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "claude_code", role: .both)],
            devSeatStore: seatStore
        )
        XCTAssertEqual(request.devModelId, "model_dev")
        XCTAssertTrue(request.rememberedDevWorker)
    }

    func testParseStartConfigHappyPathHasNoPMWorkerFlagAndSentinelPMWorkerId() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let request = try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--dev-model", "model_dev"], projectStore: store,
            models: [Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "claude_code", role: .both)]
        )
        let config = request.config
        XCTAssertEqual(config.projectRoot, project.normalizedRootPath)
        XCTAssertEqual(config.projectId, project.id)
        XCTAssertEqual(config.docPath, "docs/spec.md")
        XCTAssertEqual(config.pmModelId, RelayState.callerPMModelId, "no PM model dispatches in Pilot")
        XCTAssertEqual(config.devModelId, "model_dev")
        XCTAssertEqual(config.maxRounds, 20)
        XCTAssertNil(config.until, "pilot start never wires --until from a flag")
    }

    func testParseStartConfigCustomMaxRounds() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let request = try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--dev-model", "model_dev", "--max-rounds", "7"],
            projectStore: store,
            models: [Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "claude_code", role: .both)]
        )
        XCTAssertEqual(request.config.maxRounds, 7)
    }

    // PO-F7: `--idle-timeout` reuses PO-F5's `RunCLI.parseIdleTimeoutSeconds` helper.
    func testParseStartConfigIdleTimeoutFlowsToConfig() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let request = try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--dev-model", "model_dev", "--idle-timeout", "900"],
            projectStore: store,
            models: [Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "claude_code", role: .both)]
        )
        XCTAssertEqual(request.config.devTurnIdleTimeoutSeconds, 900)
    }

    func testParseStartConfigInvalidIdleTimeoutThrows() throws {
        let store = makeProjectStore()
        try addProject(store)
        XCTAssertThrowsError(try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "repo", "--dev-model", "model_dev", "--idle-timeout", "0"],
            projectStore: store,
            models: [Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "claude_code", role: .both)]
        )) { error in
            guard case .invalidIdleTimeout(let message) = error as? PilotCLI.PilotCLIError else {
                return XCTFail("expected invalidIdleTimeout, got \(error)")
            }
            XCTAssertTrue(message.contains("--idle-timeout"), message)
        }
    }

    // MARK: - readSubmission (legacy)

    func testReadSubmissionFromFile() throws {
        let path = tmp.appendingPathComponent("round.md")
        try "review text\n\n```json\n{\"verdict\": \"done\"}\n```".write(to: path, atomically: true, encoding: .utf8)
        let submission = try PilotCLI.readSubmission(Options(["--file", path.path]))
        XCTAssertTrue(submission.contains("review text"))
    }

    func testReadSubmissionMissingFileThrows() {
        XCTAssertThrowsError(try PilotCLI.readSubmission(Options(["--file", "/does/not/exist.md"]))) { error in
            XCTAssertEqual(error as? PilotCLI.PilotCLIError, .fileUnreadable("/does/not/exist.md"))
        }
    }

    // MARK: - parseHandoffSubmission (P1 frictionless handoff)

    func testParseHandoffSubmissionFromHandoverFileSynthesizesTail() throws {
        let orderPath = tmp.appendingPathComponent("order.md")
        let handover = "# Round 1\n\nUse ```json fenced examples.\n"
        try handover.write(to: orderPath, atomically: true, encoding: .utf8)

        let submission = try PilotCLI.parseHandoffSubmission(Options([
            "--relay", "relay_x", "--verdict", "continue", "--handover-file", orderPath.path,
        ]))
        let extraction = try XCTUnwrap(try unwrapRelayVerdict(RelayVerdictParser.extract(from: submission)))
        XCTAssertEqual(extraction.verdict.handover, handover)
        XCTAssertEqual(extraction.verdict.verdict, .continueRelay)
    }

    func testParseHandoffSubmissionDoneWithNoteOnly() throws {
        let submission = try PilotCLI.parseHandoffSubmission(Options([
            "--relay", "relay_x", "--verdict", "done", "--note", "Shipped.",
        ]))
        let extraction = try XCTUnwrap(try unwrapRelayVerdict(RelayVerdictParser.extract(from: submission)))
        XCTAssertEqual(extraction.verdict.verdict, RelayVerdict.Verdict.done)
        XCTAssertEqual(extraction.verdict.note, "Shipped.")
    }

    func testParseHandoffSubmissionFileAndHandoverFileMutuallyExclusive() {
        XCTAssertThrowsError(try PilotCLI.parseHandoffSubmission(Options([
            "--relay", "relay_x", "--file", "a.md", "--verdict", "done", "--handover-file", "b.md",
        ]))) { error in
            XCTAssertEqual(
                error as? PilotCLI.PilotCLIError,
                .mutuallyExclusive("--file", "--handover-file/--handover-stdin/--verdict")
            )
        }
    }

    func testParseHandoffSubmissionContinueWithoutHandoverThrows() {
        XCTAssertThrowsError(try PilotCLI.parseHandoffSubmission(Options([
            "--relay", "relay_x", "--verdict", "continue",
        ]))) { error in
            XCTAssertEqual(
                error as? PilotCLI.PilotCLIError,
                .missingRequired("--handover-file <path> or --handover-stdin")
            )
        }
    }

    func testParseHandoffSubmissionInvalidVerdictThrows() {
        XCTAssertThrowsError(try PilotCLI.parseHandoffSubmission(Options([
            "--relay", "relay_x", "--verdict", "maybe",
        ]))) { error in
            XCTAssertEqual(error as? PilotCLI.PilotCLIError, .invalidVerdict("maybe"))
        }
    }

    func testSynthesizeSubmissionPreservesHandoverBytesIncludingTrailingNewline() throws {
        let handover = "# Order\n\nMention ```json in prose.\n"
        let submission = try PilotCLI.synthesizeSubmission(verdict: .continueRelay, handover: handover, note: nil)
        let extraction = try XCTUnwrap(try unwrapRelayVerdict(RelayVerdictParser.extract(from: submission)))
        XCTAssertEqual(extraction.verdict.handover, handover)
    }

    private func unwrapRelayVerdict(
        _ result: Result<RelayVerdictParser.Extraction, RelayVerdictParser.ExtractError>
    ) throws -> RelayVerdictParser.Extraction {
        switch result {
        case .success(let extraction): return extraction
        case .failure(let error): throw error
        }
    }

    // MARK: - errorEnvelope (the recovery-ladder mapping the exit funnel uses)

    func testErrorEnvelopeMapsEveryCaseToACatalogCode() {
        let known = Set(ContractRegistry.milestone1.errors.map(\.code))
        let cases: [PilotCLI.PilotCLIError] = [
            .missingRequired("--doc <path>"),
            .invalidMaxRounds("0"),
            .invalidIdleTimeout("--idle-timeout must be a positive integer number of seconds, got '0'"),
            .projectNotFound("x"),
            .relayNotFound("relay_1"),
            .noSubmission,
            .noHandover,
            .fileUnreadable("/x"),
            .invalidVerdict("bogus"),
            .mutuallyExclusive("--file", "--handover-file"),
            .ambiguousDevWorker(alias: "sonnet", candidates: "model_sonnet, model_agy_sonnet"),
            .devWorkerNotFound(alias: "bogus", readySeats: "model_dev (Dev)"),
            .missingDevWorker(readySeats: "model_dev (Dev)"),
            .noReadyDevSeats,
            .invalidMaxWait("0"),
        ]
        for c in cases {
            let (code, message) = PilotCLI.errorEnvelope(c)
            XCTAssertTrue(known.contains(code), "\(code) missing from error catalog")
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testPilotRoundErrorEnvelopeMapsEveryCaseToACatalogCode() {
        let known = Set(ContractRegistry.milestone1.errors.map(\.code))
        let cases: [RelayCoordinator.PilotRoundError] = [
            .relayNotFound,
            .notPilotRelay,
            .roundInFlight,
            .notAwaitingPM(status: "done"),
            .verdictUnparseable(.noVerdictFound),
            .verdictUnparseable(.unknownVerdict("bogus")),
            .verdictUnparseable(.continueWithoutHandover),
            .handoverBlocked(dangerClass: "destructiveGit", code: "RELAY_HANDOVER_UNSAFE", reason: "destructive git instruction", snippet: "git reset --hard"),
        ]
        for c in cases {
            let (code, message) = PilotCLI.pilotRoundErrorEnvelope(c)
            XCTAssertTrue(known.contains(code), "\(code) missing from error catalog")
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testPilotRoundErrorEnvelopeSpecificCodes() {
        XCTAssertEqual(PilotCLI.pilotRoundErrorEnvelope(.roundInFlight).code, "RELAY_ROUND_IN_FLIGHT")
        XCTAssertEqual(PilotCLI.pilotRoundErrorEnvelope(.notAwaitingPM(status: "escalated")).code, "RELAY_NOT_AWAITING_PM")
        XCTAssertEqual(PilotCLI.pilotRoundErrorEnvelope(.verdictUnparseable(.noVerdictFound)).code, "RELAY_VERDICT_UNPARSEABLE")
        XCTAssertEqual(PilotCLI.pilotRoundErrorEnvelope(.relayNotFound).code, "RELAY_NOT_FOUND")
        XCTAssertEqual(
            PilotCLI.pilotRoundErrorEnvelope(.handoverBlocked(dangerClass: "massDeletion", code: "RELAY_HANDOVER_UNSAFE", reason: "r", snippet: "s")).code,
            "RELAY_HANDOVER_UNSAFE"
        )
    }

    // MARK: - nextActionLine (the next-action discipline)

    func testNextActionLineNamesTheHandoffCommandWhenAwaitingPM() {
        let state = RelayState(
            id: "relay_x", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .awaitingPM, createdAt: Date()
        )
        let line = PilotCLI.nextActionLine(for: state)
        XCTAssertTrue(line.contains("loop step"))
        XCTAssertTrue(line.contains("relay_x"))
    }

    func testNextActionLineForEachTerminalStatus() {
        func state(_ status: RelayState.Status) -> RelayState {
            RelayState(
                id: "relay_x", projectRoot: "/repo", docPath: "docs/spec.md",
                pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
                status: status, createdAt: Date()
            )
        }
        XCTAssertFalse(PilotCLI.nextActionLine(for: state(.done)).isEmpty)
        XCTAssertFalse(PilotCLI.nextActionLine(for: state(.escalated)).isEmpty)
        XCTAssertFalse(PilotCLI.nextActionLine(for: state(.stopped)).isEmpty)
        XCTAssertFalse(PilotCLI.nextActionLine(for: state(.running)).isEmpty)
    }

    // MARK: - in-flight recovery (DX5)

    func testLoadRelayStateHandoffAliveWhenOwnerLive() throws {
        let store = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let state = RelayState(
            id: "relay_live", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .running, createdAt: Date()
        )
        try store.save(state)
        let ownerURL = store.rootDirectory.appendingPathComponent("relay_live/owner.pid")
        try Data("\(ProcessInfo.processInfo.processIdentifier)".utf8).write(to: ownerURL)

        let loaded = PilotCLI.loadRelayState(
            relayId: "relay_live", stateStore: store, threadProjector: nil, reconcileOrphans: true
        )
        XCTAssertEqual(loaded?.recovery, .handoffAlive)
        XCTAssertEqual(loaded?.state.status, .running)
    }

    func testLoadRelayStateOrphanReconciledWhenOwnerDead() throws {
        let store = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays2"))
        var state = RelayState(
            id: "relay_dead", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .running,
            rounds: [RelayRound(roundNumber: 1, baselineHead: "abc", startedAt: Date())],
            createdAt: Date()
        )
        try store.save(state)
        let ownerURL = store.rootDirectory.appendingPathComponent("relay_dead/owner.pid")
        try Data("999999999".utf8).write(to: ownerURL)

        let loaded = PilotCLI.loadRelayState(
            relayId: "relay_dead", stateStore: store, threadProjector: nil, reconcileOrphans: true
        )
        XCTAssertEqual(loaded?.recovery, .orphanReconciled)
        XCTAssertEqual(loaded?.state.status, .stopped)
    }

    func testRecoveryNextActionsPreferStatusForAliveHandoff() {
        let state = RelayState(
            id: "relay_x", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .running, createdAt: Date()
        )
        let actions = PilotCLI.recoveryNextActions(for: state, recovery: .handoffAlive)
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[0].kind, "pilotStatus")
        XCTAssertTrue(actions[0].command.contains("loop status"))
        XCTAssertTrue(actions[0].command.contains("--wait-for parked"))
        XCTAssertTrue(actions[0].command.contains("--timeout 7200"))
        XCTAssertTrue(actions[0].label.lowercased().contains("wait"))
        XCTAssertTrue(actions[0].label.lowercased().contains("stream"))
        XCTAssertTrue(actions[0].label.lowercased().contains("supplementary"))
        XCTAssertEqual(actions[1].kind, "pilotWatch")
        XCTAssertTrue(actions[1].command.contains("loop wait"))
        XCTAssertTrue(actions[1].label.lowercased().contains("optional"))
    }

    func testRecoveryNextActionsOrphanInspectNotBlindRetry() {
        let state = RelayState(
            id: "relay_x", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .stopped, createdAt: Date(),
            stoppedReason: RelayState.orphanReconciledReason
        )
        let actions = PilotCLI.recoveryNextActions(for: state, recovery: .orphanReconciled)
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].kind, "pilotStatus")
        XCTAssertTrue(actions[0].label.lowercased().contains("inspect"))
        XCTAssertFalse(actions[0].label.lowercased().contains("retry handoff"))
        let line = PilotCLI.recoveryActionLine(for: state, recovery: .orphanReconciled)
        XCTAssertTrue(line?.lowercased().contains("inspect") == true)
        XCTAssertTrue(line?.lowercased().contains("blind retry") == true)
    }

    func testNextActionLineRunningPrefersStatusOverWatch() {
        let state = RelayState(
            id: "relay_x", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .running, createdAt: Date()
        )
        let line = PilotCLI.nextActionLine(for: state)
        XCTAssertTrue(line.contains("loop status"))
        XCTAssertTrue(line.contains("do not re-dispatch"))
        let statusIdx = line.range(of: "loop status")?.lowerBound
        let watchIdx = line.range(of: "loop wait")?.lowerBound
        XCTAssertNotNil(statusIdx)
        if let statusIdx, let watchIdx {
            XCTAssertLessThan(statusIdx, watchIdx)
        }
    }

    func testWatchSettledNoteWhenNothingInFlight() {
        let note = PilotCLI.watchSettledNote(recovery: .none, status: .awaitingPM)
        XCTAssertTrue(note.contains("no round in flight"))
        XCTAssertTrue(note.contains("awaitingPM"))
    }

    func testHandoffDispatchAckJSONEncodesSingleLine() throws {
        let ack = PilotHandoffDispatchJSON(
            relayId: "relay_test", status: "dispatched", roundInFlight: false, pid: 4242,
            serveAutoLaunch: "launched",
            delivery: DetachedDispatch.waitDelivery(kind: "pilot", id: "relay_test", commandPrefix: "alln"))
        let line = AllnighterCLI.jsonLine(ack)
        XCTAssertFalse(line.contains("\n"))
        let data = try XCTUnwrap(line.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["relayId"] as? String, "relay_test")
        XCTAssertEqual(json["status"] as? String, "dispatched")
        XCTAssertEqual(json["roundInFlight"] as? Bool, false)
        XCTAssertEqual(json["pid"] as? Int, 4242)
        XCTAssertEqual(json["serveAutoLaunch"] as? String, "launched")
        let delivery = try XCTUnwrap(json["delivery"] as? [String: Any])
        XCTAssertEqual(delivery["path"] as? String, "wait")
        XCTAssertEqual(
            delivery["command"] as? String,
            "alln loop status relay_test --wait-for parked --timeout 7200 --json"
        )
    }

    /// SR-13 (Sol F20): the printed `next:` command must shell-quote the scaffold path — the
    /// default lives under "…/Application Support/Allnighter/…", whose space split the
    /// unquoted command on copy-paste so the first handoff failed on every default install.
    func testHandoffNextCommandShellQuotesSpacedScaffoldPath() {
        let path = "/Users/x/Library/Application Support/Allnighter/relays/relay_9/round1.md"
        let cmd = PilotCLI.handoffNextCommand(relayId: "relay_9", scaffoldPath: path)
        XCTAssertTrue(cmd.contains("alln loop step relay_9"), "cmd: \(cmd)")
        XCTAssertTrue(cmd.contains("'\(path)'"), "cmd: \(cmd)")
        // The quoted path is a single shell token (the substring after the quote has no
        // unescaped space before the closing quote).
        XCTAssertTrue(cmd.hasSuffix("'\(path)'"), "cmd: \(cmd)")
    }

    /// Programmatic consumers must use scaffoldPath / nextCommandArgv — not parse nextCommand.
    func testPilotStartJSONExposesRawScaffoldPathAndArgv() throws {
        let path = "/Users/x/Library/Application Support/Allnighter/relays/relay_9/round1.md"
        let relay = RelayJSON.project(
            RelayState(
                id: "relay_9", projectRoot: "/repo", docPath: "d.md",
                pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
                status: .awaitingPM, createdAt: Date()
            ),
            contractVersion: ContractRegistry.contractVersion
        )
        let start = PilotStartJSON(
            relay: relay,
            nextCommand: PilotCLI.handoffNextCommand(relayId: "relay_9", scaffoldPath: path),
            scaffoldPath: path,
            nextCommandArgv: PilotStartJSON.defaultHandoffArgv(relayId: "relay_9", scaffoldPath: path),
            devModelId: "model_dev"
        )
        XCTAssertEqual(start.scaffoldPath, path)
        XCTAssertFalse(start.scaffoldPath.contains("'"))
        XCTAssertTrue(start.nextCommand.contains("'\(path)'"))
        XCTAssertEqual(start.nextCommandArgv.last, path)
        XCTAssertFalse(start.nextCommandArgv.contains { $0.contains("'") })
        let data = try JSONEncoder().encode(start)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["scaffoldPath"] as? String, path)
        let argv = try XCTUnwrap(obj["nextCommandArgv"] as? [String])
        XCTAssertEqual(argv.last, path)
    }

    // MARK: - detached handoff launch (PLT-S01)

    /// Works Test intent: clean checkout without `<cwd>/alln` — bare `alln` from PATH must
    /// still resolve to an absolute binary; child cwd must be the relay projectRoot.
    private func makeExecutable(at url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\necho ok\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func saveRelay(projectRoot: String, relayId: String = "relay_handoff") throws -> RelayStateStore {
        let store = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays-\(relayId)"))
        let state = RelayState(
            id: relayId, projectRoot: projectRoot, docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .awaitingPM, createdAt: Date()
        )
        try store.save(state)
        return store
    }

    func testDetachedHandoffLaunchPrefersCurrentExecutablePath() throws {
        let projectRoot = tmp.appendingPathComponent("repo").path
        try FileManager.default.createDirectory(atPath: projectRoot, withIntermediateDirectories: true)
        let store = try saveRelay(projectRoot: projectRoot)
        let preferred = "/usr/local/bin/alln-real"

        let launch = try PilotCLI.detachedHandoffLaunch(
            relayId: "relay_handoff",
            stateStore: store,
            argv0: "alln",
            pathEnvironment: "/should/not/be/searched",
            currentExecutablePath: { preferred }
        )

        XCTAssertEqual(launch.executableURL.path, preferred)
        XCTAssertEqual(launch.currentDirectoryURL.path, projectRoot)
    }

    func testDetachedHandoffLaunchFallsBackToInstallCLIResolverForBareArgv0() throws {
        let projectRoot = tmp.appendingPathComponent("repo2").path
        try FileManager.default.createDirectory(atPath: projectRoot, withIntermediateDirectories: true)
        let store = try saveRelay(projectRoot: projectRoot, relayId: "relay_path")
        let binary = tmp.appendingPathComponent("alln-bin")
        try makeExecutable(at: binary)
        let binDir = tmp.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: binDir.appendingPathComponent("alln").path,
            withDestinationPath: binary.path
        )
        let elsewhere = tmp.appendingPathComponent("websitemd.studio")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: elsewhere.appendingPathComponent("alln").path,
            contents: Data("not the real binary".utf8)
        )

        let launch = try PilotCLI.detachedHandoffLaunch(
            relayId: "relay_path",
            stateStore: store,
            argv0: "alln",
            pathEnvironment: binDir.path,
            currentExecutablePath: { nil }
        )

        XCTAssertEqual(launch.executableURL.path, binary.resolvingSymlinksInPath().path)
        XCTAssertEqual(launch.currentDirectoryURL.path, projectRoot)
    }

    func testDetachedHandoffLaunchFailsWhenRelayMissing() throws {
        let store = RelayStateStore(rootDirectory: tmp.appendingPathComponent("empty-relays"))
        XCTAssertThrowsError(try PilotCLI.detachedHandoffLaunch(
            relayId: "missing",
            stateStore: store,
            currentExecutablePath: { "/bin/alln" }
        )) { error in
            XCTAssertEqual(error as? PilotCLI.DetachedHandoffLaunchError, .relayNotFound("missing"))
        }
    }

    func testDetachedHandoffLaunchFailsWhenExecutableUnresolved() throws {
        let projectRoot = tmp.appendingPathComponent("repo3").path
        try FileManager.default.createDirectory(atPath: projectRoot, withIntermediateDirectories: true)
        let store = try saveRelay(projectRoot: projectRoot, relayId: "relay_unresolved")

        XCTAssertThrowsError(try PilotCLI.detachedHandoffLaunch(
            relayId: "relay_unresolved",
            stateStore: store,
            argv0: "alln",
            pathEnvironment: tmp.appendingPathComponent("empty-bin").path,
            currentExecutablePath: { nil }
        )) { error in
            XCTAssertEqual(error as? PilotCLI.DetachedHandoffLaunchError, .unresolvedExecutable)
        }
    }

    // MARK: - watch (PLT-S04)

    func testResolveWatchMaxWaitNonTTYAppliesDefault() throws {
        let resolved = try PilotCLI.resolveWatchMaxWait(opts: Options(["--relay", "x"]), stdoutIsTTY: false)
        XCTAssertEqual(resolved.seconds, PilotCLI.defaultNonTTYMaxWaitSeconds)
        XCTAssertTrue(resolved.applied)
    }

    func testResolveWatchMaxWaitTTYUnboundedUnlessFlagged() throws {
        let resolved = try PilotCLI.resolveWatchMaxWait(opts: Options(["--relay", "x"]), stdoutIsTTY: true)
        XCTAssertNil(resolved.seconds)
        XCTAssertFalse(resolved.applied)
    }

    func testResolveWatchMaxWaitExplicitWinsOverNonTTYDefault() throws {
        let resolved = try PilotCLI.resolveWatchMaxWait(
            opts: Options(["--relay", "x", "--max-wait", "120"]), stdoutIsTTY: false
        )
        XCTAssertEqual(resolved.seconds, 120)
        XCTAssertFalse(resolved.applied)
    }

    func testResolveWatchMaxWaitExplicitOnTTY() throws {
        let resolved = try PilotCLI.resolveWatchMaxWait(
            opts: Options(["--relay", "x", "--max-wait", "90"]), stdoutIsTTY: true
        )
        XCTAssertEqual(resolved.seconds, 90)
        XCTAssertFalse(resolved.applied)
    }

    func testParseMaxWaitInvalidThrows() {
        XCTAssertThrowsError(try PilotCLI.parseMaxWaitSeconds("0")) { error in
            XCTAssertEqual(error as? PilotCLI.PilotCLIError, .invalidMaxWait("0"))
        }
        XCTAssertThrowsError(try PilotCLI.parseMaxWaitSeconds("nope")) { error in
            XCTAssertEqual(error as? PilotCLI.PilotCLIError, .invalidMaxWait("nope"))
        }
    }

    func testWatchStillRunningRequiresRunningAndAliveOwner() {
        let running = RelayState(
            id: "relay_x", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .running, createdAt: Date()
        )
        XCTAssertTrue(PilotCLI.watchStillRunning(state: running, recovery: .handoffAlive))
        XCTAssertFalse(PilotCLI.watchStillRunning(state: running, recovery: .orphanReconciled))
        var awaiting = running
        awaiting.status = .awaitingPM
        XCTAssertFalse(PilotCLI.watchStillRunning(state: awaiting, recovery: .none))
    }

    func testWatchGoodbyeNoteStillRunningMentionsStatusNotFailure() {
        let note = PilotCLI.watchGoodbyeNote(
            relayId: "relay_x", reason: .interrupted, stillRunning: true
        )
        XCTAssertTrue(note.contains("still running"))
        XCTAssertTrue(note.contains("loop status"))
        XCTAssertTrue(note.contains("not a failed round"))
    }

    func testWatchGoodbyeEnvelopeStillRunningFields() throws {
        let relayJSON = RelayJSON.project(
            RelayState(
                id: "relay_watch", projectRoot: "/repo", docPath: "docs/spec.md",
                pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
                status: .running, createdAt: Date()
            ),
            contractVersion: ContractRegistry.contractVersion
        )
        let line = AllnighterCLI.jsonLine(PilotWatchJSON(
            relay: relayJSON, devReport: nil,
            note: PilotCLI.watchGoodbyeNote(relayId: "relay_watch", reason: .interrupted, stillRunning: true),
            stillRunning: true, maxWaitApplied: true
        ))
        let data = try XCTUnwrap(line.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["stillRunning"] as? Bool, true)
        XCTAssertEqual(json["maxWaitApplied"] as? Bool, true)
        XCTAssertNil(json["devReport"])
    }

    func testWatchInterruptLeavesRunningRelayUntouched() throws {
        let store = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays-watch"))
        let state = RelayState(
            id: "relay_live", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .running, createdAt: Date()
        )
        try store.save(state)
        let ownerURL = store.rootDirectory.appendingPathComponent("relay_live/owner.pid")
        try Data("\(ProcessInfo.processInfo.processIdentifier)".utf8).write(to: ownerURL)

        let flag = PilotCLI.WatchInterruptFlag()
        flag.fire()
        let loaded = PilotCLI.loadRelayState(
            relayId: "relay_live", stateStore: store, threadProjector: nil, reconcileOrphans: false
        )
        XCTAssertEqual(loaded?.state.status, .running)
        XCTAssertEqual(loaded?.recovery, .handoffAlive)
        XCTAssertTrue(PilotCLI.watchStillRunning(state: loaded!.state, recovery: loaded!.recovery))
        XCTAssertEqual(store.load(id: "relay_live")?.status, .running)
    }

    func testWatchHeartbeatJSONEncodesKind() throws {
        let line = AllnighterCLI.jsonLine(PilotWatchHeartbeatJSON(elapsedSeconds: 30, status: "running"))
        let data = try XCTUnwrap(line.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "pilotWatchHeartbeat")
        XCTAssertEqual(json["elapsedSeconds"] as? Int, 30)
        XCTAssertEqual(json["status"] as? String, "running")
    }

    func testWatchGoodbyeNoteMaxWaitStillRunning() {
        let note = PilotCLI.watchGoodbyeNote(
            relayId: "relay_x", reason: .maxWaitExpired, stillRunning: true
        )
        XCTAssertTrue(note.contains("max-wait"))
        XCTAssertTrue(note.contains("still running"))
        XCTAssertTrue(note.contains("loop status"))
    }

    func testDeadWaiterReconcileDisabledLeavesRunningState() throws {
        let store = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays-dead-waiter"))
        var state = RelayState(
            id: "relay_dead", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .running,
            rounds: [RelayRound(roundNumber: 1, baselineHead: "abc", startedAt: Date())],
            createdAt: Date()
        )
        try store.save(state)
        let ownerURL = store.rootDirectory.appendingPathComponent("relay_dead/owner.pid")
        try Data("999999999".utf8).write(to: ownerURL)

        let withoutReconcile = PilotCLI.loadRelayState(
            relayId: "relay_dead", stateStore: store, threadProjector: nil, reconcileOrphans: false
        )
        XCTAssertEqual(withoutReconcile?.state.status, .running)
        XCTAssertEqual(withoutReconcile?.recovery, .orphanReconciled)
        XCTAssertEqual(store.load(id: "relay_dead")?.status, .running)

        let withReconcile = PilotCLI.loadRelayState(
            relayId: "relay_dead", stateStore: store, threadProjector: nil, reconcileOrphans: true
        )
        XCTAssertEqual(withReconcile?.state.status, .stopped)
        XCTAssertEqual(withReconcile?.recovery, .orphanReconciled)
    }

    // MARK: - PLT-S02 long-job status fields

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

    func testLongJobStatusZeroCommitsFreshProgressStillAlive() throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs-s02"))
        let store = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays-s02"))
        let started = Date().addingTimeInterval(-120)
        let progressAt = Date().addingTimeInterval(-5)
        let devRunId = "run_pilot_s02_fresh"
        var round = RelayRound(roundNumber: 1, baselineHead: try XCTUnwrap(GitObserver().observe(rootPath: repo.path).head), startedAt: started)
        round.devRunId = devRunId
        let state = RelayState(
            id: "relay_s02", projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .running,
            rounds: [round],
            createdAt: Date()
        )
        try store.save(state)
        var run = TeamRun(id: devRunId, prompt: "p", status: .running, createdAt: started, repoRoot: repo.path)
        run.lastActivityAt = progressAt
        run.lastActivityKind = .message
        try runStore.save(run, models: [])
        let ownerURL = store.rootDirectory.appendingPathComponent("relay_s02/owner.pid")
        try Data("\(ProcessInfo.processInfo.processIdentifier)".utf8).write(to: ownerURL)
        let dir = try store.directory(for: "relay_s02")
        try ProcessOwnership.recordProgress(in: dir, phase: "pgid_activity", now: Date())

        let fields = PilotCLI.longJobStatusFields(
            state: state, recovery: .handoffAlive, stateStore: store, runStore: runStore, now: Date()
        )
        XCTAssertEqual(fields.ownerAlive, true)
        XCTAssertEqual(fields.commitsSinceBaseline, 0, "zero commits must not imply dead")
        XCTAssertNotNil(fields.lastProgressAt)
        XCTAssertEqual(fields.waitHintSeconds, 45)
        XCTAssertEqual(fields.watcherDisposable, true)
        XCTAssertEqual(fields.streamSilenceWarning, false)
        let elapsed = try XCTUnwrap(fields.elapsedSeconds)
        XCTAssertGreaterThanOrEqual(elapsed, 118)
        XCTAssertLessThanOrEqual(elapsed, 122)
        XCTAssertNotNil(fields.silenceAgeSeconds)
        XCTAssertLessThanOrEqual(fields.silenceAgeSeconds ?? 999, 10)

        let json = PilotCLI.makeStatusJSON(
            state: state, recovery: .handoffAlive, stateStore: store, runStore: runStore
        )
        XCTAssertEqual(json.ownerAlive, true)
        XCTAssertEqual(json.commitsSinceBaseline, 0)
        XCTAssertEqual(json.waitHintSeconds, PilotCLI.statusWaitHintSeconds)
        XCTAssertEqual(json.watcherDisposable, true)
        XCTAssertEqual(json.streamSilenceWarning, false)
        XCTAssertEqual(json.nextActions.first?.kind, "pilotStatus")
        XCTAssertTrue(json.nextActions.first?.command.contains("--wait-for parked") == true)
    }

    /// PLS-S01: hot relay heartbeat / pgid_activity must not mask stale stream silence.
    func testPrimaryLivenessIgnoresRelayHeartbeatPgidActivity() throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs-pls"))
        let store = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays-pls"))
        let started = Date().addingTimeInterval(-2000)
        let staleActivity = Date().addingTimeInterval(-1800)
        let devRunId = "run_pls_stale_stream"
        var round = RelayRound(
            roundNumber: 1,
            baselineHead: try XCTUnwrap(GitObserver().observe(rootPath: repo.path).head),
            startedAt: started
        )
        round.devRunId = devRunId
        let state = RelayState(
            id: "relay_pls", projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .running, rounds: [round], createdAt: Date()
        )
        try store.save(state)
        var run = TeamRun(id: devRunId, prompt: "p", status: .running, createdAt: started, repoRoot: repo.path)
        run.lastActivityAt = staleActivity
        run.lastActivityKind = .message
        try runStore.save(run, models: [])
        let dir = try store.directory(for: "relay_pls")
        try ProcessOwnership.recordProgress(in: dir, phase: "pgid_activity", now: Date())

        let fields = PilotCLI.longJobStatusFields(
            state: state, recovery: .handoffAlive, stateStore: store, runStore: runStore, now: Date()
        )
        let silence = try XCTUnwrap(fields.silenceAgeSeconds)
        XCTAssertGreaterThanOrEqual(silence, 1790)
        XCTAssertLessThanOrEqual(silence, 1810)
        XCTAssertEqual(fields.streamSilenceWarning, true)
        let json = PilotCLI.makeStatusJSON(
            state: state, recovery: .handoffAlive, stateStore: store, runStore: runStore
        )
        XCTAssertEqual(json.nextActions.first?.kind, "inspectStreamSilence")
    }

    func testPrimaryLivenessNilWithoutDevRunIdDespiteHotHeartbeat() throws {
        let repo = try makeGitRepo()
        let store = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays-pls2"))
        let head = try XCTUnwrap(GitObserver().observe(rootPath: repo.path).head)
        let state = RelayState(
            id: "relay_pls2", projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .running,
            rounds: [RelayRound(roundNumber: 1, baselineHead: head, startedAt: Date())],
            createdAt: Date()
        )
        try store.save(state)
        let dir = try store.directory(for: "relay_pls2")
        try ProcessOwnership.recordProgress(in: dir, phase: "pgid_activity", now: Date())

        let fields = PilotCLI.longJobStatusFields(
            state: state, recovery: .handoffAlive, stateStore: store, now: Date()
        )
        XCTAssertNil(fields.lastProgressAt)
        XCTAssertNil(fields.silenceAgeSeconds)
        XCTAssertEqual(fields.streamSilenceWarning, false)
    }

    func testStreamSilenceWarningThreshold() throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs-pls3"))
        let store = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays-pls3"))
        let devRunId = "run_pls_warn"
        let silenceBase = Date().addingTimeInterval(-300)
        var round = RelayRound(
            roundNumber: 1,
            baselineHead: try XCTUnwrap(GitObserver().observe(rootPath: repo.path).head),
            startedAt: Date().addingTimeInterval(-400)
        )
        round.devRunId = devRunId
        let state = RelayState(
            id: "relay_pls3", projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .running, rounds: [round], createdAt: Date()
        )
        try store.save(state)
        var run = TeamRun(id: devRunId, prompt: "p", status: .running, createdAt: silenceBase, repoRoot: repo.path)
        run.lastActivityAt = silenceBase
        run.lastActivityKind = .stdout
        try runStore.save(run, models: [])

        let fields = PilotCLI.longJobStatusFields(
            state: state, recovery: .handoffAlive, stateStore: store, runStore: runStore, now: Date()
        )
        XCTAssertEqual(fields.streamSilenceWarning, true)
        XCTAssertGreaterThanOrEqual(fields.silenceAgeSeconds ?? 0, 295)
    }

    func testLongJobStatusFieldsOmittedWhenNotRunning() {
        let store = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays-s02b"))
        let state = RelayState(
            id: "relay_parked", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .awaitingPM, createdAt: Date()
        )
        let fields = PilotCLI.longJobStatusFields(
            state: state, recovery: .none, stateStore: store
        )
        XCTAssertNil(fields.elapsedSeconds)
        XCTAssertNil(fields.ownerAlive)
        XCTAssertNil(fields.lastProgressAt)
        XCTAssertNil(fields.silenceAgeSeconds)
        XCTAssertNil(fields.commitsSinceBaseline)
        XCTAssertNil(fields.waitHintSeconds)
        XCTAssertNil(fields.watcherDisposable)
    }

    func testContractDocumentsCommitsSinceBaselineAsSupplementaryNotLiveness() {
        let status = ContractRegistry.milestone1.commands.first { $0.name == "pair pilot status" }
        let summary = status?.summary ?? ""
        let jsonFlag = status?.flags.first { $0.name == "json" }?.summary ?? ""
        let blob = summary + "\n" + jsonFlag
        XCTAssertTrue(blob.contains("commitsSinceBaseline"))
        XCTAssertTrue(
            blob.lowercased().contains("supplementary") || blob.lowercased().contains("not liveness"),
            "contract must label commitsSinceBaseline as not liveness: \(blob)"
        )
        XCTAssertTrue(blob.contains("waitHintSeconds"))
        XCTAssertTrue(blob.contains("45"))
        XCTAssertTrue(blob.lowercased().contains("stream"))
    }
}
