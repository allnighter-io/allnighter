import SwiftUI
import AppKit
import AllnighterCore

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
        // LSUIElement apps promoted to .regular get NO main menu from SwiftUI — so the
        // standard Edit menu is absent and ⌘V/⌘C/⌘X/⌘Z have no item to route to (they
        // just beep in text fields). Install a real menu bar so editing shortcuts work.
        installMainMenu()
        MacNotificationDelivery.shared.configure()
        do {
            try SupportStartupMigrator.runOnce()
        } catch {
            NSLog("SupportStartupMigrator failed: \(error.localizedDescription)")
        }
        // ONB-S02b: keep Application Support/Recipes in sync with the bundled cards
        // so Finder / agents find them without opening Settings.
        RecipeInstallMirror.sync()
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

    /// Build a standard AppKit main menu (App · Edit · Window). The Edit items use the
    /// first-responder editing selectors (`paste:`, `copy:`, …) so they route to whatever
    /// text view is focused — which is exactly what was missing.
    private func installMainMenu() {
        let appName = ProcessInfo.processInfo.processName
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        // OPC-S06b: About opens Settings › About & updates (shared release channel),
        // not the stock empty about panel.
        appMenu.addItem(
            withTitle: "About \(appName)",
            action: #selector(AppDelegate.openAboutUpdates(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu — the part that fixes the beep.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Window menu (standard).
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    /// Posted when the user chooses App › About — RootView opens Settings › About.
    @objc func openAboutUpdates(_ sender: Any?) {
        NotificationCenter.default.post(name: .allnighterOpenAboutUpdates, object: nil)
    }
}

extension Notification.Name {
    static let allnighterOpenAboutUpdates = Notification.Name("allnighter.openAboutUpdates")
}

@main
struct AllnighterMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var remoteAccount = RemoteAccountModel()
    @State private var floorStatus = FloorManagerStatus()
    @State private var threads: ThreadsViewModel
    @State private var projects = ProjectsViewModel()
    @State private var releaseUpdates = ReleaseUpdateModel()

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
                .environment(remoteAccount)
                .environment(threads)
                .environment(projects)
                .environment(releaseUpdates)
                .environment(floorStatus)
                .frame(minWidth: 1100, minHeight: 720)
                .task {
                    // Started BEFORE the network bootstrap, and never behind it: a
                    // hung or slow `bootstrap()` used to leave an open, visible app
                    // that never drained the mailbox — indistinguishable, from the
                    // caller's side, from Allnighter not being open at all.
                    // Lets Allnighter work from inside a sandboxed terminal: that
                    // caller can't start your AI tools, so it leaves the request
                    // here and the app runs it. See SandboxHandoffHost.
                    SandboxHandoffHost.shared.start()
                    await remoteAccount.bootstrap()
                }
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
