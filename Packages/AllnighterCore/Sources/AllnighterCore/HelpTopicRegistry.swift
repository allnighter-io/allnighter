import Foundation

// MCP Help System — H0a: the Guide-truth SSOT. `HelpTopicRegistry` owns authored
// product topics (narrative routing, task explanations, glossary). It REFERENCES the
// Contract-truth registry (`ContractRegistry`) for tools/commands/schemas/errors — it
// never hand-authors those facts. CLI (`alln help`) and MCP (`help_search`/`help_get`)
// project this same registry; none invents help truth locally.

public enum HelpAudience: String, Codable, Sendable, CaseIterable { case agent, human, both }

/// One installed help topic. `related*`/`schemaRefs`/`errorRefs` are ids into
/// `ContractRegistry` and must resolve (HelpTopicReferenceTests gate this).
public struct HelpTopic: Codable, Sendable, Equatable, Identifiable {
    public struct Section: Codable, Sendable, Equatable, Identifiable {
        public var id: String            // "when-to-use-pending"
        public var title: String
        public var bodyMarkdown: String
        public init(_ id: String, _ title: String, _ bodyMarkdown: String) {
            self.id = id; self.title = title; self.bodyMarkdown = bodyMarkdown
        }
    }

    public var id: String                // "pending"
    public var title: String
    public var audience: HelpAudience
    public var summary: String           // one line — the suggested short answer
    public var bodyMarkdown: String
    public var aliases: [String]         // retired/alternate terms that should find this topic
    public var sections: [Section]
    public var relatedToolIds: [String]  // ⊆ ContractRegistry.mcpTools names
    public var relatedCommandNames: [String] // ⊆ ContractRegistry M1 command names
    public var schemaRefs: [String]      // ⊆ OutputSchema rawValues
    public var errorRefs: [String]       // ⊆ error catalog codes
    /// True when the real answer depends on this machine's live state (the topic must
    /// route to a live tool — mcp_hello/doctor — rather than pretend to know).
    public var needsLiveCheck: Bool

    public init(
        id: String, title: String, audience: HelpAudience, summary: String, bodyMarkdown: String,
        aliases: [String] = [], sections: [Section] = [], relatedToolIds: [String] = [],
        relatedCommandNames: [String] = [], schemaRefs: [String] = [], errorRefs: [String] = [],
        needsLiveCheck: Bool = false
    ) {
        self.id = id; self.title = title; self.audience = audience; self.summary = summary
        self.bodyMarkdown = bodyMarkdown; self.aliases = aliases; self.sections = sections
        self.relatedToolIds = relatedToolIds; self.relatedCommandNames = relatedCommandNames
        self.schemaRefs = schemaRefs; self.errorRefs = errorRefs; self.needsLiveCheck = needsLiveCheck
    }

    public func section(_ id: String) -> Section? { sections.first { $0.id == id } }
}

