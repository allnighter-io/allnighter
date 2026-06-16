import Foundation
import AppKit
import AllnighterCore

/// Designer-mock harness for the GUI Visual Proof Gate.
///
/// ENTIRELY env-gated: when `ALLNIGHTER_GUI_FIXTURE` is unset — every real
/// launch — this type seeds nothing, captures nothing, and is inert. It exists
/// so an agent can render a deterministic UI state, self-capture the window to a
/// PNG, and *look at the pixels* before claiming a GUI fix is done.
///
/// Why self-capture (not the `screencapture` CLI): grabbing another process's
/// window needs Screen-Recording TCC permission, which would re-open the exact
/// launch-permission code red the app just escaped. Rendering our OWN window to a
/// bitmap needs no permission, no network, no probes, and no quota.
///
/// See `docs/phases/GUI_Visual_Proof_Gate.md`.
enum GUIFixture {
    /// The active fixture name, or nil on every normal launch.
    static var active: String? {
        let v = ProcessInfo.processInfo.environment["ALLNIGHTER_GUI_FIXTURE"]
        return (v?.isEmpty == false) ? v : nil
    }

    static var isActive: Bool { active != nil }

    /// Deep-link: open the Team dropdown for `team-*` fixtures so the popover —
    /// where the worst layout bugs live — is captured without a scripted gesture.
    static var opensTeamDropdown: Bool { (active ?? "").hasPrefix("team-") }

    /// A fixed, deterministic window size for proof captures so the same fixture
    /// always renders to the same frame.
    static let captureWindowSize = NSSize(width: 1100, height: 720)

    // MARK: - Seeded health (DESIGNER MOCK — never a real launch)

    /// Mixed-health probe records keyed off the live model driverIds, so the
    /// bench dropdown produces real rows in a known state. This is the only
    /// place fabricated health is allowed, and only when a fixture is active.
    static func seededToolStatuses(for models: [Model], now: Date) -> [ToolProbeRecord] {
        let drivers = orderedDrivers(in: models)
        let name = active ?? ""
        return drivers.enumerated().map { index, driver in
            let status = status(for: name, index: index)
            return ToolProbeRecord(
                driverId: driver,
                status: status,
                version: status.isReady ? "1.0.0" : nil,
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

    private static func status(for fixture: String, index: Int) -> ModelSetupStatus {
        switch fixture {
        case "team-open-ready":
            return .ready(version: "1.0.0")
        case "team-open-mixed":
            // Deterministic spread that exercises the dot, the issue badge, and
            // the Repair affordance side by side.
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
        default:
            return .ready(version: "1.0.0")
        }
    }

    // MARK: - Self-capture

    /// If `ALLNIGHTER_GUI_PROOF_OUT` is set, resize the main window to a fixed
    /// frame, let SwiftUI settle, render the window content to a PNG at that
    /// path, then terminate. No-op when no output path is requested (so a
    /// fixture can also be launched interactively for hand inspection).
    @MainActor
    static func captureAndExitIfRequested() {
        guard isActive,
              let out = ProcessInfo.processInfo.environment["ALLNIGHTER_GUI_PROOF_OUT"],
              !out.isEmpty
        else { return }

        Task { @MainActor in
            // Stage 1: pin the window to a deterministic size.
            try? await Task.sleep(for: .milliseconds(500))
            if let window = mainWindow() {
                window.setContentSize(captureWindowSize)
                window.center()
            }
            // Stage 2: snapshot once layout has settled, then exit.
            try? await Task.sleep(for: .seconds(1))
            writePNG(to: URL(fileURLWithPath: out))
            NSApp.terminate(nil)
        }
    }

    /// The largest visible content window — the main "Allnighter" window, not the
    /// MenuBarExtra's host window.
    @MainActor
    private static func mainWindow() -> NSWindow? {
        NSApp.windows
            .filter { $0.isVisible && $0.contentView != nil }
            .max { a, b in
                let aa = a.contentView!.bounds, bb = b.contentView!.bounds
                return aa.width * aa.height < bb.width * bb.height
            }
    }

    @MainActor
    private static func writePNG(to url: URL) {
        guard let view = mainWindow()?.contentView else {
            FileHandle.standardError.write(Data("gui-fixture: no window to capture\n".utf8))
            return
        }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            FileHandle.standardError.write(Data("gui-fixture: could not allocate bitmap\n".utf8))
            return
        }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("gui-fixture: PNG encode failed\n".utf8))
            return
        }
        do {
            try data.write(to: url)
            FileHandle.standardError.write(Data("gui-fixture: wrote \(url.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("gui-fixture: write failed: \(error)\n".utf8))
        }
    }
}
