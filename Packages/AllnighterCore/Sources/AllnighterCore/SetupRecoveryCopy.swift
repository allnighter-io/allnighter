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
            return "Not checked yet — opening this panel scans for you."
        case .installedNotProbed:
            return "Installed but not checked yet — scanning…"
        case .detecting, .reprobing:
            return "Re-checking this CLI…"
        case .queued:
            return "Queued for check…"
        }
    }

    public enum AttentionState: Sendable {
        case needsLogin, needsPath, notInstalled, probeFailed, rateLimited
        case notChecked, installedNotProbed, detecting, reprobing, queued
    }

    private static func probeFailedAttention(driverId: String, reason: String?) -> String {
        let raw = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lower = raw.lowercased()
        if driverId == CursorAgentCLIInstall.driverId,
           lower.contains("grok") || lower.contains("--single") {
            return "Cursor Agent CLI not installed — Grok’s `agent` is not Cursor."
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

    /// Login docs when distinct from install docs (Cursor: using vs installation).
    public static func loginDocsURL(for manifest: DriverManifest) -> String? {
        let login = manifest.setup?.loginFlow?.docsURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let login, !login.isEmpty else { return nil }
        let install = manifest.setup?.docsURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if login == install { return nil }
        return login
    }
}
