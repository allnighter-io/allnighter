import Foundation
import AllnighterCore

/// Mechanical `--pm-read-only` enforcement (PM_Relay.md §4.2). `Unified_Run_Model.md`
/// ("Safety — the honest version") named the law — "Answer runs are read-only by
/// mechanism, not by prompt. Telling a model 'don't write' is not safety" — and named
/// candidate mechanisms ("a driver's own read-only/sandbox flag where it exists"), but
/// left it an "open implementation decision" that never shipped: no code anywhere
/// enforces it today, only `RunWritePolicy` (which gates the write LOCK, not the
/// worker's ability to write at all). This is the narrow, honest version, scoped to the
/// relay's PM seat only — a per-driver rewrite of `DriverManifest` argv into the CLI's
/// OWN confirmed read-only/sandbox mode.
///
/// A driver with no CONFIRMED mechanism is UNSUPPORTED — `enforce(on:)` returns `nil`
/// and every caller must fail closed (refuse to dispatch), never fall back to a
/// prompt-only "please don't write." Confirmed against each CLI's own docs
/// (2026-07-16):
///   - `claude_code`: `--permission-mode plan` — Claude Code's own tool-permission gate
///     refuses Edit/Write/mutating-Bash tool calls inside the agent loop.
///   - `codex`: `--sandbox read-only --ask-for-approval never` — an OS-level sandbox
///     (seatbelt/landlock): model-generated commands can read but never write, and the
///     approval flag makes it non-interactive (sandbox alone can still prompt).
/// Deliberately NOT listed (fail closed, not guessed):
///   - `cursor_agent` — `--mode=plan`/`--mode=ask` exist, but (a) Cursor's own headless
///     `-p/--print` reference says print mode "has access to all tools, including write
///     and shell," and (b) a live Cursor forum bug report says `--plan` "executes
///     changes instead of planning only." Not safe to claim.
///   - `grok`, `antigravity`, `opencode` — no read-only/plan flag documented for
///     headless/non-interactive use at all.
public enum RelayReadOnlyEnforcer {
    /// One driver's confirmed mechanical read-only mechanism.
    public enum Mechanism: Sendable, Equatable {
        case claudePermissionModePlan
        case codexReadOnlySandbox
    }

    /// driverId -> confirmed mechanism. The ONLY drivers `--pm-read-only` can select —
    /// extend this only after confirming a NEW driver's own docs name a real
    /// non-interactive read-only mode (never by inference from a similar-looking flag).
    public static let supported: [String: Mechanism] = [
        "claude_code": .claudePermissionModePlan,
        "codex": .codexReadOnlySandbox,
    ]

    public static var supportedDriverIds: [String] { supported.keys.sorted() }

    /// Returns a read-only VARIANT of `manifest` — every argv surface that can carry a
    /// worker to the wire (`invoke.args`, `streaming.args`, `session.firstTurnArgs`,
    /// `session.resumeArgs`) rewritten to carry the driver's own read-only flag — or
    /// `nil` when this driver has no confirmed mechanism. `nil` is the fail-closed
    /// signal: the caller must refuse to dispatch, never dispatch un-enforced.
    public static func enforce(on manifest: DriverManifest) -> DriverManifest? {
        guard let mechanism = supported[manifest.id] else { return nil }
        var out = manifest
        switch mechanism {
        case .claudePermissionModePlan:
            if var invoke = out.invoke {
                invoke.args = setFlagValue(invoke.args, flag: Self.claudePermissionModeFlag, value: "plan")
                out.invoke = invoke
            }
            if var streaming = out.streaming {
                streaming.args = setFlagValue(streaming.args, flag: Self.claudePermissionModeFlag, value: "plan")
                out.streaming = streaming
            }
            if var session = out.session {
                session.firstTurnArgs = session.firstTurnArgs.map { setFlagValue($0, flag: Self.claudePermissionModeFlag, value: "plan") }
                session.resumeArgs = session.resumeArgs.map { setFlagValue($0, flag: Self.claudePermissionModeFlag, value: "plan") }
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

    /// A human-readable, agent-actionable violation naming the driver and which
    /// drivers DO support `--pm-read-only`, or `nil` when `pmWorkerId` resolves to a
    /// driver with a confirmed mechanism. The ONE function CLI (`RelayCLI.runRelay`) and
    /// MCP (`MCPRelayHandlers.relay`) both call for the start-time pre-flight, so the
    /// "ERROR at start" message can never drift between the two surfaces (agent-first:
    /// MCP never richer/different than the CLI). `RunService`'s own dispatch-time
    /// `enforce(on:)` call is the mechanical backstop this pre-flight can never replace
    /// (an unresolvable worker id at start-time still fails at dispatch either way).
    public static func capabilityViolation(pmWorkerId: String, models: [Model], registry: DriverRegistry) -> String? {
        guard let model = models.first(where: { $0.id == pmWorkerId }) else {
            return "pm-worker '\(pmWorkerId)' is not a known model — cannot confirm --pm-read-only can be mechanically enforced. Seats that can enforce it: \(supportedDriverIds.joined(separator: ", "))."
        }
        guard let manifest = registry.manifest(for: model) else {
            return "pm-worker '\(pmWorkerId)' has no registered driver manifest — cannot confirm --pm-read-only can be mechanically enforced. Seats that can enforce it: \(supportedDriverIds.joined(separator: ", "))."
        }
        guard enforce(on: manifest) != nil else {
            return "--pm-read-only cannot be mechanically enforced for driver '\(manifest.id)' (\(manifest.displayName)) — it has no confirmed read-only/sandbox mode. Seats that can enforce it: \(supportedDriverIds.joined(separator: ", "))."
        }
        return nil
    }

    // MARK: - argv transforms

    private static let claudePermissionModeFlag = "--permission-mode"

    /// Replaces the value following `flag` if present, else appends `flag value`.
    private static func setFlagValue(_ args: [String], flag: String, value: String) -> [String] {
        if let idx = args.firstIndex(of: flag), idx + 1 < args.count {
            var out = args
            out[idx + 1] = value
            return out
        }
        return args + [flag, value]
    }

    /// Inserts `--sandbox read-only --ask-for-approval never` right after the leading
    /// `exec` subcommand token — present on every codex.json argv surface today (base
    /// `invoke`, `streaming`, and `session.resumeArgs`' `exec resume {{sessionId}}`
    /// reshape all start with it). An EMPTY array passes through unchanged (nothing to
    /// transform — e.g. `streaming.args` legitimately empty, which falls back to the
    /// already-transformed `invoke.args` per `resolvedStreamingArgs`). A NON-EMPTY array
    /// that doesn't start with `exec` returns `nil` — an unrecognized shape this
    /// mechanism cannot safely claim to have locked down, so the whole `enforce(on:)`
    /// call fails closed rather than silently returning a manifest that looks
    /// read-only-enforced but isn't.
    private static func insertCodexReadOnlySandbox(_ args: [String]) -> [String]? {
        guard !args.isEmpty else { return args }
        guard args.first == "exec" else { return nil }
        var out = args
        out.insert(contentsOf: ["--sandbox", "read-only", "--ask-for-approval", "never"], at: 1)
        return out
    }
}
