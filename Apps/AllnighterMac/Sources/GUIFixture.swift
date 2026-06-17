import Foundation
import AppKit
import AllnighterCore

/// Designer-mock harness for the GUI Visual Proof Gate.
///
/// ENTIRELY env-gated: when no proof session is active — every real launch — this
/// type seeds nothing, captures nothing, and is inert.
///
/// Proof sessions start one of two ways:
/// 1. `bash scripts/gui_proof.sh <fixture>` — writes a request JSON, launches
///    the **`.app` bundle** via `open` (Launch Services), app reads the request.
/// 2. Legacy direct exec with `ALLNIGHTER_GUI_FIXTURE` + `ALLNIGHTER_GUI_PROOF_OUT`.
///
/// Capture composites the app's OWN windows via Screen Recording APIs so native
/// SwiftUI popovers/menus/sheets (separate OS windows) appear in proofs. One-time
/// grant: `bash scripts/gui_proof_grant.sh`. See `docs/phases/GUI_Visual_Proof_Gate.md`.
enum GUIFixture {
    private static let devRoot: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Developer/Allnighter", isDirectory: true)

    /// Written by `gui_proof.sh` / `gui_proof_grant.sh`; consumed on launch.
    static let proofRequestURL = devRoot.appendingPathComponent("gui-proof-request.json")

    /// Written when Screen Recording preflight passes (grant UI or successful capture).
    static let grantMarkerURL = devRoot.appendingPathComponent("gui-proof-screen-recording.ok")

    /// Written on capture failure so `gui_proof.sh` can exit non-zero with a message.
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

    /// Fixtures that open a native SwiftUI popover/menu — capture MUST use Screen Recording.
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

    /// Home / thread conversation fixtures stay on HomeView (not the specimen).
    static var opensHomeWorkspace: Bool {
        let name = active ?? ""
        return name.hasPrefix("home-") || name.hasPrefix("thread-") || name == "command-palette"
    }

    /// Deep-link: open the ⌘K command palette over the home workspace.
    static var opensCommandPalette: Bool { active == "command-palette" }
    /// `compose-mode-menu` seeds the mode menu open for the proof capture.
    static var composeMenuOpen: Bool { active == "compose-mode-menu" }
    /// `compose-target-*` seeds the target popover open.
    static var composeTargetOpen: Bool { (active ?? "").hasPrefix("compose-target-") }
    /// Mode for the compose specimen (drives which target popover renders).
    static var composeSpecimenMode: ComposeMode {
        switch active {
        case "compose-target-fanout": return .fanout
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
        ("thread-empty", "Thread — empty work order"),
        ("thread-with-turns", "Thread — user message turn"),
        ("command-palette", "⌘K command palette"),
        ("compose-mode-menu", "Compose — mode menu (native popover)"),
        ("compose-target-chat", "Compose — route to model (native popover)"),
        ("compose-target-fanout", "Compose — fan out team (native popover)"),
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

            if needsNativeOverlays {
                await waitForOverlayWindows(timeout: 4)
            } else {
                try? await Task.sleep(for: .seconds(1))
            }

            switch captureComposite() {
            case .success(let image):
                writeGrantMarker()
                writePNG(image, to: URL(fileURLWithPath: out))
                NSApp.terminate(nil)
            case .failure(let message):
                failProof(message)
                NSApp.terminate(nil)
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

    /// Composite the app's own windows. Requires Screen Recording permission.
    @MainActor
    private static func captureComposite() -> CaptureResult {
        let windows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
        guard !windows.isEmpty else { return .failure("no window to capture") }

        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            return .failure(screenRecordingInstructions)
        }

        let ids = windows.map { CGWindowID($0.windowNumber) } as CFArray
        guard let composite = CGImage(
            windowListFromArrayScreenBounds: .null,
            windowArray: ids,
            imageOption: [.boundsIgnoreFraming]
        ) else {
            return .failure("Screen Recording capture failed — windows=\(windows.count). \(screenRecordingInstructions)")
        }

        if needsNativeOverlays, windows.count < 2 {
            return .failure("native popover window not visible at capture time (only main window captured). Re-run; if this persists, check popover wiring.")
        }

        return .success(composite)
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
