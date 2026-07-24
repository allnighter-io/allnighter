import XCTest
@testable import AllnighterEngine

final class ResidentProjectAccessBoundaryTests: XCTestCase {
    private let home = "/Users/example"

    func testProtectedHomeDirectoriesFailClosedWithoutTouchingFilesystem() {
        for directory in ["Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures"] {
            let message = ResidentProjectAccessBoundary.refusalMessage(
                forRawProjectPath: "\(home)/\(directory)/repo",
                homeDirectory: home
            )
            XCTAssertNotNil(message, "\(directory) must be protected")
        }
    }

    func testNonProtectedAbsolutePathIsNotBlocked() {
        XCTAssertNil(ResidentProjectAccessBoundary.refusalMessage(
            forRawProjectPath: "/Users/example/src/repo", homeDirectory: home
        ))
        XCTAssertNil(ResidentProjectAccessBoundary.refusalMessage(
            forRawProjectPath: "/Volumes/work/repo", homeDirectory: home
        ))
    }

    func testRelativePathAndDotTraversalFailClosedOrNormalize() {
        XCTAssertNotNil(ResidentProjectAccessBoundary.refusalMessage(
            forRawProjectPath: "repo", homeDirectory: home
        ))
        XCTAssertNotNil(ResidentProjectAccessBoundary.refusalMessage(
            forRawProjectPath: "/Users/example/Documents/../Documents/repo", homeDirectory: home
        ))
    }
}
