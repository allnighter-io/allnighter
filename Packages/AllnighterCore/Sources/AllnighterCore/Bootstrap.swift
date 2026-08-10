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
    /// `hermes` / `openclaw` are cold-install hosts (OPC-S02): released binary,
    /// no checkout, print-only system-prompt paste.
    public enum Host: String, Codable, Sendable, CaseIterable {
        case claude, cursor, codex, generic, hermes, openclaw

        public init?(argument raw: String) {
            self.init(rawValue: raw.lowercased())
        }

        /// Where the user pastes the snippet for this host.
        /// Global paths align with `TeachingInstalledCheck.hostMatrix` (v1).
        /// Hermes/OpenClaw: honest print-only — do not invent an unverified path.
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
            case .hermes, .openclaw:
                return "host system prompt / tools instructions (print-only)"
            }
        }

        /// Checkout hosts may rebuild from source; cold-install hosts only have
        /// the released binary (OPC-S02 — never teach `rebuild_cli.sh` there).
        public var includesCheckoutRebuild: Bool {
            switch self {
            case .claude, .cursor, .codex, .generic:
                return true
            case .hermes, .openclaw:
                return false
            }
        }

        /// The host's own bench driver id, when the host IS a bench vendor.
        /// `generic` is nil because we do not know who is reading; hermes and
        /// openclaw are not bench drivers.
        public var ownDriverId: String? {
            switch self {
            case .claude: return "claude_code"
            case .cursor: return "cursor_agent"
            case .codex: return "codex"
            case .generic, .hermes, .openclaw: return nil
            }
        }

        /// Stops an agent routing same-vendor work through `alln` by reflex.
        ///
        /// Frontier models keep making this call: a Claude session dispatching a
        /// single Claude run via `alln run --model model_sonnet`, which adds a
        /// subprocess and loses mid-run steering to reach a sibling it could
        /// have subagented directly. `alln`'s value is CROSSING vendors — using
        /// it to reach your own buys nothing.
        ///
        /// Not "never", though: for a loop you start and walk away from, `alln`
        /// is right regardless of vendor, because detached and tracked is
        /// exactly what it adds (founder, 2026-08-06). So the rule is never
        /// *default*, not never.
        ///
        /// Host-gated, and it names the actual driver — which is only possible
        /// because `bootstrap` knows its host. That is also why this is a
        /// preamble line and not a `TeachingSnippet` rule: the shared body is
        /// host-blind, so it could only say something vague, and it is capped at
        /// invariants anyway.
        public var sameVendorNote: String? {
            guard let driver = ownDriverId else { return nil }
            let name = pasteTargetHostName ?? rawValue
            return "- You are \(name). For a single `\(driver)` run, use your own subagents. "
                + "`alln` is for the CLIs you cannot reach — and for loops you start and leave."
        }

        /// Human name for this host, used only by `sameVendorNote`.
        var pasteTargetHostName: String? {
            switch self {
            case .claude: return "Claude Code"
            case .cursor: return "Cursor"
            case .codex: return "Codex"
            case .generic, .hermes, .openclaw: return nil
            }
        }

        /// Compact host-specific advice ahead of the shared snippet (render only).
        /// Cold hosts only — checkout hosts already live in a repo context.
        public var coldStartPreamble: String? {
            // FCS-S02: agents (not humans) run detect via menu nextAction after curl.
            let findCLIs = """
                Start with `alln menu --json`. If `benchTally.nextAction` is set, run that command once before any spend.
                """
            switch self {
            case .hermes, .openclaw:
                return """
                Allnighter runs on the subscription CLIs you already pay for — not API keys.
                \(findCLIs.trimmingCharacters(in: .whitespacesAndNewlines))
                Authorize before any spend or mutate.
                Upgrade between rounds, never mid-loop.
                """
            case .claude, .cursor, .codex, .generic:
                return findCLIs.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// Paste-ready snippet: binary fallback + optional install + marked teaching.
    /// Does **not** embed surface command rows; detached acknowledgements return
    /// the exact status waiter and recipe cards add the surface-specific context.
    /// Checkout rebuild guidance is host-gated (absent for hermes/openclaw).
    public static func snippet(binaryPath: String, onPath: Bool, host: Host = .generic) -> String {
        var lines = [
            "Allnighter is available via the `alln` CLI (fallback: `\(binaryPath)`).",
        ]
        if !onPath {
            lines.append("- Run `\(binaryPath) install-cli` once so plain `alln` works everywhere.")
        }
        if host.includesCheckoutRebuild {
            lines.append("- From the Allnighter checkout, rebuild/refresh with `bash scripts/rebuild_cli.sh`; do not hand-run a multi-step CLI refresh.")
        }
        if let sameVendor = host.sameVendorNote {
            lines.append(sameVendor)
        }
        lines.append(TeachingSnippet.wrap())
        return lines.joined(separator: "\n")
    }

    /// A **one-time** prompt to paste into a live session — not a context file.
    ///
    /// Deliberately separate from `TeachingSnippet`, and the distinction is the
    /// whole point. The teaching block is a *standing* instruction: it is read
    /// every session forever, so it pays its cost every session and may only
    /// carry invariants (which is why it is three lines). Asking an agent to
    /// introduce itself has one-time value and a permanent price — put it in the
    /// block and the user gets the same lecture at the start of every session
    /// until they delete the block (founder, 2026-08-06: "then you get annoyed
    /// with every new session").
    ///
    /// So it lives here instead: pasted once, into whichever CLI the user is
    /// trying out, where a little chattiness is exactly what is wanted. It is
    /// also the honest answer to "how do I use this in a CLI you have no
    /// installer for" — every agent can read the live menu, no file required.
    public static let starterPrompt = """
    Allnighter is on this machine as the `alln` CLI. It can dispatch work to the \
    other coding CLIs I already pay for — in parallel, or as a team.

    Read `alln menu --json`, then tell me three specific things you could do for \
    me in this project that you could not do a minute ago. Name the actual teams \
    or models you would use, and what each one is good for. Keep it short.

    Don't run anything that spends quota until I ask.
    """

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
        /// QABC-S00c — passthrough only; caller injects, Bootstrap never acquires.
        public var capacity: MenuJSON.Capacity?
        public init(
            schemaVersion: Int = 1,
            host: String,
            pasteTarget: String,
            snippet: String,
            binaryPath: String,
            onPath: Bool,
            recipes: [RecipeRef] = RecipeCatalog.summaries().map { RecipeRef(id: $0.id, title: $0.title) },
            recipesHelp: String = "alln help get recipes --format md",
            capacity: MenuJSON.Capacity? = nil
        ) {
            self.schemaVersion = schemaVersion
            self.host = host
            self.pasteTarget = pasteTarget
            self.snippet = snippet
            self.binaryPath = binaryPath
            self.onPath = onPath
            self.recipes = recipes
            self.recipesHelp = recipesHelp
            self.capacity = capacity
        }
    }

    public static func json(host: Host, binaryPath: String, onPath: Bool, capacity: MenuJSON.Capacity? = nil) -> JSON {
        JSON(
            host: host.rawValue,
            pasteTarget: host.pasteTarget,
            snippet: snippet(binaryPath: binaryPath, onPath: onPath, host: host),
            binaryPath: binaryPath,
            onPath: onPath,
            recipes: RecipeCatalog.summaries().map { RecipeRef(id: $0.id, title: $0.title) },
            recipesHelp: "alln help get recipes --format md",
            capacity: capacity
        )
    }

    public static func jsonString(host: Host, binaryPath: String, onPath: Bool, capacity: MenuJSON.Capacity? = nil) -> String {
        let data = (try? CoreJSON.encode(json(host: host, binaryPath: binaryPath, onPath: onPath, capacity: capacity))) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Human-readable rendering for the non-`--json` path: optional cold-host
    /// preamble, paste target, then the snippet — verbatim and easy to copy.
    public static func render(host: Host, binaryPath: String, onPath: Bool) -> String {
        var blocks: [String] = []
        if let preamble = host.coldStartPreamble {
            blocks.append(preamble.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        blocks.append("""
        Paste into \(host.pasteTarget):

        \(snippet(binaryPath: binaryPath, onPath: onPath, host: host))
        """)
        return blocks.joined(separator: "\n\n")
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
