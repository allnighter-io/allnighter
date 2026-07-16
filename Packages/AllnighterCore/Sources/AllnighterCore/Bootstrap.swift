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

    /// The one snippet every host pastes verbatim — host-neutral by design (the
    /// same bytes work in CLAUDE.md, .cursor/rules, or AGENTS.md), and short:
    /// budget-consciousness is the whole point of retiring MCP's always-loaded
    /// tool schemas (docs/phases/MCP_Retirement.md). SSOT shared with the
    /// `quickstart` help topic — `HelpService.hostInstructionBlock`.
    public static var snippet: String { HelpService.hostInstructionBlock }

    /// `--json` envelope: agent-first, so an agent can install itself without
    /// parsing prose.
    public struct JSON: Codable, Sendable, Equatable {
        public var schemaVersion: Int
        public var host: String
        public var pasteTarget: String
        public var snippet: String
        public init(schemaVersion: Int = 1, host: String, pasteTarget: String, snippet: String) {
            self.schemaVersion = schemaVersion; self.host = host
            self.pasteTarget = pasteTarget; self.snippet = snippet
        }
    }

    public static func json(host: Host) -> JSON {
        JSON(host: host.rawValue, pasteTarget: host.pasteTarget, snippet: snippet)
    }

    public static func jsonString(host: Host) -> String {
        let data = (try? CoreJSON.encode(json(host: host))) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Human-readable rendering for the non-`--json` path: paste target, then
    /// the snippet, verbatim and easy to copy.
    public static func render(host: Host) -> String {
        """
        Paste into \(host.pasteTarget):

        \(snippet)
        """
    }
}
