import XCTest
@testable import AllnighterCore

final class CLIPaintTests: XCTestCase {
    func testColorDisabledWhenNotTTY() {
        XCTAssertFalse(CLIPaint.colorEnabled(stdoutIsTTY: false, environment: ["TERM": "xterm-256color"]))
    }

    func testColorDisabledByNOCOLOR() {
        XCTAssertFalse(CLIPaint.colorEnabled(
            stdoutIsTTY: true,
            environment: ["TERM": "xterm-256color", "NO_COLOR": "1"]
        ))
    }

    func testColorDisabledForDumbTERM() {
        XCTAssertFalse(CLIPaint.colorEnabled(stdoutIsTTY: true, environment: ["TERM": "dumb"]))
    }

    func testColorEnabledOnTTY() {
        XCTAssertTrue(CLIPaint.colorEnabled(stdoutIsTTY: true, environment: ["TERM": "xterm-256color"]))
    }

    func testPaintIsNoOpWithoutColor() {
        XCTAssertEqual(CLIPaint.accent("allnighter", color: false), "allnighter")
        XCTAssertEqual(CLIPaint.cursorBlock(color: false), "")
        XCTAssertFalse(CLIPaint.muted("help", color: false).contains("\u{1B}"))
    }

    func testPaintEmitsTruecolorAmber() {
        let painted = CLIPaint.accent("allnighter", color: true)
        XCTAssertTrue(painted.contains("\u{1B}[1;38;2;255;166;48m"))
        XCTAssertTrue(painted.hasSuffix("\u{1B}[0m"))
        XCTAssertTrue(painted.contains("allnighter"))
    }

    func testCommandUsesLighterAmber() {
        let painted = CLIPaint.command("alln capacity", color: true)
        XCTAssertTrue(painted.contains("\u{1B}[38;2;255;193;105m"))
        XCTAssertFalse(painted.contains("\u{1B}[1;"))
    }
}
