import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

final class ModelCatalogCLITests: XCTestCase {
    private var modelsRoot: URL!
    private var rosterURL: URL!

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

    private func runtime() -> ToolRuntime {
        let registry = DriverRegistry(DefaultConfig.manifests)
        let models = ModelCatalog.resolvedModels(registry: registry)
        return ToolRuntime(
            models: models,
            registry: registry,
            teams: TeamCatalog.all,
            config: ToolConfig(),
            asyncTeam: AsyncTeamService(
                models: models, registry: registry, teams: TeamCatalog.all,
                config: ToolConfig(), invocations: [:]),
            readyModels: models.filter(\.enabled))
    }

    func testModelsJSONIsModelListEnvelope() throws {
        let json = ModelsCLI.modelListJSON(runtime: runtime())
        let data = try CoreJSON.encode(json)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj?["schemaVersion"])
        XCTAssertNotNil(obj?["contractVersion"])
        XCTAssertNotNil(obj?["models"])
        XCTAssertNotNil(obj?["diagnostics"])
        XCTAssertTrue((obj?["models"] as? [Any])?.isEmpty == false)
    }

    func testDriverFilter() throws {
        let list = ModelsCLI.modelListJSON(runtime: runtime(), driverId: "claude_code")
        XCTAssertTrue(list.models.allSatisfy { $0.driverId == "claude_code" })
        XCTAssertEqual(list.models.count, 3)   // opus, sonnet, fable
    }

    func testBenchFilterExcludesDisabled() throws {
        try ModelCatalog.setEnabled("model_sonnet", false)
        let rt = runtime()
        let list = ModelsCLI.modelListJSON(runtime: rt, benchOnly: true)
        XCTAssertFalse(list.models.contains { $0.id == "model_sonnet" })
    }

    func testDisableChangesJSON() throws {
        try ModelCatalog.setEnabled("model_sonnet", false)
        let sonnet = ModelsCLI.modelListJSON(runtime: runtime()).models.first { $0.id == "model_sonnet" }
        XCTAssertEqual(sonnet?.state, "available")
        XCTAssertFalse(sonnet?.enabled ?? true)
    }

    func testAddCustomModel() throws {
        let registry = DriverRegistry(DefaultConfig.manifests)
        _ = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Fabel", modelLabel: "fabel",
            role: .answerer, enabled: true, registry: registry)
        let list = ModelsCLI.modelListJSON(runtime: runtime(), driverId: "claude_code")
        let fabel = list.models.first { $0.displayName == "Fabel" }
        XCTAssertEqual(fabel?.state, "onBench")
        XCTAssertTrue(fabel?.enabled ?? false)
    }
}
