import Foundation
import AppKit
import AllnighterCore
import AllnighterEngine
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
///   in `docs/gui/Visual_Proof_Gate.md`.
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
        // These render their panels inline (no NSPopover), so they capture in-process
        // like the other panel fixtures.
        let inlineComposeFixtures: Set<String> = ["compose-target-inline", "compose-file-reference"]
        return (active ?? "").hasPrefix("compose-") && !inlineComposeFixtures.contains(active ?? "")
    }

    /// Deep-link: open the Team dropdown for `team-*` fixtures.
    static var opensTeamDropdown: Bool { (active ?? "").hasPrefix("team-") }

    /// Deep-link: open Bench health for `doctor-*` fixtures.
    static var opensDoctorPopover: Bool { (active ?? "").hasPrefix("doctor-") }

    /// Deep-link: open Team readiness for `readiness-*` fixtures.
    static var opensReadiness: Bool { (active ?? "").hasPrefix("readiness-") }

    /// Deep-link: show the routing-composer specimen for `compose-*` fixtures.
    static var opensComposeSpecimen: Bool { (active ?? "").hasPrefix("compose-") }

    /// Deep-link: open the Team Studio settings surface for `studio*` fixtures
    /// (and ONB-S02b / ONB-S03 settings fixtures).
    static var opensTeamStudio: Bool {
        let name = active ?? ""
        return name.hasPrefix("studio")
            || name == "settings-use-from-cli"
            || name == "settings-teach-your-clis"
    }

    /// Which Studio page a `studio-*` / settings fixture deep-links to.
    static var studioRoute: StudioRoute {
        switch active {
        case "studio-teams-code", "studio-team-editor", "studio-worker-editor", "studio-skills-code": return .teams(.code)
        case "studio-teams-design": return .teams(.design)
        case "studio-teams-copy": return .teams(.copy)
        case "studio-default-model": return .defaultModel
        case "studio-boost-window": return .boostWindow
        case "settings-use-from-cli", "studio-use-from-cli": return .useFromCLI
        case "settings-teach-your-clis", "studio-teach-your-clis": return .teachYourCLIs
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
        return name.hasPrefix("home-") || name.hasPrefix("thread-") || name == "command-palette" || name == "projects-rail"
    }

    /// UNR proof: keep selected-unread below the fold for the rail matrix capture.
    static var suppressUnreadAutoScroll: Bool { active == "home-rail-unr" }

    /// Deep-link: open the Teams workspace (Send-to-team launcher) via the toggle.
    static var opensTeamsLauncher: Bool { active == "teams-launcher" || active == "teams-compose-modal" || active == "teams-edit-drawer" }
    /// Deep-link: open the launcher with the send-to-team composer modal up.
    static var opensTeamsComposeModal: Bool { active == "teams-compose-modal" }
    /// Deep-link: open the launcher with the Team Editor drawer up (review/customize).
    static var opensTeamsEditDrawer: Bool { active == "teams-edit-drawer" }
    /// Deep-link: open the Factory Floor reader over a completed sample team run.
    static var opensFloorReader: Bool { active == "floor-reader" }
    /// Deep-link: seed the project-grouped sidebar (PRJ-S14) with sample projects.
    static var opensProjectsRail: Bool { active == "projects-rail" }
    /// R-S08: seed sample projects (same as `opensProjectsRail`) so the relay launch
    /// sheet's doc/seat pickers have a real project + bench to render against.
    static var opensRelayLaunch: Bool {
        active == "relay-launch" || active == "relay-launch-kickoff"
    }

    /// Proof: composer with the Loop tab selected (ATL-S03).
    static var composeLoopTab: Bool { active == "compose-loop" }

    /// Kickoff text seeded into the relay launch sheet for visual proof.
    static var relayLaunchKickoffMessage: String? {
        switch active {
        case "relay-launch", "relay-launch-kickoff":
            return "Ship the parser fix; PM reviews each round until done."
        default:
            return nil
        }
    }
    /// Deep-link: open the ⌘K command palette over the home workspace.
    static var opensCommandPalette: Bool { active == "command-palette" }
    /// Deep-link: open the Pending queue screen seeded with sample armed work.
    static var opensPending: Bool { active == "pending-queue" || active == "pending-review" }

    /// Open the composer-in-modal review over the first pending item.
    static var opensPendingReview: Bool { active == "pending-review" }

    /// Seed boost window settings for the `studio-boost-window` proof fixture.
    static func seedBoostWindowForProof() {
        guard active == "studio-boost-window" else { return }
        let persistence = BoostWindowSettingsPersistence()
        var settings = BoostWindowSettings(
            enabled: true,
            windowStart: BoostWindowSettings.defaultWindowStart
        )
        try? persistence.save(settings)
    }

    /// Seed a temp Pending store with sample armed work for the pending fixtures
    /// (`pending-queue` = the screen, `pending-pill` = home + the top-bar pill).
    static func seededPendingService(models: [Model]) -> PendingService? {
        guard active == "pending-queue" || active == "pending-pill" || active == "pending-review" else { return nil }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-pending-fixture", isDirectory: true)
        let service = PendingService(store: PendingStore(rootDirectory: root), models: models)
        // Seed once per store. RootView builds the service for the screen AND the
        // title-bar count, so this runs more than once — re-deleting would mint new
        // ids each call and break id-keyed lookups (e.g. the review modal's prompt).
        if (try? service.list().isEmpty) ?? true {
            for prompt in [
                "Add a dark-mode toggle to the settings panel and wire it to the theme store.",
                "Audit the auth redirect loop on sign-in and propose a fix.",
                "Draft release notes for the 0.7 build from the recent commits.",
            ] {
                _ = try? service.add(.init(prompt: prompt, workerToken: "claude", submit: true))
            }
        }
        return service
    }
    /// `compose-target-*` seeds the target popover open. `compose-loop` needs the
    /// same seeding: the whole point of that fixture is proving Model | Team | Loop
    /// render together, which is invisible while the picker is collapsed to a chip.
    static var composeTargetOpen: Bool {
        let id = active ?? ""
        if id == "compose-loop" { return true }
        return id.hasPrefix("compose-target-") && id != "compose-target-inline"
    }

    /// `compose-team` pre-selects a team so the target chip renders in team mode
    /// (name · N workers, never a fake model · effort).
    static var composeTeamId: String? { active == "compose-team" ? "design_design" : nil }

    /// `compose-file-reference` seeds an active @ query so the file picker is visible.
    static var composeFileReferenceOpen: Bool { active == "compose-file-reference" }

    /// `compose-target-inline` renders the redesigned team picker panel INLINE (not as a
    /// native NSPopover, which can't be captured in-process) seeded with a search query.
    static var composeTargetInline: Bool { active == "compose-target-inline" }

    /// `thread-copy-footer` forces the per-message copy button (hover-only) visible so
    /// its bottom-right placement can be captured.
    static var alwaysShowMessageCopy: Bool { active == "thread-copy-footer" }

    /// A real temp repo seeded with representative files so the `compose-file-reference`
    /// fixture exercises the ACTUAL `ProjectFileCatalog` ranking (prefix > contains, doc
    /// tiebreak, vendor sink) + highlighting, independent of the fixture project's root.
    static func fileReferenceFixtureRoot() -> String? {
        guard composeFileReferenceOpen else { return nil }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-fileref-fixture", isDirectory: true)
        let files = [
            "Composer.swift", "ComposerView.swift", "Sources/Common.swift",
            "docs/Composer_Guide.md", "vendor/lib-composer.js",
        ]
        for rel in files {
            let url = root.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: url.path) { continue }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "// \(rel)\n".write(to: url, atomically: true, encoding: .utf8)
        }
        return root.path
    }

    /// Dedicated fixture for testing the Screen Recording grant / preflight in isolation.
    /// Runs the composite path (so native popovers + SR are exercised) but is intended
    /// only for "does preflight + captureComposite succeed right now?" verification.
    static var isTCCProbe: Bool { (active ?? "") == "tcc-probe" }

    /// Which source the repair panel focuses on for readiness fixtures.
    static var readinessFocusDriverId: String? { readinessFocusDriverId(for: active) }

    static func readinessFocusDriverId(for scenario: String?) -> String? {
        switch scenario {
        case "readiness-mixed": return "codex"
        case "readiness-cursor-ready", "readiness-cursor-trust",
             "readiness-cursor-keychain", "readiness-cursor-not-checked":
            return "cursor_agent"
        default: return nil
        }
    }

    /// Optional bench roster override for cursor setup proof fixtures.
    static func seededModels(base: [Model]) -> [Model]? {
        seededModels(base: base, scenario: active ?? "")
    }

    static func seededModels(base: [Model], scenario: String) -> [Model]? {
        switch scenario {
        case "readiness-cursor-ready", "readiness-cursor-trust", "readiness-cursor-keychain":
            return patchCursorBench(base)
        default:
            return nil
        }
    }

    private static func patchCursorBench(_ base: [Model]) -> [Model] {
        base.map { m in
            switch m.id {
            case "model_cursor_auto", "model_cursor_composer_25":
                var copy = m
                copy.enabled = true
                return copy
            case "model_cursor_composer_25_fast":
                var copy = m
                copy.enabled = false
                return copy
            default:
                return m
            }
        }
    }

    /// Named bench-health scenarios (GUI proof fixtures + dev panel).
    static let benchScenarios: [(id: String, label: String)] = [
        ("team-open-ready", "All CLIs ready"),
        ("team-open-mixed", "Mixed — team dropdown"),
        ("doctor-open-mixed", "Mixed — CLI setup popover"),
        ("readiness-mixed", "Mixed — CLI setup page"),
        ("readiness-cold", "Cold — never scanned (CLI setup page)"),
        ("readiness-cursor-ready", "Cursor Agent — ready (CLI setup page)"),
        ("readiness-cursor-keychain", "Cursor Agent — Keychain/auth (CLI setup page)"),
        ("readiness-cursor-trust", "Cursor Agent — trust disclosure (CLI setup page)"),
        ("readiness-cursor-not-checked", "Cursor Agent — not checked (CLI setup page)"),
        ("home-with-threads", "Home — rail with conversations"),
        ("home-thread-states", "Home — 4-state rows: Draft/Running/Replied (PENDQ GUI)"),
        ("thread-copy-footer", "Thread — per-message copy button at bottom-right"),
        ("home-rail", "Home — grouped/filtered rail (CR4e)"),
        ("home-rail-th2", "Home — TH2 triage pin/unread/archive"),
        ("home-rail-unr", "Home — UNR unread matrix (S07)"),
        ("thread-empty", "Thread — empty run"),
        ("thread-with-turns", "Thread — user message turn"),
        ("thread-chat", "Thread — chat reply from a model"),
        ("thread-streaming", "Thread — live streaming reply"),
        ("thread-streaming-build", "Thread — live streaming build run"),
        ("thread-thinking-history", "Thread — thinking collapse on prior turns"),
        ("thread-team-board", "Thread — team board"),
        ("thread-live-artifact", "Thread — live team artifact seats (TRR)"),
        ("thread-user-image-attachment", "Thread — user message with image chip"),
        ("thread-worker-image-reply", "Thread — worker reply with image thumbnail"),
        ("thread-agent-image-reply", "Thread — agent run reply with image thumbnail"),
        ("thread-design-board-fanout", "Thread — design board mockup tile strip"),
        ("thread-mutating-run", "Thread — mutating run"),
        ("studio-clis", "Team Studio — CLIs (settings shell)"),
        ("settings-use-from-cli", "Settings — Use from your CLI (recipe cards)"),
        ("settings-teach-your-clis", "Settings — Teach your CLIs (global snippet install)"),
        ("studio-default-model", "Team Studio — Default model (Auto tiers)"),
        ("studio-boost-window", "Team Studio — Boost window"),
        ("studio-teams-code", "Team Studio — Code teams (detail)"),
        ("studio-team-editor", "Team Studio — Customize team editor"),
        ("studio-worker-editor", "Team Studio — Customize worker (skill + prompt)"),
        ("command-palette", "⌘K command palette"),
        ("teams-launcher", "Teams — Send-to-team launcher (G-T0)"),
        ("teams-compose-modal", "Teams — send-to-team composer modal (G-T2)"),
        ("teams-edit-drawer", "Teams — hover-edit → Team Editor drawer (#3)"),
        ("floor-reader", "Floor — team reply reader (G-T3, markdown)"),
        ("projects-rail", "Home — project-grouped sidebar (PRJ-S14)"),
        ("pending-queue", "Pending — queued work screen (PENDQ GUI)"),
        ("pending-pill", "Home — top-bar 'N pending' pill (PENDQ GUI)"),
        ("pending-review", "Pending — composer-in-modal review (PENDQ GUI)"),
        ("compose-target-chat", "Compose — route target popover (native popover)"),
        ("compose-target-inline", "Compose — redesigned team picker panel (Auto/search/favorites)"),
        ("compose-team", "Compose — team target (name · workers, not fake model)"),
        ("compose-file-reference", "Compose — file reference picker"),
        ("compose-target-send-to-team", "Compose — team target popover (native popover)"),
        ("compose-loop", "Compose — Loop tab (ATL-S03)"),
        ("relay-launch-kickoff", "Loop launch sheet — Kickoff field populated (ATL-S03)"),
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
        if scenario == "readiness-cold" || scenario == "readiness-cursor-not-checked" { return [] }
        let drivers = probeDrivers(for: scenario, models: models)
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

    /// Setup/bench fixtures seed every supported headless CLI so roster cards never vanish.
    private static func probeDrivers(for scenario: String, models: [Model]) -> [String] {
        if scenario.hasPrefix("readiness-") || scenario.hasPrefix("doctor-") || scenario.hasPrefix("team-open-") {
            return ["claude_code", "codex", "grok", "antigravity", "cursor_agent"]
        }
        return orderedDrivers(in: models)
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
        if fixture.hasPrefix("readiness-cursor") && driverId == "cursor_agent" {
            if case .ready = status { return "cursor-agent 2.5" }
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
            case "cursor_agent": return .ready(version: "cursor-agent 2.5")
            default: return .ready(version: "1.0.0")
            }
        case "readiness-mixed":
            switch driverId {
            case "claude_code": return .ready(version: "claude 1.2.4")
            case "antigravity": return .ready(version: "agy")
            case "codex": return .probeFailed(reason: "error: unknown flag --model (exit 2)")
            case "grok": return .notInstalled
            case "cursor_agent": return .notInstalled
            default: return .ready(version: "1.0.0")
            }
        case "readiness-cursor-ready", "readiness-cursor-trust":
            switch driverId {
            case "cursor_agent": return .ready(version: "cursor-agent 2.5")
            default: return .ready(version: "1.0.0")
            }
        case "readiness-cursor-keychain":
            switch driverId {
            case "cursor_agent":
                return .installedNotSignedIn(LoginFlow(
                    interactiveCommand: "agent login",
                    instructions: "Run `agent login`. SecItemCopyMatching failed — open Cursor once and retry setup."
                ))
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
    static var composeTargetOpen: Bool { false }
    static var composeTargetInline: Bool { false }
    static var alwaysShowMessageCopy: Bool { false }
    static func fileReferenceFixtureRoot() -> String? { nil }
    static var composeFileReferenceOpen: Bool { false }
    static var opensTeamDropdown: Bool { false }
    static var opensDoctorPopover: Bool { false }
    static var opensReadiness: Bool { false }
    static var opensComposeSpecimen: Bool { false }
    static var opensCommandPalette: Bool { false }
    static var opensFloorReader: Bool { false }
    static var opensPending: Bool { false }
    static var opensPendingReview: Bool { false }
    static var opensHomeWorkspace: Bool { false }
    static var suppressUnreadAutoScroll: Bool { false }
    static func seededPendingService(models: [Model]) -> PendingService? { nil }
    static func readinessFocusDriverId(for scenario: String?) -> String? { nil }
    static func seededModels(base: [Model]) -> [Model]? { nil }
    static func seededModels(base: [Model], scenario: String) -> [Model]? { nil }
    static func seededToolStatuses(for models: [Model], now: Date) -> [ToolProbeRecord] { [] }
    static func captureAndExitIfRequested() {}
}

#endif
