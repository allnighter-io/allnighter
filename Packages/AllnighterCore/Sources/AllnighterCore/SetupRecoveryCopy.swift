import AgentOSCLI
import Foundation

/// Shared human/agent recovery copy for setup surfaces (detect, doctor, Mac cards).
/// Catalog fields are the source; this only formats them — never invents install paths.
public enum SetupRecoveryCopy {

    /// One-line detail when a supported driver has an explicit `.notInstalled` record.
    public static func notInstalledDetail(
        for manifest: DriverManifest,
        cursorAppPresent: Bool? = nil
    ) -> String {
        if manifest.id == CursorAgentCLIInstall.driverId {
            let appPresent = cursorAppPresent ?? CursorAgentCLIInstall.isCursorAppInstalled()
            let hint = manifest.setup?.installHint?.trimmingCharacters(in: .whitespacesAndNewlines)
            if appPresent {
                let base = "You have Cursor. Alln needs the Agent CLI (the app is not the seat) — install once, then Composer can join the bench."
                if let hint, !hint.isEmpty { return "\(base) \(hint)" }
                return "\(base) \(CursorAgentCLIInstall.shellCommand)"
            }
            let base = "Cursor Agent CLI not found — the Cursor app is not the seat."
            if let hint, !hint.isEmpty { return "\(base) \(hint)" }
            return "\(base) \(CursorAgentCLIInstall.shellCommand)"
        }
        let name = manifest.displayName
        if let hint = manifest.setup?.installHint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hint.isEmpty {
            return "\(name) not found on PATH or known paths. \(hint)"
        }
        return "\(name) not found on PATH or known paths"
    }

    /// One-line Needs-attention reason. Prefer a named disease over "health check failed."
    public static func attentionDetail(
        driverId: String,
        state: AttentionState,
        probeReason: String?,
        cursorAppPresent: Bool? = nil
    ) -> String {
        switch state {
        case .needsLogin:
            if driverId == "claude_code" {
                return "Login expired — open Claude Code, type `/login`, finish browser sign-in, then run `alln detect`."
            }
            return "Installed but signed out — sign in to use its models."
        case .needsPath:
            return "Installed but not on PATH — locate it to use its models."
        case .notInstalled:
            if driverId == CursorAgentCLIInstall.driverId {
                let appPresent = cursorAppPresent ?? CursorAgentCLIInstall.isCursorAppInstalled()
                if appPresent {
                    return "You have Cursor — install the Agent CLI to use Composer."
                }
                return "Cursor Agent CLI not installed — install it to use Composer."
            }
            return "Not installed."
        case .probeFailed:
            return probeFailedAttention(driverId: driverId, reason: probeReason)
        case .rateLimited:
            return probeReason ?? "Out of capacity — clears when the vendor resets."
        case .notChecked:
            return "Not checked yet — run `alln detect`."
        case .installedNotProbed:
            return "Installed but not checked yet — run `alln detect`."
        case .detecting, .reprobing:
            return "Re-checking this CLI…"
        case .queued:
            return "Queued for check…"
        }
    }

    /// Actionable projection for detect/doctor/drivers — same disease as Mac cards, CLI verbs.
    public struct Recovery: Equatable, Sendable {
        public var statusKind: String
        public var detail: String?
        public var fixCommand: String?
        public var nextAction: AgentSurfaceNextAction?

        public init(
            statusKind: String,
            detail: String? = nil,
            fixCommand: String? = nil,
            nextAction: AgentSurfaceNextAction? = nil
        ) {
            self.statusKind = statusKind
            self.detail = detail
            self.fixCommand = fixCommand
            self.nextAction = nextAction
        }
    }

