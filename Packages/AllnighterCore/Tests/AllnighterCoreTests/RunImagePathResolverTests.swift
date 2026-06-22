import XCTest
@testable import AllnighterCore

final class RunImagePathResolverTests: XCTestCase {
    func testIsImagePath() {
        XCTAssertTrue(RunImagePathResolver.isImagePath("option_model_grok#0.png"))
        XCTAssertFalse(RunImagePathResolver.isImagePath("answer.md"))
    }
}
