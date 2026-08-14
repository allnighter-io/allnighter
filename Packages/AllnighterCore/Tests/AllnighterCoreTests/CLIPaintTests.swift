import XCTest
@testable import AllnighterCore

final class CLIPaintTests: XCTestCase {
    private let modernEnv = ["TERM": "xterm-256color", "TERM_PROGRAM": "iTerm.app"]
    private let terminalAppEnv = ["TERM": "xterm-256color", "TERM_PROGRAM": "Apple_Terminal"]

    func testColorDisabledWhenNotTTY() {
        XCTAssertFalse(CLIPaint.colorEnabled(stdoutIsTTY: false, environment: modernEnv))
    }

    func testColorDisabledByNOCOLOR() {
        XCTAssertFalse(CLIPaint.colorEnabled(
            stdoutIsTTY: true,
            environment: modernEnv.merging(["NO_COLOR": "1"]) { _, new in new }
        ))
    }

    func testColorDisabledForDumbTERM() {
        XCTAssertFalse(CLIPaint.colorEnabled(stdoutIsTTY: true, environment: ["TERM": "dumb"]))
    }

    func testColorEnabledOnTTY() {
        XCTAssertTrue(CLIPaint.colorEnabled(stdoutIsTTY: true, environment: modernEnv))
    }

    func testColorModeUsesIndexed256OnAppleTerminal() {
        XCTAssertEqual(
            CLIPaint.colorMode(stdoutIsTTY: true, environment: terminalAppEnv),
            .indexed256
        )
    }

    func testColorModeUsesTruecolorOnModernTerminals() {
        XCTAssertEqual(
            CLIPaint.colorMode(stdoutIsTTY: true, environment: modernEnv),
            .truecolor
        )
    }

    func testPaintIsNoOpWithoutColor() {
        XCTAssertEqual(CLIPaint.accent("allnighter", color: false), "allnighter")
        XCTAssertEqual(CLIPaint.cursorBlock(color: false), "")
        XCTAssertFalse(CLIPaint.muted("help", color: false).contains("\u{1B}"))
    }

    func testPaintEmitsTruecolorAmberOnModernTerminals() {
        let painted = CLIPaint.accent("allnighter", color: true, environment: modernEnv)
        XCTAssertTrue(painted.contains("\u{1B}[1;38;2;255;166;48m"))
        XCTAssertTrue(painted.hasSuffix("\u{1B}[0m"))
        XCTAssertTrue(painted.contains("allnighter"))
    }

    func testPaintEmitsIndexedAmberOnAppleTerminal() {
        let painted = CLIPaint.accent("allnighter", color: true, environment: terminalAppEnv)
        let index = CLIPaint.indexed256(CLIPaint.accent)
        XCTAssertTrue(painted.contains("\u{1B}[1;38;5;\(index)m"))
        XCTAssertFalse(painted.contains("38;2;"))
        XCTAssertFalse(painted.contains("48;2;"))
    }

    func testCommandUsesLighterAmberOnModernTerminals() {
        let painted = CLIPaint.command("alln capacity", color: true, environment: modernEnv)
        XCTAssertTrue(painted.contains("\u{1B}[38;2;255;193;105m"))
        XCTAssertFalse(painted.contains("\u{1B}[1;"))
    }

    func testCommandUsesIndexedAmberOnAppleTerminal() {
        let painted = CLIPaint.command("alln capacity", color: true, environment: terminalAppEnv)
        let index = CLIPaint.indexed256(CLIPaint.accentText)
        XCTAssertTrue(painted.contains("\u{1B}[38;5;\(index)m"))
        XCTAssertFalse(painted.contains("38;2;255;193;105m"))
    }

    func testCursorBlockUsesIndexedBackgroundOnAppleTerminal() {
        let block = CLIPaint.cursorBlock(color: true, environment: terminalAppEnv)
        let index = CLIPaint.indexed256(CLIPaint.accent)
        XCTAssertTrue(block.contains("\u{1B}[48;5;\(index)m"))
        XCTAssertFalse(block.contains("48;2;"))
    }
}
