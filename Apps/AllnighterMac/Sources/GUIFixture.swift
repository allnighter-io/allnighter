import Foundation
import AppKit
import AllnighterCore
@preconcurrency import ScreenCaptureKit

#if DEBUG

/// Designer-mock harness for the GUI Visual Proof Gate (DEBUG builds only).
///
/// ENTIRELY DEBUG-only: compiled out of Release builds. When no proof session is
/// active, this type seeds nothing, captures nothing, and is inert.
///
/// Proof sessions start one of two ways:
/// 1. `bash scripts/gui_proof.sh <fixture>` — writes a request JSON, launches
///    the **`.app` bundle** via `open` (Launch Services), app reads the request.
/// 2. Legacy direct exec with `ALLNIGHTER_GUI_FIXTURE` + `ALLNIGHTER_GUI_PROOF_OUT`.
///
/// Capture is tiered (DEBUG only):
/// - compose-* / tcc-probe: ScreenCaptureKit screenshot (Apple-supported replacement
///   for deprecated CGWindowListCreateImage). Requires Screen Recording grant.
/// - All other fixtures (home-*, thread-*, team-*, etc.): in-process snapshot of
///   the primary window's content view (no TCC, no separate windows). See policy
///   in `docs/phases/GUI_Visual_Proof_Gate.md`.
enum GUIFixture {
    private static let devRoot: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Developer/Allnighter", isDirectory: true)

    static let proofRequestURL = devRoot.appendingPathComponent("gui-proof-request.json")
    static let grantMarkerURL = devRoot.appendingPathComponent("gui-proof-screen-recording.ok")

    static var lastErrorURL: URL {
        buildRoot.appendingPathComponent("gui-proof-last-error.txt")
    }

    private static var buildRoot: URL {
        if let dir = ProcessInfo.processInfo.environment["ALLNIGHTER_BUILD_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return devRoot.appendingPathComponent("Build", isDirectory: true)
    }

    private struct ProofRequest: Codable {
        var fixture: String
        var output: String?
    }

    nonisolated(unsafe) private static var sessionFixture: String?
    nonisolated(unsafe) private static var sessionOutput: String?
    nonisolated(unsafe) private static var didBootstrap = false

    /// Call once at app launch before any fixture gate is read.
    static func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        loadProofRequestIfNeeded()
    }

    /// The active fixture name, or nil on every normal launch.
    static var active: String? {
        bootstrap()
        if let v = ProcessInfo.processInfo.environment["ALLNIGHTER_GUI_FIXTURE"], !v.isEmpty { return v }
        return sessionFixture
    }

    static var isActive: Bool { active != nil }

    static var isGrantSession: Bool { active == "proof-grant" }

    /// PNG output path for the active proof capture session.
    static var proofOutputPath: String? {
        bootstrap()
        if let v = ProcessInfo.processInfo.environment["ALLNIGHTER_GUI_PROOF_OUT"], !v.isEmpty { return v }
        return sessionOutput
    }

    /// Human-readable path mentors/operators paste into the Screen Recording + picker.
    static var grantAppPath: String {
        Bundle.main.bundlePath
    }

    /// Fixtures that open a *native* SwiftUI popover (via .alPopover / AppKit NSPopover window).
    /// These require the full window-list composite capture (Screen Recording TCC).
    /// All other fixtures (home-*, thread-*, team-*, doctor-*, readiness-*) use an
    /// in-process main-window bitmap snapshot and need no Screen Recording permission.
    static var needsNativeOverlays: Bool {
        (active ?? "").hasPrefix("compose-")
    }

    /// Deep-link: open the Team dropdown for `team-*` fixtures.
    static var opensTeamDropdown: Bool { (active ?? "").hasPrefix("team-") }

    /// Deep-link: open Bench health for `doctor-*` fixtures.
    static var opensDoctorPopover: Bool { (active ?? "").hasPrefix("doctor-") }

    /// Deep-link: open Team readiness for `readiness-*` fixtures.
    static var opensReadiness: Bool { (active ?? "").hasPrefix("readiness-") }

    /// Deep-link: show the routing-composer specimen for `compose-*` fixtures.
    static var opensComposeSpecimen: Bool { (active ?? "").hasPrefix("compose-") }

