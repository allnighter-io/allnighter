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
        XCTAssertEqual(models.filter(\.enabled).count, 6)
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
        try ModelCatalog.setEnabled("model_opus", false)
        try ModelCatalog.setEnabled("model_sonnet", false)
        XCTAssertEqual(ModelCatalog.probeModelLabel(driverId: "claude_code"), "opus")
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
}