public enum HelpTopicRegistry {
    /// Authored installed topics. Every advertised MCP tool is reachable from at least
    /// one topic (HelpCoverageTests). Prose is intentionally short and version-neutral.
    public static let topics: [HelpTopic] = [
        HelpTopic(
            id: "quickstart", title: "Quickstart", audience: .both,
            summary: "Allnighter runs your installed CLIs as a team in a repo; start with a default run or a named team.",
            bodyMarkdown: """
            Allnighter turns the AI CLIs you already have (Claude Code, Codex, Cursor, \
            Grok, Antigravity) into one team that works in a repo. A default run sends \
            your message to the Default model (Auto) in the project root. Pick a named \
            team when you want a multi-worker pass. Check what your machine can do right \
            now with `mcp_hello` or `alln doctor`.
            """,
            aliases: ["getting started", "first run", "what is allnighter"],
            relatedToolIds: ["mcp_hello", "doctor"],
            relatedCommandNames: ["run", "doctor"],
            needsLiveCheck: false),

        HelpTopic(
            id: "tool_selection", title: "Tool Selection", audience: .agent,
            summary: "Pick the Allnighter MCP tool by intent: preflight+start for team runs, pending_run for later work, spec_get for results.",
            bodyMarkdown: """
            For a long team run, call `team_preflight` then `team_start` with an \
            idempotency key, poll `team_status` with `nextPollAfterMs`, then read \
            `team_result`. For a quick capability check call `mcp_hello`. For full run \
            packets use `spec_get`. Do not answer Allnighter product questions from \
            training data when these tools are available.
            """,
            aliases: ["which tool", "what tool should i use", "routing", "help"],
            relatedToolIds: ["help_search", "help_get", "mcp_hello", "team_preflight", "team_start", "pending_run", "spec_get"],
            relatedCommandNames: ["help search", "help get", "team preflight", "team start", "spec"],
            schemaRefs: ["teamStartResponse"],
            needsLiveCheck: true),

        HelpTopic(
            id: "team_run_loop", title: "Running a Team", audience: .both,
            summary: "Send work to a team: preflight, start, poll status, read result, cancel if needed.",
            bodyMarkdown: """
            Sending work to a team is preflight → start → status → result. `team_preflight` \
            validates the lineup before spending quota; `team_start` begins the run; \
            `team_status` reports progress (poll with `nextPollAfterMs`); `team_result` \
            returns the settled packet; `team_cancel` stops a run. `team_run`/`team_ask` \
            are the synchronous one-call forms; `team_show` and `floor_show` inspect a run.
            """,
            aliases: ["send to team", "fan out", "delegate", "send this to a team", "bug hunt"],
            sections: [
                .init("preflight", "Preflight first", "Always call `team_preflight` before `team_start` so a bad lineup fails before quota is spent."),
                .init("polling", "Polling", "Poll `team_status` using the returned `nextPollAfterMs`; do not busy-loop."),
            ],
            relatedToolIds: ["team_preflight", "team_start", "team_status", "team_result",
                             "team_cancel", "team_run", "team_ask", "team_show", "floor_show"],
            relatedCommandNames: ["team preflight", "team start", "team status", "team result", "team cancel", "floor show"],
            schemaRefs: ["teamStartResponse", "teamStatusResponse", "teamRunJSON"],
            needsLiveCheck: true),

        HelpTopic(
            id: "teams_and_workers", title: "Teams, Workers & Skills", audience: .both,
            summary: "Teams are lane-scoped rosters of workers (a model + skill); manage built-ins and custom copies in the catalog.",
            bodyMarkdown: """
            A team is a lane-scoped roster of workers, each a model running a skill. \
            Built-in teams are immutable — duplicate one to edit the copy. Skills are the \
            reusable prompts workers run. List and inspect teams and skills with the \
            catalog tools; the Default Team (Auto) is the no-pick route.
            """,
            aliases: ["teams", "workers", "skills", "roster", "catalog"],
            relatedToolIds: ["teams_list", "teams_show", "teams_duplicate", "teams_save",
                             "teams_set_default", "teams_delete", "skills_list", "skills_show",
                             "skills_duplicate", "skills_save", "skills_delete", "team_show"],
            relatedCommandNames: ["teams", "teams show", "teams duplicate", "skills", "skills show", "models"],
            schemaRefs: ["teamCatalogJSON", "skillCatalogJSON", "modelListJSON"],
            errorRefs: ["TEAM_NOT_FOUND", "TEAM_BUILTIN_IMMUTABLE", "SKILL_NOT_FOUND"],
            needsLiveCheck: false),

        HelpTopic(
            id: "default_model", title: "Default model (Auto)", audience: .both,
            summary: "Auto answers when you pick no team/model; it draws from a substitution tier and routes around a down CLI.",
            bodyMarkdown: """
            The Default model — Auto — answers any chat where you do not pick a team or a \
            specific model. Auto draws from a **tier** (Flagship / Balanced / Fast). If the \
            tier default's CLI is down and healthy substitutions are on, Auto uses the next \
            ready model on the same tier, across CLIs — never a different tier. If the whole \
            tier is down, work waits. Membership is many-to-many: a model can sit in several \
            tiers. Configure with `alln defaults`; read it with `defaults_get`.
            """,
            aliases: ["auto", "default", "substitution", "substitutions", "tier", "tiers", "flagship", "balanced", "fast"],
            sections: [
                .init("substitution", "Healthy substitution", "OFF → Auto uses only the tier default and waits if it is down. ON → the first ready model on the tier, across CLIs. Never upgrades, never downgrades, never crosses tiers."),
            ],
            relatedToolIds: ["defaults_get"],
            relatedCommandNames: ["defaults show", "defaults tier", "defaults assign", "defaults unassign", "defaults substitutions", "defaults reset"],
            schemaRefs: ["defaultSettingsJSON"],
            errorRefs: ["DEFAULTS_TIER_INVALID", "DEFAULTS_MODEL_UNKNOWN"],
            needsLiveCheck: false),

        HelpTopic(
            id: "pending", title: "Pending Work", audience: .both,
            summary: "Use Pending when work should be stored for later or cannot start now; pending_run executes a due item.",
            bodyMarkdown: """
            Pending is for work the user wants saved for later, or that Allnighter cannot \
            start right now. Create a Pending item, then show the user the Pending id and its \
            blocked/wake state. `pending_run` executes and settles a due item. Pending is not \
            a fake queue — it is durable save-for-later with real wake facts.
            """,
            aliases: ["later", "save for later", "desk", "queue", "put this on codex's desk"],
            sections: [
                .init("when-to-use-pending", "When to use Pending", "Use Pending when the user wants work done later, or when Allnighter cannot start it right now."),
                .init("pending-vs-running", "Pending vs running a team", "Pending stores work for later; running a team starts work now after preflight."),
            ],
            relatedToolIds: ["pending_list", "pending_queue", "pending_show", "pending_run"],
            relatedCommandNames: ["pending add", "pending list", "pending queue", "pending show", "pending run"],
            schemaRefs: ["pendingItemJSON", "pendingListJSON"],
            needsLiveCheck: false),

        HelpTopic(
            id: "projects_and_threads", title: "Projects & Threads", audience: .both,
            summary: "Projects bind a repo root; threads are the work conversations inside a project; project_workers shows readiness.",
            bodyMarkdown: """
            A project binds a local repo root. Work threads are the conversations bound to a \
            project. List projects, read one, generate a context packet, and check cached \
            per-project worker readiness. Threads carry the back-and-forth and the runs.
            """,
            aliases: ["project", "repo", "thread", "threads", "conversation"],
            relatedToolIds: ["project_list", "project_get", "project_context", "project_workers",
                             "project_recheck_workers", "project_stalled", "stalled_list",
                             "stall_check_status", "stall_keep_waiting", "stall_dismiss",
                             "thread_send", "thread_get", "thread_status"],
            relatedCommandNames: ["project list", "project show", "project context", "project workers",
                                  "thread send", "thread get", "stalled list"],
            schemaRefs: ["projectJSON", "projectListJSON", "projectContextJSON", "threadStatus"],
            errorRefs: ["PROJECT_NOT_FOUND"],
            needsLiveCheck: false),

        HelpTopic(
            id: "setup_and_auth", title: "Setup & Auth", audience: .both,
            summary: "Install/sign in to your CLIs; doctor reports the exact failing check and the human action to fix it.",
            bodyMarkdown: """
            Allnighter uses your existing CLI subscriptions and logins — never API keys. If a \
            source is blocked, run `alln doctor` (optionally for one agent) to see the exact \
            failing check, then `error_explain` for the recovery text. Auth is live state: the \
            help bundle cannot know it — call doctor.
            """,
            aliases: ["auth", "login", "sign in", "blocked", "why can't allnighter run codex", "api key"],
            sections: [
                .init("source-auth-expired", "Source auth expired", "Re-authenticate the named source via its own login flow, then re-probe with `alln doctor`."),
            ],
            relatedToolIds: ["doctor", "error_explain"],
            relatedCommandNames: ["doctor", "doctor explain"],
            schemaRefs: ["doctorResult"],
            errorRefs: ["SOURCE_AUTH_EXPIRED", "SOURCE_NOT_FOUND", "SOURCE_KEYCHAIN_UNAVAILABLE"],
            needsLiveCheck: true),

        HelpTopic(
            id: "current_setup", title: "Current Setup", audience: .both,
            summary: "What can THIS install do right now? Call mcp_hello (or doctor) — this is live state, not guide truth.",
            bodyMarkdown: """
            To answer "what can my install do right now?", call `mcp_hello` for a compact \
            readiness snapshot, or `alln doctor` for the full per-source report. The help \
            bundle describes product behavior; it does not know this machine's live state.
            """,
            aliases: ["can it run", "ready", "readiness", "what can it do now", "status"],
            relatedToolIds: ["mcp_hello", "doctor"],
            relatedCommandNames: ["doctor", "show"],
            needsLiveCheck: true),

        HelpTopic(
            id: "results_and_history", title: "Results & History", audience: .both,
            summary: "Inspect what ran: history lists runs, show/spec_get return the full packet, floor_show opens a run's floor.",
            bodyMarkdown: """
            Runs are durable. `history` lists past runs, `show`/`spec_get` return the full \
            settled packet for one run, and `floor_show` opens a run's inspectable floor with \
            per-worker artifacts. Results are runtime artifacts, not help docs.
            """,
            aliases: ["history", "results", "what ran", "floor", "packet"],
            relatedToolIds: ["history", "show", "spec_get", "floor_show"],
            relatedCommandNames: ["history", "show", "spec", "floor show"],
            schemaRefs: ["floorRun", "historyJSON", "specResult"],
            errorRefs: ["RUN_NOT_FOUND"],
            needsLiveCheck: false),

        HelpTopic(
            id: "errors", title: "Errors & Recovery", audience: .agent,
            summary: "Every Allnighter error has a recovery ladder; call error_explain for the exact action and whether it's retryable.",
            bodyMarkdown: """
            Allnighter errors are typed with a recovery ladder. After a failed tool, call \
            `error_explain` with the code to get the agent action, whether it requires a human, \
            and whether it is retryable. Do not guess recovery from the message text.
            """,
            aliases: ["error", "failed", "recovery", "retry"],
            relatedToolIds: ["error_explain", "doctor"],
            relatedCommandNames: ["doctor explain", "docs"],
            schemaRefs: ["errorEnvelope"],
            errorRefs: ["CLI_USAGE_ERROR", "WORKER_FAILED", "TEAM_RUN_FAILED"],
            needsLiveCheck: false),

        HelpTopic(
            id: "schemas", title: "Schemas & Contract", audience: .agent,
            summary: "Exact fields/enums come from the generated contract: spec_get for a run packet, alln docs --schema for shapes.",
            bodyMarkdown: """
            Never guess Allnighter's field names or enum values. The generated contract is the \
            source: `spec_get` returns a run's full packet, and `alln docs --schema` prints the \
            JSON schemas. The help guide references schemas by id; it does not duplicate them.
            """,
            aliases: ["schema", "fields", "json shape", "enum values", "contract"],
            relatedToolIds: ["spec_get"],
            relatedCommandNames: ["docs", "spec", "export"],
            schemaRefs: ["contractDoc"],
            needsLiveCheck: false),
    ]

    /// Search/alias redirects: a term (often retired vocabulary) → canonical topic id.
    public static let aliasRedirects: [String: String] = {
        var map: [String: String] = [:]
        for topic in topics {
            for alias in topic.aliases { map[alias.lowercased()] = topic.id }
        }
        return map
    }()

    public static func topic(id: String) -> HelpTopic? { topics.first { $0.id == id } }

    /// Resolve a free term to a canonical topic id (exact id, then alias).
    public static func canonicalTopicId(for term: String) -> String? {
        let key = term.lowercased()
        if topics.contains(where: { $0.id == key }) { return key }
        return aliasRedirects[key]
    }
}