    public static func recovery(
        for record: ToolProbeRecord,
        manifest: DriverManifest?
    ) -> Recovery {
        switch record.status {
        case .ready:
            return .init(statusKind: "ready")
        case .installedNotProbed:
            return .init(
                statusKind: "installedNotProbed",
                detail: attentionDetail(driverId: record.driverId, state: .installedNotProbed, probeReason: nil),
                fixCommand: BenchTallyProjector.detectCommand,
                nextAction: AgentSurfaceNextAction(
                    kind: "detectCLIs",
                    label: "Finish CLI smoke check",
                    command: BenchTallyProjector.detectCommand
                )
            )
        case .installedNotSignedIn(let flow):
            let detail: String
            if record.driverId == "claude_code" {
                detail = attentionDetail(driverId: record.driverId, state: .needsLogin, probeReason: nil)
            } else {
                let base = attentionDetail(driverId: record.driverId, state: .needsLogin, probeReason: nil)
                let instructions = flow.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                detail = instructions.isEmpty ? base : "\(base) \(instructions)"
            }
            let fix = doctorFixCommand(
                driverId: record.driverId,
                state: .needsLogin,
                loginInteractiveCommand: flow.interactiveCommand
            )
            let next: AgentSurfaceNextAction?
            if record.driverId == "claude_code" {
                next = claudeHumanSignInNextAction
            } else if let fix {
                next = AgentSurfaceNextAction(
                    kind: "signInCLI",
                    label: "Sign in \(manifest?.displayName ?? record.driverId)",
                    command: fix
                )
            } else {
                next = nil
            }
            return .init(statusKind: "needsSignIn", detail: detail, fixCommand: fix, nextAction: next)
        case .shimmedNeedsConfirm(let res):
            return .init(
                statusKind: "needsPath",
                detail: attentionDetail(driverId: record.driverId, state: .needsPath, probeReason: nil)
                    + " (\(res.rawCommandV))",
                fixCommand: "alln doctor --full --json",
                nextAction: AgentSurfaceNextAction(
                    kind: "runDoctorFull",
                    label: "Confirm CLI path",
                    command: "alln doctor --full --json"
                )
            )
        case .notInstalled:
            let detail: String
            let installShell: String?
            let docs: String?
            if let manifest {
                detail = notInstalledDetail(for: manifest)
                installShell = notInstalledInstallShellCommand(for: manifest)
                docs = notInstalledFixCommand(for: manifest)
            } else {
                detail = "Not found on PATH or known paths"
                installShell = nil
                docs = nil
            }
            let fix = installShell ?? docs
            let next: AgentSurfaceNextAction? = fix.map {
                AgentSurfaceNextAction(
                    kind: "installCLI",
                    label: "Install \(manifest?.displayName ?? record.driverId)",
                    command: $0
                )
            }
            return .init(statusKind: "notInstalled", detail: detail, fixCommand: fix, nextAction: next)
        case .probeFailed(let reason):
            let detail = attentionDetail(
                driverId: record.driverId, state: .probeFailed, probeReason: reason)
            let looksLikeLogin = record.driverId == "claude_code"
                && (isOpaqueSmokeExit(reason)
                    || reason.lowercased().contains("oauth session expired")
                    || reason.lowercased().contains("failed to authenticate")
                    || reason.lowercased().contains("login expired"))
            if looksLikeLogin {
                let loginDetail = attentionDetail(
                    driverId: record.driverId, state: .needsLogin, probeReason: nil)
                return .init(
                    statusKind: "needsSignIn",
                    detail: loginDetail,
                    fixCommand: nil,
                    nextAction: claudeHumanSignInNextAction
                )
            }
            let fix = doctorFixCommand(
                driverId: record.driverId, state: .probeFailed, loginInteractiveCommand: nil)
            return .init(
                statusKind: "probeFailed",
                detail: detail,
                fixCommand: fix,
                nextAction: fix.map {
                    AgentSurfaceNextAction(
                        kind: "repairProbe",
                        label: "Repair \(manifest?.displayName ?? record.driverId)",
                        command: $0
                    )
                }
            )
        case .rateLimited(let observation):
            return .init(
                statusKind: "rateLimited",
                detail: DoctorReport.rateLimitedDetail(observation: observation)
            )
        }
    }

    /// Prefer finishing installed CLIs (sign-in / repair) over installing more seats.
    public static func nextActionPriority(kind: String) -> Int {
        switch kind {
        case "signInClaude", "signInCLI": return 0
        case "repairProbe", "runDoctorFull", "confirmPath": return 1
        case "detectCLIs": return 2
        case "installCLI": return 3
        default: return 4
        }
    }

    /// Claude `/login` is human-only. Never point `command` at `alln detect` —
    /// agents that run nextAction blindly would loop forever on the same disease.
    /// Teach the step via help; re-check is in the label after the human finishes.
    public static let claudeHumanSignInNextAction = AgentSurfaceNextAction(
        kind: "signInClaude",
        label: "Open Claude Code, type /login, finish browser sign-in, then run alln detect",
        command: "alln help get setup_and_auth"
    )

