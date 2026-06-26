import XCTest
@testable import AllnighterEngine

final class OpenCodeVisibleTextTests: XCTestCase {
    func testSmokeFixtureShape() {
        let raw = """
        ALLNIGHTER_READY
        > Build · Qwen/Qwen3-Coder-Next · 1.8s
        """
        XCTAssertEqual(TextUtil.extractOpenCodeVisibleText(raw), "ALLNIGHTER_READY")
    }

    func testMultiLineAnswer() {
        let raw = """
        Line one
        Line two
        > Build · zai-org/GLM-5.2 · 2.2s
        """
        XCTAssertEqual(TextUtil.extractOpenCodeVisibleText(raw), "Line one\nLine two")
    }
}
