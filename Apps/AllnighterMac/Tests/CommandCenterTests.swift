import XCTest
import SwiftUI
@testable import AllnighterMac

/// The keyboard-command spine: accelerator labels render correctly and the
/// palette filter is honored, so the menu bar and ⌘K palette stay in sync.
final class CommandCenterTests: XCTestCase {

    private func command(
        _ id: String, _ title: String, key: KeyEquivalent,
        modifiers: EventModifiers = .command, hiddenInPalette: Bool = false
    ) -> AppCommand {
        AppCommand(id: id, title: title, symbol: "circle", key: key,
                   modifiers: modifiers, hiddenInPalette: hiddenInPalette) {}
    }

    func testShortcutLabelRendersCommandAndDigit() {
        XCTAssertEqual(command("a", "A", key: "1").shortcutLabel, "⌘1")
        XCTAssertEqual(command("b", "B", key: "n").shortcutLabel, "⌘N")
    }

    func testShortcutLabelOrdersModifiers() {
        let cmd = command("c", "C", key: "k", modifiers: [.command, .shift, .option])
        XCTAssertEqual(cmd.shortcutLabel, "⌥⇧⌘K")
    }

    func testShortcutLabelRendersFunctionAndSpecialKeys() {
        // F2 used to render as "⌘?" — the bug this fixes.
        let f2 = KeyEquivalent(Character(UnicodeScalar(0xF705)!))
        XCTAssertEqual(command("rename", "Rename", key: f2, modifiers: []).shortcutLabel, "F2")
        XCTAssertEqual(command("up", "Up", key: .upArrow).shortcutLabel, "⌘↑")
        XCTAssertEqual(command("ret", "Send", key: .return).shortcutLabel, "⌘↩")
        XCTAssertEqual(command("pick", "Picker", key: "/").shortcutLabel, "⌘/")
    }

    func testDefaultBindingCapturesKeyAndModifiers() {
        let cmd = command("x", "X", key: "k", modifiers: [.command, .shift])
        XCTAssertEqual(cmd.defaultBinding, KeyBinding(key: "k", modifiers: [.command, .shift]))
        XCTAssertNotEqual(cmd.defaultBinding, KeyBinding(key: "k", modifiers: [.command]))
    }

    func testPaletteHidesHiddenCommandsButMenuKeepsThem() {
        let all = [
            command("new", "New run", key: "n"),
            command("palette", "Command palette", key: "k", hiddenInPalette: true),
        ]
        let visible = all.filter { !$0.hiddenInPalette }
        XCTAssertEqual(visible.map(\.id), ["new"])
        XCTAssertEqual(all.count, 2)
    }
}
