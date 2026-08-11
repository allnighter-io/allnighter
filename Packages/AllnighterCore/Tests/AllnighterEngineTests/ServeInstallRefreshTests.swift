import XCTest
@testable import AllnighterEngine

/// ASR-S02c — `refreshAfterInstall()` was superseded by the convergence
/// routine and `CanonicalCLIInstall.beforeBytesChange`. These tests are
/// retired; the live-host rebind arrives in S02d.
final class ServeInstallRefreshTests: XCTestCase {

    func testRefreshAfterInstallIsRetired() {
        XCTAssertTrue(true, "refreshAfterInstall moved to CanonicalCLIInstall.beforeBytesChange — S02d rebinds the live host")
    }
}
