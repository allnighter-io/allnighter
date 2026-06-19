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
        MacNotificationDelivery.shared.configure()
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
    @State private var floorStatus = FloorManagerStatus()
    @State private var threads: ThreadsViewModel
    @State private var projects = ProjectsViewModel()

    init() {
        #if DEBUG
        GUIFixture.bootstrap()
        #endif
        let floor = FloorManagerStatus()
        _floorStatus = State(initialValue: floor)
        _threads = State(initialValue: ThreadsViewModel(floorStatus: floor))
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        Window("Allnighter", id: "main") {
            RootView(threads: threads)
                .environment(model)
                .environment(threads)
                .environment(projects)
                .environment(floorStatus)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommandMenu() }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .environment(threads)
                .environment(projects)
                .environment(floorStatus)
        } label: {
            MenuBarLabel()
                .environment(floorStatus)
        }
    }
}

private struct MenuBarLabel: View {
    @Environment(FloorManagerStatus.self) private var floorStatus

    var body: some View {
        HStack(spacing: 3) {
            Image("MenuBarGlyph")
            if floorStatus.anyThreadRunning {
                Circle()
                    .fill(ALColor.accent)
                    .frame(width: 5, height: 5)
                    .accessibilityLabel("Bench running")
            }
            if floorStatus.needsAttentionCount > 0 {
                Text("\(floorStatus.needsAttentionCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ALColor.textPrimary)
                    .accessibilityLabel("\(floorStatus.needsAttentionCount) threads need attention")
            }
        }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var model
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(FloorManagerStatus.self) private var floorStatus

    var body: some View {
        if floorStatus.anyThreadRunning {
            Label("Bench running", systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(ALColor.accent)
        }
        if floorStatus.needsAttentionCount > 0 {
            Text("\(floorStatus.needsAttentionCount) need attention")
                .font(.caption)
        }
        Button(attentionButtonTitle) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
            threads.openPriorityThreadFromMenuBar()
        }
        .disabled(floorStatus.priorityThreadId == nil)
        Button("Open Allnighter") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Button("Quick capture (paste prompt)") {
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

    private var attentionButtonTitle: String {
        if floorStatus.needsAttentionCount > 0 {
            return "Open attention (\(floorStatus.needsAttentionCount))"
        }
        return "Open highest-priority thread"
    }
}