    /// Deep-link: open the Team Studio settings surface for `studio*` fixtures.
    static var opensTeamStudio: Bool { (active ?? "").hasPrefix("studio") }

    /// Which Studio page a `studio-*` fixture deep-links to.
    static var studioRoute: StudioRoute {
        switch active {
        case "studio-teams-code", "studio-team-editor", "studio-worker-editor": return .teams(.code)
        case "studio-teams-design": return .teams(.design)
        case "studio-teams-copy": return .teams(.copy)
        case "studio-skills-code": return .skills(.code)
        default: return .clis
        }
    }

    /// Deep-link: open the team Customize editor over the selected team.
    static var opensTeamEditor: Bool { active == "studio-team-editor" || active == "studio-worker-editor" }

    /// Deep-link: push straight into the level-2 Customize-worker editor.
    static var opensWorkerEditor: Bool { active == "studio-worker-editor" }

    /// Home / thread conversation fixtures stay on HomeView (not the specimen).
    static var opensHomeWorkspace: Bool {
        let name = active ?? ""
        return name.hasPrefix("home-") || name.hasPrefix("thread-") || name == "command-palette"
    }

    /// UNR proof: keep selected-unread below the fold for the rail matrix capture.
    static var suppressUnreadAutoScroll: Bool { active == "home-rail-unr" }

    /// Deep-link: open the Teams workspace (Send-to-team launcher) via the toggle.
    static var opensTeamsLauncher: Bool { active == "teams-launcher" }
    /// Deep-link: open the ⌘K command palette over the home workspace.
    static var opensCommandPalette: Bool { active == "command-palette" }
    /// `compose-mode-menu` seeds the mode menu open for the proof capture.
    static var composeMenuOpen: Bool { active == "compose-mode-menu" }
    /// `compose-target-*` seeds the target popover open.
    static var composeTargetOpen: Bool { (active ?? "").hasPrefix("compose-target-") }

    /// Dedicated fixture for testing the Screen Recording grant / preflight in isolation.
    /// Runs the composite path (so native popovers + SR are exercised) but is intended
    /// only for "does preflight + captureComposite succeed right now?" verification.
    static var isTCCProbe: Bool { (active ?? "") == "tcc-probe" }
    /// Mode for the compose specimen (drives which target popover renders).
    static var composeSpecimenMode: ComposeMode {
        switch active {
        case "compose-target-send-to-team": return .sendToTeam
        case "compose-target-exec": return .exec
        default: return .chat
        }
    }

    /// Which source the repair panel focuses on for readiness fixtures.
    static var readinessFocusDriverId: String? { readinessFocusDriverId(for: active) }

    static func readinessFocusDriverId(for scenario: String?) -> String? {
        switch scenario {
        case "readiness-mixed": return "codex"
        default: return nil
        }
    }

    /// Named bench-health scenarios (GUI proof fixtures + dev panel).
    static let benchScenarios: [(id: String, label: String)] = [
        ("team-open-ready", "All CLIs ready"),
        ("team-open-mixed", "Mixed — team dropdown"),
        ("doctor-open-mixed", "Mixed — CLI setup popover"),
        ("readiness-mixed", "Mixed — CLI setup page"),
        ("readiness-cold", "Cold — never scanned (CLI setup page)"),
        ("home-with-threads", "Home — rail with conversations"),
        ("home-rail", "Home — grouped/filtered rail (CR4e)"),
        ("home-rail-th2", "Home — TH2 triage pin/unread/archive"),
        ("home-rail-unr", "Home — UNR unread matrix (S07)"),
        ("thread-empty", "Thread — empty work order"),
        ("thread-with-turns", "Thread — user message turn"),
        ("thread-chat", "Thread — chat reply from a model"),
        ("thread-team-board", "Thread — fan-out team board"),
        ("thread-dispatch", "Thread — execute → dispatch to repo"),
        ("studio-clis", "Team Studio — CLIs (settings shell)"),
        ("studio-teams-code", "Team Studio — Code teams (detail)"),
        ("studio-skills-code", "Team Studio — Code skills (detail)"),
        ("studio-team-editor", "Team Studio — Customize team editor"),
        ("studio-worker-editor", "Team Studio — Customize worker (skill + prompt)"),
        ("command-palette", "⌘K command palette"),
        ("teams-launcher", "Teams — Send-to-team launcher (G-T0)"),
        ("compose-mode-menu", "Compose — mode menu (native popover)"),
        ("compose-target-chat", "Compose — route to model (native popover)"),
        ("compose-target-send-to-team", "Compose — send to team (native popover)"),
        ("tcc-probe", "TCC / Screen Recording grant probe (forces composite path)"),
    ]

