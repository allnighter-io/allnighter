import XCTest
@testable import AllnighterCore

final class ModelDisplayNameTests: XCTestCase {
    func testDefaultDriverOmitsParenthetical() {
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "GPT-5.6 Sol (Codex)", modelId: "model_gpt_sol", driverId: "codex"),
            "GPT-5.6 Sol")
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "Opus 5", modelId: "model_opus", driverId: "claude_code"),
            "Opus 5")
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "GPT-5.6 Terra (Codex)", modelId: "model_gpt_terra", driverId: "codex"),
            "GPT-5.6 Terra")
    }

    func testNonDefaultDriverAddsParenthetical() {
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "GPT-5.6 Sol", modelId: "model_cursor_gpt_sol", driverId: "cursor_agent"),
            "GPT-5.6 Sol (Cursor)")
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "Fable 5", modelId: "model_cursor_fable", driverId: "cursor_agent"),
            "Fable 5 (Cursor)")
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "Opus 5", modelId: "model_cursor_opus", driverId: "cursor_agent"),
            "Opus 5 (Cursor)")
    }

    func testDriverSubtitleUsesFriendlyHomeLabelOrRawDriverId() {
        XCTAssertEqual(
            ModelDisplayName.driverSubtitle(modelId: "model_gpt_sol", driverId: "codex"),
            "Codex")
        XCTAssertEqual(
            ModelDisplayName.driverSubtitle(modelId: "model_gpt_terra", driverId: "codex"),
            "Codex")
        XCTAssertEqual(
            ModelDisplayName.driverSubtitle(modelId: "model_cursor_gpt_sol", driverId: "cursor_agent"),
            "cursor_agent")
        XCTAssertEqual(
            ModelDisplayName.driverSubtitle(modelId: "model_cursor_fable", driverId: "cursor_agent"),
            "cursor_agent")
        XCTAssertEqual(
            ModelDisplayName.driverSubtitle(modelId: "model_cursor_composer_25", driverId: "cursor_agent"),
            "Cursor")
    }

    func testCursorNativeSeatsStayUnsuffixedOnCursor() {
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "Composer 2.5", modelId: "model_cursor_composer_25", driverId: "cursor_agent"),
            "Composer 2.5")
    }

    func testAntigravityClaudeSeatsShowAntigravityParenthetical() {
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "Opus 4.6", modelId: "model_agy_opus", driverId: "antigravity"),
            "Opus 4.6 (Antigravity)")
        XCTAssertEqual(
            ModelDisplayName.format(baseName: "Sonnet 4.6", modelId: "model_agy_sonnet", driverId: "antigravity"),
            "Sonnet 4.6 (Antigravity)")
    }
}
