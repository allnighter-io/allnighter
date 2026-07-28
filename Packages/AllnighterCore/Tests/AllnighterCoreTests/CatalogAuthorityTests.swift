import XCTest
@testable import AllnighterCore
import AgentOSCLI

final class CatalogAuthorityTests: XCTestCase {

    func testAllBuiltInsOriginateInAgentOSCatalog() throws {
        let catalog = try CatalogLoader.bundled()
        let catalogIDs = Set(catalog.models.map(\.id))
        for builtIn in ModelCatalog.builtIns {
            XCTAssertTrue(catalogIDs.contains(builtIn.id), "built-in \(builtIn.id) missing from AgentOS catalog")
        }
    }

    func testLegacyCatalogResourcesAreNotShipped() {
        let jsons = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let names = Set(jsons.map { $0.deletingPathExtension().lastPathComponent })
        XCTAssertFalse(names.contains("team_default"))
        XCTAssertFalse(names.contains("claude_code"))
        XCTAssertFalse(names.contains("grok"))
    }

    func testMergedCatalogNoSecondBuiltInsEncyclopedia() {
        let source = String(
            decoding: try! Data(contentsOf: catalogSourceURL()),
            as: UTF8.self
        )
        XCTAssertFalse(source.contains("def(\"model_grok\""))
        XCTAssertFalse(source.contains("builtInCapabilities: [String: ModelCapabilities] = ["))
    }

    func testBundledRegistryMatchesAgentOSCatalog() throws {
        let catalog = try CatalogLoader.bundled()
        let registry = ModelCatalog.bundledRegistry()
        XCTAssertEqual(Set(registry.all.map(\.id)), Set(catalog.drivers.map(\.id)))
    }

    private func catalogSourceURL() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AllnighterCore/ModelCatalog.swift")
    }
}
