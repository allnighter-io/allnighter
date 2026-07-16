import Foundation

/// The milestone-1 `alln` contract, transcribed from
/// docs/phases/CLI_Implementation_Contract.md (§Milestone Boundary, §CLI Grammar,
/// §NDJSON Stream, §Error Envelope, §Doctor Contract). This is the data; the
/// generators that project docs/schemas from it are step 3.
public extension ContractRegistry {
    static let contractVersion = "1.0.0"

    static let milestone1 = ContractRegistry(
        schemaVersion: 1,
        contractVersion: contractVersion,
        commands: m1Commands + deferredCommands,
        errors: m1Errors,
        doctorChecks: m1DoctorChecks,
        events: m1Events,
        nextActionKinds: m1NextActionKinds,
        examples: m1Examples
    )

    // MARK: - Commands (in scope)

    static let m1Commands: [CommandSpec] = [
        CommandSpec(
            "docs", summary: "Generated AI-facing command reference.", milestone: .m1,
            args: [ArgSpec("topic", required: false, summary: "Limit docs to one command family.")],
            flags: [
                FlagSpec("errors", summary: "Print the error/recovery table."),
                FlagSpec("schema", summary: "Print JSON/NDJSON schemas."),
                FlagSpec("examples", summary: "Print example recipes."),
            ],
            outputSchema: .contractDoc, exampleIds: ["docs_all"]
        ),
        CommandSpec(
            "doctor", summary: "Check sources, models, auth, and coordinator.", milestone: .m1,
            flags: [
                FlagSpec("json", summary: "Structured DoctorResult for agents/GUI."),
                FlagSpec("quiet", summary: "Failed checks only."),
                FlagSpec("full", summary: "Deeper probes, bounded timeout."),
                FlagSpec("auto-fix", summary: "Apply safe Allnighter-owned fixes."),
                FlagSpec("agent", takesValue: true, valueType: "sourceId", summary: "Limit probes and checks to one source (e.g. cursor_agent)."),
            ],
            outputSchema: .doctorResult, exampleIds: ["doctor_json"]
        ),
        CommandSpec(
            "doctor explain", summary: "Explain one failure/recovery code, bridged to the help topic that documents it.", milestone: .m1,
            args: [ArgSpec("code", required: true, summary: "Error code to explain.")],
            flags: [FlagSpec("json", summary: "Structured explanation (ErrorExplainJSON: the catalog row + helpRef + recovery plan).")],
            outputSchema: .errorExplainJSON,
            exampleIds: ["doctor_explain"]
        ),
        CommandSpec(
            "bootstrap", summary: "Print a paste-ready agent-activation snippet for a host's context file (never edits files).", milestone: .m1,
            flags: [
                FlagSpec("host", takesValue: true, valueType: "host", summary: "claude | cursor | codex | generic (default generic)."),
                FlagSpec("json", summary: "Structured { host, pasteTarget, snippet }."),
            ],
            outputSchema: .bootstrapJSON, exampleIds: ["bootstrap_json"]
        ),
        CommandSpec(
            "models", summary: "List model catalog and Bench state.", milestone: .m1,
            flags: [
                FlagSpec("json", summary: "Structured ModelListJSON."),
                FlagSpec("driver", takesValue: true, valueType: "driverId", summary: "Filter to one source."),
                FlagSpec("bench", summary: "Show only enabled Bench models."),
            ],
            outputSchema: .modelListJSON, exampleIds: ["models_json"]
        ),
        CommandSpec(
            "models enable", summary: "Enable a model on the Bench.", milestone: .m1,
            args: [ArgSpec("model-id", required: true, summary: "Model id to enable.")],
            flags: [FlagSpec("json", summary: "Return refreshed ModelListJSON.")],
            outputSchema: .modelListJSON
        ),
        CommandSpec(
            "models disable", summary: "Remove a model from the Bench.", milestone: .m1,
            args: [ArgSpec("model-id", required: true, summary: "Model id to disable.")],
            flags: [FlagSpec("json", summary: "Return refreshed ModelListJSON.")],
            outputSchema: .modelListJSON
        ),
        CommandSpec(
            "models add", summary: "Add a custom model for a source.", milestone: .m1,
            flags: [
                FlagSpec("driver", takesValue: true, valueType: "driverId", summary: "Source driver id."),
                FlagSpec("name", takesValue: true, valueType: "string", summary: "Display name."),
                FlagSpec("model-label", takesValue: true, valueType: "string", summary: "Label passed to the CLI."),
                FlagSpec("role", takesValue: true, valueType: "modelRole", summary: "answerer|planWriter|both (default answerer)."),
                FlagSpec("disabled", summary: "Create off-Bench."),
                FlagSpec("json", summary: "Return refreshed ModelListJSON."),
            ],
            outputSchema: .modelListJSON
        ),
        CommandSpec(
            "models update", summary: "Update a custom model definition.", milestone: .m1,
            args: [ArgSpec("model-id", required: true, summary: "Custom model id.")],
            flags: [
                FlagSpec("name", takesValue: true, valueType: "string", summary: "New display name."),
                FlagSpec("model-label", takesValue: true, valueType: "string", summary: "New CLI model label."),
                FlagSpec("role", takesValue: true, valueType: "modelRole", summary: "New role."),
                FlagSpec("json", summary: "Return refreshed ModelListJSON."),
            ],
            outputSchema: .modelListJSON
        ),
        CommandSpec(
            "models delete", summary: "Delete a custom model definition.", milestone: .m1,
            args: [ArgSpec("model-id", required: true, summary: "Custom model id.")],
            flags: [FlagSpec("json", summary: "Return refreshed ModelListJSON.")],
            outputSchema: .modelListJSON
        ),
        CommandSpec(
            "team show", summary: "Show the default team for each lane.", milestone: .m1,
            flags: [FlagSpec("lane", takesValue: true, valueType: "lane", summary: "Limit to one lane."),
                    FlagSpec("json", summary: "Structured team snapshot.")],
            exampleIds: ["team_show_json"]
        ),
        CommandSpec(
            "teams", summary: "List the lane-scoped team catalog.", milestone: .m1,
            flags: [FlagSpec("lane", takesValue: true, valueType: "lane", summary: "Filter to one lane."),
                    FlagSpec("all", summary: "Include inactive (switched-OFF) teams."),
                    FlagSpec("json", summary: "Structured catalog summary.")],
            outputSchema: .teamCatalogJSON, exampleIds: ["teams_code_json"]
        ),
        CommandSpec(
            "thread send", summary: "Send a message and/or images to a work thread.", milestone: .m1,
            args: [
                ArgSpec("thread-id", required: true, summary: "Thread id or `latest`."),
                ArgSpec("message", required: false, summary: "User message text."),
            ],
            flags: [
                FlagSpec("image", takesValue: true, valueType: "path", summary: "Attach an image (repeatable)."),
                FlagSpec("ref", takesValue: true, valueType: "path[:start-end]", summary: "Reference a project file or line range (repeatable)."),
                FlagSpec("worker", takesValue: true, valueType: "string", summary: "Requested worker/model id."),
                FlagSpec("idempotency-key", takesValue: true, valueType: "string", summary: "Idempotency key (24h)."),
                FlagSpec("json", summary: "Structured send result."),
            ],
            exampleIds: ["thread_send_json"]
        ),
        CommandSpec(
            "thread get", summary: "Fetch one work thread snapshot.", milestone: .m1,
            args: [ArgSpec("thread-id", required: true, summary: "Thread id or `latest`.")],
            flags: [FlagSpec("json", summary: "Structured thread JSON.")],
            outputSchema: .threadGetJSON,
            exampleIds: ["thread_get_json"]
        ),
        CommandSpec(
            "thread rename", summary: "Rename a work thread (same SSOT as the inbox double-click rename).", milestone: .m1,
            args: [ArgSpec("thread-id", required: true, summary: "Thread id or `latest`."),
                   ArgSpec("title", required: true, summary: "New non-empty thread title.")],
            flags: [FlagSpec("json", summary: "Structured thread JSON.")],
            outputSchema: .threadGetJSON,
            exampleIds: ["thread_rename_json"]
        ),
        CommandSpec(
            "thread attachment", summary: "Fetch one thread attachment by id.", milestone: .m1,
            args: [
                ArgSpec("thread-id", required: true, summary: "Thread id or `latest`."),
                ArgSpec("attachment-id", required: true, summary: "Attachment id."),
            ],
            flags: [FlagSpec("json", summary: "Structured attachment JSON.")],
            outputSchema: .threadAttachmentJSON
        ),
        CommandSpec(
            "thread status", summary: "Poll thread running/attention state.", milestone: .m1,
            args: [ArgSpec("thread-id", required: true, summary: "Thread id or `latest`.")],
            flags: [FlagSpec("json", summary: "Structured status JSON.")],
            outputSchema: .threadStatus, exampleIds: ["thread_status_json"]
        ),
        CommandSpec(
            "skills", summary: "List the lane-scoped skill catalog.", milestone: .m1,
            flags: [FlagSpec("lane", takesValue: true, valueType: "lane", summary: "Filter to one lane."),
                    FlagSpec("json", summary: "Structured catalog summary (no templates).")],
            outputSchema: .skillCatalogJSON, exampleIds: ["skills_code_json"]
        ),
        CommandSpec(
            "skills show", summary: "Show one skill definition including template.", milestone: .m1,
            args: [ArgSpec("skill-id", required: true, summary: "Skill id.")],
            flags: [FlagSpec("json", summary: "Structured skill detail.")],
            exampleIds: ["skills_show_json"]
        ),
        CommandSpec(
            "teams show", summary: "Show one team definition including worker rows.", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "Team id.")],
            flags: [FlagSpec("json", summary: "Structured team detail.")],
            exampleIds: ["teams_show_json"]
        ),
        CommandSpec(
            "teams definition", summary: "Full TeamPreset JSON round-trippable through teams edit/save.", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "Team id.")],
            flags: [FlagSpec("json", summary: "Structured team definition.")],
            exampleIds: ["teams_definition_json"]
        ),
        CommandSpec(
            "teams duplicate", summary: "Duplicate a built-in team into a custom team.", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "Source team id.")],
            flags: [FlagSpec("name", takesValue: true, valueType: "string", summary: "Display name for the copy."),
                    FlagSpec("json", summary: "Structured team detail.")],
            exampleIds: ["teams_duplicate_json"]
        ),
        CommandSpec(
            "teams edit", summary: "Edit a custom team definition (full replacement).", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "Team id.")],
            flags: [FlagSpec("file", takesValue: true, valueType: "path", summary: "TeamPreset JSON file."),
                    FlagSpec("json", summary: "Structured team detail.")],
            exampleIds: ["teams_edit_json"]
        ),
        CommandSpec(
            "teams set-default", summary: "Set the default team for a lane.", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "Team id.")],
            flags: [FlagSpec("json", summary: "Structured team detail.")],
            exampleIds: ["teams_set_default_json"]
        ),
        CommandSpec(
            "teams delete", summary: "Delete a custom team (or restore a built-in to shipped).", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "Team id.")],
            flags: [FlagSpec("json", summary: "Deletion acknowledgement JSON.")],
            exampleIds: ["teams_delete_json"]
        ),
        CommandSpec(
            "teams restore", summary: "Restore a built-in team to its shipped version (remove edits).", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "Team id.")],
            flags: [FlagSpec("json", summary: "Restore acknowledgement JSON.")],
            exampleIds: ["teams_restore_json"]
        ),
        CommandSpec(
            "skills duplicate", summary: "Duplicate a built-in skill into a custom skill.", milestone: .m1,
            args: [ArgSpec("skill-id", required: true, summary: "Source skill id.")],
            flags: [FlagSpec("name", takesValue: true, valueType: "string", summary: "Display name for the copy."),
                    FlagSpec("json", summary: "Structured skill detail.")],
            exampleIds: ["skills_duplicate_json"]
        ),
        CommandSpec(
            "skills new", summary: "Create a custom skill.", milestone: .m1,
            flags: [
                FlagSpec("lane", takesValue: true, valueType: "lane", summary: "build | design | copy."),
                FlagSpec("name", takesValue: true, valueType: "string", summary: "Display name."),
                FlagSpec("purpose", takesValue: true, valueType: "purpose", summary: "answer | review | planWriter."),
                FlagSpec("template-file", takesValue: true, valueType: "path", summary: "Skill template text file."),
                FlagSpec("json", summary: "Structured skill detail."),
            ],
            exampleIds: ["skills_new_json"]
        ),
        CommandSpec(
            "skills edit", summary: "Edit a custom skill definition.", milestone: .m1,
            args: [ArgSpec("skill-id", required: true, summary: "Skill id.")],
            flags: [
                FlagSpec("name", takesValue: true, valueType: "string", summary: "New display name."),
                FlagSpec("template-file", takesValue: true, valueType: "path", summary: "Replacement template file."),
                FlagSpec("json", summary: "Structured skill detail."),
            ],
            exampleIds: ["skills_edit_json"]
        ),
        CommandSpec(
            "skills delete", summary: "Delete a custom skill.", milestone: .m1,
            args: [ArgSpec("skill-id", required: true, summary: "Skill id.")],
            flags: [FlagSpec("json", summary: "Deletion acknowledgement JSON.")],
            exampleIds: ["skills_delete_json"]
        ),
        CommandSpec(
            "team hello", summary: "Agent bootstrap: readiness + ready teams + next action (quota-free).", milestone: .m1,
            outputSchema: .none
        ),
        CommandSpec(
            "team preflight", summary: "Validate lane/team/effort against the ready bench without running.", milestone: .m1,
            flags: [
                FlagSpec("lane", takesValue: true, valueType: "lane", summary: "build | design | copy."),
                FlagSpec("team", takesValue: true, valueType: "id", summary: "Team id."),
                FlagSpec("effort", takesValue: true, valueType: "effort", summary: "low | med | high."),
                FlagSpec("type", takesValue: true, valueType: "type", summary: "Copy-only routing sugar."),
            ]
        ),
        CommandSpec(
            "team start", summary: "Start a resumable/asynchronous team run.", milestone: .m1,
            args: [ArgSpec("prompt", required: false, summary: "The prompt (or use --file).")],
            flags: [
                FlagSpec("lane", takesValue: true, valueType: "lane", summary: "build | design | copy."),
                FlagSpec("team", takesValue: true, valueType: "id", summary: "Team id."),
                FlagSpec("effort", takesValue: true, valueType: "effort", summary: "low | med | high."),
                FlagSpec("type", takesValue: true, valueType: "type", summary: "Copy-only routing sugar."),
                FlagSpec("json", summary: "Structured TeamStartResponse."),
                FlagSpec("idempotency-key", takesValue: true, valueType: "id", summary: "Client idempotency key."),
                FlagSpec("conversation-id", takesValue: true, valueType: "id", summary: "Origin conversation id."),
                FlagSpec("message-id", takesValue: true, valueType: "id", summary: "Origin message id."),
                FlagSpec("thread-id", takesValue: true, valueType: "id", summary: "Owning work thread id."),
            ],
            outputSchema: .teamStartResponse,
            exampleIds: ["team_start_json"]
        ),
        CommandSpec(
            "team status", summary: "Poll live state for an async team run.", milestone: .m1,
            args: [ArgSpec("run-id", required: true, summary: "The run id from team start.")],
            flags: [FlagSpec("json", summary: "Structured TeamStatusResponse.")],
            outputSchema: .teamStatusResponse
        ),
        CommandSpec(
            "team result", summary: "Fetch TeamRunJSON when an async run is terminal.", milestone: .m1,
            args: [ArgSpec("run-id", required: true, summary: "The run id from team start.")],
            flags: [FlagSpec("json", summary: "TeamRunJSON or not-ready envelope.")],
            outputSchema: .teamRunJSON
        ),
        CommandSpec(
            "team cancel", summary: "Cancel an active async team run.", milestone: .m1,
            args: [ArgSpec("run-id", required: true, summary: "The run id from team start.")],
            flags: [FlagSpec("json", summary: "Structured TeamCancelResponse.")],
            outputSchema: .teamCancelResponse
        ),
        CommandSpec(
            "run", summary: "Unified run: message + optional team + worker in a project repo root.", milestone: .m1,
            args: [ArgSpec("message", required: true, summary: "The user's prompt.")],
            flags: [
                FlagSpec("project", takesValue: true, valueType: "id", summary: "Project id, name, or repo path (required)."),
                FlagSpec("team", takesValue: true, valueType: "id", summary: "Team preset id; omit for Default Team."),
                FlagSpec("worker", takesValue: true, valueType: "id", summary: "Override worker model id."),
                FlagSpec("effort", takesValue: true, valueType: "effort", summary: "low | med | high."),
                FlagSpec("lane", takesValue: true, valueType: "lane", summary: "code | design | copy | signal."),
                FlagSpec("type", takesValue: true, valueType: "type", summary: "Copy routing sugar."),
                FlagSpec("context", takesValue: true, valueType: "string", summary: "Bounded context snippet."),
                FlagSpec("json", summary: "Emit TeamRunJSON."),
                FlagSpec("stream", summary: "Emit NDJSON events."),
            ],
            mutuallyExclusiveFlags: [["json", "stream"]],
            outputSchema: .teamRunJSON
        ),
        CommandSpec(
            "pair relay", summary: "Run the PM Relay unattended: a PM seat reviews the repo and a dev seat builds, round after round, until done/escalate/a ceiling.", milestone: .m1,
            flags: [
                FlagSpec("doc", takesValue: true, valueType: "path", summary: "Repo-relative spec doc path (required) — the PM re-reads it fresh each round."),
                FlagSpec("project", takesValue: true, valueType: "id", summary: "Project id, name, or repo path (required)."),
                FlagSpec("pm-worker", takesValue: true, valueType: "id", summary: "PM seat model id (required)."),
                FlagSpec("dev-worker", takesValue: true, valueType: "id", summary: "Dev seat model id (required)."),
                FlagSpec("until", takesValue: true, valueType: "time", summary: "Hard stop HH:MM (local)."),
                FlagSpec("max-rounds", takesValue: true, valueType: "integer", summary: "Round ceiling (default 20)."),
                FlagSpec("json", summary: "Emit NDJSON RelayProgressJSON events, then a final RelayJSON envelope."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair relay-status", summary: "Read a PM Relay's durable state — rounds, verdicts, gate decisions.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("json", summary: "Emit RelayJSON."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair relay-resume", summary: "Resume an escalated PM Relay with the founder's answer, then continue the loop.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("answer", takesValue: true, valueType: "string", summary: "The founder's answer to the escalation (required)."),
                FlagSpec("until", takesValue: true, valueType: "time", summary: "Hard stop HH:MM (local) for the resumed stretch."),
                FlagSpec("max-rounds", takesValue: true, valueType: "integer", summary: "Round ceiling for the resumed stretch (default 20)."),
                FlagSpec("json", summary: "Emit NDJSON RelayProgressJSON events, then a final RelayJSON envelope."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair relay adopt", summary: "Night-shift handover: converts a parked Pilot relay (awaitingPM or escalated) to a spawned PM relay and continues the loop from the durable round log.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("pm-worker", takesValue: true, valueType: "id", summary: "The spawned PM seat's model id (required)."),
                FlagSpec("max-rounds", takesValue: true, valueType: "integer", summary: "Round ceiling for the adopted stretch — counts TOTAL rounds including the piloted ones already on the log (default 20)."),
                FlagSpec("until", takesValue: true, valueType: "time", summary: "Hard stop HH:MM (local) for the adopted stretch."),
                FlagSpec("json", summary: "Emit NDJSON RelayProgressJSON events, then a final RelayJSON envelope."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair pilot start", summary: "Start a Pilot relay: this session is the PM, Allnighter runs the crew (dev seat + rails). Parks awaitingPM.", milestone: .m1,
            flags: [
                FlagSpec("doc", takesValue: true, valueType: "path", summary: "Repo-relative spec doc path (required) — the piloting session re-reads it fresh each round."),
                FlagSpec("project", takesValue: true, valueType: "id", summary: "Project id, name, or repo path (required)."),
                FlagSpec("dev-worker", takesValue: true, valueType: "id", summary: "Dev seat model id (required)."),
                FlagSpec("max-rounds", takesValue: true, valueType: "integer", summary: "Round ceiling, set once here — Pilot has no long-lived process to re-supply it per handoff (default 20)."),
                FlagSpec("json", summary: "Emit RelayJSON."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair pilot handoff", summary: "Submit this round's review (RelayVerdict tail or --verdict + handover file); blocks through the dev turn by default and prints the dev's report verbatim.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("file", takesValue: true, valueType: "path", summary: "Read the full submission markdown from a file (verdict tail included; omit to read stdin)."),
                FlagSpec("verdict", takesValue: true, valueType: "continue|done|escalate", summary: "Required with --handover-file/--handover-stdin; synthesizes the RelayVerdict tail internally."),
                FlagSpec("handover-file", takesValue: true, valueType: "path", summary: "Raw order markdown for the dev seat (mutually exclusive with --file)."),
                FlagSpec("handover-stdin", summary: "Read the handover markdown from stdin (mutually exclusive with --file)."),
                FlagSpec("note", takesValue: true, valueType: "string", summary: "Optional closing note for done/escalate verdicts."),
                FlagSpec("no-wait", summary: "Return immediately after dispatch instead of blocking through the dev turn."),
                FlagSpec("json", summary: "Emit RelayJSON (+ devReport when the dev turn delivered in this call)."),
            ],
            mutuallyExclusiveFlags: [["file", "handover-file"], ["file", "handover-stdin"], ["handover-file", "handover-stdin"]],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair pilot status", summary: "Read a Pilot relay's durable state — rounds, verdicts, gate decisions, dirty-tree snapshots.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("json", summary: "Emit RelayJSON."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair pilot watch", summary: "Poll a Pilot relay until its in-flight round settles back to awaitingPM (or a terminal status).", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("json", summary: "Emit RelayJSON."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair pilot adopt", summary: "Reverse flip: hands a parked spawned relay's PM seat to a piloting session (pmMode → external, status → awaitingPM). No dispatch.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("json", summary: "Emit RelayJSON."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "team", summary: "Run a lane team on a prompt, foreground.", milestone: .m1,
            args: [ArgSpec("prompt", required: false, summary: "The prompt (or use --file).")],
            flags: [
                FlagSpec("file", takesValue: true, valueType: "path", summary: "Read the prompt from a file."),
                FlagSpec("lane", takesValue: true, valueType: "lane", summary: "code | design | copy | signal."),
                FlagSpec("team", takesValue: true, valueType: "id", summary: "Team id (the public team selector)."),
                FlagSpec("type", takesValue: true, valueType: "type", summary: "Copy-only routing sugar."),
                FlagSpec("effort", takesValue: true, valueType: "effort", summary: "low | med | high."),
                FlagSpec("json", summary: "Emit one TeamRunJSON object."),
                FlagSpec("stream", summary: "Emit NDJSON events."),
            ],
            mutuallyExclusiveFlags: [["json", "stream"]],
            outputSchema: .teamRunJSON, exampleIds: ["team_basic", "team_json", "team_stream"]
        ),
        CommandSpec(
            "show", summary: "Show one run.", milestone: .m1,
            args: [ArgSpec("run-id|latest", required: true, summary: "A run id or `latest`.")],
            flags: [FlagSpec("json", summary: "Emit the run as TeamRunJSON."),
                    FlagSpec("full", summary: "Include resolved worker prompt snapshots (audit).")],
            outputSchema: .teamRunJSON, exampleIds: ["show_latest_json"]
        ),
        CommandSpec(
            "floor show", summary: "Show the inspectable Floor for one team run (worker lanes, artifacts, typed return, timeline, Execute requirements).", milestone: .m1,
            args: [ArgSpec("run-id|latest", required: false, summary: "A run id or `latest` (default latest).")],
            flags: [FlagSpec("json", summary: "Emit the FloorRun projection.")],
            outputSchema: .floorRun
        ),
        CommandSpec(
            "spec", summary: "Retrieve a run's spec/result packet (summary|full|artifactRefsOnly).", milestone: .m1,
            args: [ArgSpec("run-id|latest", required: false, summary: "A run id or `latest` (default latest).")],
            flags: [FlagSpec("detail", takesValue: true, valueType: "detail", defaultValue: "summary", summary: "summary | full | artifactRefsOnly."),
                    FlagSpec("json", summary: "Structured SpecRetrieval result.")],
            outputSchema: .specResult, exampleIds: ["spec_full"]
        ),
        CommandSpec(
            "export", summary: "Export a result bundle.", milestone: .m1,
            args: [ArgSpec("run-id|latest", required: true, summary: "A run id or `latest`.")],
            flags: [FlagSpec("format", takesValue: true, valueType: "format", defaultValue: "md", summary: "Export format (md).")],
            outputSchema: .markdown, exampleIds: ["export_md"]
        ),
        CommandSpec(
            "history", summary: "Search prior team runs (read-only).", milestone: .m1,
            args: [ArgSpec("query", required: true, summary: "Search text.")],
            flags: [FlagSpec("json", summary: "Structured results.")],
            outputSchema: .historyJSON
        ),
        CommandSpec(
            "dev export-contracts", summary: "Regenerate or verify generated artifacts.", milestone: .m1,
            flags: [FlagSpec("check", summary: "Fail when generated output drifts from the registry.")],
            exampleIds: ["export_contracts_check"]
        ),
        CommandSpec(
            "serve", summary: "Resident Mac coordinator (foreground skeleton).", milestone: .m1,
            flags: [
                FlagSpec("health", summary: "Read-only coordinator health; does not start serve."),
                FlagSpec("json", summary: "Structured CoordinatorHealth output."),
            ],
            outputSchema: .coordinatorHealth,
            exampleIds: ["serve_health_json"]
        ),
        CommandSpec(
            "pending add", summary: "Create a Draft Pending item.", milestone: .m1,
            args: [ArgSpec("prompt", required: false, summary: "Work prompt (or use --file).")],
            flags: [
                FlagSpec("file", takesValue: true, valueType: "path", summary: "Read prompt from a file."),
                FlagSpec("worker", takesValue: true, valueType: "id", summary: "Target worker model id."),
                FlagSpec("team", takesValue: true, valueType: "id", summary: "Team preset id."),
                FlagSpec("fallback", takesValue: true, valueType: "id", summary: "Fallback worker id."),
                FlagSpec("when", takesValue: true, valueType: "when", summary: "ready | away | manual."),
                FlagSpec("cwd", takesValue: true, valueType: "path", summary: "Working directory context."),
                FlagSpec("submit", summary: "Create directly as Pending."),
                FlagSpec("json", summary: "Emit one PendingItemJSON object."),
            ],
            outputSchema: .pendingItemJSON,
            exampleIds: ["pending_add_json"]
        ),
        CommandSpec(
            "pending list", summary: "List Pending items.", milestone: .m1,
            flags: [FlagSpec("json", summary: "Structured PendingListJSON.")],
            outputSchema: .pendingListJSON,
            exampleIds: ["pending_list_json"]
        ),
        CommandSpec(
            "pending queue", summary: "Render-ready Pending queue (armed items grouped by project, in order, headed by the running item) + total armed count for the pending pill.", milestone: .m1,
            flags: [FlagSpec("json", summary: "Emit a PendingQueueJSON object.")],
            outputSchema: .pendingQueueJSON
        ),
        CommandSpec(
            "pending show", summary: "Show one Pending item.", milestone: .m1,
            args: [ArgSpec("pending-id", required: true, summary: "Pending item id.")],
            flags: [FlagSpec("json", summary: "Emit one PendingItemJSON object.")],
            outputSchema: .pendingItemJSON
        ),
        CommandSpec(
            "pending submit", summary: "Move a Draft item to Pending.", milestone: .m1,
            args: [ArgSpec("pending-id", required: true, summary: "Pending item id.")],
            flags: [FlagSpec("json", summary: "Emit one PendingItemJSON object.")],
            outputSchema: .pendingItemJSON
        ),
        CommandSpec(
            "pending edit", summary: "Edit a Pending item (Pending returns to Draft).", milestone: .m1,
            args: [ArgSpec("pending-id", required: true, summary: "Pending item id.")],
            flags: [
                FlagSpec("prompt", takesValue: true, valueType: "string", summary: "Replacement prompt text."),
                FlagSpec("file", takesValue: true, valueType: "path", summary: "Replacement prompt file."),
                FlagSpec("worker", takesValue: true, valueType: "id", summary: "Target worker model id."),
                FlagSpec("team", takesValue: true, valueType: "id", summary: "Team preset id."),
                FlagSpec("fallback", takesValue: true, valueType: "id", summary: "Fallback worker id."),
                FlagSpec("when", takesValue: true, valueType: "when", summary: "ready | away | manual."),
                FlagSpec("cwd", takesValue: true, valueType: "path", summary: "Working directory context."),
                FlagSpec("json", summary: "Emit one PendingItemJSON object."),
            ],
            outputSchema: .pendingItemJSON
        ),
        CommandSpec(
            "pending reorder", summary: "Reorder Pending items.", milestone: .m1,
            args: [ArgSpec("pending-id", required: true, summary: "Item to move.")],
            flags: [
                FlagSpec("before", takesValue: true, valueType: "id", summary: "Move before another item."),
                FlagSpec("after", takesValue: true, valueType: "id", summary: "Move after another item."),
                FlagSpec("position", takesValue: true, valueType: "integer", summary: "Move to zero-based position."),
                FlagSpec("json", summary: "Emit one PendingItemJSON object."),
            ],
            outputSchema: .pendingItemJSON
        ),
        CommandSpec(
            "pending cancel", summary: "Cancel a Draft or Pending item.", milestone: .m1,
            args: [ArgSpec("pending-id", required: true, summary: "Pending item id.")],
            flags: [FlagSpec("json", summary: "Emit one PendingItemJSON object.")],
            outputSchema: .pendingItemJSON
        ),
        CommandSpec(
            "pending run", summary: "Run a Pending item now (manual attempt; no drain).", milestone: .m1,
            args: [ArgSpec("pending-id", required: true, summary: "Pending item id.")],
            flags: [
                FlagSpec("json", summary: "Emit one PendingItemJSON object."),
                FlagSpec("stream", summary: "NDJSON attempt events (deferred until async attempts)."),
            ],
            mutuallyExclusiveFlags: [["json", "stream"]],
            outputSchema: .pendingItemJSON
        ),
        // Project foundation (PRJ-S07). list/add/show/archive the local work
        // floors and read the threads/pending/context bound to one.
        CommandSpec(
            "project list", summary: "List projects (active by default; --all includes archived).", milestone: .m1,
            flags: [FlagSpec("all", summary: "Include archived projects."), FlagSpec("json", summary: "Emit a ProjectListJSON object.")],
            outputSchema: .projectListJSON
        ),
        CommandSpec(
            "project add", summary: "Add (or return the existing) project for a local root. Idempotent on normalized root.", milestone: .m1,
            args: [ArgSpec("path", required: true, summary: "Local folder / git repo root.")],
            flags: [FlagSpec("name", takesValue: true, valueType: "string", summary: "Display name (defaults to the folder name)."), FlagSpec("json", summary: "Emit a ProjectJSON object.")],
            outputSchema: .projectJSON
        ),
        CommandSpec(
            "project show", summary: "Show one project; re-observes root/git so output reflects current truth.", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectJSON object.")],
            outputSchema: .projectJSON
        ),
        CommandSpec(
            "project archive", summary: "Archive a project (hides it; never deletes local files or threads).", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectJSON object.")],
            outputSchema: .projectJSON
        ),
        CommandSpec(
            "project unarchive", summary: "Restore an archived project to the active roster.", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectJSON object.")],
            outputSchema: .projectJSON
        ),
        CommandSpec(
            "project threads", summary: "List the work threads bound to one project.", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectThreadsJSON object.")],
            outputSchema: .projectThreadsJSON
        ),
        CommandSpec(
            "project pending", summary: "List the pending work bound to one project (a filtered view of the one Pending store).", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectPendingJSON object.")],
            outputSchema: .projectPendingJSON
        ),
        CommandSpec(
            "project stalled", summary: "Read-only stalled-work episodes for one project.", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [
                FlagSpec("json", summary: "Emit a StallEpisodeListJSON object."),
                FlagSpec("include-cleared", summary: "Include cleared episodes."),
            ],
            outputSchema: .stallEpisodeListJSON
        ),
        CommandSpec(
            "stalled list", summary: "Aggregate stalled-work episodes grouped by project.", milestone: .m1,
            flags: [
                FlagSpec("all", summary: "Include all projects (required)."),
                FlagSpec("json", summary: "Emit a StallListJSON object."),
            ],
            outputSchema: .stallListJSON
        ),
        CommandSpec(
            "stalled check", summary: "Re-observe a stall episode's target; clears it if it progressed/terminated.", milestone: .m1,
            args: [ArgSpec("episode-id", required: true, summary: "Stall episode id.")],
            flags: [FlagSpec("json", summary: "Emit a StallEpisodeJSON object.")],
            outputSchema: .stallEpisodeJSON
        ),
        CommandSpec(
            "stalled wait", summary: "Snooze a stall episode's attention for N minutes (default 30).", milestone: .m1,
            args: [ArgSpec("episode-id", required: true, summary: "Stall episode id.")],
            flags: [
                FlagSpec("minutes", takesValue: true, valueType: "int", defaultValue: "30", summary: "Snooze minutes."),
                FlagSpec("json", summary: "Emit a StallEpisodeJSON object."),
            ],
            outputSchema: .stallEpisodeJSON
        ),
        CommandSpec(
            "stalled dismiss", summary: "Dismiss a stall episode (cleared, user-dismiss). Re-surfaces on the next scan if still stalled.", milestone: .m1,
            args: [ArgSpec("episode-id", required: true, summary: "Stall episode id.")],
            flags: [FlagSpec("json", summary: "Emit a StallEpisodeJSON object.")],
            outputSchema: .stallEpisodeJSON
        ),
        CommandSpec(
            "project context", summary: "Generate the on-demand, source-labeled context packet for a project (a receipt, never durable truth).", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectContextJSON object.")],
            outputSchema: .projectContextJSON
        ),
        CommandSpec(
            "project workers", summary: "Show cached per-project worker readiness (read-only; never probes).", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectWorkersJSON object.")],
            outputSchema: .projectWorkersJSON
        ),
        CommandSpec(
            "project recheck-workers", summary: "Rerun driver-declared safe probes for a project and refresh the readiness cache. No auto-config/auth.", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectWorkersJSON object.")],
            outputSchema: .projectWorkersJSON
        ),
        // Default model & Substitutions — the Auto tier, the per-tier rosters
        // (many-to-many membership), and the healthy-substitution toggle. Every
        // command returns the whole DefaultSettingsJSON (with live readiness) so a
        // caller always gets the resolved truth back.
        CommandSpec(
            "defaults show", summary: "Show the Default model: Auto's tier, the per-tier rosters, the unassigned shelf, and what Auto resolves to right now.", milestone: .m1,
            flags: [FlagSpec("json", summary: "Emit a DefaultSettingsJSON object.")],
            outputSchema: .defaultSettingsJSON
        ),
        CommandSpec(
            "defaults tier", summary: "Set which tier Auto draws from (flagship|balanced|fast).", milestone: .m1,
            args: [ArgSpec("tier", required: true, summary: "flagship | balanced | fast.")],
            flags: [FlagSpec("json", summary: "Emit a DefaultSettingsJSON object.")],
            outputSchema: .defaultSettingsJSON
        ),
        CommandSpec(
            "defaults assign", summary: "Add a model to a tier (or move it within that tier). Membership is many-to-many — assigning to one tier never removes it from another.", milestone: .m1,
            args: [ArgSpec("model", required: true, summary: "Model id (see `alln models --json`).")],
            flags: [
                FlagSpec("tier", takesValue: true, valueType: "tier", summary: "flagship | balanced | fast (required)."),
                FlagSpec("default", summary: "Place at the top of the tier (make it that tier's default)."),
                FlagSpec("position", takesValue: true, valueType: "int", summary: "0-based index within the tier (default: append)."),
                FlagSpec("json", summary: "Emit a DefaultSettingsJSON object."),
            ],
            mutuallyExclusiveFlags: [["default", "position"]],
            outputSchema: .defaultSettingsJSON
        ),
        CommandSpec(
            "defaults unassign", summary: "Remove a model from one tier (--tier) or from all tiers (default). Removing from every tier benches it from Auto & substitution.", milestone: .m1,
            args: [ArgSpec("model", required: true, summary: "Model id.")],
            flags: [
                FlagSpec("tier", takesValue: true, valueType: "tier", summary: "Limit removal to one tier; omit to remove from all."),
                FlagSpec("json", summary: "Emit a DefaultSettingsJSON object."),
            ],
            outputSchema: .defaultSettingsJSON
        ),
        CommandSpec(
            "defaults substitutions", summary: "Turn healthy substitutions on or off. ON: a down model falls back to a ready model on the same tier. OFF: Auto uses only the tier default and waits if it's down.", milestone: .m1,
            args: [ArgSpec("state", required: true, summary: "on | off.")],
            flags: [FlagSpec("json", summary: "Emit a DefaultSettingsJSON object.")],
            outputSchema: .defaultSettingsJSON
        ),
        CommandSpec(
            "defaults reset", summary: "Restore the fresh-install tier seed and substitutions ON.", milestone: .m1,
            flags: [FlagSpec("json", summary: "Emit a DefaultSettingsJSON object.")],
            outputSchema: .defaultSettingsJSON
        ),
        // Boost window — rolling-bucket seed placement (Utilization_Window_Priming).
        CommandSpec(
            "boost-window show", summary: "Show Boost window settings, derived seed/reset times, provider rows, and display state.", milestone: .m1,
            flags: [FlagSpec("json", summary: "Emit a BoostWindowSettingsJSON object.")],
            outputSchema: .boostWindowSettingsJSON
        ),
        CommandSpec(
            "boost-window set", summary: "Set Boost window master toggle, 5h window start, and applies-to sources.", milestone: .m1,
            flags: [
                FlagSpec("enabled", takesValue: true, valueType: "bool", summary: "true | false."),
                FlagSpec("window-start", takesValue: true, valueType: "time", summary: "HH:MM (snapped to 15m)."),
                FlagSpec("applies-to", takesValue: true, valueType: "string", summary: "Comma-separated source ids."),
                FlagSpec("json", summary: "Emit a BoostWindowSettingsJSON object."),
            ],
            outputSchema: .boostWindowSettingsJSON
        ),
        CommandSpec(
            "boost-window seed", summary: "Force one Boost window seed for a configured source.", milestone: .m1,
            args: [ArgSpec("source-id", required: true, summary: "Driver id (e.g. claude_code, codex).")],
            flags: [FlagSpec("json", summary: "Emit a UtilizationSeedEvent object.")],
            outputSchema: .utilizationSeedEventJSON
        ),
        CommandSpec(
            "boost-window observations clear", summary: "Clear local Boost window seed observations.", milestone: .m1,
            flags: [
                FlagSpec("source", takesValue: true, valueType: "sourceId", summary: "Limit clear to one source."),
                FlagSpec("json", summary: "Emit a UtilizationObservationsClearJSON object."),
            ],
            outputSchema: .utilizationObservationsClearJSON
        ),
        // Help System — the installed product guide. `alln help` answers usage; `alln
        // docs` stays the raw generated contract reference.
        CommandSpec(
            "help search", summary: "Search the installed help for a product question; returns ranked topics, a suggested answer, and a next-tool plan.", milestone: .m1,
            args: [ArgSpec("query", required: true, summary: "Natural-language question or keywords.")],
            flags: [
                FlagSpec("limit", takesValue: true, valueType: "int", defaultValue: "5", summary: "Max results."),
                FlagSpec("json", summary: "Emit a HelpSearchJSON object."),
            ],
            outputSchema: .helpSearchJSON
        ),
        CommandSpec(
            "help get", summary: "Retrieve one help topic by id, alln:// ref, --tool, or --error. Unknown selectors return close matches + the sitemap.", milestone: .m1,
            args: [ArgSpec("topic", required: false, summary: "Topic id or alln:// ref (omit when using --ref/--tool/--error).")],
            flags: [
                FlagSpec("ref", takesValue: true, valueType: "string", summary: "An alln:// ref (help/tool/schema/error)."),
                FlagSpec("tool", takesValue: true, valueType: "string", summary: "Find the topic that documents this tool/action id."),
                FlagSpec("error", takesValue: true, valueType: "string", summary: "Find the topic for this error code."),
                FlagSpec("format", takesValue: true, valueType: "format", defaultValue: "json", summary: "json | md."),
                FlagSpec("json", summary: "Emit a HelpGetJSON object."),
            ],
            mutuallyExclusiveFlags: [["tool", "error"]],
            outputSchema: .helpGetJSON
        ),
        CommandSpec(
            "help topics", summary: "List the installed help topic sitemap + the help-first routing law.", milestone: .m1,
            flags: [FlagSpec("json", summary: "Emit a HelpTopicsJSON object.")],
            outputSchema: .helpTopicsJSON
        ),
    ]

    // MARK: - Commands (named but deferred past M1)

    static let deferredCommands: [CommandSpec] = [
        CommandSpec("pending stop", summary: "Stop a running Pending item.", milestone: .deferred),
        CommandSpec("pair", summary: "Approve iOS/Mac pairing.", milestone: .deferred),
    ]

    // MARK: - Error catalog

    static let m1Errors: [ErrorSpec] = [
        ErrorSpec("CLI_USAGE_ERROR", ruleId: "cli.usage.error", agentAction: "Re-run `alln docs <command>` and fix arguments.", requiresManual: true, retryable: false, explain: "The command was called with invalid or conflicting arguments. Consult the generated docs for the command and correct the invocation.", exitClass: .usage),
        ErrorSpec("CONTRACT_DRIFT", ruleId: "contract.drift", agentAction: "Run `alln dev export-contracts`, then rebuild.", requiresManual: true, retryable: false, explain: "Generated artifacts no longer match the registry. Regenerate and rebuild before relying on output."),
        ErrorSpec("DEFAULTS_TIER_INVALID", ruleId: "defaults.tier.invalid", agentAction: "Use one of flagship | balanced | fast.", requiresManual: true, retryable: false, explain: "The tier name was not one of flagship, balanced, or fast.", exitClass: .usage),
        ErrorSpec("DEFAULTS_MODEL_UNKNOWN", ruleId: "defaults.model.unknown", agentAction: "Run `alln models --json` and pass a known model id.", requiresManual: true, retryable: false, explain: "The model id is not in the catalog, so it cannot be assigned to a tier. List models and use a real id."),
        ErrorSpec("STALL_EPISODE_NOT_FOUND", ruleId: "stall.episode.not_found", agentAction: "Run `alln stalled list --all --json` and use a current episode id.", requiresManual: false, retryable: false, explain: "No stall episode matches the given id (it may have cleared). List stalled work and retry with a live episode id."),
        ErrorSpec("DOCTOR_CHECK_FAILED", ruleId: "doctor.check.failed", agentAction: "Run `alln doctor --json`.", requiresManual: false, retryable: true, explain: "A required doctor check failed. Inspect the structured report and address the named check, then retry."),
        ErrorSpec("SOURCE_NOT_FOUND", ruleId: "source.not_found", agentAction: "Run `alln doctor --json`; add/configure the missing source.", requiresManual: true, retryable: false, explain: "A required source CLI/runtime was not resolved on this machine. Install or locate it, then re-probe."),
        ErrorSpec("SOURCE_AUTH_EXPIRED", ruleId: "source.auth.expired", agentAction: "Re-authenticate the named source.", requiresManual: true, retryable: false, explain: "The source resolved but its authentication is invalid or expired. Sign in via the source's own login flow."),
        ErrorSpec("SOURCE_KEYCHAIN_UNAVAILABLE", ruleId: "source.auth.keychain", agentAction: "Open the provider app once, run its login command in Terminal, then `alln doctor --full --agent <source>`.", requiresManual: true, retryable: true, explain: "The source CLI could not read credentials from the macOS Keychain (SecItemCopyMatching failed). Common when Allnighter or the CLI is launched outside Terminal. Open the provider app, complete sign-in, then re-probe."),
        ErrorSpec("MODEL_UNAVAILABLE", ruleId: "model.unavailable", agentAction: "Run `alln models --json`; pick an on-Bench ready model or enable one.", requiresManual: false, retryable: true, explain: "The requested model is not runnable: it may be off-Bench, its source may not be ready, or it may not exist. Use `alln models --json` to see available vs on-Bench vs ready state."),
        ErrorSpec("DEFAULT_TEAM_INVALID", ruleId: "team.default.invalid", agentAction: "Run `alln team show --json`; fix unavailable workers.", requiresManual: true, retryable: false, explain: "The default team has no runnable workers. Inspect and repair the team lineup before running."),
        ErrorSpec("WORKER_FAILED", ruleId: "worker.failed", agentAction: "Inspect `workerId` and source error; failed worker remains visible.", requiresManual: false, retryable: true, explain: "One worker failed. The failure is shown, never hidden; other workers may still have answered. Retry the worker or proceed with partial results."),
        ErrorSpec("PLAN_WRITER_FAILED", ruleId: "plan_writer.failed", agentAction: "Retry with a ready plan writer or export worker answers.", requiresManual: false, retryable: true, explain: "The plan-writer stage failed. Retry with a ready plan writer, or export the worker answers and synthesize later."),
        ErrorSpec("TEAM_RUN_TIMEOUT", ruleId: "team.run.timeout", agentAction: "Retry with lower effort or fewer workers.", requiresManual: false, retryable: true, explain: "The team run exceeded its time budget. Reduce effort or the worker count and retry."),
        ErrorSpec("TEAM_RUN_FAILED", ruleId: "team.run.failed", agentAction: "Inspect failed workers and stages; retry or adjust the team.", requiresManual: false, retryable: true, explain: "The team run ended without a usable result (e.g. failed or cancelled). Inspect the failed workers/stages in the run, then retry or change the team."),
        ErrorSpec("NESTED_TEAM_BLOCKED", ruleId: "team.nested.blocked", agentAction: "Do not recursively spawn teams without explicit depth budget.", requiresManual: true, retryable: false, explain: "A worker tried to start another team run beyond the allowed depth. Set an explicit depth budget if nesting is intended."),
        ErrorSpec("TEAM_GOVERNOR_BUSY", ruleId: "team.governor.busy", agentAction: "Wait or retry after current team run completes.", requiresManual: false, retryable: true, explain: "The concurrency governor is at capacity. Wait for a slot and retry; this is a real busy state, not a fake queue."),
        ErrorSpec("TEAM_GOVERNOR_UNAVAILABLE", ruleId: "team.governor.unavailable", agentAction: "Run `alln doctor --json`; ensure Allnighter's support directory is writable, or set a writable support root for eval runs.", requiresManual: true, retryable: true, explain: "The team-run governor could not create, open, or lock its slot store. This is a storage/permission/configuration problem, not a capacity limit."),
        ErrorSpec("PENDING_MUTATION_DEFERRED", ruleId: "pending.mutation.deferred", agentAction: "Keep item Draft/Pending; mutating pending runs are outside Pending M1.", requiresManual: true, retryable: false, explain: "Mutating pending runs are not enabled in this milestone. Keep the item Draft/Pending."),
        ErrorSpec("PENDING_REORDER_INVALID", ruleId: "pending.reorder.invalid", agentAction: "Keep order unchanged; reorder only Pending items in the same serialized group.", requiresManual: true, retryable: false, explain: "The requested Pending reorder was rejected because the item and anchor do not share the same serialized group."),
        ErrorSpec("IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD", ruleId: "idempotency.key.reused", agentAction: "Generate a new key or reuse the original payload.", requiresManual: false, retryable: false, explain: "The same idempotency key was reused with a different canonical payload. Use a new key or repeat the original request."),
        ErrorSpec("RESULT_NOT_READY", ruleId: "result.not_ready", agentAction: "Poll team status using nextPollAfterMs, then call team result again.", requiresManual: false, retryable: true, explain: "The run is not terminal yet. Poll team status and retry team result when resultAvailable is true."),
        ErrorSpec("RUN_NOT_FOUND", ruleId: "run.not_found", agentAction: "Run `alln history --json`.", requiresManual: true, retryable: false, explain: "No run matches the given id. List history and pick a valid run id or `latest`."),
        ErrorSpec("COORDINATOR_UNAVAILABLE", ruleId: "coordinator.unavailable", agentAction: "Use foreground CLI or start resident mode when available.", requiresManual: false, retryable: true, explain: "The resident coordinator is not running. Use a foreground command, or start resident mode when it is available."),
        ErrorSpec("SKILL_NOT_FOUND", ruleId: "skill.not_found", agentAction: "Run `alln skills --lane <lane> --json` and pick a valid skill id.", requiresManual: true, retryable: false, explain: "No skill matches the given id. List skills for the lane and retry with a valid SkillID."),
        ErrorSpec("TEAM_NOT_FOUND", ruleId: "team.not_found", agentAction: "Run `alln teams --lane <lane> --json` and pick a valid team id.", requiresManual: true, retryable: false, explain: "No team matches the given id. List teams for the lane and retry with a valid TeamID."),
        ErrorSpec("TEAM_BUILTIN_IMMUTABLE", ruleId: "team.builtin.immutable", agentAction: "Edit the team with `teams edit` instead; only delete an edited built-in (which restores the shipped version).", requiresManual: true, retryable: false, explain: "A built-in team that was never edited has nothing to delete. Edit it in place with `teams edit`, or use `teams restore` to revert prior edits."),
        ErrorSpec("TEAM_RESTORE_UNSUPPORTED", ruleId: "team.restore.unsupported", agentAction: "Only built-in teams can be restored; for a custom team, edit or delete it instead.", requiresManual: true, retryable: false, explain: "Restore reverts a built-in team to its shipped version. A custom team has no shipped version to restore to."),
        ErrorSpec("SKILL_BUILTIN_IMMUTABLE", ruleId: "skill.builtin.immutable", agentAction: "Duplicate the built-in skill, then edit the custom copy.", requiresManual: true, retryable: false, explain: "Built-in skills cannot be edited or deleted. Duplicate to a custom skill and edit that copy."),
        ErrorSpec("TEAM_ID_COLLISION", ruleId: "team.id.collision", agentAction: "Pick a different team id or delete the conflicting custom team.", requiresManual: true, retryable: false, explain: "A team with this id already exists."),
        ErrorSpec("SKILL_ID_COLLISION", ruleId: "skill.id.collision", agentAction: "Pick a different skill id or delete the conflicting custom skill.", requiresManual: true, retryable: false, explain: "A skill with this id already exists."),
        ErrorSpec("TEAM_INVALID", ruleId: "team.invalid", agentAction: "Fix the team definition and retry `alln teams edit`.", requiresManual: true, retryable: false, explain: "The team definition is invalid (missing rows, unknown skills, or bad effort/output kind)."),
        ErrorSpec("SKILL_INVALID", ruleId: "skill.invalid", agentAction: "Fix the skill definition and retry `alln skills edit`.", requiresManual: true, retryable: false, explain: "The skill definition is invalid (empty template, missing lane, or unknown purpose)."),
        ErrorSpec("TEAM_DEFAULT_INVALID", ruleId: "team.catalog.default.invalid", agentAction: "Set another default team before deleting or changing the lane default.", requiresManual: true, retryable: false, explain: "The default-team change would leave a lane without a valid default."),
        ErrorSpec("SKILL_IN_USE", ruleId: "skill.in_use", agentAction: "Remove the skill from team definitions before deleting.", requiresManual: true, retryable: false, explain: "The skill is still referenced by one or more team definitions."),
        ErrorSpec("SKILL_LANE_MISMATCH", ruleId: "skill.lane.mismatch", agentAction: "Pick a skill from the same lane as the team.", requiresManual: true, retryable: false, explain: "A team row references a skill from another lane."),
        ErrorSpec("CATALOG_ID_INVALID", ruleId: "catalog.id.invalid", agentAction: "Use a canonical lowercase id matching the catalog rules.", requiresManual: true, retryable: false, explain: "The catalog id fails canonical ID rules."),
        ErrorSpec("JSON_SCHEMA_VIOLATION", ruleId: "json.schema.violation", agentAction: "Treat as implementation bug; run export-contracts check.", requiresManual: true, retryable: false, explain: "Output failed to match its declared schema. This is an implementation bug; run the export-contracts drift check."),
        ErrorSpec("PERMISSION_REQUIRED", ruleId: "permission.required", agentAction: "Ask the user for the named permission.", requiresManual: true, retryable: false, explain: "The action needs a user-granted permission that is not present. Request the named permission before retrying."),
        ErrorSpec("ATTACHMENT_HASH_MISMATCH", ruleId: "attachment.hash.mismatch", agentAction: "Re-ingest or re-send the attachment; do not retry with stale bytes.", requiresManual: true, retryable: false, explain: "Attachment storedSha256 does not match on-disk bytes."),
        ErrorSpec("ATTACHMENT_NOT_FOUND", ruleId: "attachment.not_found", agentAction: "Use thread_get to list resolved attachments for the turn.", requiresManual: false, retryable: false, explain: "No attachment record exists for the requested id."),
        ErrorSpec("ATTACHMENT_TOO_MANY", ruleId: "attachment.too_many", agentAction: "Remove attachments until within the count cap.", requiresManual: true, retryable: false, explain: "Too many images attached for one send."),
        ErrorSpec("ATTACHMENT_TOO_LARGE", ruleId: "attachment.too_large", agentAction: "Use a smaller image or fewer attachments.", requiresManual: true, retryable: false, explain: "An attachment exceeds byte or megapixel limits."),
        ErrorSpec("ATTACHMENT_UNSUPPORTED_TYPE", ruleId: "attachment.unsupported_type", agentAction: "Send PNG/JPEG/GIF/WebP only.", requiresManual: true, retryable: false, explain: "Attachment MIME type is not allowed."),
        ErrorSpec("ATTACHMENT_DECODE_FAILED", ruleId: "attachment.decode_failed", agentAction: "Fix or replace the corrupt image file.", requiresManual: true, retryable: false, explain: "Image could not be decoded."),
        ErrorSpec("ATTACHMENT_BASE64_INVALID", ruleId: "attachment.base64_invalid", agentAction: "Fix the base64 payload.", requiresManual: true, retryable: false, explain: "Base64 image payload is invalid."),
        ErrorSpec("ATTACHMENT_STAGE_FAILED", ruleId: "attachment.stage_failed", agentAction: "Check workingDir permissions and disk space.", requiresManual: true, retryable: true, explain: "Could not copy attachment into workspace mirror."),
        ErrorSpec("ATTACHMENT_STAGE_UNIGNORED", ruleId: "attachment.stage_unignored", agentAction: "Add `.allnighter/` to gitignore or info/exclude manually.", requiresManual: true, retryable: false, explain: "Staged mirror but could not update git ignore rules."),
        ErrorSpec("CONTEXT_ATTACHMENT_CAP_EXCEEDED", ruleId: "context.attachment.cap", agentAction: "Reduce message or attachment count; never silently trim current send.", requiresManual: true, retryable: false, explain: "Protected attachment block does not fit context cap."),
        ErrorSpec("FILE_REFERENCE_PROJECT_ROOT_MISSING", ruleId: "file.reference.project_root_missing", agentAction: "Bind the thread to a project/working directory, then retry.", requiresManual: true, retryable: false, explain: "File references resolve against the Mac project root. The thread has no usable root."),
        ErrorSpec("FILE_REFERENCE_OUTSIDE_PROJECT", ruleId: "file.reference.outside_project", agentAction: "Pick a path inside the project root.", requiresManual: true, retryable: false, explain: "The requested path escapes the enrolled project root, so Allnighter refused to read it."),
        ErrorSpec("FILE_REFERENCE_NOT_FOUND", ruleId: "file.reference.not_found", agentAction: "Refresh the file picker or choose an existing project file.", requiresManual: true, retryable: false, explain: "The referenced file no longer exists at run time."),
        ErrorSpec("FILE_REFERENCE_UNREADABLE", ruleId: "file.reference.unreadable", agentAction: "Check file permissions or choose another file.", requiresManual: true, retryable: false, explain: "The file exists but Allnighter could not read it as a regular file."),
        ErrorSpec("FILE_REFERENCE_BINARY_UNSUPPORTED", ruleId: "file.reference.binary_unsupported", agentAction: "Reference text files only in v1.", requiresManual: true, retryable: false, explain: "File references v1 injects UTF-8 text. Binary files are not delivered."),
        ErrorSpec("FILE_REFERENCE_TOO_LARGE", ruleId: "file.reference.too_large", agentAction: "Reference a smaller file or a line range.", requiresManual: true, retryable: false, explain: "The source file exceeds the v1 per-file read cap."),
        ErrorSpec("FILE_REFERENCE_TOO_MANY", ruleId: "file.reference.too_many", agentAction: "Remove file references until within the cap.", requiresManual: true, retryable: false, explain: "The send has more file references than v1 allows."),
        ErrorSpec("FILE_REFERENCE_SENSITIVE_BLOCKED", ruleId: "file.reference.sensitive_blocked", agentAction: "Do not attach secrets; summarize the needed config manually.", requiresManual: true, retryable: false, explain: "The path looks like credentials, keys, or an environment file and was blocked."),
        ErrorSpec("FILE_REFERENCE_LINE_RANGE_INVALID", ruleId: "file.reference.line_range_invalid", agentAction: "Choose a valid 1-based line range inside the file.", requiresManual: true, retryable: false, explain: "The requested line range is empty, reversed, or past the end of the file."),
        ErrorSpec("FILE_REFERENCE_CHANGED_BEFORE_INVOKE", ruleId: "file.reference.changed_before_invoke", agentAction: "Refresh the reference and re-approve the changed file before running.", requiresManual: true, retryable: false, explain: "A delayed or pending send would read different bytes than the approved reference hash."),
        ErrorSpec("FILE_REFERENCE_CATALOG_STALE", ruleId: "file.reference.catalog_stale", agentAction: "Refresh the Project file picker and retry.", requiresManual: false, retryable: true, explain: "The search catalog was stale. The resolver remains authoritative and did not deliver stale content."),
        ErrorSpec("FILE_REFERENCE_WORKER_UNSUPPORTED", ruleId: "file.reference.worker_unsupported", agentAction: "Choose a worker that can receive referenced file text or use a chat worker.", requiresManual: true, retryable: false, explain: "The selected route cannot accept Project file references."),
        ErrorSpec("THREAD_SEND_IDEMPOTENCY_CONFLICT", ruleId: "thread.send.idempotency.conflict", agentAction: "Use a new idempotency key or repeat the original payload.", requiresManual: false, retryable: false, explain: "Same idempotency key reused with a different thread send payload."),
        ErrorSpec("THREAD_NOT_FOUND", ruleId: "thread.not_found", agentAction: "Run `alln history --json` (or create a thread); retry with a valid thread id.", requiresManual: true, retryable: false, explain: "No thread matches the given id, or no threads exist yet. List threads and retry with a valid thread id."),
        ErrorSpec("TRY_FIX_PACKET_MISSING", ruleId: "try_fix.packet.missing", agentAction: "Re-run the Bug Hunt diagnosis; the fix attempt needs a typed fix packet.", requiresManual: false, retryable: true, explain: "The Bug Hunt answer run produced no typed fix packet (the writer emitted no fenced fix-packet block), so there is no hypothesis to try. Re-run the diagnosis with a sharper report."),
        ErrorSpec("TRY_FIX_PACKET_UNSAFE", ruleId: "try_fix.packet.unsafe", agentAction: "Read the gate reason; resolve the danger flag / add an actionable hypothesis + proof, then retry.", requiresManual: true, retryable: false, explain: "The fix packet is not safe to execute: it carries a danger flag (credentials, deletion, deploy…), lacks an actionable hypothesis (a fix within a boundary), names no truth owner, or its proof method is incomplete. Danger blocks; doubt does not."),
        ErrorSpec("TRY_FIX_EXECUTOR_INVALID", ruleId: "try_fix.executor.invalid", agentAction: "Pass --executor a single mutating team that is runnable on this bench (default execution_playbook).", requiresManual: true, retryable: false, explain: "The chosen fix executor is not a single, mutating, runnable team. The fix attempt must resolve to exactly one mutating worker."),
        ErrorSpec("RELAY_NOT_FOUND", ruleId: "relay.not_found", agentAction: "Run `alln pair relay-status --relay <id> --json` with a valid relay id, or start a new relay with `alln pair relay`.", requiresManual: true, retryable: false, explain: "No PM Relay matches the given id."),
        ErrorSpec("RELAY_INVALID_STATE", ruleId: "relay.invalid_state", agentAction: "Only an `escalated` relay can be resumed; check status first with `pair relay-status`.", requiresManual: true, retryable: false, explain: "The requested relay transition is not valid for its current status (e.g. resuming a relay that is not escalated)."),
        ErrorSpec("RELAY_HANDOVER_UNSAFE", ruleId: "relay.handover.unsafe", agentAction: "The PM's handover named a danger instruction (credentials, signing, destructive git, sandbox/TCC, mass deletion); the relay escalated instead of dispatching it. Answer the escalation or rewrite the round's intent.", requiresManual: true, retryable: false, explain: "HandoverGate blocked a PM handover before it reached the dev seat — danger blocks, doubt does not."),
        ErrorSpec("RELAY_ROUND_IN_FLIGHT", ruleId: "relay.round.in_flight", agentAction: "Wait for the in-flight round to settle, then run `alln pair pilot status --relay <id> --json` and retry `pilot handoff` once status is `awaitingPM`.", requiresManual: false, retryable: true, explain: "A pilot relay round is already dispatching (status == running) — one mutating dev turn at a time, unchanged law. A concurrent `pilot handoff` on the same relay is refused rather than racing a second dev turn onto one repo root."),
        ErrorSpec("RELAY_NOT_AWAITING_PM", ruleId: "relay.not_awaiting_pm", agentAction: "Run `alln pair pilot status --relay <id> --json`; a relay only accepts `pilot handoff` while its status is `awaitingPM` (done/escalated/stopped have nothing left to hand off to).", requiresManual: true, retryable: false, explain: "`pilot handoff` was called against a relay that isn't parked at `awaitingPM` — it already reached a terminal status, or isn't a Pilot relay's normal between-rounds state."),
        ErrorSpec("RELAY_VERDICT_UNPARSEABLE", ruleId: "relay.verdict.unparseable", agentAction: "The piloting session's submission needs exactly one trailing ```json RelayVerdict block (verdict: continue|done|escalate; handover required for continue). Fix the tail and resubmit `pilot handoff` — the relay is still `awaitingPM`, no re-ask machinery runs.", requiresManual: true, retryable: true, explain: "Pilot's `pilot handoff` submission didn't end with a parseable RelayVerdict tail (missing entirely, an unknown verdict value, or `continue` with no handover). Unlike a spawned PM turn, there is no automatic re-ask — the piloting session is live and just resubmits."),
        ErrorSpec("THREAD_SEND_FAILED", ruleId: "thread.send.failed", agentAction: "Inspect the error detail; retry the send or fix the worker.", requiresManual: false, retryable: true, explain: "The thread send did not complete (worker or transport failure). Inspect the detail, then retry."),
        ErrorSpec("MODEL_NOT_FOUND", ruleId: "model.not_found", agentAction: "Run `alln models --json` and retry with a valid model id.", requiresManual: true, retryable: false, explain: "No model matches the given id. List models and retry with a valid ModelID."),
        ErrorSpec("MODEL_BUILTIN_IMMUTABLE", ruleId: "model.builtin.immutable", agentAction: "Duplicate the built-in model, then edit the custom copy.", requiresManual: true, retryable: false, explain: "Built-in models cannot be edited or deleted. Duplicate to a custom model and edit that copy."),
        ErrorSpec("MODEL_ID_COLLISION", ruleId: "model.id.collision", agentAction: "Pick a different model id or delete the conflicting custom model.", requiresManual: true, retryable: false, explain: "A model with this id already exists."),
        ErrorSpec("MODEL_INVALID", ruleId: "model.invalid", agentAction: "Fix the model definition and retry the edit.", requiresManual: true, retryable: false, explain: "The model definition or id is invalid (bad id, missing fields, or unknown driver mapping)."),
        ErrorSpec("MODEL_DRIVER_MISSING", ruleId: "model.driver.missing", agentAction: "Reference a known driver id, or add the driver manifest first.", requiresManual: true, retryable: false, explain: "The model references a driver that is not registered. Use a known driver id or add its manifest."),
        ErrorSpec("INTERNAL_ERROR", ruleId: "internal.error", agentAction: "Capture the message and `traceId`; retry once, then report if it persists.", requiresManual: true, retryable: false, explain: "An unexpected internal failure occurred (not a usage error). The detail is in the message; this is a defensive catch-all, not a routine condition."),
        // Project foundation (PRJ-S07+). The full set is registered up front so the
        // recovery ladder and doctor explain cover them as the later slices emit them.
        ErrorSpec("PROJECT_NOT_FOUND", ruleId: "project.not_found", agentAction: "Run `alln project list --json`; retry with a valid id or name.", requiresManual: true, retryable: false, explain: "No project matches the given id or name. List projects and retry with a valid identifier."),
        ErrorSpec("NO_PROJECT_SELECTED", ruleId: "project.none_selected", agentAction: "Select or add a project, then re-run the mutating action.", requiresManual: true, retryable: false, explain: "A mutating action was attempted with no project selected. Mutating work is always scoped to one project root.", exitClass: .usage),
        ErrorSpec("DUPLICATE_PROJECT_ROOT", ruleId: "project.duplicate_root", agentAction: "Use the existing project that owns this normalized root.", requiresManual: false, retryable: false, explain: "The path resolves to an existing project's normalized root; the existing project is returned rather than a duplicate."),
        ErrorSpec("PROJECT_ROOT_UNAVAILABLE", ruleId: "project.root_unavailable", agentAction: "Restore the folder/permissions, then `alln project show <id>` to re-observe.", requiresManual: true, retryable: true, explain: "The project root is missing or permission-denied (rootState != available); mutating runs are blocked until the root is restored."),
        ErrorSpec("PROJECT_ARCHIVED", ruleId: "project.archived", agentAction: "Run `alln project unarchive <id>` before new runs.", requiresManual: true, retryable: false, explain: "The project is archived. Unarchive it before starting new runs; reads remain available."),
        ErrorSpec("THREAD_UNASSIGNED", ruleId: "thread.unassigned", agentAction: "Assign the thread/pending item to a project, then retry.", requiresManual: true, retryable: false, explain: "The thread or pending item has no project. Assign it to a project before a mutating run."),
        ErrorSpec("WORKER_NOT_READY_IN_PROJECT", ruleId: "project.worker_not_ready", agentAction: "Run `alln project workers <id> --json`; open the CLI in the project folder and complete its trust/login, then recheck.", requiresManual: true, retryable: true, explain: "The target worker's project readiness is not `ready` for this root. The run waits until the worker is ready here."),
        ErrorSpec("RUN_WRITE_LOCK_BUSY", ruleId: "run.write_lock_busy", agentAction: "The active mutating run on this repo root looks stuck (the wait bound elapsed); wait for it to finish or stop it, then retry.", requiresManual: false, retryable: true, explain: "At most one mutating run per canonical repo root. A second mutating run normally QUEUES (FIFO) behind the active one and runs when it finishes; this error is the safety valve — it fires only when the active run is still holding the lock after the wait bound (it is wedged), so the queued run is refused instead of hanging forever."),
        ErrorSpec("NO_PROJECT_ROOT", ruleId: "run.no_project_root", agentAction: "Restore the project folder or pick an available project root, then retry.", requiresManual: true, retryable: true, explain: "The project repo root is missing or unreadable; runs require a real cwd in the repo."),
        ErrorSpec("WORKER_NOT_READY", ruleId: "run.worker_not_ready", agentAction: "Pick a ready worker or run setup health, then retry.", requiresManual: true, retryable: true, explain: "No runnable worker resolved for this run (missing CLI, wrong driver, or bench not ready)."),
        ErrorSpec("EXECUTION_TEAM_MIXED_SOURCES", ruleId: "execution.team.mixed_sources", agentAction: "Pick one execution source, run as non-mutating review/propose, or split into judgment then execution.", requiresManual: true, retryable: false, explain: "Mutating execution teams must resolve to one CLI driver. Mixed-source execution is blocked before spawn."),
        // Boost window (Utilization_Window_Priming).
        ErrorSpec("UTILIZATION_SOURCE_NOT_FOUND", ruleId: "utilization.source.not_found", agentAction: "Run `alln models --json`; use a known driver id in appliesTo.", requiresManual: true, retryable: false, explain: "The utilization source id is not registered on this bench.", exitClass: .usage),
        ErrorSpec("UTILIZATION_SOURCE_UNCONFIGURED", ruleId: "utilization.source.unconfigured", agentAction: "Add the source to Boost window appliesTo, then retry.", requiresManual: true, retryable: false, explain: "The source is not included in the Boost window appliesTo list.", exitClass: .usage),
        ErrorSpec("UTILIZATION_AUTH_REQUIRED", ruleId: "utilization.auth.required", agentAction: "Sign in to the named CLI, then retry the seed.", requiresManual: true, retryable: false, explain: "The seed stopped on an auth prompt. Allnighter never auto-confirms sign-in."),
        ErrorSpec("UTILIZATION_BILLING_PROMPT", ruleId: "utilization.billing.prompt", agentAction: "Resolve billing on the provider, then retry.", requiresManual: true, retryable: false, explain: "The seed stopped on a billing or quota prompt. Allnighter never auto-confirms payment."),
    ]

    // MARK: - Doctor checks (stable names)

    static let m1DoctorChecks: [DoctorCheckSpec] = [
        DoctorCheckSpec("binaryVersion", meaning: "CLI binary reports version."),
        DoctorCheckSpec("docsVersion", meaning: "Generated docs match binary contract."),
        DoctorCheckSpec("configDir", meaning: "Allnighter config dir exists and is writable."),
        DoctorCheckSpec("runsDir", meaning: "Run journal dir exists and is writable."),
        DoctorCheckSpec("sources", meaning: "Known source manifests load."),
        DoctorCheckSpec("source.<sourceId>.installed", meaning: "Source CLI/runtime exists."),
        DoctorCheckSpec("source.<sourceId>.auth", meaning: "Source auth appears valid when safely probeable."),
        DoctorCheckSpec("source.<sourceId>.headlessTrust", meaning: "Headless trust/mutation posture is declared for sources that require it."),
        DoctorCheckSpec("source.<sourceId>.smoke", meaning: "Bounded smoke test when --full."),
        DoctorCheckSpec(
            "source.cursor_agent.shellAllowlist",
            meaning: "Cursor CLI global shell allowlist is not so restrictive that headless turns cannot run git/python (read-only; Allnighter never writes vendor config)."
        ),
        DoctorCheckSpec("benchReadyCount", meaning: "At least one model is ready."),
        DoctorCheckSpec("defaultTeamValid", meaning: "Default team has runnable workers."),
        DoctorCheckSpec("planWriterReady", meaning: "Default team has a ready plan worker."),
        DoctorCheckSpec("coordinator", meaning: "Resident coordinator state; may be degraded in M1."),
        DoctorCheckSpec("journal.incrementalDurable", meaning: "Async run journal persists worker/status transitions incrementally."),
        DoctorCheckSpec("journal.orphanRecovery", meaning: "Orphaned async runs resolve to interrupted."),
        DoctorCheckSpec("pending.storeReadable", meaning: "Pending store can be read."),
        DoctorCheckSpec("pending.storeWritable", meaning: "Pending store can be mutated."),
    ]

    // MARK: - NDJSON events

    static let m1Events: [EventSpec] = [
        EventSpec("teamRunStarted", requiredData: ["status", "origin", "teamPresetId"]),
        EventSpec("workerStarted", requiredData: ["workerId", "modelId", "skillId"]),
        EventSpec("workerAnswered", requiredData: ["workerId", "durationMs"]),
        EventSpec("workerFailed", requiredData: ["workerId", "error"]),
        EventSpec("planStarted", requiredData: ["workerId", "stageId"]),
        EventSpec("planWritten", requiredData: ["workerId", "stageId", "durationMs"]),
        EventSpec("teamRunCompleted", requiredData: ["status", "planStageId", "durationMs"]),
        EventSpec("teamRunFailed", requiredData: ["status", "error"]),
        EventSpec("error", requiredData: ["error"]),
        EventSpec("pendingAdded", requiredData: ["pendingItemId", "status"]),
        EventSpec("pendingSubmitted", requiredData: ["pendingItemId", "status"]),
        EventSpec("pendingEdited", requiredData: ["pendingItemId", "status"]),
        EventSpec("pendingReordered", requiredData: ["pendingItemId"]),
        EventSpec("pendingCancelled", requiredData: ["pendingItemId", "status"]),
    ]

    /// The closed `nextActions.kind` catalog. Must stay in lock-step with
    /// `TeamRunJSON.NextAction.Kind` (a test enforces parity).
    static let m1NextActionKinds: [NextActionKindSpec] = [
        NextActionKindSpec("showRun", summary: "Show the full run."),
        NextActionKindSpec("export", summary: "Export the result bundle."),
        NextActionKindSpec("showHistory", summary: "List recent runs."),
        NextActionKindSpec("submitPending", summary: "Submit a Draft item to Pending."),
        NextActionKindSpec("runPending", summary: "Run a Pending item now."),
        NextActionKindSpec("showPending", summary: "Show one Pending item."),
        NextActionKindSpec("cancelPending", summary: "Cancel a Pending item."),
    ]

    // MARK: - Example recipes

    static let m1Examples: [ExampleRecipe] = [
        ExampleRecipe("docs_all", title: "Generate the full reference", command: "alln docs"),
        ExampleRecipe("doctor_json", title: "Structured diagnostics", command: "alln doctor --json"),
        ExampleRecipe("doctor_explain", title: "Explain an error code", command: "alln doctor explain SOURCE_AUTH_EXPIRED --json"),
        ExampleRecipe("bootstrap_json", title: "Agent activation snippet for Claude Code", command: "alln bootstrap --host claude --json"),
        ExampleRecipe("models_json", title: "List model catalog and Bench state", command: "alln models --json"),
        ExampleRecipe("team_show_json", title: "Show the current team", command: "alln team show --json"),
        ExampleRecipe("teams_code_json", title: "List Code teams", command: "alln teams --lane code --json"),
        ExampleRecipe("teams_definition_json", title: "Full team definition for edit", command: "alln teams definition code_bug_hunt --json"),
        ExampleRecipe("skills_code_json", title: "List Code skills", command: "alln skills --lane code --json"),
        ExampleRecipe("skills_show_json", title: "Show a Code skill", command: "alln skills show bug_reproducer --json"),
        ExampleRecipe("team_preflight", title: "Preflight a team", command: "alln team preflight --lane code --team code_bug_hunt --effort high"),
        ExampleRecipe("team_basic", title: "Ask the team", command: "alln team --lane code --team code_bug_hunt \"Why does run history disappear?\""),
        ExampleRecipe("team_json", title: "Machine team run", command: "alln team --json \"Give me one small naming test.\""),
        ExampleRecipe("team_stream", title: "Streamed team run", command: "alln team --stream \"Give me one tiny event-stream test.\""),
        ExampleRecipe("team_start_json", title: "Start async team run", command: "alln team start --json --lane code --team code_bug_hunt --effort low \"tiny async sanity\""),
        ExampleRecipe("show_latest_json", title: "Show the latest run", command: "alln show latest --json"),
        ExampleRecipe("spec_full", title: "Retrieve the full result packet", command: "alln spec latest --detail full --json"),
        ExampleRecipe("export_md", title: "Export the latest result", command: "alln export latest --format md"),
        ExampleRecipe("export_contracts_check", title: "Verify no contract drift", command: "alln dev export-contracts --check"),
        ExampleRecipe("thread_send_json", title: "Send message with image and file reference to thread", command: "alln thread send latest \"describe this\" --image ./shot.png --ref Sources/App.swift:10-80 --json"),
        ExampleRecipe("thread_rename_json", title: "Rename a work thread", command: "alln thread rename latest \"Paste-image bug\" --json"),
        ExampleRecipe("serve_health_json", title: "Coordinator health", command: "alln serve --health --json"),
        ExampleRecipe("pending_add_json", title: "Create a Draft Pending item", command: "alln pending add --worker model_opus --when ready --json \"Review this patch when Claude is available.\""),
        ExampleRecipe("pending_list_json", title: "List Pending items", command: "alln pending list --json"),
        ExampleRecipe("boost_window_show_json", title: "Show Boost window settings", command: "alln boost-window show --json"),
        ExampleRecipe("boost_window_set_json", title: "Enable Boost window for Claude and Codex", command: "alln boost-window set --enabled true --window-start 08:00 --applies-to claude_code,codex --json"),
    ]
}
