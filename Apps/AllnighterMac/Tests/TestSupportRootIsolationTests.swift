import XCTest
import AllnighterCore
import AllnighterEngine

/// Mac-host twin of `TestSupportRootIsolationTests`: the original corruption was
/// proven via `RelayResumeControllerTests` under `xcodebuild test`, so this
/// guard must also fail on the Mac XCTest host if the redirect regresses.
final class TestSupportRootIsolationTests: XCTestCase {
    private var previousSupportDir: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousSupportDir = ProcessInfo.processInfo.environment["ALLNIGHTER_SUPPORT_DIR"]
        unsetenv("ALLNIGHTER_SUPPORT_DIR")
    }

    override func tearDownWithError() throws {
        if let previousSupportDir {
            setenv("ALLNIGHTER_SUPPORT_DIR", previousSupportDir, 1)
        } else {
            unsetenv("ALLNIGHTER_SUPPORT_DIR")
        }
        previousSupportDir = nil
        try super.tearDownWithError()
    }

    func testResolvedSupportRootIsNotRealUserLocationUnderTest() throws {
        XCTAssertTrue(
            AllnighterSupportRoot.isRunningUnderTestHost,
            "this test must run under an XCTest host"
        )

        let real = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ).appendingPathComponent("Allnighter", isDirectory: true)
        let realPath = real.standardizedFileURL.path

        let resolved = AllnighterPaths.support.standardizedFileURL
        XCTAssertNotEqual(
            resolved.path, realPath,
            "Mac XCTest must not resolve the real user support root; got \(resolved.path)"
        )
        XCTAssertTrue(
            AllnighterSupportRoot.isTestSupportRedirectActive,
            "redirect must be discoverable"
        )
        let setupURL = SetupStore().fileURL.standardizedFileURL
        XCTAssertTrue(
            setupURL.path.hasPrefix(resolved.path + "/"),
            "SetupStore default must land under the redirected root; got \(setupURL.path)"
        )
    }
}
