import XCTest
import AllnighterCore
import AllnighterEngine

/// Guards `DefaultConfig` against drift from `Resources/Drivers/*.json`. The
/// embedded strings are a safety net when the bundle fails to load — they must
/// match the invoke/detect contract, not a stale subset.
final class DefaultConfigDriftTests: XCTestCase {

    private func driversDir() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("Apps/AllnighterMac/Resources/Drivers")
    }

    private func bundledManifest(_ name: String) throws -> DriverManifest {
        let url = driversDir().appendingPathComponent(name)
        return try CoreJSON.decode(DriverManifest.self, from: Data(contentsOf: url))
    }

    func testEmbeddedManifestsMatchBundledCoreFields() throws {
        for embedded in DefaultConfig.manifests {
            let bundled = try bundledManifest("\(embedded.id).json")
            XCTAssertEqual(bundled.id, embedded.id)
            XCTAssertEqual(bundled.displayName, embedded.displayName)
            XCTAssertEqual(bundled.kind, embedded.kind)
            XCTAssertEqual(bundled.detectCommand, embedded.detectCommand)
            XCTAssertEqual(bundled.smokeTestCommand, embedded.smokeTestCommand)
            XCTAssertEqual(bundled.smokeTestExpect, embedded.smokeTestExpect)
            XCTAssertEqual(bundled.invoke?.command, embedded.invoke?.command)
            XCTAssertEqual(bundled.invoke?.args, embedded.invoke?.args)
        }
    }

    func testEmbeddedWorkersMatchModelCatalogBuiltIns() throws {
        let url = driversDir().appendingPathComponent("team_default.json")
        let bundled = try CoreJSON.decode([Model].self, from: Data(contentsOf: url))
        let expected = ModelCatalog.defaultFreshModels()
        let sortByID: ([Model]) -> [Model] = { $0.sorted { $0.id < $1.id } }
        XCTAssertEqual(sortByID(bundled).map(\.id), sortByID(expected).map(\.id))
        XCTAssertEqual(sortByID(bundled).map(\.driverId), sortByID(expected).map(\.driverId))
        XCTAssertEqual(sortByID(bundled).map(\.modelLabel), sortByID(expected).map(\.modelLabel))
        XCTAssertEqual(sortByID(bundled).map(\.displayName), sortByID(expected).map(\.displayName))
    }

    func testEveryHeadlessDriverHasBuiltInModelAndProbeLabel() {
        let registry = DefaultConfig.registry
        for manifest in registry.all where manifest.kind == .headlessCLI {
            let models = ModelCatalog.list(driverId: manifest.id)
            XCTAssertFalse(models.isEmpty, "driver \(manifest.id) missing built-in models")
            XCTAssertNotNil(
                ModelCatalog.probeModelLabel(driverId: manifest.id),
                "driver \(manifest.id) missing probe label")
        }
    }
}
