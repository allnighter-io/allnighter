import Foundation

/// `alln bootstrap` — the activation surface that replaced `alln mcp install`
/// (docs/phases/MCP_Retirement.md §Activation). It PRINTS a paste-ready
/// instruction block for a host agent's own context file — same consent
/// posture as the old MCP install: Allnighter never edits another tool's
/// config, the user pastes.
///
/// Teaching body SSOT is `TeachingSnippet` (ONB-S01). Marker append/repair on
/// a human click is a deliberate Mac-app carve-out from this CLI print-never-
/// edit posture (`docs/phases/Agent_Onboarding.md` Decision 3) — the CLI still
/// never edits.
public enum Bootstrap {
    /// The host agent surfaces `--host` targets. `generic` is host-neutral —
    /// used when the caller doesn't know (or care) which host it's talking to.
    public enum Host: String, Codable, Sendable, CaseIterable {
        case claude, cursor, codex, generic

        public init?(argument raw: String) {
            self.init(rawValue: raw.lowercased())
        }

        /// Where the user pastes the snippet for this host.
        /// Global paths align with `TeachingInstalledCheck.hostMatrix` (v1).
        public var pasteTarget: String {
            switch self {
            case .claude:
                return "~/.claude/CLAUDE.md (user-global), or CLAUDE.md (project root)"
            case .cursor:
                return "~/.cursor/rules/allnighter.mdc (user-global Cursor rules), or project .cursor/rules"
            case .codex:
                return "AGENTS.md (project — Codex has no global instruction file in v1)"
            case .generic:
                return "your agent host's context file — ~/.claude/CLAUDE.md, ~/.cursor/rules/allnighter.mdc, or project AGENTS.md"
            }
        }
    }

    /// Paste-ready snippet: binary fallback + optional install + marked teaching.
    /// Does **not** include Panel/Pilot recipes (see `help get panel`).
    public static func snippet(binaryPath: String, onPath: Bool) -> String {
        var lines = [
            "Allnighter is available via the `alln` CLI (fallback: `\(binaryPath)`).",
        ]
        if !onPath {
            lines.append("- Run `\(binaryPath) install-cli` once so plain `alln` works everywhere.")
        }
        lines.append(TeachingSnippet.wrap())
        return lines.joined(separator: "\n")
    }

    /// `--json` envelope: agent-first, so an agent can install itself without
    /// parsing prose.
    public struct JSON: Codable, Sendable, Equatable {
        public var schemaVersion: Int
        public var host: String
        public var pasteTarget: String
        public var snippet: String
        public var binaryPath: String
        public var onPath: Bool
        public init(
            schemaVersion: Int = 1,
            host: String,
            pasteTarget: String,
            snippet: String,
            binaryPath: String,
            onPath: Bool
        ) {
            self.schemaVersion = schemaVersion
            self.host = host
            self.pasteTarget = pasteTarget
            self.snippet = snippet
            self.binaryPath = binaryPath
            self.onPath = onPath
        }
    }

    public static func json(host: Host, binaryPath: String, onPath: Bool) -> JSON {
        JSON(
            host: host.rawValue,
            pasteTarget: host.pasteTarget,
            snippet: snippet(binaryPath: binaryPath, onPath: onPath),
            binaryPath: binaryPath,
            onPath: onPath
        )
    }

    public static func jsonString(host: Host, binaryPath: String, onPath: Bool) -> String {
        let data = (try? CoreJSON.encode(json(host: host, binaryPath: binaryPath, onPath: onPath))) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Human-readable rendering for the non-`--json` path: paste target, then
    /// the snippet, verbatim and easy to copy.
    public static func render(host: Host, binaryPath: String, onPath: Bool) -> String {
        """
        Paste into \(host.pasteTarget):

        \(snippet(binaryPath: binaryPath, onPath: onPath))
        """
    }

    /// Live activation context from argv[0] + PATH (CLI entry).
    public static func liveContext(
        argv0: String? = CommandLine.arguments.first,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        fileManager: FileManager = .default
    ) -> (binaryPath: String, onPath: Bool) {
        let binaryPath = InstallCLI.resolvedRunningBinary(
            argv0: argv0,
            pathEnvironment: pathEnvironment,
            fileManager: fileManager
        ) ?? argv0 ?? "alln"
        let onPath = InstallCLI.onPath(
            runningBinary: binaryPath,
            pathEnvironment: pathEnvironment,
            fileManager: fileManager
        )
        return (binaryPath, onPath)
    }
}
