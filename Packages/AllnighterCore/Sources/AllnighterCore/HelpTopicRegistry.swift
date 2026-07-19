import Foundation

// Help System — H0a: the Guide-truth SSOT. `HelpTopicRegistry` owns authored
// product topics (narrative routing, task explanations, glossary). It REFERENCES the
// Contract-truth registry (`ContractRegistry`) for commands/schemas/errors — it
// never hand-authors those facts. `alln help` projects this same registry; nothing
// invents help truth locally.

public enum HelpAudience: String, Codable, Sendable, CaseIterable { case agent, human, both }

/// One installed help topic. `relatedCommandNames`/`schemaRefs`/`errorRefs` are ids into
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
    public var relatedCommandNames: [String] // ⊆ ContractRegistry M1 command names
    public var schemaRefs: [String]      // ⊆ OutputSchema rawValues
    public var errorRefs: [String]       // ⊆ error catalog codes
    /// True when the real answer depends on this machine's live state (the topic must
    /// route to a live command — `alln team hello` / `alln doctor` — rather than pretend to know).
    public var needsLiveCheck: Bool

    public init(
        id: String, title: String, audience: HelpAudience, summary: String, bodyMarkdown: String,
        aliases: [String] = [], sections: [Section] = [],
        relatedCommandNames: [String] = [], schemaRefs: [String] = [], errorRefs: [String] = [],
        needsLiveCheck: Bool = false
    ) {
        self.id = id; self.title = title; self.audience = audience; self.summary = summary
        self.bodyMarkdown = bodyMarkdown; self.aliases = aliases; self.sections = sections
        self.relatedCommandNames = relatedCommandNames
        self.schemaRefs = schemaRefs; self.errorRefs = errorRefs; self.needsLiveCheck = needsLiveCheck
    }

    public func section(_ id: String) -> Section? { sections.first { $0.id == id } }
}

