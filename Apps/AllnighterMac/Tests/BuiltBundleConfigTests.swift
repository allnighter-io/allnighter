import XCTest
import AllnighterCore
import AllnighterEngine
import AgentOSCLI
@testable import AllnighterMac

/// Release gate: the built `.app` must load the shared AgentOS catalog and overlay.
final class BuiltBundleConfigTests: XCTestCase {

    func testBuiltBundleRegistryMatchesAgentOSCatalog() throws {
        let catalog = try CatalogLoader.bundled()
        let registry = AppConfig.loadDefaultRegistry()
        XCTAssertEqual(Set(registry.all.map(\.id)), Set(catalog.drivers.map(\.id)))
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
        XCTAssertGreaterThanOrEqual(models.count, 14)
        XCTAssertFalse(models.filter(\.enabled).isEmpty)
        XCTAssertGreaterThanOrEqual(Set(models.map(\.driverId)).count, 5)
    }

    func testConfigurationLoadsFromSharedCatalogAuthority() {
        let config = AppConfig.loadConfiguration()
        XCTAssertEqual(config.modelsSource, .bundleResources)
        XCTAssertEqual(config.registrySource, .bundleResources)
    }

    func testConfigurationIsNotBrokenFromBuiltBundle() {
        let config = AppConfig.loadConfiguration()
        XCTAssertFalse(config.isBroken)
        XCTAssertGreaterThanOrEqual(config.models.count, 14)
        XCTAssertFalse(config.models.filter(\.enabled).isEmpty)
        XCTAssertGreaterThanOrEqual(config.registry.all.filter { $0.kind == .headlessCLI }.count, 5)
    }

    func testBuiltBundleDoesNotShipLegacyDriverJSON() {
        let rootJSONs = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let names = Set(rootJSONs.map { $0.deletingPathExtension().lastPathComponent })
        XCTAssertFalse(names.contains("team_default"))
        XCTAssertFalse(names.contains("claude_code"))
        XCTAssertFalse(names.contains("grok"))
    }
}
