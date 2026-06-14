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
                .frame(minWidth: 720, minHeight: 560)
        }
        .windowResizability(.contentMinSize)

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
        if model.isRunning {
            Text("Council running…")
        }
        Divider()
        Button("Quit Allnighter") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
