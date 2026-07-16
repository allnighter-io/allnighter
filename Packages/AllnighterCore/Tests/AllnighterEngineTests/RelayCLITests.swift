import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

/// `alln pair relay` / `pair relay-status` / `pair relay-resume` flag parsing +
/// validation (docs/phases/PM_Relay.md §6 R-S05). Mirrors `PairCLITests`: the
/// exit-free `parse*` helpers are the unit-testable surface (the thin `run*` entry
/// points that call `exit()` on failure are not, matching the house pattern —
/// `PairProgrammingCLI.runSlice/runQueue/runStatus` are untested the same way).
final class RelayCLITests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relay-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeProjectStore() -> ProjectStore {
        ProjectStore(rootDirectory: tmp.appendingPathComponent("projects"))
    }

    private func makeRelayStateStore() -> RelayStateStore {
        RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
    }

    @discardableResult
    private func addProject(_ store: ProjectStore, path: String = "repo") throws -> Project {
        let dir = tmp.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try store.add(path: dir.path, name: nil)
    }

    // MARK: - parseStartConfig

    func testParseStartConfigMissingDocThrows() {
        XCTAssertThrowsError(try RelayCLI.parseStartConfig(["--project", "x", "--pm-worker", "a", "--dev-worker", "b"])) { error in
            XCTAssertEqual(error as? RelayCLI.RelayCLIError, .missingRequired("--doc <path>"))
        }
    }

    func testParseStartConfigMissingProjectThrows() {
        XCTAssertThrowsError(try RelayCLI.parseStartConfig(["--doc", "docs/spec.md", "--pm-worker", "a", "--dev-worker", "b"])) { error in
            XCTAssertEqual(error as? RelayCLI.RelayCLIError, .missingRequired("--project <id|path>"))
        }
    }

    func testParseStartConfigMissingPmWorkerThrows() {
        XCTAssertThrowsError(try RelayCLI.parseStartConfig(["--doc", "docs/spec.md", "--project", "x", "--dev-worker", "b"])) { error in
            XCTAssertEqual(error as? RelayCLI.RelayCLIError, .missingRequired("--pm-worker <modelId>"))
        }
    }

    func testParseStartConfigMissingDevWorkerThrows() {
        XCTAssertThrowsError(try RelayCLI.parseStartConfig(["--doc", "docs/spec.md", "--project", "x", "--pm-worker", "a"])) { error in
            XCTAssertEqual(error as? RelayCLI.RelayCLIError, .missingRequired("--dev-worker <modelId>"))
        }
    }

    func testParseStartConfigUnknownProjectThrowsProjectNotFound() throws {
        let store = makeProjectStore()
        XCTAssertThrowsError(try RelayCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "does_not_exist", "--pm-worker", "a", "--dev-worker", "b"],
            projectStore: store
        )) { error in
            XCTAssertEqual(error as? RelayCLI.RelayCLIError, .projectNotFound("does_not_exist"))
        }
    }

    func testParseStartConfigInvalidMaxRoundsThrows() throws {
        let store = makeProjectStore()
        try addProject(store)
        XCTAssertThrowsError(try RelayCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "repo", "--pm-worker", "a", "--dev-worker", "b", "--max-rounds", "0"],
            projectStore: store
        )) { error in
            XCTAssertEqual(error as? RelayCLI.RelayCLIError, .invalidMaxRounds("0"))
        }
        XCTAssertThrowsError(try RelayCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "repo", "--pm-worker", "a", "--dev-worker", "b", "--max-rounds", "nope"],
            projectStore: store
        ))
    }

    func testParseStartConfigHappyPathResolvesProjectAndDefaults() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let config = try RelayCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--pm-worker", "model_pm", "--dev-worker", "model_dev"],
            projectStore: store
        )
        XCTAssertEqual(config.projectRoot, project.normalizedRootPath)
        XCTAssertEqual(config.projectId, project.id)
        XCTAssertEqual(config.docPath, "docs/spec.md")
        XCTAssertEqual(config.pmWorkerId, "model_pm")
        XCTAssertEqual(config.devWorkerId, "model_dev")
        XCTAssertEqual(config.maxRounds, 20)   // default
        XCTAssertNil(config.until)
    }

    func testParseStartConfigCustomMaxRoundsAndUntil() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let config = try RelayCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--pm-worker", "model_pm", "--dev-worker", "model_dev",
             "--max-rounds", "7", "--until", "23:59"],
            projectStore: store
        )
        XCTAssertEqual(config.maxRounds, 7)
        XCTAssertNotNil(config.until)
    }

    // MARK: - parseResumeRequest

    func testParseResumeRequestMissingRelayThrows() {
        XCTAssertThrowsError(try RelayCLI.parseResumeRequest(["--answer", "76"])) { error in
            XCTAssertEqual(error as? RelayCLI.RelayCLIError, .missingRequired("--relay <id>"))
        }
    }

    func testParseResumeRequestMissingAnswerThrows() {
        XCTAssertThrowsError(try RelayCLI.parseResumeRequest(["--relay", "relay_1"])) { error in
            XCTAssertEqual(error as? RelayCLI.RelayCLIError, .missingRequired("--answer <text>"))
        }
    }

    func testParseResumeRequestBlankAnswerThrows() {
        XCTAssertThrowsError(try RelayCLI.parseResumeRequest(["--relay", "relay_1", "--answer", "   "])) { error in
            XCTAssertEqual(error as? RelayCLI.RelayCLIError, .missingRequired("--answer <text>"))
        }
    }

    func testParseResumeRequestUnknownRelayThrowsRelayNotFound() {
        let stateStore = makeRelayStateStore()
        XCTAssertThrowsError(try RelayCLI.parseResumeRequest(
            ["--relay", "relay_ghost", "--answer", "76"], stateStore: stateStore
        )) { error in
            XCTAssertEqual(error as? RelayCLI.RelayCLIError, .relayNotFound("relay_ghost"))
        }
    }

    func testParseResumeRequestNonEscalatedRelayThrowsInvalidState() throws {
        let stateStore = makeRelayStateStore()
        let running = RelayState(
            id: "relay_running", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running, createdAt: Date()
        )
        try stateStore.save(running)
        XCTAssertThrowsError(try RelayCLI.parseResumeRequest(
            ["--relay", "relay_running", "--answer", "76"], stateStore: stateStore
        )) { error in
            XCTAssertEqual(error as? RelayCLI.RelayCLIError, .relayNotEscalated(status: "running"))
        }
    }

    /// Works-test hazard #1: "escalated-only was too narrow" — a `.running` relay whose
    /// owner process died mid-round must be accepted by `relay-resume`, not rejected the
    /// way a genuinely-still-running relay correctly is (see
    /// `testParseResumeRequestNonEscalatedRelayThrowsInvalidState` above).
    func testParseResumeRequestOrphanedRunningRelayIsEligible() throws {
        let stateStore = makeRelayStateStore()
        let running = RelayState(
            id: "relay_orphaned", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running, createdAt: Date()
        )
        try stateStore.save(running)
        // Simulate the owner process dying mid-round (mirrors RunStoreJournalTests'
        // dead-pid fixture): overwrite the marker `save` just wrote for THIS (alive) test
        // process with a pid that cannot possibly be alive.
        let ownerURL = stateStore.rootDirectory.appendingPathComponent("relay_orphaned", isDirectory: true)
            .appendingPathComponent("owner.pid")
        try Data("2000000".utf8).write(to: ownerURL)

        let request = try RelayCLI.parseResumeRequest(
            ["--relay", "relay_orphaned", "--answer", "76"], stateStore: stateStore
        )
        XCTAssertEqual(request.relayId, "relay_orphaned")
    }

    func testParseResumeRequestEscalatedRelayResolvesConfigFromPersistedState() throws {
        let stateStore = makeRelayStateStore()
        let projectStore = makeProjectStore()
        let project = try addProject(projectStore)
        let escalated = RelayState(
            id: "relay_escalated", projectRoot: project.normalizedRootPath, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .escalated, createdAt: Date(),
            note: "76/77 or 88 — say which"
        )
        try stateStore.save(escalated)

        let request = try RelayCLI.parseResumeRequest(
            ["--relay", "relay_escalated", "--answer", "77", "--max-rounds", "5"],
            stateStore: stateStore, projectStore: projectStore
        )
        XCTAssertEqual(request.relayId, "relay_escalated")
        XCTAssertEqual(request.answer, "77")
        XCTAssertEqual(request.priorState.status, .escalated)
        // docPath/pmWorkerId/devWorkerId/projectRoot are taken from the persisted state,
        // never re-derived from CLI flags (a resume can never silently redirect a relay).
        XCTAssertEqual(request.config.projectRoot, project.normalizedRootPath)
        XCTAssertEqual(request.config.projectId, project.id)
        XCTAssertEqual(request.config.docPath, "docs/spec.md")
        XCTAssertEqual(request.config.pmWorkerId, "model_pm")
        XCTAssertEqual(request.config.devWorkerId, "model_dev")
        XCTAssertEqual(request.config.maxRounds, 5)
    }

    // MARK: - errorEnvelope (the recovery-ladder mapping the exit funnel uses)

    func testErrorEnvelopeMapsEveryCaseToACatalogCode() {
        let known = Set(ContractRegistry.milestone1.errors.map(\.code))
        let cases: [RelayCLI.RelayCLIError] = [
            .missingRequired("--doc <path>"),
            .invalidMaxRounds("0"),
            .projectNotFound("x"),
            .relayNotFound("relay_1"),
            .relayNotEscalated(status: "running"),
        ]
        for c in cases {
            let (code, message) = RelayCLI.errorEnvelope(c)
            XCTAssertTrue(known.contains(code), "\(code) missing from error catalog")
            XCTAssertFalse(message.isEmpty)
        }
    }

    // MARK: - RelayDispatch progress/human mappings

    func testProgressJSONMapsEveryEventCase() {
        let events: [RelayCoordinator.RelayEvent] = [
            .roundStarted(round: 1),
            .pmTurnFinished(round: 1, verdict: .continueRelay),
            .gateBlocked(round: 1, dangerClass: "destructiveGit", reason: "destructive git instruction"),
            .devTurnFinished(round: 1),
            .escalated(note: "76/77?"),
            .done(note: "shipped"),
            .stopped(reason: "reached --max-rounds (20)"),
        ]
        for event in events {
            let json = RelayDispatch.progressJSON(event)
            XCTAssertEqual(json.contractVersion, ContractRegistry.contractVersion)
            XCTAssertFalse(json.event.isEmpty)
            XCTAssertFalse(RelayDispatch.humanProgressLine(event).isEmpty)
        }
    }

    func testProgressJSONCarriesEventSpecificFields() {
        XCTAssertEqual(RelayDispatch.progressJSON(.roundStarted(round: 3)).round, 3)
        let pm = RelayDispatch.progressJSON(.pmTurnFinished(round: 2, verdict: .done))
        XCTAssertEqual(pm.round, 2)
        XCTAssertEqual(pm.verdict, "done")
        let gate = RelayDispatch.progressJSON(.gateBlocked(round: 1, dangerClass: "massDeletion", reason: "mass-deletion instruction"))
        XCTAssertEqual(gate.dangerClass, "massDeletion")
        XCTAssertEqual(gate.reason, "mass-deletion instruction")
        XCTAssertEqual(RelayDispatch.progressJSON(.escalated(note: "q?")).note, "q?")
        XCTAssertEqual(RelayDispatch.progressJSON(.done(note: "ok")).note, "ok")
        XCTAssertEqual(RelayDispatch.progressJSON(.stopped(reason: "ceiling")).reason, "ceiling")
    }
}
