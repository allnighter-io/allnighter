import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// Release gate for Cause 0: the built `.app` must ship real driver manifests and
/// the six-worker panel. Source-tree tests alone cannot catch flattened resources.
final class BuiltBundleConfigTests: XCTestCase {

    func testBuiltBundleShipsDriverManifestsAtResourceRoot() {
        let rootJSONs = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let names = Set(rootJSONs.map { $0.deletingPathExtension().lastPathComponent })
        XCTAssertTrue(
            names.contains("claude_code"),
            "Expected claude_code.json at bundle resource root; found: \(names.sorted())"
        )
        XCTAssertTrue(names.contains("panel_default"), "Expected panel_default.json at bundle resource root")
        XCTAssertGreaterThanOrEqual(names.count, 5, "Expected at least five JSON resources in the built bundle")
    }

    func testBuiltBundleRegistryHasMinimumHeadlessDrivers() {
        let registry = AppConfig.loadDefaultRegistry()
        let headless = registry.all.filter { $0.kind == .headlessCLI }
        XCTAssertGreaterThanOrEqual(
            headless.count, 4,
            "Built bundle registry must include claude_code, codex, grok, antigravity"
        )
    }

    func testBuiltBundlePanelHasSixWorkers() {
        let panel = AppConfig.loadDefaultPanel()
        XCTAssertEqual(panel.count, 6, "panel_default defines six seats across four tools")
        XCTAssertEqual(Set(panel.map(\.driverId)).count, 4, "Six seats on four distinct drivers")
    }

    func testConfigurationLoadsFromBundleNotEmbeddedFallback() {
        let config = AppConfig.loadConfiguration()
        XCTAssertEqual(config.panelSource, .bundleResources, "Panel should load from shipped JSON, not DefaultConfig fallback")
        XCTAssertEqual(config.registrySource, .bundleResources, "Registry should load from shipped JSON, not DefaultConfig fallback")
    }

    func testConfigurationIsNotBrokenFromBuiltBundle() {
        let config = AppConfig.loadConfiguration()
        XCTAssertFalse(config.isBroken)
        XCTAssertEqual(config.panel.count, 6)
        XCTAssertGreaterThanOrEqual(config.registry.all.filter { $0.kind == .headlessCLI }.count, 4)
    }
}
