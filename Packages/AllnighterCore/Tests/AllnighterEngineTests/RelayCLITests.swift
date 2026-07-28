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

    /// Hermetic worker catalog fixture (mirrors `PilotCLITests`) — `parseStartConfig`
    /// resolves `--pm-worker`/`--dev-worker` before it resolves the project, so every
    /// call that reaches that far needs a catalog; this keeps tests off live user
    /// config (founder's real enabled models are unrelated ids like model_opus).
    private let testModels: [Model] = [
        Model(id: "model_pm", displayName: "PM", modelLabel: "pm", driverId: "claude_code", role: .both),
        Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "claude_code", role: .both),
    ]

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
            ["--doc", "docs/spec.md", "--project", "does_not_exist", "--pm-worker", "model_pm", "--dev-worker", "model_dev"],
            projectStore: store,
            models: testModels
        )) { error in
            XCTAssertEqual(error as? RelayCLI.RelayCLIError, .projectNotFound("does_not_exist"))
        }
    }

    func testParseStartConfigInvalidMaxRoundsThrows() throws {
        let store = makeProjectStore()
        try addProject(store)
        XCTAssertThrowsError(try RelayCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "repo", "--pm-worker", "model_pm", "--dev-worker", "model_dev", "--max-rounds", "0"],
            projectStore: store,
            models: testModels
        )) { error in
            XCTAssertEqual(error as? RelayCLI.RelayCLIError, .invalidMaxRounds("0"))
        }
        XCTAssertThrowsError(try RelayCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "repo", "--pm-worker", "model_pm", "--dev-worker", "model_dev", "--max-rounds", "nope"],
            projectStore: store,
            models: testModels
        ))
    }

    func testParseStartConfigHappyPathResolvesProjectAndDefaults() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let config = try RelayCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--pm-worker", "model_pm", "--dev-worker", "model_dev"],
            projectStore: store,
            models: testModels
        )
        XCTAssertEqual(config.projectRoot, project.normalizedRootPath)
        XCTAssertEqual(config.projectId, project.id)
        XCTAssertEqual(config.docPath, "docs/spec.md")
        XCTAssertEqual(config.pmWorkerId, "model_pm")
        XCTAssertEqual(config.devWorkerId, "model_dev")
        XCTAssertEqual(config.maxRounds, 20)   // default
        XCTAssertNil(config.until)
        XCTAssertNil(config.devTurnIdleTimeoutSeconds)   // default: no override
    }

    func testParseStartConfigCustomMaxRoundsAndUntil() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let config = try RelayCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--pm-worker", "model_pm", "--dev-worker", "model_dev",
             "--max-rounds", "7", "--until", "23:59"],
            projectStore: store,
            models: testModels
        )
        XCTAssertEqual(config.maxRounds, 7)
        XCTAssertNotNil(config.until)
    }

    /// SR-8 (Sol F18): a malformed `--until` must be rejected loudly, not silently dropped
    /// (which would leave an unattended relay running past its intended ceiling).
    func testParseStartConfigInvalidUntilThrows() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        for bad in ["7am", "25:00", "12:99", "noon"] {
            XCTAssertThrowsError(try RelayCLI.parseStartConfig(
                ["--doc", "docs/spec.md", "--project", project.id, "--pm-worker", "model_pm", "--dev-worker", "model_dev", "--until", bad],
                projectStore: store,
                models: testModels
            )) { error in
                XCTAssertEqual(error as? RelayCLI.RelayCLIError, .invalidUntil(bad), "bad=\(bad)")
            }
        }
    }

    // PO-F7: `--idle-timeout` reuses PO-F5's `RunCLI.parseIdleTimeoutSeconds` helper.
    func testParseStartConfigIdleTimeoutFlowsToConfig() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let config = try RelayCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--pm-worker", "model_pm", "--dev-worker", "model_dev",
             "--idle-timeout", "900"],
            projectStore: store,
            models: testModels
        )
        XCTAssertEqual(config.devTurnIdleTimeoutSeconds, 900)
    }

    func testParseStartConfigInvalidIdleTimeoutThrows() throws {
        let store = makeProjectStore()
        try addProject(store)
        XCTAssertThrowsError(try RelayCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "repo", "--pm-worker", "model_pm", "--dev-worker", "model_dev", "--idle-timeout", "0"],
            projectStore: store,
            models: testModels
        )) { error in
            guard case .invalidIdleTimeout(let message) = error as? RelayCLI.RelayCLIError else {
                return XCTFail("expected invalidIdleTimeout, got \(error)")
            }
            XCTAssertTrue(message.contains("--idle-timeout"), message)
        }
    }

    /// The regression this whole file exists to prevent: an unresolvable
    /// `--pm-worker`/`--dev-worker` must THROW (not `exit()` the process) — this is
    /// a `throws` parse helper called in-process by unit tests, not a `run*` entry
    /// point, and the file's own header comment says only entry points touch `exit()`.
    func testParseStartConfigUnknownPmWorkerThrowsWorkerNotAvailable() throws {
        let store = makeProjectStore()
        try addProject(store)
        XCTAssertThrowsError(try RelayCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "repo", "--pm-worker", "model_ghost", "--dev-worker", "model_dev"],
            projectStore: store,
            models: testModels
        )) { error in
            guard case .workerNotAvailable(let failure) = error as? RelayCLI.RelayCLIError else {
                return XCTFail("expected workerNotAvailable, got \(error)")
            }
            XCTAssertEqual(failure.code, "WORKER_NOT_AVAILABLE")
            XCTAssertEqual(failure.flag, "--pm-worker")
            XCTAssertEqual(failure.provided, "model_ghost")
        }
    }

    func testParseStartConfigUnknownDevWorkerThrowsWorkerNotAvailable() throws {
        let store = makeProjectStore()
        try addProject(store)
        XCTAssertThrowsError(try RelayCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "repo", "--pm-worker", "model_pm", "--dev-worker", "model_ghost"],
            projectStore: store,
            models: testModels
        )) { error in
            guard case .workerNotAvailable(let failure) = error as? RelayCLI.RelayCLIError else {
                return XCTFail("expected workerNotAvailable, got \(error)")
            }
            XCTAssertEqual(failure.code, "WORKER_NOT_AVAILABLE")
            XCTAssertEqual(failure.flag, "--dev-worker")
            XCTAssertEqual(failure.provided, "model_ghost")
        }
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
            .invalidUntil("7am"),
            .invalidIdleTimeout("--idle-timeout must be a positive integer number of seconds, got '0'"),
            .projectNotFound("x"),
            .relayNotFound("relay_1"),
            .relayNotEscalated(status: "running"),
            .workerNotAvailable(ExactIdResolver.Failure(
                code: "WORKER_NOT_AVAILABLE", kind: .worker, flag: "--pm-worker", provided: "model_ghost",
                message: "unknown worker id 'model_ghost'", candidates: [], discoveryCommand: "alln menu --json"
            )),
        ]
        for c in cases {
            let (code, message) = RelayCLI.errorEnvelope(c)
            XCTAssertTrue(known.contains(code), "\(code) missing from error catalog")
            XCTAssertFalse(message.isEmpty)
        }
    }

    /// RSC-S01: `RelayCoordinator.resume`'s `DispatchRefusal` channel, including the
    /// new `.roundInFlight` case, maps to a real catalog code — specifically
    /// `RELAY_ROUND_IN_FLIGHT` (reused, not invented) for the dispatch-lock refusal.
    func testResumeErrorEnvelopeMapsEveryCaseToACatalogCode() {
        let known = Set(ContractRegistry.milestone1.errors.map(\.code))
        let cases: [RelayCoordinator.DispatchRefusal] = [
            .relayNotFound,
            .notResumable(status: "done"),
            .roundInFlight,
            // RSC-S02: unreachable from `resume` in practice, but `DispatchRefusal` is
            // shared with `run` now — the exhaustive mapping must still cover it.
            .alreadyActive(relayId: "relay_other"),
        ]
        for c in cases {
            let (code, message) = RelayCLI.resumeErrorEnvelope(c, relayId: "relay_1")
            XCTAssertTrue(known.contains(code), "\(code) missing from error catalog")
            XCTAssertFalse(message.isEmpty)
        }
        let (roundInFlightCode, _) = RelayCLI.resumeErrorEnvelope(.roundInFlight, relayId: "relay_1")
        XCTAssertEqual(roundInFlightCode, "RELAY_ROUND_IN_FLIGHT", "reuses the existing pilot code, never a new one")
    }

    /// RSC-S02: `RelayCoordinator.run`'s `DispatchRefusal` channel — `.alreadyActive`
    /// is the only case `run` actually produces — maps to the new `RELAY_ALREADY_ACTIVE`
    /// catalog code and names the existing relay id in the message.
    func testStartErrorEnvelopeMapsAlreadyActiveToRelayAlreadyActive() {
        let known = Set(ContractRegistry.milestone1.errors.map(\.code))
        let (code, message) = RelayCLI.startErrorEnvelope(.alreadyActive(relayId: "relay_existing"))
        XCTAssertEqual(code, "RELAY_ALREADY_ACTIVE")
        XCTAssertTrue(known.contains(code), "\(code) missing from error catalog")
        XCTAssertTrue(message.contains("relay_existing"), "message must name the existing relay id, not just refuse silently")
    }

    /// RSC-S01: `RelayCoordinator.adopt`'s `AdoptError` channel, including the new
    /// `.roundInFlight` case, maps to a real catalog code the same way.
    func testAdoptErrorEnvelopeMapsEveryCaseToACatalogCode() {
        let known = Set(ContractRegistry.milestone1.errors.map(\.code))
        let cases: [RelayCoordinator.AdoptError] = [
            .relayNotFound,
            .notPilotRelay,
            .notAdoptable(status: "running"),
            .roundInFlight,
        ]
        for c in cases {
            let (code, message) = RelayCLI.adoptErrorEnvelope(c)
            XCTAssertTrue(known.contains(code), "\(code) missing from error catalog")
            XCTAssertFalse(message.isEmpty)
        }
        let (roundInFlightCode, _) = RelayCLI.adoptErrorEnvelope(.roundInFlight)
        XCTAssertEqual(roundInFlightCode, "RELAY_ROUND_IN_FLIGHT", "reuses the existing pilot code, never a new one")
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
