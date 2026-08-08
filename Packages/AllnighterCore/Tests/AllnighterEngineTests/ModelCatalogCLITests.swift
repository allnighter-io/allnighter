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
        XCTAssertNotNil(obj?["nextActions"])
        XCTAssertTrue((obj?["models"] as? [Any])?.isEmpty == false)
    }

    func testHumanAndJSONShareModelCount() {
        let json = ModelsCLI.modelListJSON(runtime: runtime())
        XCTAssertEqual(json.models.count, ModelCatalog.list().count)
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

    /// `alln models` is the CATALOG view, not the selection menu. A model that
    /// is off-Bench must still be listed as `available` — otherwise
    /// `models add` → `models verify` → `models enable` is unusable, because the
    /// seat is invisible in the command the user runs to confirm it exists.
    ///
    /// Regression: `ModelListProjector` reconciled through
    /// `MenuCatalog.project(...)` without `detailed:`, inheriting the menu's
    /// `filter(\.enabled)` and silently dropping every disabled model.
    func testCatalogViewListsOffBenchModelsThatTheMenuWouldHide() throws {
        try ModelCatalog.setEnabled("model_sonnet", false)
        let registry = DriverRegistry(DefaultConfig.manifests)
        _ = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Offbench", modelLabel: "offbench",
            role: .answerer, enabled: true, registry: registry)

        let list = ModelsCLI.modelListJSON(runtime: runtime(), driverId: "claude_code")
        let ids = Set(list.models.map(\.id))

        XCTAssertTrue(ids.contains("model_sonnet"), "a disabled built-in must stay in the catalog view")
        XCTAssertEqual(list.models.first { $0.id == "model_sonnet" }?.state, "available")
        XCTAssertTrue(
            list.models.contains { $0.displayName == "Offbench" },
            "a freshly added custom is off-Bench by design and must still be listed")

        // And the Bench view still excludes them — the filter belongs there.
        let bench = ModelsCLI.modelListJSON(runtime: runtime(), driverId: "claude_code", benchOnly: true)
        XCTAssertFalse(bench.models.contains { $0.id == "model_sonnet" })
        XCTAssertFalse(bench.models.contains { $0.displayName == "Offbench" })
    }

    func testAddCustomModel() throws {
        let registry = DriverRegistry(DefaultConfig.manifests)
        _ = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Fabel", modelLabel: "fabel",
            role: .answerer, enabled: true, registry: registry)
        let list = ModelsCLI.modelListJSON(runtime: runtime(), driverId: "claude_code")
        // `try XCTUnwrap`, never `!`: a force-unwrap here aborts the whole test
        // process (signal 5), taking every other suite's result with it. That is
        // how one broken assertion made an entire wall run unreadable.
        let fabel = try XCTUnwrap(
            list.models.first { $0.displayName == "Fabel" },
            "custom model missing from the catalog view")
        // Custom models stay off-Bench until smoke-verified + enable.
        XCTAssertEqual(fabel.state, "available")
        XCTAssertFalse(fabel.enabled)
        XCTAssertEqual(ModelCatalog.get(fabel.id)?.modelSmokeStatus, "unverified")
    }
}
