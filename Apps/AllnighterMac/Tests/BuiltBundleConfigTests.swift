import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// Release gate for Cause 0: the built `.app` must ship real driver manifests and
/// the model catalog/bench. Source-tree tests alone cannot catch flattened resources.
final class BuiltBundleConfigTests: XCTestCase {

    func testBuiltBundleShipsDriverManifestsAtResourceRoot() {
        let rootJSONs = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let names = Set(rootJSONs.map { $0.deletingPathExtension().lastPathComponent })
        XCTAssertTrue(
            names.contains("claude_code"),
            "Expected claude_code.json at bundle resource root; found: \(names.sorted())"
        )
        XCTAssertTrue(names.contains("cursor_agent"), "Expected cursor_agent.json at bundle resource root")
        XCTAssertTrue(names.contains("team_default"), "Expected team_default.json at bundle resource root")
        XCTAssertGreaterThanOrEqual(names.count, 6, "Expected at least six JSON resources in the built bundle")
    }

    func testBuiltBundleRegistryHasMinimumHeadlessDrivers() {
        let registry = AppConfig.loadDefaultRegistry()
        let headless = registry.all.filter { $0.kind == .headlessCLI }
        XCTAssertGreaterThanOrEqual(
            headless.count, 5,
            "Built bundle registry must include claude_code, codex, grok, antigravity, cursor_agent"
        )
    }

    func testBuiltBundlePanelHasExpectedCatalogAndBench() {
        let models = AppConfig.loadDefaultModels()
        XCTAssertGreaterThanOrEqual(models.count, 14, "team_default defines the shipped model catalog")
        XCTAssertFalse(models.filter(\.enabled).isEmpty, "the resolved bench should not be empty")
        XCTAssertGreaterThanOrEqual(Set(models.map(\.driverId)).count, 5, "catalog spans the expected driver set")
    }

    func testConfigurationLoadsFromBundleNotEmbeddedFallback() {
        let config = AppConfig.loadConfiguration()
        XCTAssertEqual(config.modelsSource, .bundleResources, "Models should load from shipped JSON, not DefaultConfig fallback")
        XCTAssertEqual(config.registrySource, .bundleResources, "Registry should load from shipped JSON, not DefaultConfig fallback")
    }

    func testConfigurationIsNotBrokenFromBuiltBundle() {
        let config = AppConfig.loadConfiguration()
        XCTAssertFalse(config.isBroken)
        XCTAssertGreaterThanOrEqual(config.models.count, 14)
        XCTAssertFalse(config.models.filter(\.enabled).isEmpty)
        XCTAssertGreaterThanOrEqual(config.registry.all.filter { $0.kind == .headlessCLI }.count, 5)
    }
}
