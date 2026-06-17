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
        #if DEBUG
        // Grant fixture: request Screen Recording at launch, before SwiftUI paints.
        // No env flags, no gating — macOS must see the request from a frontmost app.
        if GUIFixture.isGrantSession {
            let requested = CGRequestScreenCaptureAccess()
            let preflight = CGPreflightScreenCaptureAccess()
            FileHandle.standardError.write(Data(
                "gui-grant(launch): request=\(requested) preflight=\(preflight) path=\(Bundle.main.bundlePath)\n".utf8
            ))
        }
        #endif
    }
}

@main
struct AllnighterMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        #if DEBUG
        GUIFixture.bootstrap()
        #endif
        // HOTFIX (Launch Authority TCC): cold launch must be process-quiet.
        // Do NOT capture login-shell PATH here — spawning a login shell before
        // first paint reads login profiles/version-manager hooks and triggers
        // TCC prompts attributed to this GUI app. PATH capture is now explicit
        // user intent only (full setup/recheck). Runs reuse cached absolute
        // ToolInvocations from detection (health == runs), so launch needs no
        // ambient PATH mutation.
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
        .commands { AppCommandMenu() }

        // Crescent-only brand mark (template → adapts to the menu bar). The old
        // moon+sparkle SF Symbol is retired everywhere (allnighter-logos README).
        MenuBarExtra("Allnighter", image: "MenuBarGlyph") {
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
            // Use the notification so the single handler owns threads prefill
            // (new thread + composer text) + legacy prompt path + activation.
            NotificationCenter.default.post(name: .allnQuickCapture, object: nil)
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
