import SwiftUI
import AppKit

/// The bundle launches as an accessory (`LSUIElement` in Info.plist) so the
/// hosted unit-test runner can connect without hanging. For a real launch we
/// promote to a regular Dock app: visible Dock icon, activated, main window.
/// (Mac_Standalone slice 2 — a standalone Dock app, not menu-bar-only.)
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isTesting: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isTesting else { return }   // stay accessory under XCTest
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct AllnighterMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            Divider()
            Text("Team running…")
            Button("Stop team") { model.stop() }
        }
        Divider()
        Button("Quit Allnighter") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
