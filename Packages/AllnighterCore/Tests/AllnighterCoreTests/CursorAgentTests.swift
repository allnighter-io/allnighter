import XCTest
@testable import AllnighterCore

final class CursorAgentTests: XCTestCase {
    private var rosterURL: URL!

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        rosterURL = base.appendingPathComponent("model_roster.json")
        CatalogRoots.overrideForTesting(
            teams: base.appendingPathComponent("teams", isDirectory: true),
            skills: base.appendingPathComponent("skills", isDirectory: true),
            models: base.appendingPathComponent("models", isDirectory: true))
        ModelCatalog.overrideRosterForTesting(fileURL: rosterURL)
    }

    override func tearDown() {
        CatalogRoots.resetTestingOverrides()
        ModelCatalog.resetTestingOverrides()
        super.tearDown()
    }

    func testManifestRoundTripFromFixture() throws {
        let manifest = try Fixtures.manifest(.manifestCursor)
        XCTAssertEqual(manifest.id, "cursor_agent")
        XCTAssertEqual(manifest.invoke?.command, "agent")
        XCTAssertTrue(manifest.invoke?.args.contains("--trust") ?? false)
        XCTAssertEqual(manifest.setup?.bins, ["agent", "cursor-agent"])
        XCTAssertEqual(manifest.setup?.knownPaths, ["~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"])
        XCTAssertFalse(manifest.setup?.knownPaths.contains(where: { $0.contains("Cursor.app") }) ?? true)
        XCTAssertEqual(manifest.smokeTestCommand?.contains("composer-2.5"), true)
        XCTAssertFalse(manifest.smokeTestCommand?.contains("composer-2.5-fast") ?? true)
        XCTAssertTrue(manifest.setup?.headlessTrust?.required ?? false)
    }

    func testFreshInstallDefaultsAutoAndComposerOnBenchFastOff() {
        let fresh = ModelCatalog.defaultFreshModels()
        let auto = fresh.first { $0.id == "model_cursor_auto" }
        let regular = fresh.first { $0.id == "model_cursor_composer_25" }
        let fast = fresh.first { $0.id == "model_cursor_composer_25_fast" }
        XCTAssertEqual(auto?.driverId, "cursor_agent")
        XCTAssertEqual(auto?.modelLabel, "auto")
        XCTAssertTrue(auto?.enabled ?? false)
        XCTAssertEqual(regular?.driverId, "cursor_agent")
        XCTAssertEqual(regular?.modelLabel, "composer-2.5")
        XCTAssertTrue(regular?.enabled ?? false)
        XCTAssertEqual(fast?.modelLabel, "composer-2.5-fast")
        XCTAssertFalse(fast?.enabled ?? true)
    }

    func testCursorModelIdsAreDriverScoped() {
        XCTAssertTrue(ModelCatalog.builtIns.contains { $0.id == "model_cursor_auto" && $0.driverId == "cursor_agent" })
        XCTAssertTrue(ModelCatalog.builtIns.contains { $0.id == "model_cursor_composer_25" && $0.driverId == "cursor_agent" })
        XCTAssertTrue(ModelCatalog.builtIns.contains { $0.id == "model_cursor_grok_45" && $0.driverId == "cursor_agent" })
        XCTAssertNotEqual("model_cursor_composer_25", "model_composer")
    }

    func testCursorGrok45EncodesEffortInModelLabel() {
        let def = ModelCatalog.builtIns.first { $0.id == "model_cursor_grok_45" }!
        XCTAssertEqual(def.displayName, "Cursor Grok 4.5")
        XCTAssertEqual(def.effortVariants?[.low], "cursor-grok-4.5-low")
        XCTAssertEqual(def.effortVariants?[.med], "cursor-grok-4.5-medium")
        XCTAssertEqual(def.effortVariants?[.high], "cursor-grok-4.5-high")
        let model = Model(id: def.id, displayName: def.displayName, modelLabel: def.modelLabel,
                          driverId: def.driverId, effortVariants: def.effortVariants)
        XCTAssertEqual(model.resolvedLabel(at: .med), "cursor-grok-4.5-medium")
        XCTAssertTrue(model.supportsEffort(manifest: try! Fixtures.manifest(.manifestCursor)))
    }

    func testProbeLabelNeverUsesFastOrAuto() throws {
        try ModelCatalog.setEnabled("model_cursor_composer_25_fast", true)
        try ModelCatalog.setEnabled("model_cursor_auto", true)
        XCTAssertEqual(ModelCatalog.probeModelLabel(driverId: "cursor_agent"), "composer-2.5")
    }

    func testSmokeCommandDoesNotSubstituteFastModel() throws {
        let manifest = try Fixtures.manifest(.manifestCursor)
        XCTAssertEqual(
            manifest.resolvedCommandString(manifest.smokeTestCommand, model: "composer-2.5-fast"),
            manifest.smokeTestCommand)
    }

    func testCodeCorePrefersCursorComposer25() {
        let team = BuiltInTeams.team("code_core")!
        let ready: [Model] = [
            Model(id: "model_cursor_auto", displayName: "Auto", modelLabel: "auto",
                  driverId: "cursor_agent", role: .answerer),
            Model(id: "model_cursor_composer_25", displayName: "Composer 2.5", modelLabel: "composer-2.5",
                  driverId: "cursor_agent", role: .answerer),
            Model(id: "model_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code", role: .both),
            Model(id: "model_chatgpt", displayName: "ChatGPT 5.5", modelLabel: "gpt-5.5", driverId: "codex", role: .answerer),
        ]
        let resolved = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .med, readyModels: ready)
        XCTAssertTrue(resolved.isRunnable)
        XCTAssertEqual(resolved.answerWorkers.first?.modelId, "model_cursor_composer_25")
        XCTAssertEqual(resolved.planWriter?.modelId, "model_opus")
    }
}
