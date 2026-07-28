import XCTest
@testable import AllnighterCore

final class ModelDisplayNameTests: XCTestCase {
    func testDefaultDriverOmitsParenthetical() {
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "ChatGPT 5.6 Sol (Codex)", modelId: "model_chatgpt", driverId: "codex"),
            "ChatGPT 5.6 Sol")
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "Opus 5", modelId: "model_opus", driverId: "claude_code"),
            "Opus 5")
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "ChatGPT 5.6 Terra (Codex)", modelId: "model_chatgpt_terra", driverId: "codex"),
            "ChatGPT 5.6 Terra")
    }

    func testNonDefaultDriverAddsParenthetical() {
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "ChatGPT 5.6 Sol", modelId: "model_chatgpt_sol", driverId: "cursor_agent"),
            "ChatGPT 5.6 Sol (Cursor)")
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "Fable 5", modelId: "model_fable", driverId: "cursor_agent"),
            "Fable 5 (Cursor)")
    }

    func testCursorNativeSeatsStayUnsuffixedOnCursor() {
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "Composer 2.5", modelId: "model_cursor_composer_25", driverId: "cursor_agent"),
            "Composer 2.5")
    }
}
