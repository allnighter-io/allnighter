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

    func testEmbeddedWorkersMatchPanelDefaultJSON() throws {
        let url = driversDir().appendingPathComponent("panel_default.json")
        let bundled = try CoreJSON.decode([Worker].self, from: Data(contentsOf: url))
        XCTAssertEqual(bundled.map(\.id), DefaultConfig.workers.map(\.id))
        XCTAssertEqual(bundled.map(\.driverId), DefaultConfig.workers.map(\.driverId))
        XCTAssertEqual(bundled.map(\.modelLabel), DefaultConfig.workers.map(\.modelLabel))
    }
}