    public enum AttentionState: Sendable {
        case needsLogin, needsPath, notInstalled, probeFailed, rateLimited
        case notChecked, installedNotProbed, detecting, reprobing, queued
    }

    /// Opaque nonzero smoke with no vendor prose — often Claude OAuth with empty capture.
    public static func isOpaqueSmokeExit(_ reason: String?) -> Bool {
        let raw = reason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !raw.isEmpty else { return false }
        if raw.hasPrefix("smoke exited ") { return true }
        return raw.range(of: #"^smoke exited \d+$"#, options: .regularExpression) != nil
    }

    private static func probeFailedAttention(driverId: String, reason: String?) -> String {
        let raw = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lower = raw.lowercased()
        if driverId == CursorAgentCLIInstall.driverId,
           lower.contains("grok") || lower.contains("--single") {
            return "Cursor Agent CLI not installed — Grok’s `agent` is not Cursor."
        }
        if driverId == "claude_code",
           isOpaqueSmokeExit(raw)
            || lower.contains("oauth session expired")
            || lower.contains("failed to authenticate")
            || lower.contains("login expired") {
            return attentionDetail(driverId: driverId, state: .needsLogin, probeReason: nil)
        }
        if driverId == "opencode",
           lower.contains("portownedbyforeign") || lower.contains("port owned") {
            return "OpenCode serve is busy on :4096 — attach or free the port, then re-check."
        }
        if driverId == "opencode",
           lower.contains("providermodelnotfound")
            || lower.contains("model not found")
            || lower.contains("opencode-go/")
            || (lower.contains("http 500") && lower.contains("unknownerror")) {
            return "OpenCode is installed — the smoke model/provider was rejected. Re-try probe (uses OpenCode Zen). This isn’t a missing binary."
        }
        if driverId == "opencode",
           lower.contains("opencode smoke") || lower.contains("messagefailed") {
            return "OpenCode serve answered, but the smoke turn failed — Re-try probe. Not a Locate-binary problem."
        }
        if !raw.isEmpty {
            let clipped = raw.count > 120 ? String(raw.prefix(117)) + "…" : raw
            return clipped
        }
        return "Health check failed — re-check this CLI."
    }

    /// Prefer install docs URL for “open this page”; login docs stay separate.
    public static func notInstalledFixCommand(for manifest: DriverManifest) -> String? {
        let docs = manifest.setup?.docsURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let docs, !docs.isEmpty { return docs }
        return nil
    }

    /// Shell one-liner for one-click / Terminal install when the driver supports it.
    public static func notInstalledInstallShellCommand(for manifest: DriverManifest) -> String? {
        if manifest.id == CursorAgentCLIInstall.driverId {
            return CursorAgentCLIInstall.shellCommand
        }
        return nil
    }

    /// Doctor/detect `fixCommand`: prefer a runnable shell fix; never treat Claude `/login` as a shell command.
    public static func doctorFixCommand(
        driverId: String,
        state: AttentionState,
        loginInteractiveCommand: String?
    ) -> String? {
        switch state {
        case .needsLogin:
            if driverId == "claude_code" { return nil }
            if driverId == CursorAgentCLIInstall.driverId {
                let cmd = loginInteractiveCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if cmd == "agent" || cmd == "agent login" { return "cursor-agent login" }
                return cmd.isEmpty ? "cursor-agent login" : cmd
            }
            let cmd = loginInteractiveCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return cmd.isEmpty ? nil : cmd
        case .notInstalled:
            return nil // caller supplies install shell / docs
        case .probeFailed:
            if driverId == "claude_code" { return nil }
            if driverId == CursorAgentCLIInstall.driverId { return "cursor-agent login" }
            if driverId == "opencode" { return "alln detect" }
            return "alln doctor --full"
        default:
            return nil
        }
    }

    /// Login docs when distinct from install docs (Cursor: using vs installation).
    public static func loginDocsURL(for manifest: DriverManifest) -> String? {
        let login = manifest.setup?.loginFlow?.docsURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let login, !login.isEmpty else { return nil }
        let install = manifest.setup?.docsURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if login == install { return nil }
        return login
    }
}
