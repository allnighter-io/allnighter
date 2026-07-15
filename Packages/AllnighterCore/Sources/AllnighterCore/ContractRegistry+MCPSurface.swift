import Foundation

/// Slice 1 MCP tool surface (61 → 30). See docs/phases/MCP_Tool_Upgrade.md §4–§5A.
/// Wire `mcpTools` on `milestone1` should reference `upgradedMCPTools`.
public extension ContractRegistry {
    static let upgradedMCPTools: [MCPToolSpec] = [
        // MARK: Bootstrap & recovery (6)

        MCPToolSpec(
            "mcp_hello",
            command: "teams",
            summary: """
            DOES: Router bootstrap — readiness, nextToolPlan, workflows, and contractHash (no tool roster or help sitemap).
            USE WHEN: First call in a session or after a contract/auth change.
            NOT WHEN: You need product how-to prose (use help) or deep machine diagnostics (use doctor).
            NEXT: Follow nextToolPlan — typically team_start(dryRun:true), else doctor.
            """,
            params: [.init("agent", summary: "Calling agent id for provenance (advisory only).")],
            idempotency: .idempotent,
            title: "Hello"
        ),

        MCPToolSpec(
            "doctor",
            command: "doctor",
            summary: """
            DOES: Diagnostics report for sources, models, auth, coordinator, and Boost window readout.
            USE WHEN: mcp_hello routes here, a run is blocked, or you need live machine health.
            NOT WHEN: You only need one error code explained (use error_explain) or product docs (use help).
            NEXT: error_explain on failed checks; then retry the blocked workflow.
            """,
            params: [
                .init("full", type: "boolean", summary: "Run smoke probes (spends quota)."),
                .init("agent", summary: "Limit to one source id (e.g. cursor_agent)."),
            ],
            outputSchema: .doctorResult,
            errors: ["SOURCE_NOT_FOUND", "DOCTOR_CHECK_FAILED", "CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Doctor"
        ),

        MCPToolSpec(
            "error_explain",
            command: "doctor explain",
            summary: """
            DOES: Explain one error/recovery code with cause, who fixes it, agentAction, and helpRef.
            USE WHEN: A tool failed and you need structured recovery (also covers trimmed thread_send attachment/file codes).
            NOT WHEN: You need live readiness (use doctor) or a full help topic (use help).
            NEXT: Follow agentAction; re-call the tool that failed or use help(topic/error).
            """,
            params: [.init("code", required: true, summary: "Error code, e.g. SOURCE_AUTH_EXPIRED.")],
            outputSchema: .errorExplainJSON,
            errors: ["CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Explain error"
        ),

        MCPToolSpec(
            "help",
            command: "help search",
            summary: """
            DOES: Search or fetch installed Allnighter help — product how-to, tool choice, setup, safety.
            USE WHEN: Any Allnighter usage question before answering from memory.
            NOT WHEN: You need this machine's live state (use mcp_hello/doctor) or a run record (use run_get).
            NEXT: Follow the returned next-tool plan; static topics also live at allnighter://help/{topic}.
            SELECTOR: query → ranked search; topic|ref|tool|error → fetch one topic.
            """,
            params: [
                .init("query", summary: "Natural-language question or keywords (search)."),
                .init("topic", summary: "Topic id or alln:// ref (fetch)."),
                .init("ref", summary: "An alln:// ref (help/tool/schema/error)."),
                .init("tool", summary: "Find the topic documenting this MCP tool."),
                .init("error", summary: "Find the topic for this error code."),
                .init("limit", type: "integer", summary: "Max search results (default 5)."),
            ],
            outputSchema: .helpSearchJSON,
            errors: ["CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Help"
        ),

        MCPToolSpec(
            "defaults_get",
            command: "defaults show",
            summary: """
            DOES: Read Default model settings — Auto tier, per-tier rosters, unassigned shelf, live resolution.
            USE WHEN: Choosing a worker override or explaining what Auto resolves to right now.
            NOT WHEN: You need per-project worker cache (use project_workers) or catalog teams (use teams_get).
            NEXT: team_start(dryRun) or team_run with an explicit worker override.
            """,
            outputSchema: .defaultSettingsJSON,
            errors: ["CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Get defaults"
        ),

        MCPToolSpec(
            "history",
            command: "history",
            summary: """
            DOES: Search prior local team runs (read-only, zero quota).
            USE WHEN: You need an old run id or to recall prior prompts/results.
            NOT WHEN: You have a run id already (use run_get) or need live async status (use team_result).
            NEXT: run_get with the chosen run id.
            """,
            params: [
                .init("query", required: true, summary: "Search text."),
                .init("limit", type: "integer", summary: "Maximum results (default 25)."),
                .init("cursor", summary: "Pagination cursor from a prior response."),
            ],
            outputSchema: .historyJSON,
            errors: ["CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Search history"
        ),

        // MARK: Catalog (4)

        MCPToolSpec(
            "teams_get",
            command: "teams",
            summary: """
            DOES: List, show, or fetch round-trippable definitions for teams; no-arg also returns per-lane defaults.
            USE WHEN: Discovering teams, inspecting one team, or exporting a TeamPreset for teams_edit(save).
            NOT WHEN: Mutating catalog entries (use teams_edit) or running a team (use team_ask/team_run).
            NEXT: teams_edit to save changes; team_start or team_ask to run.
            MODE: teamId omitted → summary list (+ lane defaults); teamId present → full record; detail:definition → TeamPreset JSON.
            """,
            params: [
                .init("teamId", summary: "One team id — returns full summary (absorbs teams_show)."),
                .init("detail", summary: "definition → round-trippable TeamPreset (absorbs teams_definition)."),
                .init("lane", summary: "Filter list to code|design|copy|signal."),
                .init("includeInactive", type: "boolean", summary: "Include inactive teams in list (default false)."),
                .init("limit", type: "integer", summary: "Maximum list items (default 25)."),
                .init("cursor", summary: "Pagination cursor from a prior list response."),
            ],
            outputSchema: .teamCatalogJSON,
            errors: ["TEAM_NOT_FOUND", "DEFAULT_TEAM_INVALID", "CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Get teams"
        ),

        MCPToolSpec(
            "teams_edit",
            command: "teams edit",
            summary: """
            DOES: PATCH-dispatched team catalog mutations — save, duplicate, set default, delete, restore.
            USE WHEN: Creating or updating custom teams or lane defaults.
            NOT WHEN: Read-only inspection (use teams_get) or running a team (use team_ask/team_run).
            NEXT: teams_get to verify; team_start(dryRun) before first run with a changed team.
            ACTION: save → partial-merge definition; duplicate → copy; set_default → lane default; delete → remove custom/builtin edits; restore → shipped builtin.
            """,
            params: [
                .init("action", required: true, summary: "save | duplicate | set_default | delete | restore."),
                .init("teamId", required: true, summary: "Target team id."),
                .init("definition", type: "object", summary: "TeamPreset JSON for action:save (partial merge)."),
                .init("name", summary: "Display name for action:duplicate."),
            ],
            errors: [
                "TEAM_NOT_FOUND", "TEAM_ID_COLLISION", "TEAM_INVALID", "CATALOG_ID_INVALID",
                "SKILL_LANE_MISMATCH", "TEAM_DEFAULT_INVALID", "TEAM_BUILTIN_IMMUTABLE",
                "TEAM_RESTORE_UNSUPPORTED", "CLI_USAGE_ERROR", "INTERNAL_ERROR",
            ],
            idempotency: .notIdempotent,
            title: "Edit team"
        ),

        MCPToolSpec(
            "skills_get",
            command: "skills",
            summary: """
            DOES: List lane-scoped skill summaries or fetch one skill including its template.
            USE WHEN: Discovering skills or reading a template before skills_edit(save).
            NOT WHEN: Mutating skills (use skills_edit) or running work (use team_ask/team_run).
            NEXT: skills_edit to save; teams_get to see which skills a team uses.
            MODE: skillId omitted → summary list; skillId present → full skill record (absorbs skills_show).
            """,
            params: [
                .init("skillId", summary: "One skill id — returns full definition."),
                .init("lane", summary: "Filter list to code|design|copy|signal."),
                .init("limit", type: "integer", summary: "Maximum list items (default 25)."),
                .init("cursor", summary: "Pagination cursor from a prior list response."),
            ],
            outputSchema: .skillCatalogJSON,
            errors: ["SKILL_NOT_FOUND", "CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Get skills"
        ),

        MCPToolSpec(
            "skills_edit",
            command: "skills edit",
            summary: """
            DOES: PATCH-dispatched skill catalog mutations — save, duplicate, delete.
            USE WHEN: Creating or updating custom skills.
            NOT WHEN: Read-only inspection (use skills_get) or running work.
            NEXT: skills_get to verify the saved skill.
            ACTION: save → replace definition; duplicate → copy builtin; delete → remove custom skill.
            """,
            params: [
                .init("action", required: true, summary: "save | duplicate | delete."),
                .init("skillId", required: true, summary: "Target skill id."),
                .init("definition", type: "object", summary: "Skill JSON for action:save."),
                .init("name", summary: "Display name for action:duplicate."),
            ],
            errors: [
                "SKILL_NOT_FOUND", "SKILL_ID_COLLISION", "SKILL_INVALID", "SKILL_BUILTIN_IMMUTABLE",
                "SKILL_IN_USE", "CATALOG_ID_INVALID", "CLI_USAGE_ERROR", "INTERNAL_ERROR",
            ],
            idempotency: .notIdempotent,
            title: "Edit skill"
        ),

        // MARK: Execution (6)

        MCPToolSpec(
            "team_ask",
            command: "team",
            summary: """
            DOES: Run a lane answer team on a prompt; returns a board/synthesis. Never takes the write lock or execution lane.
            USE WHEN: Parallel non-mutating judgment — options, review, design boards.
            NOT WHEN: Repo-scoped mutating execution (use team_run) or async overnight runs (use team_start).
            NEXT: run_get or history to retrieve the structured run; team_run only if the user explicitly executes one pick.
            """,
            params: [
                .init("question", required: true, summary: "The prompt to ask the team."),
                .init("lane", summary: "code|design|copy|signal (explicit; never inferred)."),
                .init("team", summary: "Team id."),
                .init("effort", summary: "low|med|high (optional)."),
                .init("type", summary: "Copy-only routing sugar (optional)."),
                .init("context", summary: "Bounded context snippet (optional)."),
            ],
            outputSchema: .teamRunJSON,
            errors: [
                "DEFAULT_TEAM_INVALID", "TEAM_NOT_FOUND", "MODEL_UNAVAILABLE", "TEAM_RUN_TIMEOUT",
                "TEAM_RUN_FAILED", "PLAN_WRITER_FAILED", "WORKER_FAILED", "NESTED_TEAM_BLOCKED",
                "TEAM_GOVERNOR_BUSY", "TEAM_GOVERNOR_UNAVAILABLE", "CLI_USAGE_ERROR",
            ],
            idempotency: .notIdempotent,
            title: "Ask team"
        ),

        MCPToolSpec(
            "team_run",
            command: "run",
            summary: """
            DOES: Project-scoped unified run — may dispatch one mutating worker under the execution lane write lock.
            USE WHEN: The user wants code/design/copy changes applied in a repo root.
            NOT WHEN: Non-mutating parallel options (use team_ask) or fire-and-forget async (use team_start).
            NEXT: run_get for the finished run; project_context after a mutating run in the same project.
            """,
            params: [
                .init("message", required: true, summary: "The user's prompt."),
                .init("project", required: true, summary: "Project id, name, or repo path."),
                .init("team", summary: "Team preset id; omit for Default Team."),
                .init("worker", summary: "Override worker model id (execution/default)."),
                .init("effort", summary: "low|med|high (optional)."),
                .init("lane", summary: "code|design|copy|signal when routing answer teams."),
                .init("type", summary: "Copy routing sugar (optional)."),
                .init("context", summary: "Bounded context snippet (optional)."),
            ],
            outputSchema: .teamRunJSON,
            errors: [
                "PROJECT_NOT_FOUND", "NO_PROJECT_ROOT", "RUN_WRITE_LOCK_BUSY", "DEFAULT_TEAM_INVALID",
                "TEAM_NOT_FOUND", "WORKER_NOT_READY", "CLI_USAGE_ERROR",
            ],
            idempotency: .notIdempotent,
            title: "Run team"
        ),

        MCPToolSpec(
            "team_start",
            command: "team start",
            summary: """
            DOES: Start an async team run (or validate with dryRun:true — absorbs team_preflight).
            USE WHEN: Overnight/async fan-out where you poll team_result until terminal.
            NOT WHEN: Synchronous answer (use team_ask) or project-scoped mutating execute (use team_run).
            NEXT: team_result (poll); run_get when terminal; team_cancel to abort.
            """,
            params: [
                .init("prompt", required: true, summary: "The prompt to run."),
                .init("dryRun", type: "boolean", summary: "When true, preflight only — no run, no quota (absorbs team_preflight)."),
                .init("lane", summary: "code|design|copy|signal."),
                .init("team", summary: "Team id."),
                .init("effort", summary: "low|med|high."),
                .init("type", summary: "Copy-only routing sugar (optional)."),
                .init("context", summary: "Bounded inline context (optional)."),
                .init("threadId", summary: "Owning work thread id (optional)."),
                .init("originAgent", summary: "Calling agent id for provenance."),
                .init("originConversationId", summary: "Origin conversation id."),
                .init("originMessageId", summary: "Origin message id."),
                .init("idempotencyKey", summary: "Client idempotency key (24h retention)."),
            ],
            outputSchema: .teamStartResponse,
            errors: [
                "DEFAULT_TEAM_INVALID", "TEAM_NOT_FOUND", "MODEL_UNAVAILABLE", "NESTED_TEAM_BLOCKED",
                "TEAM_GOVERNOR_BUSY", "TEAM_GOVERNOR_UNAVAILABLE",
                "IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD", "COORDINATOR_UNAVAILABLE", "CLI_USAGE_ERROR",
            ],
            idempotency: .keyed,
            title: "Start team run"
        ),

        MCPToolSpec(
            "team_result",
            command: "team result",
            summary: """
            DOES: Poll async run state — running envelope with nextPollAfterMs, or terminal TeamRunJSON (absorbs team_status).
            USE WHEN: After team_start, until status is terminal.
            NOT WHEN: You already have a terminal run id and want audit/history shape only (use run_get).
            NEXT: Poll again after nextPollAfterMs while running; run_get(view:summary) when done.
            MODE: running → lightweight status; terminal → full TeamRunJSON (detail/full for prompt snapshots).
            """,
            params: [
                .init("runId", required: true, summary: "Run id from team_start."),
                .init("detail", summary: "summary | full (full embeds worker prompt snapshots)."),
                .init("includePrompts", type: "boolean", summary: "When true, embed worker prompt snapshots."),
            ],
            outputSchema: .teamRunJSON,
            errors: ["RUN_NOT_FOUND", "RESULT_NOT_READY", "CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Get team result"
        ),

        MCPToolSpec(
            "team_cancel",
            command: "team cancel",
            summary: """
            DOES: Cancel an active async team run.
            USE WHEN: User abort or superseded work on a team_start run id.
            NOT WHEN: The run is already terminal (use team_result/run_get to confirm).
            NEXT: team_result to confirm cancelled terminal state.
            """,
            params: [.init("runId", required: true, summary: "Run id from team_start.")],
            outputSchema: .teamCancelResponse,
            errors: ["RUN_NOT_FOUND", "CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Cancel team run"
        ),

        MCPToolSpec(
            "run_get",
            command: "show",
            summary: """
            DOES: Fetch one run by id/latest in summary, spec, or floor view (absorbs show, spec_get, floor_show).
            USE WHEN: Inspecting a finished or historical run — workers, artifacts, floor, spec packet.
            NOT WHEN: Polling a live async team_start run (use team_result).
            NEXT: thread_get if the run owned a thread; pending_list if execute was deferred.
            VIEW: summary → TeamRunJSON; spec → spec/result packet; floor → inspectable Floor run.
            """,
            params: [
                .init("run", required: true, summary: "Run id or latest."),
                .init("view", summary: "summary | spec | floor (default summary)."),
                .init("full", type: "boolean", summary: "For view:summary — include worker prompt snapshots."),
                .init("detail", summary: "For view:spec — summary | full | artifactRefsOnly."),
            ],
            outputSchema: .teamRunJSON,
            errors: ["RUN_NOT_FOUND", "CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Get run"
        ),

        // MARK: Pair executor (2)

        MCPToolSpec(
            "pair_run",
            command: "pair run",
            summary: """
            DOES: Run a durable slice queue unattended, or dispatch one inline slice packet (absorbs pair_slice).
            USE WHEN: Sprint/pair-programming automation with gate → executor → repo check.
            NOT WHEN: A single synchronous team_run suffices or you only need queue status (use pair_status).
            NEXT: pair_status while running; run_get on child run ids.
            MODE: queueDir → unattended queue; packet|packetPath → one bounded slice (absorbs pair_slice).
            """,
            params: [
                .init("project", required: true, summary: "Project id, name, or repo path."),
                .init("queueDir", summary: "Directory of slice packets for queue mode (pair run)."),
                .init("packetPath", summary: "Path to one WorkSlicePacket .json or markdown fence (single-slice mode)."),
                .init("packet", type: "object", summary: "Inline WorkSlicePacket JSON (single-slice mode)."),
                .init("until", summary: "Hard stop clock HH:MM (local) for queue mode."),
                .init("maxRetries", type: "integer", summary: "Legacy stall nudge cap (queue mode)."),
                .init("executorAttemptsBeforePlanner", type: "integer", summary: "GLM attempts per packet before planner takeover (default 3)."),
                .init("executor", summary: "Mutating executor team id (default default_chat)."),
                .init("plannerWorker", summary: "Planner model id (default Composer 2.5)."),
                .init("executorWorker", summary: "Executor model id (default Gemini 3.5 Flash)."),
            ],
            outputSchema: .pairQueueJSON,
            errors: [
                "PROJECT_NOT_FOUND", "PAIR_SLICE_PACKET_MISSING", "PAIR_SLICE_UNSAFE",
                "PAIR_SLICE_EXECUTOR_INVALID", "PAIR_SERVE_UNAVAILABLE", "RUN_WRITE_LOCK_BUSY",
                "WORKER_NOT_READY", "CLI_USAGE_ERROR",
            ],
            idempotency: .notIdempotent,
            title: "Run pair queue"
        ),

        MCPToolSpec(
            "pair_status",
            command: "pair status",
            summary: """
            DOES: Read slice queue state — per-entry status, child run id, elapsed time, stall guidance.
            USE WHEN: Monitoring an in-flight pair_run queue.
            NOT WHEN: Starting or advancing the queue (use pair_run).
            NEXT: pair_run to continue; run_get on the active child run id.
            """,
            params: [.init("queueDir", required: true, summary: "Directory containing queue.json and slice packets.")],
            outputSchema: .pairStatusJSON,
            errors: ["CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Pair queue status"
        ),

        // MARK: PM Relay (1)

        // One tool, action-dispatched (start | status | resume) — NOT three. The
        // CLI keeps three separate subcommands (`pair relay` / `relay-status` /
        // `relay-resume` — different flag shapes read better as distinct verbs at
        // a terminal), but the MCP surface is under the T1 tool-count cap (§3):
        // adding three tools would land at 33 (over the ≤32 cap with only 2 slots
        // of headroom); folding status/resume into one `action`-dispatched tool —
        // the same shape `teams_edit`/`skills_edit`/`pending_update` already use —
        // costs exactly one new slot (30 → 31).
        MCPToolSpec(
            "pair_relay",
            command: "pair relay",
            summary: """
            DOES: Start, check status of, or resume the PM Relay — a PM seat reviews the repo and a dev seat builds, round after round, until done/escalate/a ceiling.
            USE WHEN: Automating the founder's PM↔dev copy-paste loop unattended on a spec doc, or checking/answering an in-flight relay.
            NOT WHEN: A single synchronous change (use team_run).
            NEXT: action:status to inspect a relay; action:resume once status is escalated.
            ACTION: start → doc/project/pmWorker/devWorker required, begins a new relay and runs to done/escalate/a ceiling; status → relay required, reads durable state; resume → relay+answer required, injects the founder's answer into an escalated relay and continues.
            """,
            params: [
                .init("action", required: true, summary: "start | status | resume."),
                .init("doc", summary: "Repo-relative spec doc path (action:start) — the PM re-reads it fresh each round."),
                .init("project", summary: "Project id, name, or repo path (action:start)."),
                .init("pmWorker", summary: "PM seat model id (action:start)."),
                .init("devWorker", summary: "Dev seat model id (action:start)."),
                .init("relay", summary: "Relay id (action:status/resume)."),
                .init("answer", summary: "The founder's answer to the escalation (action:resume)."),
                .init("until", summary: "Hard stop clock HH:MM local (action:start/resume)."),
                .init("maxRounds", type: "integer", summary: "Round ceiling, default 20 (action:start/resume)."),
                .init("pmReadOnly", type: "boolean", summary: "Flag PM turns as non-mutating, advisory (action:start; default false)."),
            ],
            outputSchema: .relayJSON,
            errors: ["PROJECT_NOT_FOUND", "RELAY_NOT_FOUND", "RELAY_INVALID_STATE", "CLI_USAGE_ERROR"],
            idempotency: .notIdempotent,
            title: "PM relay"
        ),

        // MARK: Threads (3)

        MCPToolSpec(
            "thread_send",
            command: "thread send",
            summary: """
            DOES: Send a message and/or images/file refs to a work thread worker.
            USE WHEN: Continuing a project thread conversation with optional attachments.
            NOT WHEN: Read-only thread inspection (use thread_get) or renaming (use thread_rename).
            NEXT: thread_get to read the updated snapshot; error_explain for attachment/file codes (allnighter://errors/*).
            """,
            params: [
                .init("threadId", summary: "Thread id or latest."),
                .init("message", summary: "User message text."),
                .init("workerId", summary: "Requested worker/model id."),
                .init("idempotencyKey", summary: "Client idempotency key (24h retention)."),
                .init("images", type: "array", summary: "Image paths or base64 objects.", arrayItems: .init(oneOf: [
                    .init(type: "string"),
                    .init(type: "object", properties: ["mimeType": .init(type: "string"), "base64": .init(type: "string")], required: ["base64"]),
                ])),
                .init("fileReferences", type: "array", summary: "Project file refs as paths or objects with path/startLine/endLine.", arrayItems: .init(oneOf: [
                    .init(type: "string"),
                    .init(type: "object", properties: [
                        "path": .init(type: "string"),
                        "startLine": .init(type: "integer"),
                        "endLine": .init(type: "integer"),
                    ], required: ["path"]),
                ])),
            ],
            errors: [
                "THREAD_NOT_FOUND", "THREAD_SEND_IDEMPOTENCY_CONFLICT", "WORKER_FAILED",
                "THREAD_SEND_FAILED", "CLI_USAGE_ERROR",
            ],
            idempotency: .keyed,
            title: "Send to thread"
        ),

        MCPToolSpec(
            "thread_get",
            command: "thread get",
            summary: """
            DOES: Fetch a work thread snapshot, status/attention, or one attachment (absorbs thread_status, thread_attachment_get).
            USE WHEN: Reading thread state before/after thread_send or polling running attention.
            NOT WHEN: Sending a message (use thread_send) or renaming (use thread_rename).
            NEXT: thread_send to continue; run_get for linked team runs.
            MODE: threadId only → snapshot incl. running/attention; attachmentId → that attachment body.
            """,
            params: [
                .init("threadId", required: true, summary: "Thread id or latest."),
                .init("attachmentId", summary: "Fetch one attachment by id (absorbs thread_attachment_get)."),
            ],
            outputSchema: .threadGetJSON,
            errors: ["THREAD_NOT_FOUND", "ATTACHMENT_NOT_FOUND", "CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Get thread"
        ),

        MCPToolSpec(
            "thread_rename",
            command: "thread rename",
            summary: """
            DOES: Rename a work thread (same SSOT as inbox double-click rename).
            USE WHEN: User-visible thread title cleanup.
            NOT WHEN: Sending messages (use thread_send) or reading state (use thread_get).
            NEXT: thread_get to confirm the new title.
            """,
            params: [
                .init("threadId", required: true, summary: "Thread id."),
                .init("title", required: true, summary: "New non-empty thread title."),
            ],
            outputSchema: .threadGetJSON,
            errors: ["THREAD_NOT_FOUND", "CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Rename thread"
        ),

        // MARK: Pending (4)

        MCPToolSpec(
            "pending_list",
            command: "pending list",
            summary: """
            DOES: List Pending items, show one item, or render the armed queue bundle (absorbs pending_show, pending_queue).
            USE WHEN: Inspecting the Pending floor before submit/run/edit.
            NOT WHEN: Mutating content (use pending_edit) or arming/cancelling (use pending_update).
            NEXT: pending_edit to change draft content; pending_update(submit) to arm; pending_run to execute.
            MODE: pendingId → one item; mode:queue → armed-queue bundle; else paginated list (project optional).
            """,
            params: [
                .init("project", summary: "Project id or name (optional; omit for --all aggregate)."),
                .init("pendingId", summary: "One Pending item id (absorbs pending_show)."),
                .init("mode", summary: "queue → render-ready armed queue bundle (absorbs pending_queue)."),
                .init("limit", type: "integer", summary: "Maximum items (default 25)."),
                .init("cursor", summary: "Pagination cursor from a prior list response."),
            ],
            outputSchema: .pendingListJSON,
            errors: ["CLI_USAGE_ERROR", "PROJECT_NOT_FOUND"],
            idempotency: .idempotent,
            title: "List pending"
        ),

        MCPToolSpec(
            "pending_edit",
            command: "pending edit",
            summary: """
            DOES: Edit a Pending/Draft item's prompt or target; Pending items return to Draft when edited.
            USE WHEN: Changing what will run before arming — richer schema than pending_update.
            NOT WHEN: Thin state transitions only (use pending_update) or executing (use pending_run).
            NEXT: pending_update(submit) to re-arm after editing a Pending item.
            """,
            params: [
                .init("pendingId", required: true, summary: "Pending item id."),
                .init("prompt", summary: "Replacement prompt text."),
                .init("worker", summary: "Target worker model id."),
                .init("team", summary: "Team preset id."),
                .init("fallback", summary: "Fallback worker id."),
                .init("when", summary: "ready | away | manual."),
            ],
            outputSchema: .pendingItemJSON,
            errors: ["CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Edit pending"
        ),

        MCPToolSpec(
            "pending_update",
            command: "pending submit",
            summary: """
            DOES: Thin Pending state transitions — arm, cancel, or reorder (absorbs pending_submit, pending_cancel, pending_reorder).
            USE WHEN: Arming a draft, removing from queue, or changing queue position without editing content.
            NOT WHEN: Editing prompt/worker fields (use pending_edit) or executing (use pending_run).
            NEXT: pending_list(mode:queue) to verify order; pending_run when armed.
            ACTION: submit → Draft to Pending; cancel → remove; reorder → before|after|position.
            """,
            params: [
                .init("action", required: true, summary: "submit | cancel | reorder."),
                .init("pendingId", required: true, summary: "Pending item id."),
                .init("before", summary: "For reorder — move before this item id."),
                .init("after", summary: "For reorder — move after this item id."),
                .init("position", type: "integer", summary: "For reorder — move to 0-based position."),
            ],
            outputSchema: .pendingItemJSON,
            errors: ["CLI_USAGE_ERROR", "PENDING_REORDER_INVALID"],
            idempotency: .idempotent,
            title: "Update pending"
        ),

        MCPToolSpec(
            "pending_run",
            command: "pending run",
            summary: """
            DOES: Execute a Pending workerChat or non-mutating teamRun item; mutating execute teams stay lane-safe.
            USE WHEN: Running an armed Pending item headlessly.
            NOT WHEN: Editing or queue management (use pending_edit / pending_update).
            NEXT: run_get or thread_get depending on item kind; project_context after mutating execute in project.
            """,
            params: [.init("pendingId", required: true, summary: "Pending item id.")],
            outputSchema: .pendingItemJSON,
            errors: ["CLI_USAGE_ERROR", "PENDING_MUTATION_DEFERRED", "EXECUTION_TEAM_MIXED_SOURCES"],
            idempotency: .notIdempotent,
            title: "Run pending"
        ),

        // MARK: Stalled (2)

        MCPToolSpec(
            "stalled_list",
            command: "stalled list",
            summary: """
            DOES: List stalled-work episodes aggregate or for one project (absorbs project_stalled).
            USE WHEN: Finding work that needs user attention across projects or in one project.
            NOT WHEN: Acting on an episode (use stalled_update).
            NEXT: stalled_update(action:check) on the episode; ask user to wait or dismiss.
            MODE: project omitted → aggregate by project; project set → that project's episodes.
            """,
            params: [
                .init("project", summary: "Project id or name (optional; absorbs project_stalled)."),
                .init("includeCleared", type: "boolean", summary: "Include cleared episodes for one project."),
                .init("limit", type: "integer", summary: "Maximum episodes (default 25)."),
                .init("cursor", summary: "Pagination cursor from a prior list response."),
            ],
            outputSchema: .stallListJSON,
            errors: ["CLI_USAGE_ERROR", "PROJECT_NOT_FOUND"],
            idempotency: .idempotent,
            title: "List stalled work"
        ),

        MCPToolSpec(
            "stalled_update",
            command: "stalled check",
            summary: """
            DOES: Re-observe, snooze, or dismiss a stall episode (absorbs stall_check_status, stall_keep_waiting, stall_dismiss).
            USE WHEN: Recovery flow after stalled_list surfaces an episode.
            NOT WHEN: Read-only stall discovery (use stalled_list).
            NEXT: stalled_list to confirm cleared/snoozed state.
            ACTION: check → re-observe target; wait → snooze N minutes; dismiss → user-dismiss (may resurface).
            """,
            params: [
                .init("action", required: true, summary: "check | wait | dismiss."),
                .init("episodeId", required: true, summary: "Stall episode id."),
                .init("minutes", type: "integer", summary: "For action:wait — snooze minutes (default 30)."),
            ],
            outputSchema: .stallEpisodeJSON,
            errors: ["STALL_EPISODE_NOT_FOUND", "CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Update stalled work"
        ),

        // MARK: Projects (3)

        MCPToolSpec(
            "project_get",
            command: "project show",
            summary: """
            DOES: List projects or show one project with fresh root/git observation (absorbs project_list).
            USE WHEN: Resolving a project id/path or enumerating projects before team_run.
            NOT WHEN: Capability pack (use project_context) or worker readiness (use project_workers).
            NEXT: project_context before a complex run; team_run with the resolved project.
            MODE: project omitted → paginated list; project present → full record.
            """,
            params: [
                .init("project", summary: "Project id or name — omit to list."),
                .init("all", type: "boolean", summary: "Include archived projects in list."),
                .init("limit", type: "integer", summary: "Maximum list items (default 25)."),
                .init("cursor", summary: "Pagination cursor from a prior list response."),
            ],
            outputSchema: .projectJSON,
            errors: ["PROJECT_NOT_FOUND", "CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Get project"
        ),

        MCPToolSpec(
            "project_context",
            command: "project context",
            summary: """
            DOES: Generate the versioned project context pack — runnable teams, admission hints, workers, feature flags.
            USE WHEN: Before team_run/pending_run in a project; re-fetch after mutating runs or doctor health changes.
            NOT WHEN: Simple project metadata only (use project_get) or live worker probes (use project_workers(refresh:true)).
            NEXT: team_start(dryRun) or team_run; also exposed as allnighter://projects/{id}/context.
            """,
            params: [.init("project", required: true, summary: "Project id or name.")],
            outputSchema: .projectContextJSON,
            errors: ["PROJECT_NOT_FOUND", "CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Get project context"
        ),

        MCPToolSpec(
            "project_workers",
            command: "project workers",
            summary: """
            DOES: Read cached per-project worker readiness, or refresh via safe probes (absorbs project_recheck_workers).
            USE WHEN: Choosing a worker override or verifying readiness before execute.
            NOT WHEN: Full project context pack (use project_context) — never auto-configures auth.
            NEXT: team_run/worker override or doctor if refresh shows blocked sources.
            MODE: refresh:false → cached read; refresh:true → driver-declared safe probes only.
            """,
            params: [
                .init("project", required: true, summary: "Project id or name."),
                .init("refresh", type: "boolean", summary: "When true, rerun safe probes and refresh cache (absorbs project_recheck_workers)."),
            ],
            outputSchema: .projectWorkersJSON,
            errors: ["PROJECT_NOT_FOUND", "CLI_USAGE_ERROR"],
            idempotency: .idempotent,
            title: "Get project workers"
        ),
    ]
}
