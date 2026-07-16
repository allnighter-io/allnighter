import Foundation

/// Read-only probe of Cursor CLI's global shell permissions
/// (`~/.cursor/cli-config.json`). Allnighter never writes vendor config — this
/// only surfaces a warning when a restrictive shell allowlist would silently
/// cap headless `cursor-agent` turns (even under `--trust`).
///
/// See `docs/phases/Pilot_Defect_Fixes.md` D2.
public enum CursorShellAllowlist {
    public static let checkName = "source.cursor_agent.shellAllowlist"

    /// Default global config path on this machine (`~/.cursor/cli-config.json`).
    public static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/cli-config.json")
    }

    /// Build the doctor check for an optional config URL.
    /// - `nil` path → `notChecked` (call site chose not to probe; tests use this).
    /// - Missing file → `notChecked` (no allowlist configured).
    /// - Restrictive Shell allowlist → `degraded` with a fix hint (file path +
    ///   project-scoped `.cursor/cli.json` override note).
    /// - Permissive / no Shell restriction → `ok`.
    public static func check(
        configURL: URL?,
        fileManager: FileManager = .default
    ) -> DoctorResult.Check {
        guard let configURL else {
            return .init(
                name: checkName,
                status: .notChecked,
                detail: "Cursor CLI shell allowlist not checked (no config path)"
            )
        }

        let path = configURL.path
        guard fileManager.fileExists(atPath: path) else {
            return .init(
                name: checkName,
                status: .notChecked,
                detail: "no Cursor CLI config at \(path) (shell allowlist not configured)"
            )
        }

        guard let data = fileManager.contents(atPath: path) else {
            return .init(
                name: checkName,
                status: .degraded,
                detail: "Cursor CLI config at \(path) is unreadable",
                requiresManual: true
            )
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .init(
                name: checkName,
                status: .degraded,
                detail: "Cursor CLI config at \(path) is not valid JSON",
                requiresManual: true
            )
        }

        return evaluate(root: root, path: path)
    }

    // MARK: - Evaluation

    /// Pure evaluation over a decoded config object (testable without files).
    static func evaluate(root: [String: Any], path: String) -> DoctorResult.Check {
        let approvalMode = (root["approvalMode"] as? String)?.lowercased()
        let permissions = root["permissions"] as? [String: Any]
        let allow = (permissions?["allow"] as? [String]) ?? []

        // Not in allowlist mode and no allow entries → no shell restriction observed.
        if allow.isEmpty {
            if approvalMode == "allowlist" {
                // Empty allow under allowlist mode blocks shell entirely.
                return restrictive(
                    path: path,
                    summary: "approvalMode is allowlist with an empty permissions.allow list"
                )
            }
            return .init(
                name: checkName,
                status: .ok,
                detail: "Cursor CLI shell allowlist not restrictive at \(path)"
            )
        }

        let shellEntries = allow.filter { isShellPermission($0) }
        if shellEntries.isEmpty {
            // Allowlist present but Shell not listed → shell denied under allowlist mode.
            if approvalMode == nil || approvalMode == "allowlist" {
                return restrictive(
                    path: path,
                    summary: "permissions.allow has no Shell entry (shell denied under allowlist)"
                )
            }
            return .init(
                name: checkName,
                status: .ok,
                detail: "Cursor CLI shell allowlist not restrictive at \(path)"
            )
        }

        if shellEntries.contains(where: isPermissiveShell) {
            return .init(
                name: checkName,
                status: .ok,
                detail: "Cursor CLI shell allowlist permits broad shell at \(path)"
            )
        }

        // Finite, non-wildcard Shell(...) entries — the failure mode from the pilot.
        let listed = shellEntries.joined(separator: ", ")
        return restrictive(
            path: path,
            summary: "restrictive shell allowlist (\(listed))"
        )
    }

    private static func restrictive(path: String, summary: String) -> DoctorResult.Check {
        .init(
            name: checkName,
            status: .degraded,
            detail: "Cursor CLI \(summary) in \(path). "
                + "Headless cursor-agent turns cannot run git/python even under --trust. "
                + "Allnighter never writes vendor config — widen the allowlist in that file, "
                + "or add a project-scoped .cursor/cli.json override.",
            requiresManual: true
        )
    }

    private static func isShellPermission(_ entry: String) -> Bool {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "Shell" || trimmed.hasPrefix("Shell(")
    }

    /// Broad forms that do not silently cap headless workers.
    private static func isPermissiveShell(_ entry: String) -> Bool {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "Shell" { return true }
        // Shell(*), Shell(**), Shell(.*), Shell(*)
        guard trimmed.hasPrefix("Shell("), trimmed.hasSuffix(")") else { return false }
        let inner = String(trimmed.dropFirst("Shell(".count).dropLast())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if inner.isEmpty { return true }
        if inner == "*" || inner == "**" || inner == ".*" { return true }
        return false
    }
}
