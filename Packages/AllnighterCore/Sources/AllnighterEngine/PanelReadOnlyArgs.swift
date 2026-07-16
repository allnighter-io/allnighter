import Foundation
import AllnighterCore

/// Panel-scoped mechanical read-only argv injection for seats whose drivers have
/// a confirmed RO mode (`docs/phases/Pilot_Panel.md` decision 7 / PN-S02 + PN-S06).
/// Reconstructs the confirmed per-driver read-only flags from the capability table
/// in `Unified_Run_Model.md` without resurrecting the deleted `RelayReadOnlyEnforcer`.
///
/// Confirmed (2026-07-16):
///   - `claude_code`: `--permission-mode plan`
///   - `codex`: `--sandbox read-only --ask-for-approval never`
///
/// Every other driver is isolated via **ephemeral clone** (`PanelSeatIsolation`) —
/// "no seat is ever refused". This type only rewrites argv for RO-enforcing
/// drivers; it does not refuse.
public enum PanelReadOnlyArgs {
    public enum Mechanism: Sendable, Equatable {
        case claudePermissionModePlan
        case codexReadOnlySandbox
    }

    /// Legacy code name — now means clone materialization failed (see
    /// `PanelSeatIsolation.seatNotIsolatedCode`), not "driver has no RO mode".
    public static let seatNotIsolatedCode = PanelSeatIsolation.seatNotIsolatedCode

    public static let supported: [String: Mechanism] = [
        "claude_code": .claudePermissionModePlan,
        "codex": .codexReadOnlySandbox,
    ]

    public static var supportedDriverIds: [String] { supported.keys.sorted() }

    /// Returns a read-only VARIANT of `manifest` with argv surfaces rewritten, or
    /// `nil` when this driver has no confirmed mechanism (`nil` = use clone isolation).
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

    /// True when this worker can run with driver-enforced RO args on the real root.
    public static func isDriverEnforced(
        workerId: String,
        models: [Model],
        registry: DriverRegistry
    ) -> Bool {
        guard let model = models.first(where: { $0.id == workerId }),
              let manifest = registry.manifest(for: model),
              enforce(on: manifest) != nil else {
            return false
        }
        return true
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
    /// Empty args pass through; non-empty non-exec shapes fail closed (`nil` → clone).
    private static func insertCodexReadOnlySandbox(_ args: [String]) -> [String]? {
        guard !args.isEmpty else { return args }
        guard args.first == "exec" else { return nil }
        var out = args
        out.insert(contentsOf: ["--sandbox", "read-only", "--ask-for-approval", "never"], at: 1)
        return out
    }
}
