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

    // MARK: - parseStartConfig

    func testParseStartConfigMissingDocThrows() {
        XCTAssertThrowsError(try PilotCLI.parseStartConfig(["--project", "x", "--dev-worker", "b"])) { error in
            XCTAssertEqual(error as? PilotCLI.PilotCLIError, .missingRequired("--doc <path>"))
        }
    }

    func testParseStartConfigMissingProjectThrows() {
        XCTAssertThrowsError(try PilotCLI.parseStartConfig(["--doc", "docs/spec.md", "--dev-worker", "b"])) { error in
            XCTAssertEqual(error as? PilotCLI.PilotCLIError, .missingRequired("--project <id|path>"))
        }
    }

    func testParseStartConfigUnknownProjectThrowsProjectNotFound() throws {
        let store = makeProjectStore()
        XCTAssertThrowsError(try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "does_not_exist", "--dev-worker", "model_dev"],
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
            ["--doc", "docs/spec.md", "--project", "repo", "--dev-worker", "model_dev", "--max-rounds", "0"],
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
        try seatStore.save(projectId: project.id, devWorkerId: "model_dev")
        let request = try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id],
            projectStore: store,
            models: [Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "claude_code", role: .both)],
            devSeatStore: seatStore
        )
        XCTAssertEqual(request.devWorkerId, "model_dev")
        XCTAssertTrue(request.rememberedDevWorker)
    }

    func testParseStartConfigHappyPathHasNoPMWorkerFlagAndSentinelPMWorkerId() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let request = try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--dev-worker", "model_dev"], projectStore: store,
            models: [Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "claude_code", role: .both)]
        )
        let config = request.config
        XCTAssertEqual(config.projectRoot, project.normalizedRootPath)
        XCTAssertEqual(config.projectId, project.id)
        XCTAssertEqual(config.docPath, "docs/spec.md")
        XCTAssertEqual(config.pmWorkerId, RelayState.externalPMWorkerId, "no PM model dispatches in Pilot")
        XCTAssertEqual(config.devWorkerId, "model_dev")
        XCTAssertEqual(config.maxRounds, 20)
        XCTAssertNil(config.until, "pilot start never wires --until from a flag")
    }

    func testParseStartConfigCustomMaxRounds() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let request = try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--dev-worker", "model_dev", "--max-rounds", "7"],
            projectStore: store,
            models: [Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "claude_code", role: .both)]
        )
        XCTAssertEqual(request.config.maxRounds, 7)
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
            pmWorkerId: RelayState.externalPMWorkerId, devWorkerId: "model_dev",
            status: .awaitingPM, pmMode: .external, createdAt: Date()
        )
        let line = PilotCLI.nextActionLine(for: state)
        XCTAssertTrue(line.contains("pilot handoff"))
        XCTAssertTrue(line.contains("handover-file"))
        XCTAssertTrue(line.contains("relay_x"))
    }

    func testNextActionLineForEachTerminalStatus() {
        func state(_ status: RelayState.Status) -> RelayState {
            RelayState(
                id: "relay_x", projectRoot: "/repo", docPath: "docs/spec.md",
                pmWorkerId: RelayState.externalPMWorkerId, devWorkerId: "model_dev",
                status: status, pmMode: .external, createdAt: Date()
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
            pmWorkerId: RelayState.externalPMWorkerId, devWorkerId: "model_dev",
            status: .running, pmMode: .external, createdAt: Date()
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
            pmWorkerId: RelayState.externalPMWorkerId, devWorkerId: "model_dev",
            status: .running, pmMode: .external,
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

    func testRecoveryNextActionsNameWatchForAliveHandoff() {
        let state = RelayState(
            id: "relay_x", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: RelayState.externalPMWorkerId, devWorkerId: "model_dev",
            status: .running, pmMode: .external, createdAt: Date()
        )
        let actions = PilotCLI.recoveryNextActions(for: state, recovery: .handoffAlive)
        XCTAssertEqual(actions.count, 1)
        XCTAssertTrue(actions[0].command.contains("pilot watch"))
    }

    func testWatchSettledNoteWhenNothingInFlight() {
        let note = PilotCLI.watchSettledNote(recovery: .none, status: .awaitingPM)
        XCTAssertTrue(note.contains("no round in flight"))
        XCTAssertTrue(note.contains("awaitingPM"))
    }

    func testHandoffDispatchAckJSONEncodesSingleLine() throws {
        let ack = PilotHandoffDispatchJSON(
            relayId: "relay_test", status: "dispatched", roundInFlight: false, pid: 4242)
        let line = PilotCLI.compactJSONString(ack)
        XCTAssertFalse(line.contains("\n"))
        let data = try XCTUnwrap(line.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["relayId"] as? String, "relay_test")
        XCTAssertEqual(json["status"] as? String, "dispatched")
        XCTAssertEqual(json["roundInFlight"] as? Bool, false)
        XCTAssertEqual(json["pid"] as? Int, 4242)
    }
}
