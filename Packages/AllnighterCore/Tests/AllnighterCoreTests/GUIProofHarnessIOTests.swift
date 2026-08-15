import XCTest
@testable import AllnighterCore

final class GUIProofHarnessIOTests: XCTestCase {
    private var scratch: URL!

    override func setUp() {
        super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("gui-proof-io-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        GUIProofHarnessIO.devRootOverride = scratch
    }

    override func tearDown() {
        GUIProofHarnessIO.devRootOverride = nil
        try? FileManager.default.removeItem(at: scratch)
        scratch = nil
        super.tearDown()
    }

    func testWriteLastErrorLandsAtStableDevRootPath() throws {
        GUIProofHarnessIO.writeLastError("catalog missing")
        let body = try String(contentsOf: scratch.appendingPathComponent("gui-proof-last-error.txt"))
        XCTAssertEqual(body, "catalog missing")
        XCTAssertEqual(
            GUIProofHarnessIO.lastErrorURL.lastPathComponent,
            "gui-proof-last-error.txt"
        )
        XCTAssertFalse(GUIProofHarnessIO.lastErrorURL.path.contains("/Build/"))
    }

    func testGrantMarkerIsDeletedWhenPreflightIsFalse() throws {
        GUIProofHarnessIO.writeGrantMarker(
            granted: true,
            bundleIdentifier: "com.allnighter.mac",
            bundlePath: "/tmp/Allnighter.app"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: GUIProofHarnessIO.grantMarkerURL.path))

        GUIProofHarnessIO.writeGrantMarker(
            granted: false,
            bundleIdentifier: "com.allnighter.mac",
            bundlePath: "/tmp/Allnighter.app"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: GUIProofHarnessIO.grantMarkerURL.path))
    }

    func testGrantMarkerRecordsLivePreflight() throws {
        GUIProofHarnessIO.writeGrantMarker(
            granted: true,
            bundleIdentifier: "com.allnighter.mac",
            bundlePath: "/tmp/Allnighter.app"
        )
        let body = try String(contentsOf: GUIProofHarnessIO.grantMarkerURL)
        XCTAssertTrue(body.contains("preflight=true"))
        XCTAssertTrue(body.contains("bundle=com.allnighter.mac"))
    }
}
