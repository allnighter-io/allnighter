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

    func testParseStartConfigMissingDevWorkerThrows() {
        XCTAssertThrowsError(try PilotCLI.parseStartConfig(["--doc", "docs/spec.md", "--project", "x"])) { error in
            XCTAssertEqual(error as? PilotCLI.PilotCLIError, .missingRequired("--dev-worker <modelId>"))
        }
    }

    func testParseStartConfigUnknownProjectThrowsProjectNotFound() throws {
        let store = makeProjectStore()
        XCTAssertThrowsError(try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "does_not_exist", "--dev-worker", "b"], projectStore: store
        )) { error in
            XCTAssertEqual(error as? PilotCLI.PilotCLIError, .projectNotFound("does_not_exist"))
        }
    }

    func testParseStartConfigInvalidMaxRoundsThrows() throws {
        let store = makeProjectStore()
        try addProject(store)
        XCTAssertThrowsError(try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "repo", "--dev-worker", "b", "--max-rounds", "0"], projectStore: store
        )) { error in
            XCTAssertEqual(error as? PilotCLI.PilotCLIError, .invalidMaxRounds("0"))
        }
    }

    func testParseStartConfigHappyPathHasNoPMWorkerFlagAndSentinelPMWorkerId() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let config = try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--dev-worker", "model_dev"], projectStore: store
        )
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
        let config = try PilotCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--dev-worker", "model_dev", "--max-rounds", "7"], projectStore: store
        )
        XCTAssertEqual(config.maxRounds, 7)
    }

    // MARK: - readSubmission

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

    // MARK: - errorEnvelope (the recovery-ladder mapping the exit funnel uses)

    func testErrorEnvelopeMapsEveryCaseToACatalogCode() {
        let known = Set(ContractRegistry.milestone1.errors.map(\.code))
        let cases: [PilotCLI.PilotCLIError] = [
            .missingRequired("--doc <path>"),
            .invalidMaxRounds("0"),
            .projectNotFound("x"),
            .relayNotFound("relay_1"),
            .noSubmission,
            .fileUnreadable("/x"),
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
}