public enum HelpTopicRegistry {
    /// Authored installed topics. Cross-links use `relatedCommandNames` only
    /// (ContractRegistry M1 names). Prose is intentionally short and version-neutral.
    public static let topics: [HelpTopic] = [
        HelpTopic(
            id: "quickstart", title: "Quickstart", audience: .both,
            summary: "Ensure `alln` is on your PATH, then check readiness with `alln team hello` or `alln doctor`.",
            bodyMarkdown: """
            Step zero: make sure `alln` resolves on your PATH. If `which alln` fails, run \
            `alln install-cli` (or invoke the built binary by absolute path and follow its \
            install step). Then check what your machine can do with `alln team hello` or \
            `alln doctor`.

            Allnighter turns the AI CLIs you already have (Claude Code, Codex, Cursor, \
            Grok, Antigravity) into one team that works in a repo. A default run sends \
            your message to the Default model (Auto) in the project root. Pick a named \
            team when you want a multi-worker pass.

            Other agents: run `alln bootstrap` for a paste-ready context snippet that teaches \
            the router reflex (`alln team hello --for`) in one paste (no MCP server, no config file edits).
            """,
            aliases: ["getting started", "first run", "what is allnighter"],
            relatedCommandNames: ["install-cli", "run", "doctor", "bootstrap", "team hello"],
            needsLiveCheck: false),

        HelpTopic(
            id: "bootstrap", title: "Bootstrap (agent activation)", audience: .agent,
            summary: "`alln bootstrap [--host claude|cursor|codex|generic] [--json]` prints a paste-ready context snippet — no MCP server, no config file edits.",
            bodyMarkdown: """
            Step zero: ensure `alln` is on PATH (`alln install-cli` if `which alln` fails). \
            Allnighter has no MCP server and no daemon to install — the CLI is the whole \
            agent surface, no humans in the loop. `alln bootstrap` PRINTS (never edits \
            files) a short, paste-ready instruction block for a host agent's own context: \
            `~/.claude/CLAUDE.md` for Claude, `~/.cursor/rules/allnighter.mdc` for Cursor, \
            project AGENTS.md for Codex (no global Codex path in v1), or a host-neutral \
            block when `--host` is omitted. The block teaches one reflex — \
            `alln team hello --for "<intent>" --json` (read-only, free; run \
            `recommended.command` only when the user already authorized that work), plus \
            `alln help search`/`alln help get` and `alln doctor --json`. Panel cockpit \
            recipes stay in `help get panel`, not bootstrap. Marker-delimited with schema \
            version + content hash so `alln doctor` can report teaching.installed. \
            `--json` returns `{ host, pasteTarget, snippet, binaryPath, onPath, recipes, recipesHelp }` \
            so an agent can install itself and discover intent-titled recipe cards \
            (`recipes[]` is id+title only; full markdown via `recipesHelp`).

            When unsure which verb to use (`run` vs `team` vs `thread send` vs `pending`), \
            call `alln team hello --for` or read `alln help get tool_selection`.

            To rebuild this CLI from an Allnighter checkout: `swift build -c release --product alln`, \
            then `alln install-cli` (symlinks the workspace release build onto PATH). Confirm \
            freshness with `alln version --json` (binaryVersion plus gitSha / buildTime).
            """,
            aliases: ["install", "setup", "connect agent", "activation", "add to agent",
                     "wire up allnighter", "onboard agent", "mcp install", "mcp", "install mcp",
                     "rebuild", "self build", "fresh binary", "build alln"],
            relatedCommandNames: ["install-cli", "bootstrap", "help get", "help search", "team hello", "doctor", "version"],
            schemaRefs: [],
            needsLiveCheck: false),

        HelpTopic(
            id: "tool_selection", title: "Command Selection", audience: .agent,
            summary: "When unsure, start with `alln team hello --for`. Then pick `run`, `team`/`team start`, `thread send`, or `pending` by intent.",
            bodyMarkdown: """
            When unsure which command to use, call `alln team hello --for "<intent>" --json` \
            first — it recommends a team or primitive and a runnable `command`. Do not invent flags.

            Verb tree:
            - `alln run` — single worker / chat / named-model ask in the project root \
            (Default Team). One message; optional `--worker` or `--team`.
            - `alln team` — foreground multi-seat lane team on a prompt.
            - `alln team start` — async multi-seat team run. Always `alln team preflight` \
            before a real start; poll `alln team status` / `alln team result` with \
            `nextPollAfterMs`, then `alln show`.
            - `alln thread send` — continue an existing work thread (not a fresh one-shot).
            - `alln pending` — defer work (`alln pending add`); run later with `alln pending run`.

            For a quick capability check call `alln team hello`. For full run packets use \
            `alln spec`. Do not answer Allnighter product questions from training data when \
            these commands are available.
            """,
            aliases: ["which tool", "what tool should i use", "routing", "help",
                      "which command", "which command should i use", "what command",
                      "run vs team", "thread send", "command selection", "first contact",
                      "when to use run", "when to use team"],
            sections: [
                .init("when-unsure", "When unsure", "Call `alln team hello --for \"<intent>\" --json` before picking a verb."),
                .init("run", "alln run", "Single worker / chat / named-model ask in the project root."),
                .init("team", "alln team / team start", "Multi-seat: foreground `alln team`, or async `alln team start` after preflight."),
                .init("thread", "alln thread send", "Continue a work thread with `alln thread send`."),
                .init("pending", "alln pending", "Defer with `alln pending add`; execute later with `alln pending run`."),
            ],
            relatedCommandNames: ["help search", "help get", "team hello", "run", "team",
                                  "team preflight", "team start", "team result", "thread send",
                                  "pending add", "pending run", "spec", "show"],
            schemaRefs: ["teamStartResponse"],
            needsLiveCheck: true),

        HelpTopic(
            id: "team_run_loop", title: "Running a Team", audience: .both,
            summary: "Send work to a team: preflight, start, poll status/result, cancel if needed.",
            bodyMarkdown: """
            Sending work to a team is preflight → start → status/result. `alln team preflight` \
            validates the lineup before spending quota; `alln team start` begins the run; \
            `alln team status` and `alln team result` report progress or the settled packet \
            (poll with `nextPollAfterMs`); `alln team cancel` stops a run. Inspect a finished \
            run with `alln show`, `alln spec`, or `alln floor show`.
            """,
            aliases: ["send to team", "fan out", "delegate", "send this to a team", "bug hunt"],
            sections: [
                .init("preflight", "Preflight first", "Always call `alln team preflight` before a real `alln team start` so a bad lineup fails before quota is spent."),
                .init("polling", "Polling", "Poll `alln team result` using the returned `nextPollAfterMs`; do not busy-loop."),
            ],
            relatedCommandNames: ["team preflight", "team start", "team status", "team result", "team cancel", "team reconcile", "floor show"],
            schemaRefs: ["teamStartResponse", "teamStatusResponse", "teamRunJSON"],
            needsLiveCheck: true),

        HelpTopic(
            id: "pm_relay", title: "PM Relay", audience: .both,
            summary: "Mechanizes the founder's PM↔dev copy-paste loop: a PM seat reviews the repo and writes a handover, a dev seat builds and commits, round after round, unattended.",
            bodyMarkdown: """
            The PM Relay automates a two-seat loop that used to be a human relaying prose \
            between two CLI sessions. Each round: the PM seat re-reads the spec doc and the \
            actual commit range, writes free-form review plus a handover, and ends with one \
            small verdict block — continue (with a handover for the dev), done (closing \
            summary), or escalate (a specific question for the founder). A safety scan runs \
            over every handover before it reaches the dev seat; a danger instruction (leaking \
            credentials, destructive git, signing, sandbox/TCC changes, mass deletion) blocks \
            dispatch and escalates instead. The dev seat builds, commits through its own \
            tooling, and writes a delivery report that becomes the next round's review input. \
            The loop stops only on done, escalate, or a ceiling (`--until`, `--max-rounds`, or \
            repeated no-progress rounds) — never by inference. Drive it with CLI verbs: \
            `alln pair relay` starts a new relay, `alln pair relay-status` reads durable state, \
            `alln pair relay-resume` injects the founder's answer into an escalated relay and \
            continues. A spawned PM with repo access may complete small mechanical work itself \
            rather than dispatching another dev round — by design (PM-may-fix), not a defect.

            Pilot is the sibling mode on the SAME substrate: instead of Allnighter spawning \
            a PM model, YOUR live CLI session holds the PM seat. `alln pair pilot start` \
            parks a new relay `awaitingPM` (no clock — nothing advances until you say so); \
            `alln pair pilot handoff --relay <id> --verdict continue --handover-file <order.md>` \
            (or `--file <md>` with a RelayVerdict tail for scripted PM output) submits your \
            review, blocks through the dev turn, and prints the \
            dev's report verbatim — read it, write the next round, call `handoff` again. A \
            `continue` verdict still passes HandoverGate, but a block or an unparseable \
            verdict leaves the relay `awaitingPM` untouched rather than escalating — you're \
            right there to rephrase and resubmit. `pilot status`/`pilot watch` read the same \
            durable state a spawned relay uses; the Mac inbox shows a pilot relay exactly \
            like a spawned one.
            """,
            aliases: ["pm relay", "relay", "pair relay", "automate pm dev loop", "spec doc relay",
                      "pilot", "pair pilot", "pilot mode", "i am the pm", "drive from my session"],
            sections: [
                .init("verdict", "The only structure", "Everything the PM writes is free prose except one JSON tail: verdict continue/done/escalate. Missing or unparseable triggers one re-ask, then escalate — never a guess."),
                .init("gate", "Handover safety", "Every continue verdict's handover passes a danger scan before the dev seat ever sees it. Danger blocks and escalates; mere doubt does not block."),
                .init("ceilings", "Stopping", "`--until HH:MM`, `--max-rounds`, and a stagnation cap (repeated no-change rounds) are hard stops — the relay always ends on done, escalate, or a ceiling."),
                .init("resume", "Escalation is not failure", "An escalated relay is a real question for the founder, not an error. `alln pair relay-resume` injects the answer and the loop continues from there."),
                .init("pilot", "Pilot: you hold the PM seat", "`pair pilot start|handoff|status|watch` — no `--pm-worker` (there is no PM model) and no `--until` (no clock). `handoff` is the only mutation boundary: a parse failure or a gate block never escalates in Pilot, it just leaves the relay `awaitingPM` for you to resubmit. `done`/`escalate` verdicts settle the relay exactly like a spawned round."),
                .init("adopt", "Adopt: hand the SAME relay to a spawned PM (unattended)", "Pilot the first rounds yourself while context is hot, then `alln pair relay adopt --relay <id> --pm-worker <id>` converts a parked Pilot relay (`awaitingPM` or `escalated`) to a spawned PM relay and keeps going from the durable round log — same id, same rounds, same thread; the first spawned turn is told, once, that earlier rounds were externally piloted. `--max-rounds`/`--until` behave like a spawned run, and the round ceiling counts the piloted rounds too — an honest total, not a fresh budget. The reverse flip, `alln pair pilot adopt --relay <id>`, hands a parked spawned relay (escalated, or ceiling-stopped) back to Pilot — a plain state flip, no dispatch."),
            ],
            relatedCommandNames: [
                "pair relay", "pair relay-status", "pair relay-resume", "pair relay adopt", "project add", "project show",
                "pair pilot start", "pair pilot handoff", "pair pilot status", "pair pilot watch", "pair pilot adopt", "pair pilot scaffold-handover",
            ],
            schemaRefs: ["relayJSON"],
            errorRefs: [
                "RELAY_NOT_FOUND", "RELAY_INVALID_STATE", "RELAY_HANDOVER_UNSAFE", "PROJECT_NOT_FOUND",
                "RELAY_ROUND_IN_FLIGHT", "RELAY_NOT_AWAITING_PM", "RELAY_VERDICT_UNPARSEABLE",
                "EXECUTION_LANE_BUSY", "WRITE_SCOPE_VIOLATION", "STANDING_INVARIANT_FAILED",
            ],
            needsLiveCheck: true),

        HelpTopic(
            id: "panel", title: "Panel (blind jury)", audience: .both,
            summary: "Session-led blind jury on any target: Allnighter fans out read-only seats, stores structured findings, you synthesize and edit. Run Spec Review on specs, then chain into Pilot to build.",
            bodyMarkdown: """
            Panel is "I am always the lead; the seats are always a blind jury" — for any \
            target a session judges (a spec, a PR, an architecture call). Spec Review \
            is the hero recipe, not the product's name. \
            `alln panel start --doc <path> --project .` resolves a team roster (or \
            remembered/lane-default), pins a target content hash, scaffolds a focus brief, \
            and parks `awaitingPM`. `alln panel round --panel <id>` blocks through N blind \
            seats and returns structured findings verbatim (no material findings is valid). \
            Round 1 uses a built-in brief; round 2+ needs `--brief` with a rejection-carry \
            line. You refute and edit the target with your own hands. `--seats a,b` reruns \
            replace those seats on the SAME round (new attempt). `panel done` is declaration \
            only. Then chain: `alln pair pilot start --doc <same>`. Every seat is \
            isolated: claude/codex keep confirmed RO args on the real root; every other \
            driver runs against an ephemeral APFS clone (copy, not a worktree). No seat \
            is refused for lacking a RO mode.
            """,
            aliases: [
                "panel this", "blind jury", "spec review", "panel round", "panel start",
                "spec hardening", "jury", "alln panel",
            ],
            sections: [
                .init("roster", "Team catalog is the roster", "`--team <alias>` fuzzy-resolves a TeamPreset (unique→echoed, ambiguous→candidates with seat count). Zero-config uses remembered-else-lane-default. `--seat <alias>:<lens>` resolves the alias via PilotSeatResolver at start (real model id stored; never a raw alias) and echoes `isolation` per seat (`driverReadOnly` | `clone`)."),
                .init("rounds", "Blocking rounds + NDJSON", "`panel round` blocks; seats stream as they settle. Partial failures still settle. Built-in brief on round 1; focus brief required later."),
                .init("safety", "Read-only by mechanism", "Panels never take the mutating write lock. RO-enforcing drivers keep plan/sandbox args on the real root; other seats get an ephemeral clone under panels/<id>/clones/. PANEL_SEAT_NOT_ISOLATED means clone materialization failed, not “driver banned”."),
                .init("chain", "Harden then build", "After `panel done`, `alln pair pilot start --doc <same>` continues in the same cockpit."),
            ],
            relatedCommandNames: [
                "panel start", "panel round", "panel status", "panel watch", "panel scaffold-brief", "panel done",
                "pair pilot start",
            ],
            schemaRefs: ["panelJSON", "panelRoundJSON"],
            errorRefs: [
                "PANEL_NOT_FOUND", "PANEL_ROUND_IN_FLIGHT", "PANEL_SEAT_NOT_ISOLATED",
                "PANEL_TARGET_MISSING", "PANEL_NOT_AWAITING", "PROJECT_NOT_FOUND", "TEAM_NOT_FOUND",
            ],
            needsLiveCheck: true),

        HelpTopic(
            id: "teams_and_workers", title: "Teams, Workers & Skills", audience: .both,
            summary: "Teams are lane-scoped rosters of workers (a model + skill); manage built-ins and custom copies in the catalog.",
            bodyMarkdown: """
            A team is a lane-scoped roster of workers, each a model running a skill. \
            Built-in teams are immutable — duplicate one to edit the copy. Skills are the \
            reusable prompts workers run. List and inspect with `alln teams`, `alln skills`, \
            and `alln models`; the Default Team (Auto) is the no-pick route.
            """,
            aliases: ["teams", "workers", "skills", "roster", "catalog"],
            relatedCommandNames: ["teams", "teams show", "teams duplicate", "teams restore", "skills", "skills show", "models"],
            schemaRefs: ["teamCatalogJSON", "skillCatalogJSON", "modelListJSON"],
            errorRefs: ["TEAM_NOT_FOUND", "TEAM_BUILTIN_IMMUTABLE", "TEAM_RESTORE_UNSUPPORTED", "SKILL_NOT_FOUND"],
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
            tiers. Configure with `alln defaults`; read the live settings with \
            `alln defaults show`.
            """,
            aliases: ["auto", "default", "substitution", "substitutions", "tier", "tiers", "flagship", "balanced", "fast"],
            sections: [
                .init("substitution", "Healthy substitution", "OFF → Auto uses only the tier default and waits if it is down. ON → the first ready model on the tier, across CLIs. Never upgrades, never downgrades, never crosses tiers."),
            ],
            relatedCommandNames: ["defaults show", "defaults tier", "defaults assign", "defaults unassign", "defaults substitutions", "defaults reset"],
            schemaRefs: ["defaultSettingsJSON"],
            errorRefs: ["DEFAULTS_TIER_INVALID", "DEFAULTS_MODEL_UNKNOWN"],
            needsLiveCheck: false),

        HelpTopic(
            id: "pending", title: "Pending Work", audience: .both,
            summary: "Use Pending when work should be stored for later or cannot start now; `alln pending run` executes a due item.",
            bodyMarkdown: """
            Pending is for work the user wants saved for later, or that Allnighter cannot \
            start right now. Create a Pending item with `alln pending add`, then show the \
            user the Pending id and its blocked/wake state. `alln pending run` executes and \
            settles a due item. Pending is not a fake queue — it is durable save-for-later \
            with real wake facts.
            """,
            aliases: ["later", "save for later", "desk", "queue", "put this on codex's desk"],
            sections: [
                .init("when-to-use-pending", "When to use Pending", "Use Pending when the user wants work done later, or when Allnighter cannot start it right now."),
                .init("pending-vs-running", "Pending vs running a team", "Pending stores work for later; running a team starts work now after preflight."),
            ],
            relatedCommandNames: ["pending add", "pending list", "pending queue", "pending show", "pending run",
                                  "pending submit", "pending edit", "pending reorder", "pending cancel"],
            schemaRefs: ["pendingItemJSON", "pendingListJSON"],
            needsLiveCheck: false),

        HelpTopic(
            id: "projects_and_threads", title: "Projects & Threads", audience: .both,
            summary: "Projects bind a repo root; threads are the work conversations inside a project; `alln project workers` shows readiness.",
            bodyMarkdown: """
            A project binds a local repo root. Work threads are the conversations bound to a \
            project. List projects with `alln project list`, read one with `alln project show`, \
            generate a context packet with `alln project context`, and check cached \
            per-project worker readiness with `alln project workers`. Threads carry the \
            back-and-forth and the runs (`alln thread send` / `alln thread get`).
            """,
            aliases: ["project", "repo", "thread", "threads", "conversation"],
            relatedCommandNames: ["project list", "project show", "project context", "project workers",
                                  "thread send", "thread get", "thread rename", "stalled list"],
            schemaRefs: ["projectJSON", "projectListJSON", "projectContextJSON", "threadStatus"],
            errorRefs: ["PROJECT_NOT_FOUND"],
            needsLiveCheck: false),

        HelpTopic(
            id: "setup_and_auth", title: "Setup & Auth", audience: .both,
            summary: "Install/sign in to your CLIs; doctor reports the exact failing check and the human action to fix it.",
            bodyMarkdown: """
            Allnighter uses your existing CLI subscriptions and logins — never API keys. If a \
            source is blocked, run `alln doctor` (optionally for one agent) to see the exact \
            failing check, then `alln doctor explain` for the recovery text. Auth is live state: the \
            help bundle cannot know it — call doctor. Cursor gotcha: headless cursor-agent \
            respects `permissions.allow` in `~/.cursor/cli-config.json` even under `--trust`; \
            denied shell tools fail silently. Widen the global allowlist (e.g. `Shell(git)`, \
            `Shell(python3)`, or `Shell(**)`), or add a repo-root `.cursor/cli.json` with \
            the same `permissions.allow` / `permissions.deny` schema — project overrides \
            merge at cursor-agent process start (next headless turn). `alln doctor` reports \
            this as `source.cursor_agent.shellAllowlist` (Allnighter never writes vendor config).
            """,
            aliases: ["auth", "login", "sign in", "blocked", "why can't allnighter run codex", "api key"],
            sections: [
                .init("source-auth-expired", "Source auth expired", "Re-authenticate the named source via its own login flow, then re-probe with `alln doctor`."),
            ],
            relatedCommandNames: ["doctor", "doctor explain"],
            schemaRefs: ["doctorResult"],
            errorRefs: ["SOURCE_AUTH_EXPIRED", "SOURCE_NOT_FOUND", "SOURCE_KEYCHAIN_UNAVAILABLE"],
            needsLiveCheck: true),

        HelpTopic(
            id: "current_setup", title: "Current Setup", audience: .both,
            summary: "What can THIS install do right now? Call `alln team hello` (or `alln doctor`) — this is live state, not guide truth.",
            bodyMarkdown: """
            To answer "what can my install do right now?", call `alln team hello` for a compact \
            readiness snapshot, or `alln doctor` for the full per-source report. The help \
            bundle describes product behavior; it does not know this machine's live state.
            """,
            aliases: ["can it run", "ready", "readiness", "what can it do now", "status"],
            relatedCommandNames: ["team hello", "doctor", "show"],
            needsLiveCheck: true),

        HelpTopic(
            id: "results_and_history", title: "Results & History", audience: .both,
            summary: "Inspect what ran: `alln history` lists runs; `alln show` / `alln spec` / `alln floor show` inspect one run.",
            bodyMarkdown: """
            Runs are durable. `alln history` lists past runs; `alln show` returns the summary \
            packet, `alln spec` the full spec, and `alln floor show` the inspectable floor for \
            one run. Results are runtime artifacts, not help docs.
            """,
            aliases: ["history", "results", "what ran", "floor", "packet"],
            relatedCommandNames: ["history", "show", "spec", "floor show"],
            schemaRefs: ["floorRun", "historyJSON", "specResult"],
            errorRefs: ["RUN_NOT_FOUND"],
            needsLiveCheck: false),

        HelpTopic(
            id: "errors", title: "Errors & Recovery", audience: .agent,
            summary: "Every Allnighter error has a recovery ladder; call `alln doctor explain` for the exact action and whether it's retryable.",
            bodyMarkdown: """
            Allnighter errors are typed with a recovery ladder. After a failed command, call \
            `alln doctor explain` with the code to get the agent action, whether it requires a human, \
            and whether it is retryable. Do not guess recovery from the message text.

            For automated bug-fix rounds (Bug Hunt → gate → one bounded fix attempt), see \
            `alln help get auto_fix` (`alln run --try-fix`).
            """,
            aliases: ["error", "failed", "recovery", "retry"],
            relatedCommandNames: ["doctor explain", "docs"],
            schemaRefs: ["errorEnvelope"],
            errorRefs: ["CLI_USAGE_ERROR", "WORKER_FAILED", "TEAM_RUN_FAILED"],
            needsLiveCheck: false),

        HelpTopic(
            id: "auto_fix", title: "Auto Fix (Try Fix)", audience: .both,
            summary: "`alln run --try-fix` runs Bug Hunt diagnosis, a danger-not-doubt gate, then ONE bounded fix attempt.",
            bodyMarkdown: """
            Auto Fix is the elimination loop for repo bugs: a read-only Bug Hunt diagnosis \
            writes a typed fix packet, the gate blocks on danger (credentials, deletion, deploy…) \
            not doubt, and — when allowed — exactly one mutating fix attempt runs. Prefer it over \
            a plain team run when you have a concrete symptom and want one narrowed fix round, not \
            open-ended editing.

            Exact command (from the contract example `try_fix_bug`):
            `alln run "<symptom>" --project <id> --team code_bug_hunt --try-fix --executor build_slice --json`

            For open exploration or multi-step feature work, use a normal `alln run` or `alln team` \
            instead. If the gate blocks, read the reason — danger requires human resolution; low \
            confidence alone does not block.
            """,
            aliases: ["fix a bug", "fix a bug in my repo", "try fix", "auto fix", "bug fix", "try-fix", "auto-fix", "fix bug"],
            sections: [
                .init("chain", "The chain", "Bug Hunt (read-only) → danger-not-doubt gate → ONE bounded fix attempt (mutating)."),
                .init("gate", "Danger blocks, doubt does not", "The gate refuses credentials, mass deletion, deploys, and packets without an actionable hypothesis — never blocks merely because confidence is low."),
                .init("vs-run", "When to use it", "Use Auto Fix for a concrete bug symptom you want one fix round on. Use a plain `alln run` or team dispatch for open work."),
            ],
            relatedCommandNames: ["run"],
            errorRefs: ["TRY_FIX_PACKET_MISSING", "TRY_FIX_PACKET_UNSAFE", "TRY_FIX_EXECUTOR_INVALID"],
            needsLiveCheck: false),

        HelpTopic(
            id: "schemas", title: "Schemas & Contract", audience: .agent,
            summary: "Exact fields/enums come from the generated contract: `alln spec` for a run packet, `alln docs --schema` for shapes.",
            bodyMarkdown: """
            Never guess Allnighter's field names or enum values. The generated contract is the \
            source: `alln spec` returns a run's full packet, and `alln docs --schema` prints the \
            JSON schemas. One schema by name: `alln help get --ref alln://schema/<name>`.
            """,
            aliases: ["schema", "fields", "json shape", "enum values", "contract"],
            relatedCommandNames: ["docs", "spec", "export"],
            schemaRefs: ["contractDoc"],
            needsLiveCheck: false),

        recipesHelpTopic,
    ]

    /// ONB-S02a: intent-titled recipe cards from `RecipeCatalog` (Bundle.module Recipes/).
    /// Sections are one card each so `alln help get recipes --format md` (or JSON) yields
    /// full paste-ready markdown without a new top-level CLI verb.
    private static let recipesHelpTopic: HelpTopic = {
        let recipes = RecipeCatalog.list()
        let listing = recipes.map { "- `\($0.id)` — \($0.title)" }.joined(separator: "\n")
        return HelpTopic(
            id: "recipes",
            title: "Recipes (Use from your CLI)",
            audience: .both,
            summary: "Intent-titled recipe cards: list via `alln bootstrap --json` → `recipes[]`, full text via `alln help get recipes --format md`.",
            bodyMarkdown: """
            These cards are the v1 SSOT for human/agent "how do I…?" prompts — titled by \
            user intent, not product nouns. Each card carries example utterances, the \
            teaching snippet, and copy-paste-ready commands.

            Discovery without the Mac app:
            1. `alln bootstrap --json` → `recipes` (id + title) and `recipesHelp`
            2. `alln help get recipes --format md` (or `--json`) for full card bodies
            3. `alln help search \"recipe\"` also routes here

            Shipped cards:

            \(listing.isEmpty ? "- _(no recipes bundled — rebuild AllnighterCore)_" : listing)
            """,
            aliases: [
                "recipe", "recipes", "use from your cli", "prompt cards", "example prompts",
                "onboarding recipes", "intent recipes",
            ],
            sections: recipes.map { HelpTopic.Section($0.id, $0.title, $0.markdown) },
            relatedCommandNames: [
                "bootstrap", "help get", "help search", "team hello",
                "pair pilot start", "panel start", "pair relay", "run",
                "team status", "team result", "team cancel",
            ],
            needsLiveCheck: false
        )
    }()

    /// Search/alias redirects: a term (often retired vocabulary) → canonical topic id.
    /// Catalog-derived terms (ASF-S03) are seeded first; authored topic aliases win
    /// on collision so hand-taught redirects stay authoritative.
    public static let aliasRedirects: [String: String] = {
        var map = HelpDiscoveryIndex.catalogAliasRedirects()
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
