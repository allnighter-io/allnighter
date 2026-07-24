import Foundation

/// `alln bootstrap` — the activation surface that replaced `alln mcp install`
/// (docs/phases/MCP_Retirement.md §Activation). It PRINTS a paste-ready
/// instruction block for a host agent's own context file — same consent
/// posture as the old MCP install: Allnighter never edits another tool's
/// config, the user pastes.
///
/// **Carve-out (ONB-S03 / Decision 3):** the CLI print-never-edit posture is
/// absolute — `alln bootstrap` (and every other CLI command) never writes
/// vendor/agent files. The Mac app, on an explicit human click in
/// "Teach your CLIs", may append/repair/remove the marked GLOBAL teaching
/// block via `GlobalTeachingInstaller`. That click is the user's hands; the
/// CLI remains print-only. Teaching body SSOT is `TeachingSnippet` (ONB-S01).
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
        lines.append("- From the Allnighter checkout, rebuild/refresh with `bash scripts/rebuild_cli.sh`; do not hand-run a multi-step CLI refresh.")
        lines.append(TeachingSnippet.wrap())
        return lines.joined(separator: "\n")
    }

    /// Bounded recipe listing for agents (full markdown via `recipesHelp`).
    public struct RecipeRef: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    /// `--json` envelope: agent-first, so an agent can install itself without
    /// parsing prose. ONB-S02a adds `recipes` (id+title) + `recipesHelp`.
    public struct JSON: Codable, Sendable, Equatable {
        public var schemaVersion: Int
        public var host: String
        public var pasteTarget: String
        public var snippet: String
        public var binaryPath: String
        public var onPath: Bool
        /// Intent-titled recipe cards (v1 SSOT under Bundle.module Recipes/).
        public var recipes: [RecipeRef]
        /// How to read full recipe markdown without inventing a new CLI verb.
        public var recipesHelp: String
        public init(
            schemaVersion: Int = 1,
            host: String,
            pasteTarget: String,
            snippet: String,
            binaryPath: String,
            onPath: Bool,
            recipes: [RecipeRef] = RecipeCatalog.summaries().map { RecipeRef(id: $0.id, title: $0.title) },
            recipesHelp: String = "alln help get recipes --format md"
        ) {
            self.schemaVersion = schemaVersion
            self.host = host
            self.pasteTarget = pasteTarget
            self.snippet = snippet
            self.binaryPath = binaryPath
            self.onPath = onPath
            self.recipes = recipes
            self.recipesHelp = recipesHelp
        }
    }

    public static func json(host: Host, binaryPath: String, onPath: Bool) -> JSON {
        JSON(
            host: host.rawValue,
            pasteTarget: host.pasteTarget,
            snippet: snippet(binaryPath: binaryPath, onPath: onPath),
            binaryPath: binaryPath,
            onPath: onPath,
            recipes: RecipeCatalog.summaries().map { RecipeRef(id: $0.id, title: $0.title) },
            recipesHelp: "alln help get recipes --format md"
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
