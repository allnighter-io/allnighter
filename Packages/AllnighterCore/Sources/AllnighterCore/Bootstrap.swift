import Foundation

/// `alln bootstrap` — the activation surface that replaced `alln mcp install`
/// (docs/phases/MCP_Retirement.md §Activation). It PRINTS a paste-ready
/// instruction block for a host agent's own context file — same consent
/// posture as the old MCP install: Allnighter never edits another tool's
/// config, the user pastes.
public enum Bootstrap {
    /// The host agent surfaces `--host` targets. `generic` is host-neutral —
    /// used when the caller doesn't know (or care) which host it's talking to.
    public enum Host: String, Codable, Sendable, CaseIterable {
        case claude, cursor, codex, generic

        public init?(argument raw: String) {
            self.init(rawValue: raw.lowercased())
        }

        /// Where the user pastes the snippet for this host.
        public var pasteTarget: String {
            switch self {
            case .claude: return "CLAUDE.md (project root), or ~/.claude/CLAUDE.md for a user-level default"
            case .cursor: return ".cursor/rules (project), or AGENTS.md"
            case .codex: return "AGENTS.md"
            case .generic: return "your agent host's context file — CLAUDE.md, .cursor/rules, or AGENTS.md"
            }
        }
    }

    /// Paste-ready snippet with the running-binary fallback and optional install step.
    public static func snippet(binaryPath: String, onPath: Bool) -> String {
        var lines = [
            "Allnighter is available via the `alln` CLI (fallback: `\(binaryPath)`).",
        ]
        if !onPath {
            lines.append("- Run `\(binaryPath) install-cli` once so plain `alln` works everywhere.")
        }
        lines.append(contentsOf: HelpService.bootstrapWorkflowLines)
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
        let binaryPath = InstallCLI.resolvedRunningBinary(argv0: argv0, fileManager: fileManager)
            ?? argv0 ?? "alln"
        let onPath = InstallCLI.onPath(
            runningBinary: binaryPath,
            pathEnvironment: pathEnvironment,
            fileManager: fileManager
        )
        return (binaryPath, onPath)
    }
}
