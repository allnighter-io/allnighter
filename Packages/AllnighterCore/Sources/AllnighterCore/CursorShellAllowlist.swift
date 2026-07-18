import Foundation

/// Read-only probe of Cursor CLI shell permissions. Allnighter never writes vendor
/// config — this only surfaces a warning when a restrictive shell allowlist would
/// silently cap headless `cursor-agent` turns (even under `--trust`).
///
/// Headless cursor-agent resolves permissions from the global
/// `~/.cursor/cli-config.json` merged with project-scoped `.cursor/cli.json` files
/// (walked from git/repo root toward cwd; deeper overrides win). Permissions are
/// read at cursor-agent process start — changes apply on the next headless turn.
///
/// See `docs/phases/Pilot_Defect_Fixes.md` D2 and `Pilot_Polish_And_Agent_UX.md` P4.
public enum CursorShellAllowlist {
    public static let checkName = "source.cursor_agent.shellAllowlist"
    /// Override lookup inspects at most this many directories, including the start.
    public static let projectOverrideSearchDepth = 64

    /// Project-scoped override filename (repo root `.cursor/cli.json`).
    public static let projectOverrideRelativePath = ".cursor/cli.json"

    /// Default global config path on this machine (`~/.cursor/cli-config.json`).
    public static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/cli-config.json")
    }

    /// Discover a project override by walking up from `directory` toward the volume root.
    public static func projectOverrideURL(
        near directory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        var dir = directory.standardizedFileURL
        var visited = Set<String>()
        for _ in 0..<projectOverrideSearchDepth {
            guard visited.insert(dir.path).inserted else { break }
            let candidate = dir
                .appendingPathComponent(".cursor", isDirectory: true)
                .appendingPathComponent("cli.json", isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) { return candidate }
            let parent = dir.deletingLastPathComponent()
            guard parent.path != dir.path else { break }
            dir = parent
        }
        return nil
    }

    /// Build the doctor check for optional global + project override paths.
    /// - `nil` global path → `notChecked` (call site chose not to probe; tests use this).
    /// - Missing global file → `notChecked` (no allowlist configured).
    /// - Restrictive effective shell allowlist → `degraded` with a verified fix hint.
    /// - Permissive / adequate merged allowlist → `ok`.
    public static func check(
        configURL: URL?,
        projectOverrideURL: URL? = nil,
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

        guard let globalRoot = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .init(
                name: checkName,
                status: .degraded,
                detail: "Cursor CLI config at \(path) is not valid JSON",
                requiresManual: true
            )
        }

        let projectRoot = projectOverrideURL.flatMap { url -> [String: Any]? in
            guard fileManager.fileExists(atPath: url.path),
                  let projectData = fileManager.contents(atPath: url.path),
                  let decoded = try? JSONSerialization.jsonObject(with: projectData) as? [String: Any]
            else { return nil }
            return decoded
        }

        return evaluate(
            globalRoot: globalRoot,
            globalPath: path,
            projectRoot: projectRoot,
            projectPath: projectOverrideURL?.path
        )
    }

    // MARK: - Evaluation

    /// Pure evaluation over decoded config objects (testable without files).
    static func evaluate(
        globalRoot: [String: Any],
        globalPath: String,
        projectRoot: [String: Any]? = nil,
        projectPath: String? = nil
    ) -> DoctorResult.Check {
        let mergedAllow = mergedAllowEntries(global: globalRoot, project: projectRoot)
        let approvalMode = (globalRoot["approvalMode"] as? String)?.lowercased()

        if mergedAllow.isEmpty {
            if approvalMode == "allowlist" {
                return restrictive(
                    globalPath: globalPath,
                    projectPath: projectPath,
                    summary: "approvalMode is allowlist with an empty permissions.allow list"
                )
            }
            return .init(
                name: checkName,
                status: .ok,
                detail: "Cursor CLI shell allowlist not restrictive at \(globalPath)"
            )
        }

        let shellEntries = mergedAllow.filter { isShellPermission($0) }
        if shellEntries.isEmpty {
            if approvalMode == nil || approvalMode == "allowlist" {
                return restrictive(
                    globalPath: globalPath,
                    projectPath: projectPath,
                    summary: "permissions.allow has no Shell entry (shell denied under allowlist)"
                )
            }
            return .init(
                name: checkName,
                status: .ok,
                detail: "Cursor CLI shell allowlist not restrictive at \(globalPath)"
            )
        }

        if isAdequateForHeadlessDev(shellEntries) {
            if let projectPath, projectRoot != nil {
                return .init(
                    name: checkName,
                    status: .ok,
                    detail: "Cursor CLI shell allowlist adequate for headless dev "
                        + "(global \(globalPath) merged with project \(projectPath))"
                )
            }
            return .init(
                name: checkName,
                status: .ok,
                detail: "Cursor CLI shell allowlist permits broad shell at \(globalPath)"
            )
        }

        let listed = shellEntries.joined(separator: ", ")
        return restrictive(
            globalPath: globalPath,
            projectPath: projectPath,
            summary: "restrictive shell allowlist (\(listed))"
        )
    }

    /// Backward-compatible single-file evaluation (tests that only pass global config).
    static func evaluate(root: [String: Any], path: String) -> DoctorResult.Check {
        evaluate(globalRoot: root, globalPath: path)
    }

    private static func mergedAllowEntries(
        global: [String: Any],
        project: [String: Any]?
    ) -> [String] {
        let globalAllow = (global["permissions"] as? [String: Any])?["allow"] as? [String] ?? []
        guard let project else { return globalAllow }
        let projectAllow = (project["permissions"] as? [String: Any])?["allow"] as? [String] ?? []
        if projectAllow.isEmpty { return globalAllow }
        if globalAllow.isEmpty { return projectAllow }
        // Cursor merges project overrides with global; union matches headless behavior
        // observed when global Shell(ls) + project Shell(git) unblocks git in the same turn.
        var seen = Set<String>()
        var merged: [String] = []
        for entry in globalAllow + projectAllow {
            if seen.insert(entry).inserted { merged.append(entry) }
        }
        return merged
    }

    private static func restrictive(
        globalPath: String,
        projectPath: String?,
        summary: String
    ) -> DoctorResult.Check {
        let remedy = fixHint(globalPath: globalPath, projectPath: projectPath)
        return .init(
            name: checkName,
            status: .degraded,
            detail: "Cursor CLI \(summary) in \(globalPath). "
                + "Headless cursor-agent respects permissions.allow even under --trust; "
                + "denied shell tools fail with no detail. "
                + remedy,
            requiresManual: true
        )
    }

    /// Verified remedy text (P4): global widen OR repo-root project override.
    static func fixHint(globalPath: String, projectPath: String? = nil) -> String {
        let projectNote = projectPath.map {
            " (no adequate override at \($0))"
        } ?? ""
        return "Allnighter never writes vendor config\(projectNote) — either widen "
            + "permissions.allow in \(globalPath) (e.g. Shell(git), Shell(python3), or Shell(**)), "
            + "or add a repo-root \(projectOverrideRelativePath) such as "
            + "{\"permissions\":{\"allow\":[\"Shell(git)\",\"Shell(python3)\",\"Shell(bash)\",...],\"deny\":[]}}; "
            + "project overrides merge at cursor-agent process start and take effect on the next headless turn."
    }

    private static func isShellPermission(_ entry: String) -> Bool {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "Shell" || trimmed.hasPrefix("Shell(")
    }

    /// Broad forms or explicit git+python coverage for headless dev seats.
    private static func isAdequateForHeadlessDev(_ entries: [String]) -> Bool {
        if entries.contains(where: isPermissiveShell) { return true }
        let lowered = Set(entries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let hasGit = lowered.contains("shell") || lowered.contains("shell(git)")
        let hasPython = lowered.contains("shell") || lowered.contains("shell(python3)")
        return hasGit && hasPython
    }

    /// Broad forms that do not silently cap headless workers.
    private static func isPermissiveShell(_ entry: String) -> Bool {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "Shell" { return true }
        guard trimmed.hasPrefix("Shell("), trimmed.hasSuffix(")") else { return false }
        let inner = String(trimmed.dropFirst("Shell(".count).dropLast())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if inner.isEmpty { return true }
        if inner == "*" || inner == "**" || inner == ".*" { return true }
        return false
    }
}
