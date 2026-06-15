import SwiftUI

@main
struct AllnighterMacApp: App {
    @State private var model: AppModel

    init() {
        // Make spawned CLIs resolve/authenticate as in a terminal.
        LoginShell.applyToProcessEnvironment()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        Window("Allnighter", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("Allnighter", systemImage: "moon.stars.fill") {
            MenuBarContent()
                .environment(model)
        }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Open Allnighter") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Button("Quick capture (paste prompt)") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
            model.quickCapture(prefillClipboard: true)
        }
        Text("Global hotkey: ⌥⌘Space")
            .font(.caption)
        if model.isRunning {
            Text("Team running…")
        }
        Divider()
        Button("Quit Allnighter") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
