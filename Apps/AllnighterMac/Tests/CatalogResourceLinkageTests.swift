import XCTest
import AgentOSCLI

/// MCAT-S01a host boundary proof: the Mac app links AgentOSCLI and can resolve
/// the bundled catalog resource through `CatalogLoader.bundled()`.
final class CatalogResourceLinkageTests: XCTestCase {

    func testHostCanLoadAgentOSBundledCatalog() throws {
        let catalog = try CatalogLoader.bundled()
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertTrue(catalog.drivers.contains { $0.id == "grok" })
        XCTAssertTrue(catalog.models.contains { $0.id == "model_grok" })
        XCTAssertEqual(catalog.manifest(driverId: "grok")?.invoke?.timeoutSeconds, 1800)
    }
}
