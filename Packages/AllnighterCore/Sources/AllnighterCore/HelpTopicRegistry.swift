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
    /// route to a live command — `alln menu` / `alln doctor` — rather than pretend to know).
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
            summary: "Ensure `alln` is on your PATH, then check readiness with `alln menu --json` or `alln doctor`.",
            bodyMarkdown: """
            Step zero: make sure `alln` resolves on your PATH. Cold install (no `alln` \
            anywhere): `\(ReleaseChannel.installCommand)`. PATH repair only (binary exists \
            but plain `alln` does not resolve): `alln install-cli` (or invoke the built binary \
            by absolute path and follow its install step). Then check what your machine can \
            do with `alln menu --json` or `alln doctor`. Updates appear on `alln menu --json` \
            (`update` field) and use the same one-liner.

            Allnighter turns the AI CLIs you already have (Claude Code, Codex, Cursor Agent, \
            Grok, Antigravity) into one team that works in a repo. A default run sends \
            your message to the Default model (Auto) in the project root. Pick a named \
            team when you want a multi-agent pass.

            After install, read `alln menu --json`. If `benchTally.nextAction` is set \
            (headline `neverScanned`), run that command once — usually `alln detect` — \
            before spending quota. Never treat an empty probe cache as "0 of N ready."

            Other agents: run `alln bootstrap` for a paste-ready context snippet that teaches \
            the live-menu reflex (`alln menu --json`) in one paste (no MCP server, no config file edits).
            """,
            aliases: ["getting started", "first run", "what is allnighter",
                      "no alln", "get alln", "curl", "PATH", "update", "upgrade"],
            relatedCommandNames: ["install-cli", "run", "doctor", "bootstrap", "menu", "detect"],
            needsLiveCheck: false),

        HelpTopic(
            id: "bootstrap", title: "Bootstrap (agent activation)", audience: .agent,
            summary: "`alln bootstrap [--host claude|cursor|codex|generic|hermes|openclaw] [--json]` prints a paste-ready context snippet — no MCP server, no config file edits.",
            bodyMarkdown: """
            Step zero: ensure `alln` is on PATH. Cold install (no `alln` anywhere): \
            `\(ReleaseChannel.installCommand)`. PATH repair only (binary exists but plain \
            `alln` does not resolve): `alln install-cli`. \
            Allnighter has no MCP server and no daemon to install — the CLI is the whole \
            agent surface, no humans in the loop. `alln bootstrap` PRINTS (never edits \
            files) a short, paste-ready instruction block for a host agent's own context: \
            `~/.claude/CLAUDE.md` for Claude, `~/.cursor/rules/allnighter.mdc` for Cursor, \
            project AGENTS.md for Codex (no global Codex path in v1), host system prompt / \
            tools instructions (print-only) for Hermes and OpenClaw, or a host-neutral \
            block when `--host` is omitted. The block teaches the four-rule live-menu \
            reflex only: read `alln menu --json` before first use; choose from \
            useWhen/dontUseWhen with canonical ids; run the validation template before \
            unfamiliar agent-starting actions; re-read the live menu in a new session \
            and never trust a pasted catalog. It does not embed models, teams, recipes, \
            or command rows. Marker-delimited with schema version + content hash so \
            `alln doctor` can report teaching.installed. \
            `--json` returns `{ host, pasteTarget, snippet, binaryPath, onPath, recipes, recipesHelp }` \
            so an agent can install itself and discover intent-titled recipe cards \
            (`recipes[]` is id+title only; full markdown via `recipesHelp`).

            When unsure which verb to use (`run` vs `thread send` vs `pending`), \
            call `alln menu --json` or `alln help search "<intent>" --json` for matching \
            menu cards (no recommended winner).

            To rebuild this CLI from an Allnighter checkout: `swift build -c release --product alln`, \
            then `alln install-cli` (symlinks the workspace release build onto PATH). Confirm \
            freshness with `alln version --json` (binaryVersion plus gitSha / buildTime).
            """,
            aliases: ["install", "setup", "connect agent", "activation", "add to agent",
                     "wire up allnighter", "onboard agent", "mcp install", "mcp", "install mcp",
                     "rebuild", "self build", "fresh binary", "build alln",
                     "hermes", "openclaw"],
            relatedCommandNames: ["install-cli", "bootstrap", "help get", "help search", "menu", "doctor", "version", "detect"],
            schemaRefs: [],
            needsLiveCheck: false),

        HelpTopic(
            id: "tool_selection", title: "Command Selection", audience: .agent,
            summary: "When unsure, start with `alln menu --json`. Then pick foreground `run`, `thread send`, or pending by intent.",
            bodyMarkdown: """
            When unsure which command to use, call `alln menu --json` \
            first — choose from useWhen/dontUseWhen and pass canonical ids only. Do not invent flags. \
            If `benchTally.nextAction` is present, run it once before any spend (find CLIs).

            Verb tree:
            - `alln run` — single agent / chat / named-model ask in the project root \
            (Default Team). One message; optional `--model` or `--team`. Mutating by default; queues FIFO.
            - `alln run --read-only --model <id>` — parallel feedback: same chat, no write-lock queue \
            (lock policy only — not a team, not FS isolation). Do **not** use `--no-commit` for this.
            - `alln run --team <id>` — multi-seat team in the project root.
            - `alln run` — foreground Team run in the registered repository by default; \
            with `--no-wait --json`, run the one returned `nextAction.command` once \
            (`alln show <id> --stream`) to observe mid-run and receive the terminal pmTurn.
            - `alln thread send` — continue an existing work thread (not a fresh one-shot).
            - Pending — defer work with `alln pending add`; run later with `alln pending run`.

            For a quick capability check call `alln menu --json`. For full run packets use \
            `alln spec`. Do not answer Allnighter product questions from training data when \
            these commands are available.
            """,
            aliases: ["which tool", "what tool should i use", "routing", "help",
                      "which command", "which command should i use", "what command",
                      "run vs team", "thread send", "command selection", "first contact",
                      "when to use run", "when to use team",
                      "ask a model", "which model", "resolve intent", "route", "resolve",
                      "intent", "ask sonnet", "which model",
                      "read-only", "readonly", "no commit", "write lock", "queue",
                      "parallel", "feedback", "parallel feedback"],
            sections: [
                .init("when-unsure", "When unsure", "Call `alln menu --json` before picking a verb."),
                .init("run", "alln run", "Single agent / chat / named-model ask in the project root (mutating; queues)."),
                .init("read-only", "alln run --read-only --model", "Parallel feedback without the mutator queue. `--no-commit` does not skip the queue."),
                .init("run-team", "alln run --team", "Run the selected Team in the registered repository."),
                .init("thread", "alln thread send", "Continue a work thread with `alln thread send`."),
                .init("pending", "Pending", "Defer with `alln pending add`; execute later with `alln pending run`."),
            ],
            relatedCommandNames: ["help search", "help get", "menu", "run",
                                  "show", "thread send",
                                  "pending add", "pending run", "spec", "detect"],
            schemaRefs: ["teamStartResponse"],
            needsLiveCheck: true),

        HelpTopic(
            id: "team_run_loop", title: "Running a Team", audience: .both,
            summary: "Send work to a Team in its registered repository: dry-run, then foreground run.",
            bodyMarkdown: """
            Sending work to a Team is dry-run → foreground run.             `alln run --dry-run` validates \
            the lineup before spending quota. Research Teams are observational in the real repository; \
            execution Teams resolve to one selected mutating agent. For one-off crew staffing on a \
            built-in judgment team, repeat `--seat <model_id>` in crew order with `--team` — no catalog \
            write. Durable custom rosters still use `teams duplicate` → `teams definition` → `teams edit`. \
            Inspect a finished run with \
            `alln show`, `alln spec`, or `alln floor show`.

            Dry-run `writePolicy` / `effects.repoWrite` report write *permission*, not prompt \
            intent. Research Teams use the canonical repository without permission flags or copied \
            bytes. A mutating run's observed writes appear as terminal `repoDelta`; a research \
            (read-only) run carries a bounded `researchGitObservation` — if it changed the repo's \
            Git state, `changed` is true (a surfaced research-write violation). Allnighter observes \
            only; it never resets or repairs your files.

            Observed timing on the settled packet: per-agent `queueMs` (request→spawn), \
            `ttftMs` (spawn→first token), `durationMs` (spawn→exit), plus terminal \
            `outcome.timing.wallMs` (createdAt→latest finishedAt). Null means unreported. \
            These are clock boundaries only — not forecasts, and not an invented orchestration tax.

            `--stream` emits NDJSON (one JSON object per stdout line). A stream ends with \
            exactly one of `teamRunCompleted`, `teamRunFailed`, or `error`. On `run`, \
            `--stream` is mutually exclusive with `--json` and `--dry-run`.

            Canonical answer text is `TeamRunJSON.answer` (status, markdown, source) — prefer \
            that field over hunting `answers` or plan markdown.

            `alln run` does not expose `--temperature` or `--max-tokens`. Alln drives \
            subscription CLIs; use `--effort`, `--model`, and each driver's supported controls.
            """,
            aliases: ["send to team", "fan out", "delegate", "send this to a team", "bug hunt",
                      "read-only", "readonly", "no commit", "write lock", "queue", "parallel", "feedback",
                      "tokens", "token usage", "usage", "duration", "pilot status", "observed usage",
                      "custom seats", "staff models once", "one-off team", "temporary team",
                      // Spec review is a Team run like any other. These phrases used to
                      // resolve to the deleted `panel` surface; they must keep landing on
                      // the one primitive that actually performs the work.
                      "spec review", "spec hardening", "blind jury", "jury", "panel", "panel this",
                      "read only", "readonly", "write policy", "mutating",
                      "timing", "queueMs", "ttftMs", "durationMs", "wallMs", "latency",
                      "stream", "ndjson", "temperature", "max tokens", "max-tokens",
                      "answer field", "canonical answer",
                      "no-wait", "background run", "detach", "idempotency", "retry safely",
                      // CHS-S02: multiple crew seats on one spawn-gated CLI serialize, never
                      // drop — findable by the terms an agent actually types.
                      "spawn gate", "same CLI", "same cli", "serialize seats", "serialized seats",
                      "concurrent seats", "concurrent spawn", "concurrent spawns", "gated driver",
                      "seat_driver_serialized", "cursor_agent", "understaffed", "spawn gate timed out"],
            sections: [
                .init("preflight", "Dry-run first", "Call `alln run --dry-run` before a foreground run so a bad lineup fails before quota is spent."),
                .init("explicit-seats", "One-off crew staffing", "`alln run --team <built-in> --seat <model_id> --seat …` staffs crew seats in order without writing the catalog. Lead and scout stay on the Team. Mutating teams still use `--model`."),
                .init("spawn-gate", "Same-CLI seats serialize, never drop", "`cursor_agent`, `opencode`, and `agy` allow only one concurrent spawn each — a real process/config race, not a policy choice. Two or more crew seats on the SAME gated CLI (`--seat` or a wide capability-staffed Team) still both run; they serialize FIFO instead of dropping. Dry-run names the shape up front: `warnings` carries a flat `seat_driver_serialized: <driverId> allows <n> concurrent spawn; <model ids> will run one after another` string, and `canStart` stays true — this never refuses a same-CLI crew. Parallel-safe drivers (claude, codex, grok — no declared limit) never warn."),
                .init("write-policy", "Observation vs outcome", "`effects.repoWrite` means the resolved invocation may write. Research Teams are observational; terminal `repoDelta` reports whether a mutating run did write, and `researchGitObservation.changed` flags a read-only run that unexpectedly changed Git state (files are never reset)."),
                .init("timing", "Observed timing", "`queueMs` / `ttftMs` / `durationMs` / `outcome.timing.wallMs` are recorded clocks. Null means unreported. Do not invent an orchestration tax by subtracting duration from wall."),
                .init("stream", "NDJSON stream", "`--stream` is one JSON object per stdout line and ends with `teamRunCompleted`, `teamRunFailed`, or `error`. Mutually exclusive with `--json` / `--dry-run` on `run`."),
                .init("vendor-controls", "Vendor CLI controls", "No `--temperature` / `--max-tokens` on `alln run`. Use `--effort`, `--model`, and the selected subscription CLI's own supported flags."),
                .init("delivery", "Terminal delivery", "Use one `alln show <run-id> --stream` call to reattach and receive the terminal pmTurn; do not poll or use run resume for terminal delivery. Killing the observer never kills the run; re-running the same command reattaches."),
                .init("no-wait", "Detached runs", "`alln run … --no-wait --json` returns one `nextAction.command` = `alln show <id> --stream`. Do other work, then run that command once — it observes the middle and delivers the terminal pmTurn. `--idempotency-key` is the explicit, deliberate retry-safety contract — it is opt-in, not derived, so two intentionally identical runs are never silently collapsed into one."),
                .init("read-only", "Parallel feedback", "Doc/spec feedback without competing for the mutator: `alln run --read-only --model <id>`. Build work uses default mutating `alln run`. `--no-commit` is commit instruction only — it still takes the write lock and queues FIFO."),
                .init("usage", "Observed tokens & duration", "Live `pilot status` / `relay-status` show elapsed + observed tokens (or CLI blame when unreported). Terminal receipts and TeamRunJSON answers carry per-seat duration and usage when the driver reported it — never invented totals."),
            ],
            relatedCommandNames: ["run", "show", "team cancel", "team reconcile", "floor show"],
            schemaRefs: ["teamStartResponse", "teamRunJSON"],
            needsLiveCheck: true),

        HelpTopic(
            id: "loop", title: "Loop", audience: .both,
            summary: "Mechanizes the founder's PM↔dev copy-paste loop: a PM reviews the repo and writes an order, a dev seat builds and commits, round after round, until done/escalate/a ceiling.",
            bodyMarkdown: """
            `alln loop start "<what you want done>"` starts a durable PM↔dev loop. The brief \
            is the only required input — both seats default by tier (`--spec <path>` is a \
            shortcut for pointing at a doc instead of restating it, not the shape of the \
            feature). Each round: the PM re-reads the brief/spec and the actual commit range, \
            writes free-form review plus an order, and ends with one small verdict block — \
            continue (with an order for the dev), done (closing summary), or escalate (a \
            specific question for the founder). A safety scan runs over every order before it \
            reaches the dev seat; a danger instruction (leaking credentials, destructive git, \
            signing, sandbox/TCC changes, mass deletion) blocks dispatch and escalates instead. \
            The dev seat builds, commits through its own tooling, and writes a delivery report \
            that becomes the next round's review input. The loop stops only on done, escalate, \
            or a ceiling (`--until`, `--max-rounds`, or repeated no-progress rounds) — never by \
            inference. A PM with repo access may complete small mechanical work itself rather \
            than dispatching another dev round — by design (PM-may-fix), not a defect.

            The PM chair is an **occupant**, not a mode: `--pm caller` means YOUR live CLI \
            session holds the seat and reviews every round yourself; `--pm <agent-id>` (or the \
            default) spawns that agent as PM and runs unattended. `loop pm <loop-id> \
            <occupant>` reassigns the chair on a parked loop (`awaitingPM` or `escalated`) — \
            same id, same rounds, same thread; the first turn under the new occupant is told, \
            once, that earlier rounds were held by someone else. `--max-rounds`/`--until` \
            behave the same either way, and the round ceiling counts every round already on \
            the log — an honest total, not a fresh budget.

            Every operation is defined against the loop's **status**, never against who holds \
            the chair. `loop step <loop-id> "<order>"` (or `--done <summary>`) submits the \
            next PM decision and is accepted only in status `awaitingPM` — whether the caller \
            or a spawned agent holds the seat, the check and the error are the same. After \
            `loop step`, wait with `loop wait <loop-id>` or `loop status <loop-id> --wait-for parked` \
            to receive the pmTurn; do not re-dispatch while status is `running`. For unattended \
            dispatch, `--no-wait` applies to `loop start`, `loop resume`, and `loop pm` — NOT to \
            `loop step`. `--no-wait` still runs HandoverGate (and other non-mutating refusals) in \
            the foreground — a gate block fails closed with `RELAY_HANDOVER_UNSAFE`, never a \
            silent `dispatched` ack. `loop wait <loop-id>` is an optional disposable \
            waiter — its death is not a failed round. If the round owner died (orphan), inspect \
            status/repo before any new step. A `continue` verdict still passes HandoverGate, but \
            a block or an unparseable verdict leaves the loop `awaitingPM` untouched rather than \
            escalating — you're right there to rephrase and resubmit.
            """,
            aliases: ["pm relay", "relay", "pair relay", "automate pm dev loop", "spec doc relay",
                      "pilot", "pair pilot", "pilot mode", "i am the pm", "drive from my session",
                      "notify me", "notification", "tell me when it's done", "background notifier",
                      "no-wait", "background", "detached", "my session died", "survive",
                      "delivery loop", "kickoff", "local execution", "ollama loop",
                      "frontier plans local executes"],
            sections: [
                .init("verdict", "The only structure", "Everything the PM writes is free prose except one JSON tail: verdict continue/done/escalate. Missing or unparseable triggers one re-ask, then escalate — never a guess."),
                .init("gate", "Handover safety", "Every continue verdict's order passes a danger scan before the dev seat ever sees it. Danger blocks and escalates; mere doubt does not block."),
                .init("ceilings", "Stopping", "`--until HH:MM`, `--max-rounds`, and a stagnation cap (repeated no-change rounds) are hard stops — the loop always ends on done, escalate, or a ceiling."),
                .init("resume", "Escalation is not failure", "An escalated loop is a real question for the founder, not an error. `loop resume <loop-id> --answer <text>` injects the answer and the loop continues from there."),
                .init("stop", "Founder stop of a Loop", "`loop stop <loop-id>` abandons the loop: identity-checked teardown, durable `stopped` with reason founder stopped, and a PM Turn on transition. Idempotent on already done/stopped. Not ownership kill."),
                .init("local-dev", "Local execution seat", "`alln loop start \"…\" --pm <frontier-id> --dev <local-ollama-id>`: a frontier seat plans, a local Ollama-backed seat executes, under the same per-root write lock. An explicit `--pm` pin of a local Ollama-backed seat is allowed: Allnighter discloses local provenance and the served context window if known, once, then proceeds. Local readiness is Available or Unavailable per seat (reachable + that tag pulled) — not a capacity meter, and not Idle/Busy. Advertised tools capability is lie-prone; a G2 harness mutate does not predict a G3 alln-path pass. Failure is the common case. Allnighter stamps `roundLog.executionOutcome` from worker status, repo delta, and proofs — never from the seat's report. A local seat that claims \"ready for review\" while proofs fail (or the tree did not move) is `failed` for the lead to act on, not a silent or false success."),
                .init("pm", "Reassign the PM chair mid-loop", "Hold the first rounds yourself while context is hot, then `loop pm <loop-id> <agent-id>` converts a parked caller-held loop (`awaitingPM` or `escalated`) to a spawned PM and keeps going from the durable round log — same id, same rounds, same thread. The reverse, `loop pm <loop-id> caller`, hands a parked spawned loop (escalated, or ceiling-stopped) back to the caller — a plain state flip, no dispatch."),
                .init("golden", "Golden paths (day one)", "Attended: `alln menu --json` → `alln run` → `alln artifact show`. Unattended: `alln loop start \"<what you want done>\"` → `loop status <loop-id> --json` (or wait for a macOS notification). Status reads reconcile dead owners automatically — no manual `team reconcile` on the happy path. Default `alln ps` shows the alive floor; `alln ps --all` is history."),
                .init("notify", "You do not have to watch", "Continuity is the supervised LaunchAgent (`alln install-cli` / `alln serve enable`), not a silent spawn from loop dispatch. When a round lands or escalates — even with the Mac app closed and the CLI session that dispatched it long gone — a local notification fires: \"Loop needs an answer\" on escalation, or the normal completion notice when it settles. Stream silence on a running loop also notifies when agent output stalls. Neither you nor the human has to poll `loop status` or build a watcher for this; `alln serve` already knows. If serve is unhealthy, `alln serve repair` converges the supervised agent."),
                .init("survive", "The round outlives your session", "`--no-wait` on `loop start` / `loop resume` / `loop pm` dispatches, then returns delivery.path=wait and one exact `loop status --wait-for parked|terminal` command. A killed caller is not a killed loop: the round keeps advancing under its own process. A second dispatch against an already-active loop is refused with `RELAY_ALREADY_ACTIVE`, not raced onto the same doc."),
            ],
            relatedCommandNames: ["loop start", "project add", "project show"],
            schemaRefs: ["relayJSON"],
            errorRefs: [
                "RELAY_NOT_FOUND", "RELAY_INVALID_STATE", "RELAY_HANDOVER_UNSAFE", "PROJECT_NOT_FOUND",
                "RELAY_ROUND_IN_FLIGHT", "RELAY_STOP_FAILED", "RELAY_NOT_AWAITING_PM", "RELAY_VERDICT_UNPARSEABLE",
                "EXECUTION_LANE_BUSY", "WRITE_SCOPE_VIOLATION", "STANDING_INVARIANT_FAILED",
                "RELAY_ALREADY_ACTIVE",
            ],
            needsLiveCheck: true),

        HelpTopic(
            id: "sweep", title: "Sweep", audience: .both,
            summary: "One order over N targets, checkpointed and resumable. Every target ends done, failed, or not-attempted — never skipped and reported done.",
            bodyMarkdown: """
            `alln sweep start "<order>" --target <id> --target <id>` applies one order \
            across many targets under the existing run model: each target is an `alln run`, \
            journaled, under the per-root write lock. One mutating worker per root still \
            holds. The feature is resumability — 400 targets, the run dies at 250, \
            `alln sweep resume <id>` continues at 250 and does not redo the first 250 or skip \
            the rest.

            Honesty is the point. Every target is `done`, `failed`, or `not-attempted`. \
            `complete` is false while any target is `not-attempted`. A sweep that skips \
            targets and reports done is a lie. Read `alln sweep status <id> --json` and the \
            one sweep artifact; both list every target's outcome.
            """,
            aliases: [
                "batch", "bulk", "queue", "checkpoint", "resume sweep", "many files",
                "not-attempted", "sweep resume",
            ],
            sections: [
                .init("resume", "Kill then resume", "If the owner dies mid-sweep, remaining targets stay not-attempted. Resume the same sweep id. Do not start a second sweep and call the first done."),
                .init("artifact", "One artifact", "Each checkpoint writes one artifact naming every target and its outcome. It is not complete while not-attempted rows remain."),
                .init("lock", "Same write lock", "Sweep does not invent a parallel run model. Target runs take the per-root write lock one at a time."),
            ],
            relatedCommandNames: ["sweep start", "sweep resume", "sweep status", "run", "show"],
            schemaRefs: ["sweepJSON"],
            errorRefs: [
                "SWEEP_NOT_FOUND", "SWEEP_NO_TARGETS", "SWEEP_DUPLICATE_TARGETS",
                "SWEEP_INVALID_STATE", "SWEEP_INCOMPLETE",
            ],
            needsLiveCheck: false),

        HelpTopic(
            id: "teams_agents_and_skills", title: "Teams, Agents & Skills", audience: .both,
            summary: "Teams are lane-scoped rosters of agents (model + skill); skills are shared instruction profiles.",
            bodyMarkdown: """
            A team is a lane-scoped roster of agents — each agent is a model wearing a skill. \
            Built-in teams and skills edit in place at the same id — use \
            `teams restore` / `skills restore` to drop overrides and reveal shipped seeds. \
            Customize a shipped team with `teams duplicate` → `teams definition` → \
            `teams edit` when you need a separate id. For a one-off crew lineup on a \
            built-in judgment team, use `alln run --team <id> --seat <model_id> …` instead of \
            duplicating. Create a novel manifest with \
            `teams definition` (or a hand-authored TeamPreset) → `teams new`. \
            Skills are shared `skill.md` bodies — edit with `alln skills edit <id>` or \
            **Settings → Teams → Edit skill** (no separate Skills settings page). \
            Editing an existing skill updates every team that references that id; \
            `skills duplicate` mints an explicit new id. Pin a single model on a run with \
            `alln run --model <model_id>`. List and inspect with \
            `alln teams`, `alln skills`, and `alln models`; purge orphans with \
            `alln skills gc`. The Default Team (Auto) is the no-pick route. Looking for a \
            model or vendor by natural-language name? Use `alln menu --json` \
            — do not stop at a models/teams list miss.
            """,
            aliases: [
                "teams", "agents", "skills", "roster", "catalog", "which model", "ask a model",
                "create team", "custom team",
                "edit skill", "shared skill", "restore skill", "skill.md",
                // ADP-S04: task-verb phrasing a caller actually types for team authoring
                // must outrank the generic "team" overlap with team_run_loop (running a
                // team), which otherwise wins ties on every bare "team" query.
                "create a team", "make a team", "make a custom team", "new team",
                "customize a team", "build a team", "build a custom team",
            ],
            relatedCommandNames: ["teams", "teams show", "teams duplicate", "teams new", "teams edit", "teams restore", "skills", "skills show", "skills edit", "skills restore", "skills gc", "models", "drivers", "menu"],
            schemaRefs: ["teamCatalogJSON", "skillCatalogJSON", "modelListJSON", "driverListJSON"],
            errorRefs: ["TEAM_NOT_FOUND", "TEAM_RESTORE_UNSUPPORTED", "TEAM_ID_COLLISION", "TEAM_INVALID", "CATALOG_ID_INVALID", "SKILL_NOT_FOUND", "SKILL_RESTORE_UNSUPPORTED", "SKILL_INVALID"],
            needsLiveCheck: false),

        HelpTopic(
            id: "capacity", title: "Capacity & Quota", audience: .both,
            summary: "`alln capacity` is the seven-row human table agents must paste verbatim when the user asks to print/show/display capacity; `--json` only on explicit JSON/machine request.",
            bodyMarkdown: """
            `alln capacity` is a **trust-critical** seven-row snapshot. Bare capacity is \
            instant and **spawns nothing**: Codex and Grok read structured disk/log truth; \
            Claude / Cursor / Kimi / Antigravity show last-known (with honest age) or \
            unknown. `alln capacity --refresh` live-acquires — disk re-read for Codex/Grok, \
            one PTY adapter per PTY-only seat (Claude, Cursor, Kimi, Antigravity). Progress \
            prints on **stderr**; the complete table/JSON is on **stdout** (TTY or piped). \
            `alln capacity --refresh --source <id>` targets one seat; every other row still \
            renders — the strip is never truncated. Disk-only ids with `--source` re-read \
            disk only (no spawn). `--source` without `--refresh` is a usage error. \
            A failed refresh keeps the failure reason for that seat — it does **not** paint \
            stale history as live. Capacity is **vendor-printed when acquired** — Allnighter \
            does not invent percentages. `unknown` means the seat was not sampled, the probe \
            timed out / failed, or the parser could not read the capture. Missing data never \
            blocks (exit 0) and never fabricates 0%.

            Per-run token usage on team receipts is a **different system** — do not confuse \
            receipt token counts with the capacity strip.

            ## Agent print contract (user-visible)

            When the user asks to **print / show / display** capacity (`alln capacity`), \
            the agent must run bare `alln capacity` and include the **COMPLETE** \
            human-readable stdout table **verbatim** in its final response. Never replace \
            the table with a summary, selected highlights, JSON, or \"shown above\" — many \
            hosts collapse shell tool output so the founder never sees the table unless the \
            agent pastes it. A summary may follow **only after** the full table. Use \
            `alln capacity --json` **only** when the user explicitly requests JSON / \
            machine-readable output, or a program needs the schema (contractVersion + \
            per-source rows with weekly/5-hour remaining, reset clocks, and age).
            """,
            aliases: [
                "capacity", "quota", "usage", "weekly limit", "5 hour", "5h",
                "reset", "headroom", "rate limit", "remaining",
                "print capacity", "show capacity", "display capacity",
            ],
            relatedCommandNames: ["capacity", "drivers", "doctor", "models"],
            schemaRefs: ["capacityStripJSON"],
            needsLiveCheck: true),

        HelpTopic(
            id: "opencode_headless_completion", title: "OpenCode Headless Completion", audience: .both,
            summary: "OpenCode alln runs complete only when this session finishes — shared serve is session-scoped; prompt echo and foreign idle are not success.",
            bodyMarkdown: """
            OpenCode seats use `opencode serve` + HTTP/SSE (not cold `opencode run`). \
            Completion is **session-scoped**: a foreign `session.idle` on the shared \
            event bus cannot mark your turn done.

            ## What counts as done

            - **Answer / `--read-only`:** real assistant text that is not a prompt echo.
            - **Mutating:** assistant text, **or** tool work with commits / an honest \
              `repoDelta` (dirty tree + zero commits is `incomplete_uncommitted`, not green).

            ## `incomplete_uncommitted` means the seat left work IT created

            It fires on paths this run made dirty — measured against the tree as it \
            was at dispatch, so pre-existing WIP in your checkout never fails an \
            honest zero-edit answer (ADR-S01). A delivered answer also keeps its \
            text: the run is incomplete because work was left uncommitted, not \
            because nothing came back, so `errorKind` is not `empty_output` when the \
            seat produced output (ADR-S02).

            Default chat is **mutating**. For "read this and tell me" work, say so \
            with the flags rather than relying on a clean tree: `--read-only` \
            (needs `--model`), a judgment team, or `--no-commit`.

            ## What fails closed

            - Prompt echoed as the answer
            - Foreign idle / stream drop / timeout mid-turn
            - `stalled_no_progress` when the parent is quiet with **no** live \
              delegation child / running tools / open `task` / incomplete \
              assistant (no `time.completed` — DeepSeek thinking after tools \
              counts as busy). Do not raise the 120s stall window.
            - If the stall clock still fires but HTTP already has a completed \
              assistant, the answer is recovered instead of `empty_output`.
            - Unrecovered stall, timeout, stream drop, or cancel POSTs \
              `/session/:id/abort` so the shared serve does not keep an orphan.
            - `reconcile failed: …` when clean idle left an empty answer and the \
              final HTTP message fetch failed (OCH-S02)
            - Read-only tool loop with no answer text
            - Uncovered `external_directory` permission ask → `blockedOn: permission` \
              (arbitrary paths are not allow-listed)
            - Sibling-repo `external_directory` auto-approve only when this run holds \
              that root's write lock (run root always allowed for its own tree)

            **Serve reuse:** a healthy `opencode serve` left on port `4096` by a \
            prior run is attached and reused, not refused — identity is port + \
            health, never who spawned it. A dead/zombie listener or a non-OpenCode \
            process on the port refuses with a health-check timeout; either way \
            the listener is never SIGTERM'd to clear the port.

            Do **not** demote DeepSeek V4 Pro or treat Flash as the fix — the bug was \
            completion honesty, not the model.
            """,
            aliases: [
                "opencode", "opencode serve", "session.idle", "headless opencode",
                "opencode completion", "prompt echo", "external_directory",
                "deepseek v4 pro",
                "reconcile failed", "stalled_no_progress", "incomplete_no_final_message",
            ],
            relatedCommandNames: ["run", "show", "drivers"],
            needsLiveCheck: false),

        HelpTopic(
            id: "opencode_mutating_commit_contract",
            title: "OpenCode Mutating Commit Contract",
            audience: .both,
            summary: "Mutating OpenCode seats must git commit run-owned paths; dirty tree + zero commits is incomplete_uncommitted, not a green answer.",
            bodyMarkdown: """
            OpenCode (DeepSeek, GLM, Qwen via OpenCode, …) can edit the repo. A \
            mutating `alln run` is **not done** until run-owned changes are \
            committed — or you opted out with `--no-commit`.

            ## Required on mutating work

            1. Edit only the paths the slice names.
            2. `git add` those explicit paths (never `git add -A` that sweeps \
               ambient dirty).
            3. `git commit` with a clear message.
            4. Prove: `git status` clean for those paths; `alln show` reports \
               `committed: true`.

            ## What `incomplete_uncommitted` means

            The seat produced an answer (and maybe files) but left **run-owned** \
            dirty paths with no new commit. Pre-existing WIP in your checkout \
            does not count (ADR-S01). A delivered answer is kept — the run still \
            failed the commit contract.

            ## Flags

            - Default `alln run` / named model: **mutating** → commit expected.
            - `--read-only --model`: feedback without the write lock; no commit.
            - `--no-commit`: intentional dirty handoff for PM review — still \
              mutating and still takes the write lock.

            Orchestrators must not tell the seat “leave uncommitted” unless \
            `--no-commit` is on the command. That prompt alone turns a good \
            edit into a failed run.

            ## Long mutating runs

            During tool storms, `alln show <id> --json` → `observation.lastActivityAt` \
            advances when the seat uses tools (`worker.tool` / `workerActivity`). \
            If that clock freezes while you expect edits, treat it as stuck and \
            inspect with `--stream` — do not raise stall timeouts to hide a hang.
            """,
            aliases: [
                "opencode commit", "mutating commit", "opencode mutating",
                "incomplete_uncommitted", "commit contract", "must commit",
                "deepseek commit", "glm commit",
            ],
            relatedCommandNames: ["run", "show"],
            needsLiveCheck: false),

        HelpTopic(
            id: "opencode_go_capacity", title: "OpenCode Go Capacity", audience: .both,
            summary: "The OpenCode Go dashboard seat meters remaining credits via a browser cookie. Easiest setup: `alln opencode-go configure --from-chrome`, then meter with `alln capacity --source opencode_go`.",
            bodyMarkdown: """
            The OpenCode Go plan is metered through a dashboard scrape: `alln capacity` \
            fetches remaining credits for a workspace by sending your auth cookie to the \
            dashboard. This is seat number seven on the capacity strip — a regular bench \
            member, not gated by `--dogfood` (that flag is a developer-only direct path).

            ## Credential setup

            `alln opencode-go configure` writes a random `Config/machine.key` plus an \
            AES-GCM `Config/opencode_go.enc` (both 0600). That is our store — not the \
            Keychain. The cookie is never printed.

            **EASIEST:** log into https://opencode.ai in Chrome, then:
            ```
            alln opencode-go configure --from-chrome
            ```
            Workspace id is discovered from local OpenCode state or Chromium history \
            when exactly one `wrk_…` is present. macOS may ask once for Chrome's \
            **Safe Storage** key so the cookie jar can be decrypted — that is Chrome's \
            key, unavoidable for a Chrome cookie import, and acceptable.

            **Manual:** pipe the cookie via stdin so it never lands in shell history:
            ```
            echo '<cookie>' | alln opencode-go configure --workspace-id wrk_…
            ```

            **Interactive:** run `alln opencode-go configure` in a terminal — the auth value \
            is read with echo disabled so it never appears on screen.

            **Only when automated (less safe):** `--cookie <value>` works but the value WILL \
            be visible in shell history and process listings (`ps`).

            ## Checking status

            ```
            alln opencode-go status
            alln opencode-go status --json
            ```

            Status distinguishes two states that need different recovery:

            - `not configured` / strip **not set up** — nothing saved yet. Run \
              `alln opencode-go configure --from-chrome`.
            - `authRequired` / `decryptFailed` — a credential exists but is unusable (expired \
              cookie, rotated machine key). Run `alln opencode-go status` to confirm the \
              exact error, then re-run `alln opencode-go configure --from-chrome`. \
              Never guess which recovery path — the status output names it.

            ## Metering

            Once configured, the seat appears on every `alln capacity` call:
            ```
            alln capacity
            alln capacity --refresh --source opencode_go
            ```

            Capacity is read-only — `alln capacity` never writes or rotates your credential.
            """,
            aliases: [
                "opencode go", "go plan", "go quota", "go capacity",
                "opencode go limits", "opencode go dashboard",
                "opencode go configure", "opencode-go", "opencode_go",
            ],
            relatedCommandNames: ["capacity", "opencode-go configure", "opencode-go status"],
            schemaRefs: ["capacityStripJSON"],
            needsLiveCheck: true),

        HelpTopic(
            id: "opencode_local_setup", title: "OpenCode local Ollama setup", audience: .both,
            summary: "`alln opencode-local setup` merges Ollama into ~/.config/opencode/opencode.json without dropping opencode-go, and registers pulled tags under provider.ollama.models; `alln opencode-local undo` reverses it.",
            bodyMarkdown: """
            OpenCode reaches local Ollama through `provider.ollama` at \
            `http://localhost:11434/v1` plus `ollama` on `enabled_providers` when that \
            allowlist already exists. Setup also reads Ollama `/api/tags` and **merges** \
            any missing pulled tags into `provider.ollama.models`. Existing model \
            entries are never rewritten. If Ollama is unreachable, setup registers no \
            models and says so — it does not guess tags. Allnighter never replaces \
            `opencode.json` and never writes `enabled_providers: ["ollama"]` over Go.

            ```
            alln opencode-local setup
            alln opencode-local status --json
            alln opencode-local undo
            ```

            Setup copies `opencode.json` to a sibling \
            `opencode.json.bak-alln-ocl-s02a-<timestamp>` before writing. Undo removes \
            only what that setup added (receipt-backed), including model keys it \
            inserted. To restore by hand, copy the backup over `opencode.json`.

            After a write, setup recycles a leftover `opencode serve` on port `4096` so \
            newly registered tags are visible to `alln run --attach`. It checks \
            `ps -p <pid> -o command=` first and never stops `alln serve`.

            This does not seat models on the Allnighter bench and does not configure \
            Claude-local. `alln opencode-local status` still reads opencode.json only \
            and never contacts Ollama.

            After seating, `alln models` / `alln doctor` show local readiness per \
            seat: Available or Unavailable (Ollama reachable and that tag pulled). \
            Not Idle/Busy, not a capacity row. An OpenCode Zen smoke must never \
            classify a local Ollama seat. A leftover serve's cached model list is \
            not evidence the tag is missing. Advertised tools capability is \
            lie-prone; a G2 harness mutate does not predict a G3 alln-path pass.
            """,
            aliases: [
                "ollama opencode", "opencode ollama", "enabled_providers",
                "local ollama setup", "opencode-local", "11434",
            ],
            relatedCommandNames: [
                "opencode-local setup", "opencode-local undo", "opencode-local status",
            ],
            needsLiveCheck: false),

        HelpTopic(
            id: "claude_local_isolation", title: "Claude Code local Ollama isolation", audience: .both,
            summary: "`alln claude-local status` shows per-run env isolation for a Claude Code body on local Ollama. Never writes your shell or Claude settings.",
            bodyMarkdown: """
            Claude Code can talk to Ollama's Anthropic-compatible endpoint. Allnighter \
            does that **per run**: `ANTHROPIC_BASE_URL=http://localhost:11434`, auth \
            token `ollama`, empty API key. Paid Claude seats are unchanged.

            Seat a local body with a catalog label that starts `ollama/`:

            ```
            alln models add --driver claude_code --name qwen-local --model-label ollama/qwen2.5:0.5b
            alln models verify <id>
            alln models enable <id>
            alln claude-local status --json
            ```

            `alln models verify` for a Claude-local seat uses local evidence only \
            (Claude Code binary present + Ollama reachable with that tag). It does \
            **not** spawn `claude -p` token-echo smoke. That spawn hung while Ollama \
            and a direct Claude-local body both worked.

            When `/api/ps` has observed the served context window, the per-run env \
            sets `CLAUDE_CODE_CONTEXT_WINDOW` to that number so Claude Code \
            auto-compacts against the real window instead of assuming 200k. If the \
            window was not observed, Allnighter does not claim one and does not \
            set the key.

            A local failure is an Ollama failure (`ollama_local`). It is never an \
            Anthropic rate limit, park, backoff, or substitution. Claude's \
            `costUSD`, fake 200k `contextWindow`, and `provider: firstParty` are \
            stripped and are not treated as vendor truth.

            Local Ollama readiness is **per seat**, two words only: **Available** or \
            **Unavailable**. A seat is Available when Ollama is reachable and that \
            seat's tag is pulled locally. Ollama down makes every local seat \
            Unavailable. Failure to observe is not Available. This is not a capacity \
            meter and does not appear on `alln capacity`. Idle and Busy were the \
            old three-word surface; **Busy was cut because it inverted the word** — \
            a model resident in memory is the fast case, and Ollama queues; Busy \
            never meant the seat would refuse work. Advertised tools capability \
            is lie-prone; a G2 harness mutate does not predict a G3 alln-path pass.

            Do not export those env vars in your shell. Do not edit Claude settings \
            to point at localhost. Allnighter does not read Keychain.
            """,
            aliases: [
                "claude local", "claude-local", "ANTHROPIC_BASE_URL",
                "ollama claude", "claude ollama",
            ],
            relatedCommandNames: [
                "claude-local status", "models add", "models verify", "models enable",
            ],
            needsLiveCheck: false),

        HelpTopic(
            id: "park_cli", title: "Park a CLI", audience: .both,
            summary: "Park a CLI you are not using — no probe, no seats, no Needs attention — until you put it back on the bench.",
            bodyMarkdown: """
            Park is ignore, not delete. A parked CLI stays in CLI setup under **Parked**, \
            stays out of the Ready strip and model pickers, and is skipped on Re-check all \
            / `alln detect`. Model on/off toggles are preserved so Unpark restores the same \
            roster. CLI: `alln drivers park <driver-id>` and `alln drivers unpark <driver-id>`. \
            List with `alln drivers --json` (parked rows last — same order future capacity/status \
            strips should use).
            """,
            aliases: [
                "park", "parked", "unpark", "ignore cli", "disable cli", "on bench",
                "stop checking opencode", "hide cli", "drivers park",
            ],
            relatedCommandNames: ["drivers", "drivers park", "drivers unpark", "models", "doctor"],
            schemaRefs: ["driverListJSON"],
            errorRefs: ["SOURCE_NOT_FOUND"],
            needsLiveCheck: true),

        HelpTopic(
            id: "default_model", title: "Default model (Auto)", audience: .both,
            summary: "Auto answers when you pick no team/model; it draws from a substitution tier and routes around a down CLI.",
            bodyMarkdown: """
            The Default model — Auto — answers any chat where you do not pick a team or a \
            specific model. Auto draws from a **tier** (Frontier / Balanced / Economy). If the \
            tier default's CLI is down and healthy substitutions are on, Auto uses the next \
            ready model on the same tier, across CLIs — never a different tier. If the whole \
            tier is down, work waits. Membership is many-to-many: a model can sit in several \
            tiers. Configure and inspect with `alln defaults show`.
            """,
            aliases: ["auto", "default", "substitution", "substitutions", "tier", "tiers", "frontier", "balanced", "economy", "flagship", "fast"],
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
                .init("pending-vs-running", "Pending vs running a team", "Pending stores work for later; starting work with `alln run` happens now after dry-run."),
            ],
            relatedCommandNames: ["pending add", "pending list", "pending queue", "pending show", "pending run",
                                  "pending submit", "pending edit", "pending reorder", "pending cancel"],
            schemaRefs: ["pendingItemJSON", "pendingListJSON"],
            needsLiveCheck: false),

        HelpTopic(
            id: "projects_and_threads", title: "Projects & Threads", audience: .both,
            summary: "Projects bind a repo root; threads are the work conversations inside a project; `alln project models` shows readiness.",
            bodyMarkdown: """
            A project binds a local repo root. Work threads are the conversations bound to a \
            project. List projects with `alln project list`, read one with `alln project show`, \
            generate a context packet with `alln project context`, and check cached \
            per-project agent readiness with `alln project models`. Threads carry the \
            back-and-forth and the runs (`alln thread send` / `alln thread get`).
            """,
            aliases: ["project", "repo", "thread", "threads", "conversation"],
            relatedCommandNames: ["project list", "project show", "project context", "project models",
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
            help bundle cannot know it — call doctor.

            Cursor IDE vs Cursor Agent CLI: opening Cursor (the IDE) does **not** seat \
            `cursor_agent`. The seat is the headless `cursor-agent` binary (not Grok’s \
            `agent`). Install with the catalog curl, then `cursor-agent login` if needed, \
            then `alln detect` (or Mac Re-check). Doctor/detect never treat the IDE as the seat.

            Claude Code: expired OAuth often looks like opaque `smoke exited 1`. Open Claude \
            Code, type `/login` (in-session — not a shell `claude` login), finish the browser \
            flow, then `alln detect`.

            Qwen Code: after install, open `qwen` and type `/auth` (in-session) to connect a \
            provider — not a shell login. Antigravity (`agy`): install via the catalog curl, \
            then run `agy` (Keychain / browser Google sign-in).

            OpenCode: Zen (`opencode/*`) can be ready while Go seats stay gated until \
            `opencode-go` is connected (`/connect` after https://opencode.ai/go). \
            `alln doctor --full --json` reports `source.opencode.goConnected` as an upsell, \
            not a failure.

            Cursor gotcha: headless cursor-agent \
            respects `permissions.allow` in `~/.cursor/cli-config.json` even under `--trust`; \
            denied shell tools fail silently. Widen the global allowlist (e.g. `Shell(git)`, \
            `Shell(python3)`, or `Shell(**)`), or add a repo-root `.cursor/cli.json` with \
            the same `permissions.allow` / `permissions.deny` schema — project overrides \
            merge at cursor-agent process start (next headless turn). `alln doctor` reports \
            this as `source.cursor_agent.shellAllowlist` (Allnighter never writes vendor config).
            """,
            aliases: ["auth", "login", "sign in", "blocked", "why can't allnighter run codex", "api key",
                      "cursor ide", "cursor app", "cursor agent", "cursor-agent", "agent login",
                      "install cursor cli", "claude login", "/login", "opencode go"],
            sections: [
                .init("source-auth-expired", "Source auth expired", "Re-authenticate the named source via its own login flow, then re-probe with `alln doctor --full` / `alln detect`."),
                .init("cursor-ide-vs-agent", "Cursor IDE ≠ Agent CLI", "The Cursor app is not a seat. Install/sign in `cursor-agent`, then `alln detect`."),
                .init("claude-slash-login", "Claude `/login`", "Open Claude Code and type `/login` — not a shell login command. Then `alln detect`."),
                .init("qwen-slash-auth", "Qwen `/auth`", "Open Qwen Code (`qwen`) and type `/auth` — not a shell login. Then `alln detect`."),
                .init("opencode-go", "OpenCode Go", "Zen ready ≠ Go seats. Subscribe at opencode.ai/go, `/connect` the key, then `alln detect`."),
            ],
            relatedCommandNames: ["doctor", "doctor explain", "detect"],
            schemaRefs: ["doctorResult"],
            errorRefs: ["SOURCE_AUTH_EXPIRED", "SOURCE_NOT_FOUND", "SOURCE_KEYCHAIN_UNAVAILABLE"],
            needsLiveCheck: true),

        HelpTopic(
            id: "current_setup", title: "Current Setup", audience: .both,
            summary: "What can THIS install do right now? Read `alln menu --json` (`benchTally`); if never scanned, run `alln detect` once.",
            bodyMarkdown: """
            To answer "what can my install do right now?", call `alln menu --json`. Read \
            `benchTally.headline` and counts — the same BenchTally projector the Mac badge uses. \
            Headline `neverScanned` means no probe cache yet: **not** "0 of catalog ready." \
            When `benchTally.nextAction` is set, run that command once — `alln detect` when \
            never scanned, or `alln doctor --full --json` when CLIs need install/sign-in — \
            before spend. Prefer `alln detect --json` for per-source `detail` / `fixCommand`.

            Mac chrome says **Find my team** / **No CLIs checked yet** in that state — press \
            Find my team (or run detect on the CLI) to measure. Ready only means smoke-passed.
            """,
            aliases: ["can it run", "ready", "readiness", "what can it do now", "status",
                      "detect", "alln detect", "find clis", "find my team", "bench tally",
                      "neverScanned", "never scanned", "0/9 ready", "no clis checked"],
            relatedCommandNames: ["menu", "doctor", "show", "detect"],
            needsLiveCheck: true),

        HelpTopic(
            id: "artifact", title: "Team artifact (HTML receipt)", audience: .both,
            summary: "After a terminal team run, `alln artifact show <run-id|latest>` regenerates the private HTML team artifact and opens it (or prints the path). Use `alln artifact export --out` to copy the same HTML elsewhere.",
            bodyMarkdown: """
            The team artifact is a polished, private HTML reading document for a **finished** \
            team run. `alln artifact show <run-id|latest>` writes `artifact/index.html` under \
            the run journal, prints the absolute path, and opens it in your default browser \
            unless you pass `--no-open`. `--json` returns only the path, run id, and honesty \
            string.

            `alln artifact export <run-id|latest> --out <path>` writes the **same** styled HTML \
            to a user-chosen file for offline reading. It does not replace the markdown export \
            (`alln export --format md`).

            This is **not** the Factory Floor (`alln floor show`) and not the continuity receipt \
            (`alln continuity receipt`). There is no `receipt show` verb for this feature.

            Non-terminal runs fail closed with `RUN_NOT_TERMINAL`.
            """,
            aliases: ["report", "card", "receipt", "team artifact", "team receipt", "team card", "artifact show", "artifact export"],
            relatedCommandNames: ["artifact show", "artifact export", "show", "floor show", "export"],
            errorRefs: ["RUN_NOT_TERMINAL", "RUN_NOT_FOUND"],
            needsLiveCheck: false),

        HelpTopic(
            id: "results_and_history", title: "Results & History", audience: .both,
            summary: "Inspect what ran: `alln history` lists runs; `alln show` / `alln spec` / `alln floor show` inspect one run.",
            bodyMarkdown: """
            Runs are durable. `alln history` lists past runs; `alln show` returns the summary \
            packet, `alln spec` the full spec, and `alln floor show` the inspectable floor for \
            one run. For a polished HTML team receipt on a terminal run, use `alln artifact show`. \
            Results are runtime artifacts, not help docs.
            """,
            aliases: ["history", "results", "what ran", "floor", "packet"],
            relatedCommandNames: ["history", "show", "spec", "floor show", "artifact show"],
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
            errorRefs: ["CLI_USAGE_ERROR", "AGENT_FAILED", "TEAM_RUN_FAILED"],
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

            For open exploration or multi-step feature work, use a normal `alln run` or `alln run --team` \
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
            id: "billing", title: "Trial, free allowance, and paying", audience: .both,
            summary: "14-day unlimited trial from first run, then 3 full runs/day. Pay via Stripe Checkout (`alln billing checkout --plan monthly --json`); open the url in a browser — do not exec it. Sign in with Apple is not required to buy.",
            bodyMarkdown: """
            Allnighter is free to install. The first dispatch starts a **14-day unlimited \
            trial** on this machine (server clock — reinstall does not mint a new trial). \
            After that: **3 full-capability runs per day**. Nothing is feature-locked.

            Status: `alln billing --json`. To pay: `alln billing checkout --plan monthly|yearly|founding --json`. \
            The JSON `url` is hosted Stripe Checkout (email collected by Stripe). **Open it in a \
            browser. Do not exec the url.** Agents must run the compiled command \
            `alln billing checkout --plan monthly --json`, never a remote Stripe URL.

            When a 4th run is refused (`ENTITLEMENT_LIMIT`), quote `tellHuman` (same text as \
            `message`) to the human verbatim — do not paraphrase. Then run `nextAction.command` \
            once, paste the returned `url` into the same reply, and tell them to open it in \
            Safari or Chrome (not Cursor's preview). Do not retry the run until they say they paid.

            Builder is $8/month or $80/year. Founding Builder is $160 once, first 100 only.

            Discovery (`menu`, `help`, `doctor`, `billing`) is always free. An in-flight run \
            is never killed when a trial ends or the daily cap hits.
            """,
            aliases: [
                "pay", "stripe", "checkout", "trial", "founding",
                "billing", "free tier", "3 runs", "buy", "stripe checkout",
                "entitlement", "entitlement_limit",
            ],
            relatedCommandNames: ["billing", "billing checkout", "menu", "run"],
            schemaRefs: ["billingJSON"],
            errorRefs: ["ENTITLEMENT_LIMIT"],
            needsLiveCheck: true),

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

        HelpTopic(
            id: "serve", title: "Background scheduler (serve)", audience: .both,
            summary: "`alln serve` is the supervised per-user background scheduler (launchd LaunchAgent). `alln run` does not need it; deferred obligations do. Check with `alln serve status --json`; recover with `alln serve repair`.",
            bodyMarkdown: """
            `alln serve` is one supervised per-user background scheduler. macOS launchd \
            starts it through the LaunchAgent `com.allnighter.resident-coordinator` — no Dock \
            app and no foreground terminal required for day-to-day operation.

            ## What depends on serve

            **`alln run` does not depend on serve.** Foreground team runs and chats work \
            without it. Only **deferred** obligations do:

            - pending wake (`pendingWake`)
            - PM turn wake (`pmTurnWake`)
            - boost seed (`boostSeed`)
            - vendor backoff continuation (`vendorBackoff`)
            - local notifications for settled runs and loops (`notifications`)
            - capacity strip refresh (`capacityRefresh`)
            - probe record refresh (`probeRecordRefresh`)

            If serve is unhealthy, attended work still runs; pending wakes, loop \
            notifications, capacity refresh, and similar background duties may stall.

            ## What survives logout, sleep, and crash

            Host-proven on a second Mac (macOS 15.6, ad-hoc signing track):

            - **Logout/login:** after a full console logout/login, serve returned \
            `healthy` without the user launching anything — new daemon pid, all seven \
            schedulers registered.
            - **Sleep:** scheduler deadlines that fell due during system sleep fired \
            within **2 minutes** of wake (measured +54 s and +87 s on two schedulers).
            - **Crash:** signal death (TERM/KILL) produced a launchd respawn and active \
            health; respawn measured at 16–29 s (within the 30 s `ThrottleInterval`). \
            Deliberate exit `0` stand-down does **not** respawn — status shows `degraded` \
            with a reason and `recovery.command` (no respawn observed for 35 s, longer \
            than `ThrottleInterval`).

            ## `degraded` and recovery

            When desired state is enabled but something is wrong — stand-down, missing \
            supervisor, stale or nonresponding daemon, scheduler failure, binary \
            mismatch — `state` is `degraded`. Run `alln serve status --json` and read \
            `recovery.command` for the named recovery action (usually `alln serve repair`).

            ## Commands

            - `alln serve status --json` — read-only desired state, supervisor, daemon, \
            scheduler rows, and recovery hint
            - `alln serve repair` — converge plist and registration when enabled; first \
            try for most broken states
            - `alln serve disable` / `alln serve enable` — deliberate off/on

            **A disable persists.** On a tested host, `alln serve disable` survived \
            logout/login and `install-cli` did not silently re-enable it. If you disabled \
            serve and forgot, deferred work will not wake until you run `alln serve enable`.
            """,
            aliases: [
                "serve", "scheduler", "background", "login", "launchagent",
                "capacity stale", "pending stuck", "notification", "repair",
                "background scheduler", "launch agent", "serve degraded",
                "serve status", "alln serve",
            ],
            relatedCommandNames: ["serve status", "serve repair", "serve enable", "serve disable", "serve"],
            schemaRefs: ["serveStatusJSON"],
            errorRefs: ["SERVE_UNAVAILABLE", "SERVE_DISABLED_BY_USER"],
            needsLiveCheck: true),

        HelpTopic(
            id: "ask_ai", title: "Ask AI", audience: .both,
            summary: "Title-bar Ask AI answers questions about Allnighter on this Mac. Billing, refunds, and privacy go to support@allnighter.io.",
            bodyMarkdown: """
            The Mac app title bar has **Ask AI**. It is a regular Auto run aimed \
            inward — this Mac, setup, PATH, Teams, capacity, Boost, billing — not \
            a Team and not the repo composer. Live facts (version, PATH, bench \
            tally) ride with the question. The turn is read-only on the project.

            Regular chat / Auto is aimed at the open project. Mac-only users may \
            not know `alln` yet. Ask AI is the door that does not require that.

            For where a control lives in the Mac app, agents call `alln chrome --json`. \
            That catalog is projected from the labels the app draws. Do not guess \
            Allnighter chrome from the open repo.

            Billing, refunds, privacy, or “Ask AI was wrong”: email \
            support@allnighter.io. A real person reads it. Ask AI cannot issue a \
            refund. CLI identity (`alln version`) prints the same address.
            """,
            aliases: [
                "ask ai", "ask allnighter", "support", "contact", "contact us",
                "email support", "support email", "help button",
                "customer support", "mailto",
            ],
            sections: [
                .init("door", "The door", "Title bar → Ask AI. One question. Auto, read-only, inward prompt."),
                .init("hatch", "Email a person", "support@allnighter.io for billing, refunds, privacy, or a wrong answer. `alln version` prints the same address."),
            ],
            relatedCommandNames: ["chrome", "doctor", "help search", "billing", "install-cli", "version"],
            needsLiveCheck: true),

        HelpTopic(
            id: "chrome", title: "Mac chrome catalog", audience: .both,
            summary: "Where is that control in the Mac app? Call `alln chrome --json`. Rows are the labels on screen, not a help article.",
            bodyMarkdown: """
            `alln chrome --json` is the Mac twin of `alln menu --json`. It returns \
            owner-action rows (controlLabel, where, live facts) projected from the \
            same strings the Mac app draws.

            Use it when a human asks where a button or Settings row is, or what a \
            title-bar label means on this Mac. Optional `--screen home` (or \
            `settings.boost`, `settings.about`, …) puts on-screen rows first.

            Do not guess Allnighter chrome from the open repo. Do not use \
            `alln doctor` for “where is Boost?”. Doctor is CLI health. Missing \
            row: say you do not know yet.

            The model writes the sentence. The catalog does not ship FAQ answers.
            """,
            aliases: [
                "chrome", "alln chrome", "mac chrome", "where is the button", "gui catalog",
                "boost window", "need a step", "models dropdown",
                "use from your cli", "about path", "settings row",
            ],
            sections: [
                .init("call", "Call", "`alln chrome --json` (optional `--screen`)."),
                .init("not", "Not this", "Not `alln doctor`. Not a written Boost/Capacity article."),
            ],
            relatedCommandNames: ["chrome", "menu", "doctor", "help search"],
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
                "bootstrap", "help get", "help search", "menu",
                "loop start", "run",
                "show", "team cancel",
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