    /// A fixed, deterministic window size for proof captures so the same fixture
    /// always renders to the same frame.
    static let captureWindowSize = NSSize(width: 1100, height: 720)

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func writeGrantMarker() {
        let body = "granted-at=\(ISO8601DateFormatter().string(from: Date()))\n"
            + "bundle=\(Bundle.main.bundleIdentifier ?? "unknown")\n"
            + "path=\(Bundle.main.bundlePath)\n"
        try? FileManager.default.createDirectory(at: devRoot, withIntermediateDirectories: true)
        try? body.write(to: grantMarkerURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Proof request (Launch Services path)

    private static func loadProofRequestIfNeeded() {
        guard sessionFixture == nil,
              ProcessInfo.processInfo.environment["ALLNIGHTER_GUI_FIXTURE"]?.isEmpty != false,
              FileManager.default.fileExists(atPath: proofRequestURL.path)
        else { return }

        defer { try? FileManager.default.removeItem(at: proofRequestURL) }

        guard let data = try? Data(contentsOf: proofRequestURL),
              let req = try? JSONDecoder().decode(ProofRequest.self, from: data),
              !req.fixture.isEmpty
        else {
            log("could not read proof request at \(proofRequestURL.path)")
            return
        }
        sessionFixture = req.fixture
        sessionOutput = req.output
    }

    // MARK: - Seeded health (DESIGNER MOCK — never a real launch)

    static func seededToolStatuses(for models: [Model], now: Date) -> [ToolProbeRecord] {
        seededToolStatuses(for: models, now: now, scenario: active ?? "")
    }

    static func seededToolStatuses(for models: [Model], now: Date, scenario: String) -> [ToolProbeRecord] {
        if scenario == "readiness-cold" { return [] }
        let drivers = orderedDrivers(in: models)
        let name = scenario
        let allReady = name.hasPrefix("compose-") || name.hasPrefix("home-") || name.hasPrefix("thread-")
        return drivers.enumerated().map { index, driver in
            let status = allReady ? ModelSetupStatus.ready(version: "1.0") : status(for: name, index: index, driverId: driver)
            return ToolProbeRecord(
                driverId: driver,
                status: status,
                version: versionString(for: status, fixture: name, driverId: driver),
                lastProbeAt: now
            )
        }
    }

    private static func orderedDrivers(in models: [Model]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for m in models where m.enabled && seen.insert(m.driverId).inserted { out.append(m.driverId) }
        return out
    }

    private static func versionString(for status: ModelSetupStatus, fixture: String, driverId: String) -> String? {
        if case .ready(let v) = status { return v }
        if fixture == "readiness-mixed" {
            switch driverId {
            case "codex": return "codex 0.9.1"
            case "antigravity": return "agy"
            default: break
            }
        }
        return nil
    }

    private static func status(for fixture: String, index: Int, driverId: String) -> ModelSetupStatus {
        switch fixture {
        case "team-open-ready":
            return .ready(version: "1.0.0")
        case "team-open-mixed":
            switch index {
            case 2:
                return .installedNotSignedIn(LoginFlow(
                    interactiveCommand: "claude",
                    instructions: "Run `claude`, then `/login`."
                ))
            case 3:
                return .probeFailed(reason: "exited 1")
            default:
                return .ready(version: "1.0.0")
            }
        case "doctor-open-mixed":
            switch driverId {
            case "claude_code": return .ready(version: "claude 1.2.4")
            case "codex": return .installedNotSignedIn(LoginFlow(
                interactiveCommand: "codex", instructions: "Run `codex login`."))
            case "antigravity": return .shimmedNeedsConfirm(ToolResolution(
                invocation: .loginShell(commandName: "antigravity"),
                rawCommandV: "agy () { … }",
                isAmbiguous: true))
            case "grok": return .notInstalled
            default: return .ready(version: "1.0.0")
            }
        case "readiness-mixed":
            switch driverId {
            case "claude_code": return .ready(version: "claude 1.2.4")
            case "antigravity": return .ready(version: "agy")
            case "codex": return .probeFailed(reason: "error: unknown flag --model (exit 2)")
            case "grok": return .notInstalled
            default: return .ready(version: "1.0.0")
            }
        default:
            return .ready(version: "1.0.0")
        }
    }

    // MARK: - Screen capture

    /// If a proof output path is set, resize, capture, write PNG, terminate.
    @MainActor
    static func captureAndExitIfRequested() {
        guard isActive, !isGrantSession,
              let out = proofOutputPath, !out.isEmpty
        else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if let window = mainWindow() {
                window.setContentSize(captureWindowSize)
                window.center()
            }

            let useScreenRecordingCapture = needsNativeOverlays || isTCCProbe
            if useScreenRecordingCapture {
                if needsNativeOverlays {
                    await waitForOverlayWindows(timeout: 4)
                } else {
                    // tcc-probe: just give the app a moment to have at least the main window
                    try? await Task.sleep(for: .seconds(1))
                }
                switch await captureComposite() {
                case .success(let image):
                    writeGrantMarker()
                    writePNG(image, to: URL(fileURLWithPath: out))
                    NSApp.terminate(nil)
                case .failure(let message):
                    failProof(message)
                    NSApp.terminate(nil)
                }
            } else {
                try? await Task.sleep(for: .seconds(1))
                switch captureMainWindowOnly() {
                case .success(let image):
                    writePNG(image, to: URL(fileURLWithPath: out))
                    NSApp.terminate(nil)
                case .failure(let message):
                    failProof(message)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    @MainActor
    private static func waitForOverlayWindows(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let count = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }.count
            if count > 1 { try? await Task.sleep(for: .milliseconds(200)); return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @MainActor
    private static func writePNG(_ cgImage: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            failProof("PNG encode failed")
            return
        }
        do {
            try data.write(to: url)
            log("wrote \(url.path)")
        } catch {
            failProof("write failed: \(error.localizedDescription)")
        }
    }

    private enum CaptureResult {
        case success(CGImage)
        case failure(String)
    }

    /// Composite the app's own windows (including separate popover windows) via
    /// ScreenCaptureKit — the supported API; CGWindowListCreateImage is deprecated
    /// and returns nil on modern macOS even when Screen Recording is granted.
    @MainActor
    private static func captureComposite() async -> CaptureResult {
        let appWindows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
        guard !appWindows.isEmpty else { return .failure("no window to capture") }

        guard CGPreflightScreenCaptureAccess() else {
            NSApp.activate(ignoringOtherApps: true)
            _ = CGRequestScreenCaptureAccess()
            return .failure("""
            CGPreflightScreenCaptureAccess() is false after requesting access. \
            Open System Settings → Screen & System Audio Recording, add Allnighter \
            with + if missing, toggle ON, then re-run. \(screenRecordingInstructions)
            """)
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let bundleID = Bundle.main.bundleIdentifier ?? "com.allnighter.mac"
            let visibleIDs = Set(appWindows.map { CGWindowID($0.windowNumber) })

            var scWindows = content.windows.filter { window in
                window.owningApplication?.bundleIdentifier == bundleID && visibleIDs.contains(window.windowID)
            }
            if scWindows.isEmpty {
                scWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleID }
            }
            guard !scWindows.isEmpty else {
                return .failure("ScreenCaptureKit: no shareable windows for \(bundleID) (NSApp visible=\(appWindows.count))")
            }

            let filter: SCContentFilter
            if scWindows.count == 1, let only = scWindows.first {
                filter = SCContentFilter(desktopIndependentWindow: only)
            } else {
                guard let display = displayForCapture(mainWindow: appWindows.first, displays: content.displays) else {
                    return .failure("ScreenCaptureKit: no display for multi-window capture")
                }
                let otherApps = content.applications.filter { $0.bundleIdentifier != bundleID }
                filter = SCContentFilter(display: display, excludingApplications: otherApps, exceptingWindows: [])
            }

            let config = SCStreamConfiguration()
            config.showsCursor = false
            config.captureResolution = .best
            let scale = Double(filter.pointPixelScale)
            config.width = Int(Double(filter.contentRect.width) * scale)
            config.height = Int(Double(filter.contentRect.height) * scale)

            guard let image = try await captureScreenshot(filter: filter, configuration: config) else {
                return .failure("ScreenCaptureKit: empty screenshot (scWindows=\(scWindows.count), nsWindows=\(appWindows.count))")
            }

            if needsNativeOverlays, scWindows.count < 2 {
                return .failure("native popover window not visible at capture time (scWindows=\(scWindows.count)). Re-run; if this persists, check popover wiring.")
            }
            if isTCCProbe, scWindows.isEmpty {
                return .failure("tcc-probe: no shareable windows at capture time")
            }

            log("ScreenCaptureKit capture ok scWindows=\(scWindows.count)")
            return .success(image)
        } catch {
            return .failure("ScreenCaptureKit capture failed: \(error.localizedDescription). \(screenRecordingInstructions)")
        }
    }

    private static func displayForCapture(mainWindow: NSWindow?, displays: [SCDisplay]) -> SCDisplay? {
        if let screenNumber = mainWindow?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
           let match = displays.first(where: { $0.displayID == screenNumber }) {
            return match
        }
        return displays.first
    }

    private static func captureScreenshot(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage? {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    /// In-process snapshot of the primary window's content view only.
    /// Does not require Screen Recording permission. Captures exactly what the
    /// main window renders (including any in-window overlays). Does *not* include
    /// separate OS windows such as native SwiftUI popovers (those use captureComposite).
    @MainActor
    private static func captureMainWindowOnly() -> CaptureResult {
        guard let win = mainWindow() else { return .failure("no main window for snapshot") }
        guard let view = win.contentView else { return .failure("main window has no contentView") }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else {
            return .failure("main content bounds too small for capture (\(bounds))")
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return .failure("failed to allocate bitmap rep for main window snapshot")
        }
        view.cacheDisplay(in: bounds, to: rep)
        guard let cg = rep.cgImage else {
            return .failure("bitmap rep for main window did not produce CGImage")
        }
        return .success(cg)
    }

    private static var screenRecordingInstructions: String {
        """
        Screen Recording permission is required for this fixture (native SwiftUI overlays). \
        Run once: bash scripts/gui_proof_grant.sh — then enable Allnighter in \
        System Settings → Privacy & Security → Screen & System Audio Recording. \
        App path: \(grantAppPath)
        """
    }

    @MainActor
    private static func failProof(_ message: String) {
        try? FileManager.default.createDirectory(at: buildRoot, withIntermediateDirectories: true)
        try? message.write(to: lastErrorURL, atomically: true, encoding: .utf8)
        log("ERROR: \(message)")
    }

    @MainActor
    private static func mainWindow() -> NSWindow? {
        NSApp.windows
            .filter { $0.isVisible && $0.contentView != nil }
            .max { a, b in
                let aa = a.contentView!.bounds, bb = b.contentView!.bounds
                return aa.width * aa.height < bb.width * bb.height
            }
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("gui-fixture: \(message)\n".utf8))
    }
}

#else

/// Release stub — proof harness compiles out; every gate is inert.
enum GUIFixture {
    static func bootstrap() {}
    static var isActive: Bool { false }
    static var isGrantSession: Bool { false }
    static var active: String? { nil }
    static var composeMenuOpen: Bool { false }
    static var composeTargetOpen: Bool { false }
    static var composeSpecimenMode: ComposeMode { .chat }
    static var opensTeamDropdown: Bool { false }
    static var opensDoctorPopover: Bool { false }
    static var opensReadiness: Bool { false }
    static var opensComposeSpecimen: Bool { false }
    static var opensCommandPalette: Bool { false }
    static var opensHomeWorkspace: Bool { false }
    static var suppressUnreadAutoScroll: Bool { false }
    static func readinessFocusDriverId(for scenario: String?) -> String? { nil }
    static func seededToolStatuses(for models: [Model], now: Date) -> [ToolProbeRecord] { [] }
    static func captureAndExitIfRequested() {}
}

#endif
