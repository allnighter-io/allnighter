import XCTest
import AppKit
@testable import AllnighterMac

@MainActor
final class AllnighterTextEditorTests: XCTestCase {
    override func tearDown() {
        NSPasteboard.general.clearContents()
        super.tearDown()
    }

    func testComposerPasteInsertsPlainTextAtSelection() {
        let textView = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
        textView.string = "hello "
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("world", forType: .string)

        textView.paste(nil)

        XCTAssertEqual(textView.string, "hello world")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 11, length: 0))
    }

    func testComposerPasteReplacesSelectedText() {
        let textView = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
        textView.string = "send this"
        textView.setSelectedRange(NSRange(location: 5, length: 4))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("that", forType: .string)

        textView.paste(nil)

        XCTAssertEqual(textView.string, "send that")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))
    }
}
