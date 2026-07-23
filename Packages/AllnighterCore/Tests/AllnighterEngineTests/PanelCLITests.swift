import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

/// PN-S04: `alln panel …` parse/validation + roster resolution
/// (`docs/phases/Pilot_Panel.md`). Mirrors PilotCLITests: exit-free `parse*` helpers.
final class PanelCLITests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-panel-cli-\(UUID().uuidString)", isDirectory: true)
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
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("docs"), withIntermediateDirectories: true
        )
        try "target".write(to: dir.appendingPathComponent("docs/spec.md"), atomically: true, encoding: .utf8)
        return try store.add(path: dir.path, name: nil)
    }

    private func roModels() -> [Model] {
        [
            Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both, enabled: true),
            Model(id: "model_sonnet", displayName: "Sonnet", modelLabel: "sonnet", driverId: "claude_code", role: .both, enabled: true),
            Model(id: "model_codex", displayName: "Codex", modelLabel: "codex", driverId: "codex", role: .both, enabled: true),
            Model(id: "model_cursor_composer_25", displayName: "Composer", modelLabel: "composer", driverId: "cursor", role: .both, enabled: true),
            Model(id: "model_grok", displayName: "Grok 4.5", modelLabel: "grok-4.5", driverId: "grok", role: .both, enabled: true),
            Model(id: "model_cursor_grok_45", displayName: "Cursor Grok 4.5", modelLabel: "cursor-grok-4.5", driverId: "cursor", role: .both, enabled: false),
            Model(id: "model_agy_sonnet", displayName: "Claude Sonnet 4.6", modelLabel: "agy-sonnet", driverId: "antigravity", role: .both, enabled: false),
        ]
    }

    private func roRegistry() -> DriverRegistry {
        // Codex enforce needs args that start with `exec` (real driver shape).
        let codex = DriverManifest(
            id: "codex", displayName: "Codex", kind: .headlessCLI,
            invoke: .init(command: "codex", args: ["exec", "-m", "{{model}}", "{{prompt}}"])
        )
        return DriverRegistry([
            TestSupport.headlessManifest(id: "claude_code", command: "claude"),
            codex,
            TestSupport.headlessManifest(id: "cursor", command: "cursor-agent"),
            TestSupport.headlessManifest(id: "grok", command: "grok"),
            TestSupport.headlessManifest(id: "antigravity", command: "agy"),
        ])
    }

    private func sampleTeams() -> [TeamPreset] {
        [
            TeamPreset(
                id: "code_spec_review", displayName: "Spec Review", lane: .code,
                outputKind: .specReview,
                workerSpecs: [
                    TeamWorkerSpec(id: "a", skillId: "spec_first", purpose: .answer, preferredModelId: "model_opus"),
                    TeamWorkerSpec(id: "b", skillId: "spec_scope", purpose: .answer, preferredModelId: "model_sonnet"),
                ],
                lead: TeamLeadSpec(skillId: "writer", preferredModelId: "model_opus"),
                builtIn: true
            ),
            TeamPreset(
                id: "code_plan", displayName: "Plan", lane: .code,
                outputKind: .plan, isDefaultForLane: true,
                workerSpecs: [
                    TeamWorkerSpec(id: "p", skillId: "product_architect", purpose: .answer, preferredModelId: "model_opus"),
                ],
                lead: TeamLeadSpec(skillId: "plan_writer"),
                builtIn: true
            ),
            TeamPreset(
                id: "code_security_review", displayName: "Security Review", lane: .code,
                outputKind: .securityRegister,
                workerSpecs: [
                    TeamWorkerSpec(id: "s", skillId: "boundary", purpose: .answer, preferredModelId: "model_opus"),
                ],
                lead: TeamLeadSpec(skillId: "sec_writer"),
                builtIn: true
            ),
        ]
    }

    // MARK: - parseStartConfig validation

    func testParseStartMissingDoc() {
        XCTAssertThrowsError(try PanelCLI.parseStartConfig(["--project", "x"])) { error in
            XCTAssertEqual(error as? PanelCLI.PanelCLIError, .missingRequired("--doc <path>"))
        }
    }

    func testParseStartMissingProject() {
        XCTAssertThrowsError(try PanelCLI.parseStartConfig(["--doc", "docs/spec.md"])) { error in
            XCTAssertEqual(error as? PanelCLI.PanelCLIError, .missingRequired("--project <id|path>"))
        }
    }

    func testParseStartUnknownProject() {
        let store = makeProjectStore()
        XCTAssertThrowsError(try PanelCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", "nope", "--seat", "model_opus:adversary"],
            projectStore: store,
            models: roModels(),
            registry: roRegistry(),
            teams: sampleTeams()
        )) { error in
            XCTAssertEqual(error as? PanelCLI.PanelCLIError, .projectNotFound("nope"))
        }
    }

    func testParseStartUniqueTeam() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let request = try PanelCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--team", "code_spec_review"],
            projectStore: store,
            models: roModels(),
            registry: roRegistry(),
            teams: sampleTeams()
        )
        XCTAssertEqual(request.teamId, "code_spec_review")
        XCTAssertEqual(request.seats.count, 2)
        XCTAssertEqual(request.seats[0].workerId, "model_opus")
        XCTAssertFalse(request.rememberedTeam)
    }

    func testParseStartCapabilityOnlyTeamResolvesSkillRowsToReadyModels() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let team = try XCTUnwrap(BuiltInTeams.team("code_spec_review"))

        let request = try PanelCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--team", team.id],
            projectStore: store,
            models: roModels(),
            registry: roRegistry(),
            teams: [team]
        )

        XCTAssertEqual(request.seats.count, 5)
        XCTAssertFalse(request.seats.contains {
            $0.workerId.hasPrefix("spec_")
        })
        XCTAssertTrue(request.seats.allSatisfy {
            let modelID = PanelTeamResolver.modelId(for: $0.workerId)
            return roModels().contains(where: { $0.id == modelID })
        })
    }

    func testParseStartFuzzyTeamRejected() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        XCTAssertThrowsError(try PanelCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--team", "review"],
            projectStore: store,
            models: roModels(),
            registry: roRegistry(),
            teams: sampleTeams()
        )) { error in
            guard case .teamNotFound = error as? PanelCLI.PanelCLIError else {
                return XCTFail("expected teamNotFound, got \(error)")
            }
        }
    }

    func testParseStartNoMatchTeam() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        XCTAssertThrowsError(try PanelCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--team", "pressure"],
            projectStore: store,
            models: roModels(),
            registry: roRegistry(),
            teams: sampleTeams()
        )) { error in
            guard case .teamNotFound = error as? PanelCLI.PanelCLIError else {
                return XCTFail("expected teamNotFound, got \(error)")
            }
        }
    }

    func testParseStartSeatOverride() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let request = try PanelCLI.parseStartConfig(
            [
                "--doc", "docs/spec.md", "--project", project.id, "--team", "code_spec_review",
                "--seat", "model_opus:adversary",
                "--seat", "model_codex:contracts",
            ],
            projectStore: store,
            models: roModels(),
            registry: roRegistry(),
            teams: sampleTeams()
        )
        XCTAssertEqual(request.seats.count, 3)
        XCTAssertEqual(request.seats.first { $0.workerId == "model_opus" }?.lens, "adversary")
        XCTAssertTrue(request.seats.contains { $0.workerId == "model_codex" && $0.lens == "contracts" })
    }

    func testParseStartRememberedFallback() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let teamStore = PanelTeamStore(rootDirectory: tmp.appendingPathComponent("readiness"))
        try teamStore.save(projectId: project.id, teamId: "code_spec_review")
        let request = try PanelCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id],
            projectStore: store,
            models: roModels(),
            registry: roRegistry(),
            teams: sampleTeams(),
            teamStore: teamStore
        )
        XCTAssertTrue(request.rememberedTeam)
        XCTAssertEqual(request.teamId, "code_spec_review")
    }

    func testParseStartLaneDefaultFallback() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let teamStore = PanelTeamStore(rootDirectory: tmp.appendingPathComponent("readiness-empty"))
        let request = try PanelCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id],
            projectStore: store,
            models: roModels(),
            registry: roRegistry(),
            teams: sampleTeams(),
            teamStore: teamStore
        )
        XCTAssertTrue(request.laneDefault)
        XCTAssertEqual(request.teamId, "code_plan")
    }

    func testParseStartNonROSeatAcceptedPlansClone() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        // PN-S06: cursor is not RO-enforcing but is no longer refused — clone isolation.
        let request = try PanelCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--seat", "model_cursor_composer_25:x"],
            projectStore: store,
            models: roModels(),
            registry: roRegistry(),
            teams: sampleTeams()
        )
        XCTAssertEqual(request.seats.map(\.workerId), ["model_cursor_composer_25"])
        let plan = PanelCoordinator.isolationPlan(
            seats: request.seats, models: roModels(), registry: roRegistry()
        )
        XCTAssertEqual(plan.first?.mode, .clone)
        XCTAssertTrue(plan.first?.advisory?.contains("isolation: clone") == true)
    }

    func testParseStartInvalidMaxRounds() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        XCTAssertThrowsError(try PanelCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--team", "code_spec_review", "--max-rounds", "0"],
            projectStore: store,
            models: roModels(),
            registry: roRegistry(),
            teams: sampleTeams()
        )) { error in
            XCTAssertEqual(error as? PanelCLI.PanelCLIError, .invalidMaxRounds("0"))
        }
    }

    // MARK: - --seat exact-id resolution (MR-S04)

    func testParseStartSeatExactIdsHappyPath() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let request = try PanelCLI.parseStartConfig(
            [
                "--doc", "docs/spec.md", "--project", project.id,
                "--seat", "model_sonnet:failure-modes",
                "--seat", "model_grok:simplify",
                "--seat", "model_cursor_grok_45:adoption",
            ],
            projectStore: store,
            models: roModels(),
            registry: roRegistry(),
            teams: sampleTeams()
        )
        XCTAssertEqual(
            request.seats.map(\.workerId),
            ["model_sonnet", "model_grok", "model_cursor_grok_45"]
        )
        XCTAssertEqual(request.seats.map(\.lens), ["failure-modes", "simplify", "adoption"])
        for seat in request.seats {
            XCTAssertTrue(seat.workerId.hasPrefix("model_"))
        }
        let plan = PanelCoordinator.isolationPlan(
            seats: request.seats, models: roModels(), registry: roRegistry()
        )
        let byId = Dictionary(uniqueKeysWithValues: plan.map { ($0.workerId, $0.mode) })
        XCTAssertEqual(byId["model_sonnet"], .driverReadOnly)
        XCTAssertEqual(byId["model_grok"], .clone)
        XCTAssertEqual(byId["model_cursor_grok_45"], .clone)
    }

    func testParseStartSeatFuzzyAliasRejected() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        let models = [
            Model(id: "model_sonnet", displayName: "Sonnet", modelLabel: "sonnet", driverId: "claude_code", role: .both, enabled: true),
            Model(id: "model_agy_sonnet", displayName: "AGY Sonnet", modelLabel: "agy", driverId: "antigravity", role: .both, enabled: true),
        ]
        XCTAssertThrowsError(try PanelCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--seat", "sonnet:x"],
            projectStore: store,
            models: models,
            registry: roRegistry(),
            teams: sampleTeams()
        )) { error in
            guard case .seatNotFound(let alias, _) = error as? PanelCLI.PanelCLIError else {
                return XCTFail("expected seatNotFound, got \(error)")
            }
            XCTAssertEqual(alias, "sonnet")
        }
    }

    func testParseStartSeatAliasUnknownErrorsWithReadySeats() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        XCTAssertThrowsError(try PanelCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--seat", "not_a_model:x"],
            projectStore: store,
            models: roModels(),
            registry: roRegistry(),
            teams: sampleTeams()
        )) { error in
            guard case .seatNotFound(let alias, let ready) = error as? PanelCLI.PanelCLIError else {
                return XCTFail("expected seatNotFound, got \(error)")
            }
            XCTAssertEqual(alias, "not_a_model")
            XCTAssertTrue(ready.contains("model_sonnet"))
        }
    }

    func testParseStartTeamRosterValidatesModelsExist() throws {
        let store = makeProjectStore()
        let project = try addProject(store)
        // Team prefers a model id that is not in the catalog → fail at start.
        let badTeam = TeamPreset(
            id: "bad_team", displayName: "Bad", lane: .code,
            outputKind: .plan,
            workerSpecs: [
                TeamWorkerSpec(id: "a", skillId: "x", purpose: .answer, preferredModelId: "model_does_not_exist"),
            ],
            lead: TeamLeadSpec(skillId: "writer"),
            builtIn: true
        )
        XCTAssertThrowsError(try PanelCLI.parseStartConfig(
            ["--doc", "docs/spec.md", "--project", project.id, "--team", "bad_team"],
            projectStore: store,
            models: roModels(),
            registry: roRegistry(),
            teams: [badTeam]
        )) { error in
            guard case .unknownSeatModel = error as? PanelCLI.PanelCLIError else {
                return XCTFail("expected unknownSeatModel, got \(error)")
            }
        }
    }

    func testErrorEnvelopeSeatAliasCodes() {
        XCTAssertEqual(
            PanelCLI.errorEnvelope(.ambiguousSeat(alias: "s", candidates: "a, b")).code,
            "CLI_USAGE_ERROR"
        )
        XCTAssertEqual(
            PanelCLI.errorEnvelope(.seatNotFound(alias: "x", readySeats: "m")).code,
            "CLI_USAGE_ERROR"
        )
        XCTAssertEqual(
            PanelCLI.errorEnvelope(.unknownSeatModel(workerId: "w", modelId: "m")).code,
            "CLI_USAGE_ERROR"
        )
    }

    // MARK: - scaffold content

    func testScaffoldIncludesRejectionCarryAndStance() {
        let t = PanelBriefScaffold.template(round: 2)
        XCTAssertTrue(t.contains("stance: edit-in-place | propose-first"))
        XCTAssertTrue(t.contains("Refuted last round"))
        XCTAssertTrue(t.contains("do not re-litigate"))
    }

    // MARK: - error envelopes

    func testErrorEnvelopesMapCodes() {
        XCTAssertEqual(PanelCLI.errorEnvelope(.panelNotFound("x")).code, "PANEL_NOT_FOUND")
        XCTAssertEqual(PanelCLI.roundErrorEnvelope(.roundInFlight).code, "PANEL_ROUND_IN_FLIGHT")
        XCTAssertEqual(PanelCLI.roundErrorEnvelope(.targetMissing(path: "p")).code, "PANEL_TARGET_MISSING")
        XCTAssertEqual(PanelCLI.roundErrorEnvelope(.notAwaitingPM(status: "done")).code, "PANEL_NOT_AWAITING")
        XCTAssertEqual(PanelCLI.roundErrorEnvelope(.briefRequired).code, "CLI_USAGE_ERROR")
    }

    // MARK: - dirty advisory never refuses

    func testDirtyTargetAdvisoryIsOptionalString() throws {
        let root = tmp.appendingPathComponent("git-repo")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Without a git repo, dirty list is empty → nil advisory.
        let advisory = PanelCLI.dirtyTargetAdvisory(projectRoot: root.path, targetPath: "docs/spec.md")
        XCTAssertNil(advisory)
    }

    func testPanelStartRosterEchoesIsolationPerSeat() throws {
        let seats = [
            PanelSeat(workerId: "model_sonnet", lens: "failure-modes"),
            PanelSeat(workerId: "model_grok", lens: "simplify"),
        ]
        let isolationModes = ["model_sonnet": "driverReadOnly", "model_grok": "clone"]
        let roster = seats.map { PanelSeatJSON($0, isolation: isolationModes[$0.workerId]) }
        XCTAssertEqual(roster[0].isolation, "driverReadOnly")
        XCTAssertEqual(roster[1].isolation, "clone")
        let data = try CoreJSON.encode(roster)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(json[0]["isolation"] as? String, "driverReadOnly")
        XCTAssertNil(json[0]["isolationMode"])
        XCTAssertEqual(json[1]["isolation"] as? String, "clone")
    }
}
