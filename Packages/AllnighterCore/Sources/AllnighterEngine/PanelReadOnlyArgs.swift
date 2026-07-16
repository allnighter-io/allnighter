import Foundation
import AllnighterCore

/// Panel-scoped mechanical read-only argv injection for v0 seats
/// (`docs/phases/Pilot_Panel.md` decision 7 / PN-S02). Reconstructs the confirmed
/// per-driver read-only flags from the capability table in `Unified_Run_Model.md`
/// without resurrecting the deleted `RelayReadOnlyEnforcer` wholesale.
///
/// Confirmed (2026-07-16):
///   - `claude_code`: `--permission-mode plan`
///   - `codex`: `--sandbox read-only --ask-for-approval never`
///
/// Every other driver is REFUSED in v0 with `PANEL_SEAT_NOT_ISOLATED` (PN-S06
/// clonefile is the coming fix). Honesty over availability until then.
public enum PanelReadOnlyArgs {
    public enum Mechanism: Sendable, Equatable {
        case claudePermissionModePlan
        case codexReadOnlySandbox
    }

    /// Stable error code for a seat whose driver has no confirmed read-only mode.
    public static let seatNotIsolatedCode = "PANEL_SEAT_NOT_ISOLATED"

    public static let supported: [String: Mechanism] = [
        "claude_code": .claudePermissionModePlan,
        "codex": .codexReadOnlySandbox,
    ]

    public static var supportedDriverIds: [String] { supported.keys.sorted() }

    /// Returns a read-only VARIANT of `manifest` with argv surfaces rewritten, or
    /// `nil` when this driver has no confirmed mechanism (`nil` = fail closed).
    public static func enforce(on manifest: DriverManifest) -> DriverManifest? {
        guard let mechanism = supported[manifest.id] else { return nil }
        var out = manifest
        switch mechanism {
        case .claudePermissionModePlan:
            if var invoke = out.invoke {
                invoke.args = setFlagValue(invoke.args, flag: claudePermissionModeFlag, value: "plan")
                out.invoke = invoke
            }
            if var streaming = out.streaming {
                streaming.args = setFlagValue(streaming.args, flag: claudePermissionModeFlag, value: "plan")
                out.streaming = streaming
            }
            if var session = out.session {
                session.firstTurnArgs = session.firstTurnArgs.map {
                    setFlagValue($0, flag: claudePermissionModeFlag, value: "plan")
                }
                session.resumeArgs = session.resumeArgs.map {
                    setFlagValue($0, flag: claudePermissionModeFlag, value: "plan")
                }
                out.session = session
            }
        case .codexReadOnlySandbox:
            if var invoke = out.invoke {
                guard let transformed = insertCodexReadOnlySandbox(invoke.args) else { return nil }
                invoke.args = transformed
                out.invoke = invoke
            }
            if var streaming = out.streaming {
                guard let transformed = insertCodexReadOnlySandbox(streaming.args) else { return nil }
                streaming.args = transformed
                out.streaming = streaming
            }
            if var session = out.session {
                if let firstTurnArgs = session.firstTurnArgs {
                    guard let transformed = insertCodexReadOnlySandbox(firstTurnArgs) else { return nil }
                    session.firstTurnArgs = transformed
                }
                if let resumeArgs = session.resumeArgs {
                    guard let transformed = insertCodexReadOnlySandbox(resumeArgs) else { return nil }
                    session.resumeArgs = transformed
                }
                out.session = session
            }
        }
        return out
    }

    /// Agent-actionable refusal when a seat's driver cannot be mechanically isolated.
    /// Names `PANEL_SEAT_NOT_ISOLATED` and PN-S06 so the coming clonefile fix is findable.
    public static func isolationRefusal(
        workerId: String,
        driverId: String,
        displayName: String? = nil
    ) -> (code: String, message: String) {
        let label = displayName.map { "\($0) (\(driverId))" } ?? driverId
        let supported = supportedDriverIds.joined(separator: ", ")
        return (
            seatNotIsolatedCode,
            "Panel seat '\(workerId)' driver '\(label)' has no confirmed read-only mode in v0 — refused (\(seatNotIsolatedCode)). Seats that can enforce it: \(supported). PN-S06 (clonefile isolation) is the coming fix so no seat is refused."
        )
    }

    /// `nil` when the worker can be isolated; otherwise the refusal message.
    public static func capabilityViolation(
        workerId: String,
        models: [Model],
        registry: DriverRegistry
    ) -> (code: String, message: String)? {
        guard let model = models.first(where: { $0.id == workerId }) else {
            return (
                seatNotIsolatedCode,
                "Panel seat '\(workerId)' is not a known model — cannot confirm read-only isolation. Seats that can enforce it: \(supportedDriverIds.joined(separator: ", ")). PN-S06 (clonefile) is the coming fix."
            )
        }
        guard let manifest = registry.manifest(for: model) else {
            return (
                seatNotIsolatedCode,
                "Panel seat '\(workerId)' has no registered driver manifest — cannot confirm read-only isolation. Seats that can enforce it: \(supportedDriverIds.joined(separator: ", ")). PN-S06 (clonefile) is the coming fix."
            )
        }
        guard enforce(on: manifest) != nil else {
            return isolationRefusal(
                workerId: workerId,
                driverId: manifest.id,
                displayName: manifest.displayName
            )
        }
        return nil
    }

    // MARK: - argv transforms

    private static let claudePermissionModeFlag = "--permission-mode"

    private static func setFlagValue(_ args: [String], flag: String, value: String) -> [String] {
        if let idx = args.firstIndex(of: flag), idx + 1 < args.count {
            var out = args
            out[idx + 1] = value
            return out
        }
        return args + [flag, value]
    }

    /// Inserts `--sandbox read-only --ask-for-approval never` right after leading `exec`.
    /// Empty args pass through; non-empty non-exec shapes fail closed (`nil`).
    private static func insertCodexReadOnlySandbox(_ args: [String]) -> [String]? {
        guard !args.isEmpty else { return args }
        guard args.first == "exec" else { return nil }
        var out = args
        out.insert(contentsOf: ["--sandbox", "read-only", "--ask-for-approval", "never"], at: 1)
        return out
    }
}
