import AgentOSCLI
import Foundation

/// Shared human/agent recovery copy for setup surfaces (detect, doctor, Mac cards).
/// Catalog fields are the source; this only formats them — never invents install paths.
public enum SetupRecoveryCopy {

    /// One-line detail when a supported driver has an explicit `.notInstalled` record.
    public static func notInstalledDetail(for manifest: DriverManifest) -> String {
        if manifest.id == "cursor_agent" {
            let hint = manifest.setup?.installHint?.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = "Cursor Agent CLI not found — the Cursor app is not the seat."
            if let hint, !hint.isEmpty { return "\(base) \(hint)" }
            return base
        }
        let name = manifest.displayName
        if let hint = manifest.setup?.installHint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hint.isEmpty {
            return "\(name) not found on PATH or known paths. \(hint)"
        }
        return "\(name) not found on PATH or known paths"
    }

    /// Prefer install docs URL for “open this page”; login docs stay separate.
    public static func notInstalledFixCommand(for manifest: DriverManifest) -> String? {
        let docs = manifest.setup?.docsURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let docs, !docs.isEmpty { return docs }
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
