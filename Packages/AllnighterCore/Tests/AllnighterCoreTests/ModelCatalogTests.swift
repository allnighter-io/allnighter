import XCTest
@testable import AllnighterCore

final class ModelCatalogTests: XCTestCase {
    private var modelsRoot: URL!
    private var rosterURL: URL!

    private func testRegistry() -> DriverRegistry {
        let ids = Set(ModelCatalog.builtIns.map(\.driverId))
        return DriverRegistry(ids.sorted().map { DriverManifest(id: $0, displayName: $0, kind: .headlessCLI) })
    }

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        modelsRoot = base.appendingPathComponent("models", isDirectory: true)
        rosterURL = base.appendingPathComponent("model_roster.json")
        CatalogRoots.overrideForTesting(
            teams: base.appendingPathComponent("teams", isDirectory: true),
            skills: base.appendingPathComponent("skills", isDirectory: true),
            models: modelsRoot)
        ModelCatalog.overrideRosterForTesting(fileURL: rosterURL)
    }

    override func tearDown() {
        CatalogRoots.resetTestingOverrides()
        ModelCatalog.resetTestingOverrides()
        try? FileManager.default.removeItem(at: modelsRoot.deletingLastPathComponent())
        super.tearDown()
    }

    func testBuiltInsDefaultEnabledOnFreshInstall() {
        let registry = testRegistry()
        let models = ModelCatalog.resolvedModels(registry: registry)
        // Fable, Opus, Sonnet 5, ChatGPT 5.6 Sol (Codex), ChatGPT 5.6 Terra (Codex),
        // Grok 4.5, Kimi K3, Cursor Auto, Composer 2.5, Cursor Grok 4.5, Gemini Flash.
        // Cursor Sol + Antigravity Opus stay default-off.
        // Terra medium seat was added default-on in eff7d44e (models: add Codex Terra
        // medium seat), taking the fresh-install count 10 → 11.
        XCTAssertEqual(models.filter(\.enabled).count, 11)
        XCTAssertFalse(models.first { $0.id == "model_agy_opus" }?.enabled ?? true)
        XCTAssertTrue(models.first { $0.id == "model_fable" }?.enabled ?? false)
        XCTAssertFalse(models.first { $0.id == "model_chatgpt_sol" }?.enabled ?? true,
                       "Cursor Sol is never on-Bench by default")
        XCTAssertTrue(models.first { $0.id == "model_chatgpt" }?.enabled ?? false)
        XCTAssertEqual(models.first { $0.id == "model_sonnet" }?.modelLabel, "claude-sonnet-5")
        XCTAssertEqual(models.first { $0.id == "model_chatgpt" }?.displayName, "ChatGPT 5.6 Sol (Codex)")
    }

    func testDisableSonnetPersistsAcrossReload() throws {
        let registry = testRegistry()
        try ModelCatalog.setEnabled("model_sonnet", false)
        let models = ModelCatalog.resolvedModels(registry: registry)
        XCTAssertFalse(models.first { $0.id == "model_sonnet" }!.enabled)
        let reloaded = ModelCatalog.resolvedModels(registry: registry)
        XCTAssertFalse(reloaded.first { $0.id == "model_sonnet" }!.enabled)
    }

    func testReenableRestoresBench() throws {
        let registry = testRegistry()
        try ModelCatalog.setEnabled("model_sonnet", false)
        try ModelCatalog.setEnabled("model_sonnet", true)
        XCTAssertTrue(ModelCatalog.resolvedModels(registry: registry).first { $0.id == "model_sonnet" }!.enabled)
    }

    func testStaleRosterIDIsDiagnosed() throws {
        let registry = testRegistry()
        try ModelRosterPersistence(fileURL: rosterURL).save(
            ModelRosterState(enabledModelIds: ["model_opus", "ghost_model"]))
        let diags = ModelCatalog.diagnostics(registry: registry)
        XCTAssertTrue(diags.contains { $0.code == "MODEL_ROSTER_STALE_ID" && $0.modelId == "ghost_model" })
    }

    func testProbeLabelWhenAllClaudeModelsDisabled() throws {
        try ModelCatalog.setEnabled("model_fable", false)
        try ModelCatalog.setEnabled("model_opus", false)
        try ModelCatalog.setEnabled("model_sonnet", false)
        // Falls back to the Claude-side flagship built-in label for smoke probes.
        XCTAssertEqual(ModelCatalog.probeModelLabel(driverId: "claude_code"), "fable")
    }

    func testCustomModelCRUD() throws {
        let registry = testRegistry()
        let created = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Fabel", modelLabel: "fabel",
            role: .answerer, enabled: true, registry: registry)
        XCTAssertTrue(created.id.hasPrefix("custom_claude_code_"))
        XCTAssertTrue(ModelCatalog.resolvedModels(registry: registry).contains { $0.id == created.id && $0.enabled })

        var updated = created
        updated.displayName = "Fabel 2"
        updated.modelLabel = "fabel-2"
        try ModelCatalog.updateCustom(updated)
        XCTAssertEqual(ModelCatalog.get(created.id)?.displayName, "Fabel 2")

        try ModelCatalog.deleteCustom(created.id)
        XCTAssertNil(ModelCatalog.get(created.id))
    }

    func testAddDisabledStaysOffBench() throws {
        let registry = testRegistry()
        let created = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Fabel", modelLabel: "fabel",
            role: .answerer, enabled: false, registry: registry)
        let model = ModelCatalog.resolvedModels(registry: registry).first { $0.id == created.id }
        XCTAssertFalse(model?.enabled ?? true)
    }

    func testBuiltInDeleteFails() {
        XCTAssertThrowsError(try ModelCatalog.deleteCustom("model_opus")) { error in
            XCTAssertEqual(error as? ModelCatalogError, .builtInImmutable)
        }
    }

    func testUnknownDriverFails() {
        let registry = testRegistry()
        XCTAssertThrowsError(try ModelCatalog.createCustom(
            driverId: "missing_driver", displayName: "X", modelLabel: "x",
            role: .answerer, registry: registry)) { error in
            if case .driverMissing(let id) = error as? ModelCatalogError {
                XCTAssertEqual(id, "missing_driver")
            } else {
                XCTFail("expected driverMissing")
            }
        }
    }

    func testDiscoveryDoesNotRunFromResolvedModels() {
        let registry = testRegistry()
        _ = ModelCatalog.resolvedModels(registry: registry)
        XCTAssertNil(ModelDiscoveryRegistry.provider(for: "claude_code"))
    }

    func testRecognizedModelInheritsDriverCapabilities() {
        // A default-off recognized model (no explicit tags) inherits its CLI's lane
        // capability, so enabling it makes it usable in team resolution.
        let caps = ModelCatalog.capabilities("model_chatgpt_54")
        XCTAssertFalse(caps.laneTags.isEmpty, "gpt-5.4 inherits Codex lanes")
        XCTAssertTrue(caps.capabilityTags.contains(.code))
    }

    func testLighterVariantRanksBelowFlagship() {
        let flagship = ModelCatalog.capabilities("model_chatgpt").strengthRank
        XCTAssertLessThan(ModelCatalog.capabilities("model_chatgpt_54_mini").strengthRank, flagship)
        XCTAssertLessThan(ModelCatalog.capabilities("model_codex_spark").strengthRank, flagship)
        // ChatGPT 5.4 is a capable non-Sol Codex seat — below Sol flagship rank.
        XCTAssertLessThan(ModelCatalog.capabilities("model_chatgpt_54").strengthRank, flagship)
    }

    func testHighValueWorkerModelsOutrankSonnet() {
        let sonnet = ModelCatalog.capabilities("model_sonnet").strengthRank
        XCTAssertGreaterThan(ModelCatalog.capabilities("model_cursor_grok_45").strengthRank, sonnet)
        XCTAssertGreaterThan(ModelCatalog.capabilities("model_kimi_k3").strengthRank, sonnet)
        XCTAssertGreaterThan(ModelCatalog.capabilities("model_grok").strengthRank, sonnet)
    }
}
