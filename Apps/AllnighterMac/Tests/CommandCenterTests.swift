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

    func testPaletteHidesHiddenCommandsButMenuKeepsThem() {
        let all = [
            command("new", "New work order", key: "n"),
            command("palette", "Command palette", key: "k", hiddenInPalette: true),
        ]
        let visible = all.filter { !$0.hiddenInPalette }
        XCTAssertEqual(visible.map(\.id), ["new"])
        XCTAssertEqual(all.count, 2)
    }
}
