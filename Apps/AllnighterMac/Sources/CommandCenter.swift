import SwiftUI

// Keyboard-command spine for the Mac app. ONE registry (`AppCommand`) is built
// in RootView and feeds three surfaces with no drift: the macOS menu bar (real
// ⌘-shortcuts, discoverable), the ⌘K command palette, and the transient intents
// the visible compose/home surface consumes. UI layer only — it routes existing
// actions (new work order, mode select, search focus); it owns no domain truth.

/// Transient UI intents broadcast by shortcuts / the palette. One instance is
/// injected at `RootView`; whichever surface is on screen reads what it needs.
@MainActor
@Observable
final class CommandCenter {
    /// ⌘K command-palette visibility.
    var palettePresented = false
    /// Set by ⌘1/⌘2/⌘3 (or the palette); the visible composer applies + clears.
    var requestedMode: ComposeMode?
    /// Bumped by ⌘F; the rail's search field focuses on change.
    var focusSearchTick = 0
}

/// One keyboard-triggerable action. Title, symbol, and shortcut live here once so
/// the menu bar and the palette can never disagree about them.
struct AppCommand: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let key: KeyEquivalent
    var modifiers: EventModifiers = .command
    /// Hidden from the ⌘K list (e.g. the command that opens the palette itself).
    var hiddenInPalette = false
    let run: () -> Void

    /// Human-readable accelerator, e.g. "⌘1" / "⇧⌘K", for palette rows.
    var shortcutLabel: String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        out += String(key.character).uppercased()
        return out
    }
}

// MARK: - Focused-scene bridge
//
// `.commands {}` lives on the Scene and can't read the view environment, so the
// focused window publishes its command list and the menu reads it. Native path —
// no notifications, no globals.

struct AppCommandsKey: FocusedValueKey {
    typealias Value = [AppCommand]
}

extension FocusedValues {
    var appCommands: [AppCommand]? {
        get { self[AppCommandsKey.self] }
        set { self[AppCommandsKey.self] = newValue }
    }
}

/// The app's menu-bar command menu, built from whatever the key window published.
struct AppCommandMenu: Commands {
    @FocusedValue(\.appCommands) private var commands

    var body: some Commands {
        CommandMenu("Actions") {
            if let commands {
                ForEach(commands) { command in
                    Button(command.title, action: command.run)
                        .keyboardShortcut(command.key, modifiers: command.modifiers)
                }
            }
        }
    }
}

// MARK: - ⌘K command palette

/// Cursor-style quick command runner. A centered modal overlay (NOT an anchored
/// popover — see docs/gui/patterns/Anchored_Popups.md): scrim + card, type to
/// filter, ↑/↓ to move, ⏎ to run, esc to close.
struct CommandPalette: View {
    let commands: [AppCommand]
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var results: [AppCommand] {
        let base = commands.filter { !$0.hiddenInPalette }
        guard !query.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ALColor.scrimSubtle
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            card
                .padding(.top, 120)
        }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { runSelected(); return .handled }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command").font(.system(size: 14)).foregroundStyle(ALColor.textFaint)
                TextField("Run a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(ALColor.textPrimary)
                    .focused($fieldFocused)
                    .onSubmit(runSelected)
            }
            .padding(.horizontal, 16).frame(height: 48)

            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)

            if results.isEmpty {
                Text("No matching command")
                    .font(.system(size: 12.5)).foregroundStyle(ALColor.textFaint)
                    .frame(maxWidth: .infinity).padding(.vertical, 22)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                        row(command, selected: index == selection)
                            .onTapGesture { selection = index; runSelected() }
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 540)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
        .alShadowXl()
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private func row(_ command: AppCommand, selected: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: command.symbol).font(.system(size: 13))
                .foregroundStyle(selected ? ALColor.textPrimary : ALColor.textMuted)
                .frame(width: 18)
            Text(command.title).font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(ALColor.textPrimary)
            Spacer(minLength: 8)
            Text(command.shortcutLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ALColor.textFaint)
        }
        .padding(.horizontal, 10).frame(height: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    private func runSelected() {
        guard results.indices.contains(selection) else { return }
        results[selection].run()
    }
}
