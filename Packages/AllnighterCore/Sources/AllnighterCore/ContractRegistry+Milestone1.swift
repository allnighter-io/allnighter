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
        examples: m1Examples,
        mcpTools: m1MCPTools
    )

    /// MCP tools (M1) — thin projections of `alln` commands. No `team_recall`
    /// (retired in step 8); retrieval is `history`/`show`.
    static let m1MCPTools: [MCPToolSpec] = [
        MCPToolSpec("mcp_hello", command: "teams", summary: "Agent bootstrap: whether a team can start now, which teams are ready, and the next action. Cheap, non-mutating, no quota.",
                    params: [.init("agent", summary: "Calling agent id for provenance (advisory only).")],
                    idempotency: .idempotent),
        MCPToolSpec("teams_list", command: "teams", summary: "Lane-scoped team catalog summary (no prompt templates).",
                    params: [.init("lane", summary: "Filter to one lane: code|design|copy|signal (optional).")],
                    outputSchema: .teamCatalogJSON,
                    errors: ["CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("teams_show", command: "teams show", summary: "One team definition including worker rows.",
                    params: [.init("teamId", required: true, summary: "Team id.")],
                    errors: ["TEAM_NOT_FOUND", "CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("teams_duplicate", command: "teams duplicate", summary: "Duplicate a built-in team into a custom team.",
                    params: [.init("teamId", required: true, summary: "Source team id."),
                             .init("name", summary: "Display name for the copy (optional).")],
                    errors: ["TEAM_NOT_FOUND", "TEAM_ID_COLLISION", "CLI_USAGE_ERROR", "INTERNAL_ERROR"], idempotency: .notIdempotent),
        MCPToolSpec("teams_save", command: "teams edit", summary: "Save a custom team definition (full replacement).",
                    params: [.init("teamId", required: true, summary: "Team id."),
                             .init("definition", required: true, summary: "TeamPreset JSON object.")],
                    errors: ["TEAM_INVALID", "TEAM_BUILTIN_IMMUTABLE", "CATALOG_ID_INVALID", "SKILL_LANE_MISMATCH", "CLI_USAGE_ERROR", "INTERNAL_ERROR"], idempotency: .idempotent),
        MCPToolSpec("teams_set_default", command: "teams set-default", summary: "Set the default team for a lane.",
                    params: [.init("teamId", required: true, summary: "Team id.")],
                    errors: ["TEAM_NOT_FOUND", "TEAM_DEFAULT_INVALID", "CLI_USAGE_ERROR", "INTERNAL_ERROR"], idempotency: .idempotent),
        MCPToolSpec("teams_delete", command: "teams delete", summary: "Delete a custom team.",
                    params: [.init("teamId", required: true, summary: "Team id.")],
                    errors: ["TEAM_NOT_FOUND", "TEAM_BUILTIN_IMMUTABLE", "TEAM_DEFAULT_INVALID", "CLI_USAGE_ERROR", "INTERNAL_ERROR"], idempotency: .idempotent),
        MCPToolSpec("skills_list", command: "skills", summary: "Lane-scoped skill catalog summary (no templates).",
                    params: [.init("lane", summary: "Filter to one lane: code|design|copy|signal (optional).")],
                    outputSchema: .skillCatalogJSON,
                    errors: ["CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("skills_show", command: "skills show", summary: "One skill definition including template.",
                    params: [.init("skillId", required: true, summary: "Skill id.")],
                    errors: ["SKILL_NOT_FOUND", "CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("skills_duplicate", command: "skills duplicate", summary: "Duplicate a built-in skill into a custom skill.",
                    params: [.init("skillId", required: true, summary: "Source skill id."),
                             .init("name", summary: "Display name for the copy (optional).")],
                    errors: ["SKILL_NOT_FOUND", "SKILL_ID_COLLISION", "CLI_USAGE_ERROR", "INTERNAL_ERROR"], idempotency: .notIdempotent),
        MCPToolSpec("skills_save", command: "skills edit", summary: "Save a custom skill definition (full replacement).",
                    params: [.init("skillId", required: true, summary: "Skill id."),
                             .init("definition", required: true, summary: "Skill JSON object.")],
                    errors: ["SKILL_INVALID", "SKILL_BUILTIN_IMMUTABLE", "CATALOG_ID_INVALID", "CLI_USAGE_ERROR", "INTERNAL_ERROR"], idempotency: .idempotent),
        MCPToolSpec("skills_delete", command: "skills delete", summary: "Delete a custom skill.",
                    params: [.init("skillId", required: true, summary: "Skill id.")],
                    errors: ["SKILL_NOT_FOUND", "SKILL_BUILTIN_IMMUTABLE", "SKILL_IN_USE", "CLI_USAGE_ERROR", "INTERNAL_ERROR"], idempotency: .idempotent),
        MCPToolSpec("team_preflight", command: "team preflight", summary: "Validate lane/team/effort against the ready bench WITHOUT running or spending quota; shows resolved/blocked workers and self-fusion.",
                    params: [.init("lane", summary: "code|design|copy|signal."),
                             .init("team", summary: "Team id (e.g. code_bug_hunt)."),
                             .init("effort", summary: "low|med|high (optional; default is the team's)."),
                             .init("type", summary: "Copy-only routing sugar (optional).")],
                    errors: ["DEFAULT_TEAM_INVALID", "TEAM_NOT_FOUND", "MODEL_UNAVAILABLE", "CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("team_start", command: "team start", summary: "Start an async team run; returns run id after preflight and journal write.",
                    params: [.init("prompt", required: true, summary: "The prompt to run."),
                             .init("lane", summary: "code|design|copy|signal."),
                             .init("team", summary: "Team id."),
                             .init("effort", summary: "low|med|high."),
                             .init("type", summary: "Copy-only routing sugar (optional)."),
                             .init("context", summary: "Bounded inline context (optional)."),
                             .init("threadId", summary: "Owning work thread id (optional)."),
                             .init("originAgent", summary: "Calling agent id for provenance."),
                             .init("originConversationId", summary: "Origin conversation id."),
                             .init("originMessageId", summary: "Origin message id."),
                             .init("idempotencyKey", summary: "Client idempotency key (24h retention).")],
                    outputSchema: .teamStartResponse,
                    errors: ["DEFAULT_TEAM_INVALID", "TEAM_NOT_FOUND", "MODEL_UNAVAILABLE", "NESTED_TEAM_BLOCKED", "TEAM_GOVERNOR_BUSY", "IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD", "COORDINATOR_UNAVAILABLE", "CLI_USAGE_ERROR"],
                    idempotency: .keyed),
        MCPToolSpec("team_status", command: "team status", summary: "Poll live async run state with nextPollAfterMs.",
                    params: [.init("runId", required: true, summary: "Run id from team_start.")],
                    outputSchema: .teamStatusResponse,
                    errors: ["RUN_NOT_FOUND", "CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("team_result", command: "team result", summary: "Fetch TeamRunJSON when terminal, or a not-ready envelope.",
                    params: [.init("runId", required: true, summary: "Run id from team_start.")],
                    outputSchema: .teamRunJSON,
                    errors: ["RUN_NOT_FOUND", "RESULT_NOT_READY", "CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("team_cancel", command: "team cancel", summary: "Cancel an active async team run.",
                    params: [.init("runId", required: true, summary: "Run id from team_start.")],
                    outputSchema: .teamCancelResponse,
                    errors: ["RUN_NOT_FOUND", "CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("team_ask", command: "team", summary: "Run a lane team on a prompt; returns a synthesized result + structured run.",
                    params: [.init("question", required: true, summary: "The prompt to ask the team."),
                             .init("lane", summary: "code|design|copy|signal (explicit; never inferred)."),
                             .init("team", summary: "Team id; `--preset` is a hidden alias."),
                             .init("effort", summary: "low|med|high (optional)."),
                             .init("type", summary: "Copy-only routing sugar (optional)."),
                             .init("context", summary: "Bounded context snippet to consider (optional).")],
                    outputSchema: .teamRunJSON,
                    errors: ["DEFAULT_TEAM_INVALID", "TEAM_NOT_FOUND", "MODEL_UNAVAILABLE", "TEAM_RUN_TIMEOUT", "TEAM_RUN_FAILED", "PLAN_WRITER_FAILED", "WORKER_FAILED", "NESTED_TEAM_BLOCKED", "TEAM_GOVERNOR_BUSY", "CLI_USAGE_ERROR"],
                    idempotency: .notIdempotent),
        MCPToolSpec("team_show", command: "team show", summary: "Show the default team for each lane.",
                    errors: ["DEFAULT_TEAM_INVALID"], idempotency: .idempotent),
        MCPToolSpec("history", command: "history", summary: "Search prior local team runs (read-only, zero cost).",
                    params: [.init("query", required: true, summary: "Search text.")],
                    outputSchema: .historyJSON,
                    errors: ["CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("show", command: "show", summary: "Show one run as TeamRunJSON.",
                    params: [.init("run", required: true, summary: "A run id or `latest`."),
                             .init("full", type: "boolean", summary: "Include resolved worker prompt snapshots (audit).")],
                    outputSchema: .teamRunJSON,
                    errors: ["RUN_NOT_FOUND", "CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("doctor", command: "doctor", summary: "Diagnostics report; quota-free unless `full` is set.",
                    params: [.init("full", type: "boolean", summary: "Run smoke probes (spends quota).")],
                    outputSchema: .doctorResult,
                    errors: ["DOCTOR_CHECK_FAILED"], idempotency: .idempotent),
        MCPToolSpec("error_explain", command: "doctor explain", summary: "Explain an error/recovery code: cause, who can fix it, and the next action.",
                    params: [.init("code", required: true, summary: "The error code to explain, e.g. SOURCE_AUTH_EXPIRED.")],
                    errors: ["CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("spec_get", command: "spec", summary: "Retrieve a run's full spec/result packet without opening the GUI. Failed workers and warnings always included in full detail.",
                    params: [.init("run", summary: "Run id or `latest` (default latest)."),
                             .init("detail", summary: "summary | full | artifactRefsOnly (default summary).")],
                    outputSchema: .specResult,
                    errors: ["RUN_NOT_FOUND", "CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("floor_show", command: "floor show", summary: "The inspectable Floor for one team run: worker lanes (incl. failures), durable artifact refs, typed return (Signal insight when applicable), converge timeline, and Execute requirements.",
                    params: [.init("run", summary: "Run id or `latest` (default latest).")],
                    outputSchema: .floorRun,
                    errors: ["RUN_NOT_FOUND", "CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("thread_send", command: "thread send", summary: "Send a message and/or images to a work thread worker.",
                    params: [
                        .init("threadId", summary: "Thread id or `latest`."),
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
                    errors: ["THREAD_NOT_FOUND", "THREAD_SEND_IDEMPOTENCY_CONFLICT", "WORKER_FAILED", "THREAD_SEND_FAILED", "ATTACHMENT_TOO_MANY", "ATTACHMENT_TOO_LARGE", "ATTACHMENT_UNSUPPORTED_TYPE", "ATTACHMENT_DECODE_FAILED", "ATTACHMENT_BASE64_INVALID", "ATTACHMENT_HASH_MISMATCH", "ATTACHMENT_STAGE_FAILED", "CONTEXT_ATTACHMENT_CAP_EXCEEDED", "FILE_REFERENCE_PROJECT_ROOT_MISSING", "FILE_REFERENCE_OUTSIDE_PROJECT", "FILE_REFERENCE_NOT_FOUND", "FILE_REFERENCE_UNREADABLE", "FILE_REFERENCE_BINARY_UNSUPPORTED", "FILE_REFERENCE_TOO_LARGE", "FILE_REFERENCE_TOO_MANY", "FILE_REFERENCE_SENSITIVE_BLOCKED", "FILE_REFERENCE_LINE_RANGE_INVALID", "FILE_REFERENCE_CHANGED_BEFORE_INVOKE", "FILE_REFERENCE_CATALOG_STALE", "FILE_REFERENCE_WORKER_UNSUPPORTED", "CLI_USAGE_ERROR"],
                    idempotency: .keyed),
        MCPToolSpec("thread_get", command: "thread get", summary: "Fetch a work thread snapshot.",
                    params: [.init("threadId", required: true, summary: "Thread id.")],
                    errors: ["THREAD_NOT_FOUND", "CLI_USAGE_ERROR"], idempotency: .idempotent),
        MCPToolSpec("thread_status", command: "thread status", summary: "Poll thread running/attention state.",
                    params: [.init("threadId", required: true, summary: "Thread id.")],
                    outputSchema: .threadStatus,
                    errors: ["THREAD_NOT_FOUND", "CLI_USAGE_ERROR"], idempotency: .idempotent),
    ]

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
            ],
            outputSchema: .doctorResult, exampleIds: ["doctor_json"]
        ),
        CommandSpec(
            "doctor explain", summary: "Explain one failure/recovery code.", milestone: .m1,
            args: [ArgSpec("code", required: true, summary: "Error code to explain.")],
            flags: [FlagSpec("json", summary: "Structured explanation.")],
            // Returns the catalog ErrorSpec row (see error-codes.json), not an
            // ErrorEnvelope; no dedicated return schema marker.
            exampleIds: ["doctor_explain"]
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
                    FlagSpec("json", summary: "Structured catalog summary.")],
            outputSchema: .teamCatalogJSON, exampleIds: ["teams_build_json"]
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
            args: [ArgSpec("thread-id", required: true, summary: "Thread id.")],
            flags: [FlagSpec("json", summary: "Structured thread JSON.")],
            exampleIds: ["thread_get_json"]
        ),
        CommandSpec(
            "thread status", summary: "Poll thread running/attention state.", milestone: .m1,
            args: [ArgSpec("thread-id", required: true, summary: "Thread id.")],
            flags: [FlagSpec("json", summary: "Structured status JSON.")],
            outputSchema: .threadStatus, exampleIds: ["thread_status_json"]
        ),
        CommandSpec(
            "skills", summary: "List the lane-scoped skill catalog.", milestone: .m1,
            flags: [FlagSpec("lane", takesValue: true, valueType: "lane", summary: "Filter to one lane."),
                    FlagSpec("json", summary: "Structured catalog summary (no templates).")],
            outputSchema: .skillCatalogJSON, exampleIds: ["skills_build_json"]
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
            "teams delete", summary: "Delete a custom team.", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "Team id.")],
            flags: [FlagSpec("json", summary: "Deletion acknowledgement JSON.")],
            exampleIds: ["teams_delete_json"]
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
            "team", summary: "Run a lane team on a prompt, foreground.", milestone: .m1,
            args: [ArgSpec("prompt", required: false, summary: "The prompt (or use --file).")],
            flags: [
                FlagSpec("file", takesValue: true, valueType: "path", summary: "Read the prompt from a file."),
                FlagSpec("lane", takesValue: true, valueType: "lane", summary: "build | design | copy."),
                FlagSpec("team", takesValue: true, valueType: "id", summary: "Team id (the public team selector)."),
                FlagSpec("type", takesValue: true, valueType: "type", summary: "Copy-only routing sugar."),
                FlagSpec("effort", takesValue: true, valueType: "effort", summary: "low | med | high."),
                FlagSpec("preset", takesValue: true, valueType: "id", summary: "Deprecated alias for --team."),
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
                FlagSpec("worker", takesValue: true, valueType: "id", summary: "Target worker id or alias."),
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
                FlagSpec("worker", takesValue: true, valueType: "id", summary: "Target worker id or alias."),
                FlagSpec("team", takesValue: true, valueType: "id", summary: "Team preset id."),
                FlagSpec("fallback", takesValue: true, valueType: "id", summary: "Fallback worker id."),
                FlagSpec("when", takesValue: true, valueType: "when", summary: "ready | away | manual."),
                FlagSpec("cwd", takesValue: true, valueType: "path", summary: "Working directory context."),
                FlagSpec("json", summary: "Emit one PendingItemJSON object."),
            ],
            outputSchema: .pendingItemJSON
        ),
        CommandSpec(
            "pending reorder", summary: "Reorder Pending items (execution-lane or floor order).", milestone: .m1,
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
        CommandSpec(
            "mcp serve", summary: "Run the MCP stdio server.", milestone: .m1,
            flags: [FlagSpec("stdio", summary: "Use stdio transport (default).")]
        ),
        // Project foundation (PRJ-S07). list/add/show/archive the local work
        // floors and read the threads/pending/context bound to one. Manager chat,
        // proposals, dispatch, and verification are PRJ-S08+.
        CommandSpec(
            "project list", summary: "List projects (active by default; --all includes archived).", milestone: .m1,
            flags: [FlagSpec("all", summary: "Include archived projects."), FlagSpec("json", summary: "Emit a ProjectListJSON object.")]
        ),
        CommandSpec(
            "project add", summary: "Add (or return the existing) project for a local root. Idempotent on normalized root.", milestone: .m1,
            args: [ArgSpec("path", required: true, summary: "Local folder / git repo root.")],
            flags: [FlagSpec("name", takesValue: true, valueType: "string", summary: "Display name (defaults to the folder name)."), FlagSpec("json", summary: "Emit a ProjectJSON object.")]
        ),
        CommandSpec(
            "project show", summary: "Show one project; re-observes root/git so output reflects current truth.", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectJSON object.")]
        ),
        CommandSpec(
            "project archive", summary: "Archive a project (hides it; never deletes local files or threads).", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectJSON object.")]
        ),
        CommandSpec(
            "project unarchive", summary: "Restore an archived project to the active roster.", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectJSON object.")]
        ),
        CommandSpec(
            "project threads", summary: "List the work threads bound to one project.", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectThreadsJSON object.")]
        ),
        CommandSpec(
            "project pending", summary: "List the pending work bound to one project (a filtered view of the one Pending store).", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectPendingJSON object.")]
        ),
        CommandSpec(
            "project context", summary: "Generate the on-demand, source-labeled context packet for a project (a receipt, never durable truth).", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectContextJSON object.")]
        ),
        CommandSpec(
            "project workers", summary: "Show cached per-project worker readiness (read-only; never probes).", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectWorkersJSON object.")]
        ),
        CommandSpec(
            "project recheck-workers", summary: "Rerun driver-declared safe probes for a project and refresh the readiness cache. No auto-config/auth.", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectWorkersJSON object.")]
        ),
        CommandSpec(
            "project chat", summary: "Ask the Project Manager (a model invocation over the project context). Answers only; never auto-creates work. No ready model → a wait turn.", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name."), ArgSpec("message", required: false, summary: "The chat message (or use --file).")],
            flags: [FlagSpec("file", takesValue: true, valueType: "path", summary: "Read the message from a file."), FlagSpec("json", summary: "Emit a ProjectManagerTurnJSON object.")]
        ),
    ]

    // MARK: - Commands (named but deferred past M1)

    static let deferredCommands: [CommandSpec] = [
        CommandSpec("work", summary: "Create a work order.", milestone: .deferred),
        CommandSpec("pending stop", summary: "Stop a running Pending item.", milestone: .deferred),
        CommandSpec("dispatch", summary: "Send a work order/spec to an execution target.", milestone: .deferred),
        CommandSpec("pair", summary: "Approve iOS/Mac pairing.", milestone: .deferred),
        CommandSpec("mcp install", summary: "Write MCP config with user consent.", milestone: .deferred),
    ]

    // MARK: - Error catalog

    static let m1Errors: [ErrorSpec] = [
        ErrorSpec("CLI_USAGE_ERROR", ruleId: "cli.usage.error", agentAction: "Re-run `alln docs <command>` and fix arguments.", requiresManual: true, retryable: false, explain: "The command was called with invalid or conflicting arguments. Consult the generated docs for the command and correct the invocation.", exitClass: .usage),
        ErrorSpec("CONTRACT_DRIFT", ruleId: "contract.drift", agentAction: "Run `alln dev export-contracts`, then rebuild.", requiresManual: true, retryable: false, explain: "Generated artifacts no longer match the registry. Regenerate and rebuild before relying on output."),
        ErrorSpec("DOCTOR_CHECK_FAILED", ruleId: "doctor.check.failed", agentAction: "Run `alln doctor --json`.", requiresManual: false, retryable: true, explain: "A required doctor check failed. Inspect the structured report and address the named check, then retry."),
        ErrorSpec("SOURCE_NOT_FOUND", ruleId: "source.not_found", agentAction: "Run `alln doctor --json`; add/configure the missing source.", requiresManual: true, retryable: false, explain: "A required source CLI/runtime was not resolved on this machine. Install or locate it, then re-probe."),
        ErrorSpec("SOURCE_AUTH_EXPIRED", ruleId: "source.auth.expired", agentAction: "Re-authenticate the named source.", requiresManual: true, retryable: false, explain: "The source resolved but its authentication is invalid or expired. Sign in via the source's own login flow."),
        ErrorSpec("MODEL_UNAVAILABLE", ruleId: "model.unavailable", agentAction: "Run `alln models --json`; pick an on-Bench ready model or enable one.", requiresManual: false, retryable: true, explain: "The requested model is not runnable: it may be off-Bench, its source may not be ready, or it may not exist. Use `alln models --json` to see available vs on-Bench vs ready state."),
        ErrorSpec("DEFAULT_TEAM_INVALID", ruleId: "team.default.invalid", agentAction: "Run `alln team show --json`; fix unavailable workers.", requiresManual: true, retryable: false, explain: "The default team has no runnable workers. Inspect and repair the team lineup before running."),
        ErrorSpec("WORKER_FAILED", ruleId: "worker.failed", agentAction: "Inspect `workerId` and source error; failed worker remains visible.", requiresManual: false, retryable: true, explain: "One worker failed. The failure is shown, never hidden; other workers may still have answered. Retry the worker or proceed with partial results."),
        ErrorSpec("PLAN_WRITER_FAILED", ruleId: "plan_writer.failed", agentAction: "Retry with a ready plan writer or export worker answers.", requiresManual: false, retryable: true, explain: "The plan-writer stage failed. Retry with a ready plan writer, or export the worker answers and synthesize later."),
        ErrorSpec("TEAM_RUN_TIMEOUT", ruleId: "team.run.timeout", agentAction: "Retry with lower effort or fewer workers.", requiresManual: false, retryable: true, explain: "The team run exceeded its time budget. Reduce effort or the worker count and retry."),
        ErrorSpec("TEAM_RUN_FAILED", ruleId: "team.run.failed", agentAction: "Inspect failed workers and stages; retry or adjust the team.", requiresManual: false, retryable: true, explain: "The team run ended without a usable result (e.g. failed or cancelled). Inspect the failed workers/stages in the run, then retry or change the team."),
        ErrorSpec("NESTED_TEAM_BLOCKED", ruleId: "team.nested.blocked", agentAction: "Do not recursively spawn teams without explicit depth budget.", requiresManual: true, retryable: false, explain: "A worker tried to start another team run beyond the allowed depth. Set an explicit depth budget if nesting is intended."),
        ErrorSpec("TEAM_GOVERNOR_BUSY", ruleId: "team.governor.busy", agentAction: "Wait or retry after current team run completes.", requiresManual: false, retryable: true, explain: "The concurrency governor is at capacity. Wait for a slot and retry; this is a real busy state, not a fake queue."),
        ErrorSpec("PENDING_MUTATION_DEFERRED", ruleId: "pending.mutation.deferred", agentAction: "Keep item Draft/Pending; mutating dispatch is outside Pending M1.", requiresManual: true, retryable: false, explain: "Mutating dispatch from Pending is not enabled in this milestone. Keep the item Draft/Pending."),
        ErrorSpec("PENDING_REORDER_INVALID", ruleId: "pending.reorder.invalid", agentAction: "Keep order unchanged; reorder only Pending Execute items in the same execution lane.", requiresManual: true, retryable: false, explain: "Reorder is only valid among Pending Execute items in one execution lane. The requested reorder was rejected."),
        ErrorSpec("IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD", ruleId: "idempotency.key.reused", agentAction: "Generate a new key or reuse the original payload.", requiresManual: false, retryable: false, explain: "The same idempotency key was reused with a different canonical payload. Use a new key or repeat the original request."),
        ErrorSpec("RESULT_NOT_READY", ruleId: "result.not_ready", agentAction: "Poll team status using nextPollAfterMs, then call team result again.", requiresManual: false, retryable: true, explain: "The run is not terminal yet. Poll team status and retry team result when resultAvailable is true."),
        ErrorSpec("RUN_NOT_FOUND", ruleId: "run.not_found", agentAction: "Run `alln history --json`.", requiresManual: true, retryable: false, explain: "No run matches the given id. List history and pick a valid run id or `latest`."),
        ErrorSpec("COORDINATOR_UNAVAILABLE", ruleId: "coordinator.unavailable", agentAction: "Use foreground CLI or start resident mode when available.", requiresManual: false, retryable: true, explain: "The resident coordinator is not running. Use a foreground command, or start resident mode when it is available."),
        ErrorSpec("SKILL_NOT_FOUND", ruleId: "skill.not_found", agentAction: "Run `alln skills --lane <lane> --json` and pick a valid skill id.", requiresManual: true, retryable: false, explain: "No skill matches the given id. List skills for the lane and retry with a valid SkillID."),
        ErrorSpec("TEAM_NOT_FOUND", ruleId: "team.not_found", agentAction: "Run `alln teams --lane <lane> --json` and pick a valid team id.", requiresManual: true, retryable: false, explain: "No team matches the given id. List teams for the lane and retry with a valid TeamID."),
        ErrorSpec("TEAM_BUILTIN_IMMUTABLE", ruleId: "team.builtin.immutable", agentAction: "Duplicate the built-in team, then edit the custom copy.", requiresManual: true, retryable: false, explain: "Built-in teams cannot be edited or deleted. Duplicate to a custom team and edit that copy."),
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
        ErrorSpec("MCP_CLIENT_UNAPPROVED", ruleId: "mcp.client.unapproved", agentAction: "Approve or configure the MCP client before retrying.", requiresManual: true, retryable: false, explain: "The calling MCP client is not approved. Approve or configure it, then retry."),
        ErrorSpec("ATTACHMENT_HASH_MISMATCH", ruleId: "attachment.hash.mismatch", agentAction: "Re-ingest or re-send the attachment; do not retry with stale bytes.", requiresManual: true, retryable: false, explain: "Attachment storedSha256 does not match on-disk bytes."),
        ErrorSpec("ATTACHMENT_TOO_MANY", ruleId: "attachment.too_many", agentAction: "Remove attachments until within the count cap.", requiresManual: true, retryable: false, explain: "Too many images attached for one send."),
        ErrorSpec("ATTACHMENT_TOO_LARGE", ruleId: "attachment.too_large", agentAction: "Use a smaller image or fewer attachments.", requiresManual: true, retryable: false, explain: "An attachment exceeds byte or megapixel limits."),
        ErrorSpec("ATTACHMENT_UNSUPPORTED_TYPE", ruleId: "attachment.unsupported_type", agentAction: "Send PNG/JPEG/GIF/WebP only.", requiresManual: true, retryable: false, explain: "Attachment MIME type is not allowed."),
        ErrorSpec("ATTACHMENT_DECODE_FAILED", ruleId: "attachment.decode_failed", agentAction: "Fix or replace the corrupt image file.", requiresManual: true, retryable: false, explain: "Image could not be decoded."),
        ErrorSpec("ATTACHMENT_BASE64_INVALID", ruleId: "attachment.base64_invalid", agentAction: "Fix the base64 payload.", requiresManual: true, retryable: false, explain: "MCP base64 image payload is invalid."),
        ErrorSpec("ATTACHMENT_STAGE_FAILED", ruleId: "attachment.stage_failed", agentAction: "Check workingDir permissions and disk space.", requiresManual: true, retryable: true, explain: "Could not copy attachment into workspace mirror."),
        ErrorSpec("ATTACHMENT_STAGE_UNIGNORED", ruleId: "attachment.stage_unignored", agentAction: "Add `.allnighter/` to gitignore or info/exclude manually.", requiresManual: true, retryable: false, explain: "Staged mirror but could not update git ignore rules."),
        ErrorSpec("CONTEXT_ATTACHMENT_CAP_EXCEEDED", ruleId: "context.attachment.cap", agentAction: "Reduce message or attachment count; never silently trim current send.", requiresManual: true, retryable: false, explain: "Protected attachment block does not fit context cap."),
        ErrorSpec("FILE_REFERENCE_PROJECT_ROOT_MISSING", ruleId: "file.reference.project_root_missing", agentAction: "Bind the thread to a project/working directory, then retry.", requiresManual: true, retryable: false, explain: "File references resolve against the Mac project root. The thread has no usable root."),
        ErrorSpec("FILE_REFERENCE_OUTSIDE_PROJECT", ruleId: "file.reference.outside_project", agentAction: "Pick a path inside the project root.", requiresManual: true, retryable: false, explain: "The requested path escapes the enrolled project root, so Allnighter refused to read it."),
        ErrorSpec("FILE_REFERENCE_NOT_FOUND", ruleId: "file.reference.not_found", agentAction: "Refresh the file picker or choose an existing project file.", requiresManual: true, retryable: false, explain: "The referenced file no longer exists at dispatch time."),
        ErrorSpec("FILE_REFERENCE_UNREADABLE", ruleId: "file.reference.unreadable", agentAction: "Check file permissions or choose another file.", requiresManual: true, retryable: false, explain: "The file exists but Allnighter could not read it as a regular file."),
        ErrorSpec("FILE_REFERENCE_BINARY_UNSUPPORTED", ruleId: "file.reference.binary_unsupported", agentAction: "Reference text files only in v1.", requiresManual: true, retryable: false, explain: "File references v1 injects UTF-8 text. Binary files are not delivered."),
        ErrorSpec("FILE_REFERENCE_TOO_LARGE", ruleId: "file.reference.too_large", agentAction: "Reference a smaller file or a line range.", requiresManual: true, retryable: false, explain: "The source file exceeds the v1 per-file read cap."),
        ErrorSpec("FILE_REFERENCE_TOO_MANY", ruleId: "file.reference.too_many", agentAction: "Remove file references until within the cap.", requiresManual: true, retryable: false, explain: "The send has more file references than v1 allows."),
        ErrorSpec("FILE_REFERENCE_SENSITIVE_BLOCKED", ruleId: "file.reference.sensitive_blocked", agentAction: "Do not attach secrets; summarize the needed config manually.", requiresManual: true, retryable: false, explain: "The path looks like credentials, keys, or an environment file and was blocked."),
        ErrorSpec("FILE_REFERENCE_LINE_RANGE_INVALID", ruleId: "file.reference.line_range_invalid", agentAction: "Choose a valid 1-based line range inside the file.", requiresManual: true, retryable: false, explain: "The requested line range is empty, reversed, or past the end of the file."),
        ErrorSpec("FILE_REFERENCE_CHANGED_BEFORE_INVOKE", ruleId: "file.reference.changed_before_invoke", agentAction: "Refresh the reference and re-approve the changed file before dispatch.", requiresManual: true, retryable: false, explain: "A delayed or pending send would read different bytes than the approved reference hash."),
        ErrorSpec("FILE_REFERENCE_CATALOG_STALE", ruleId: "file.reference.catalog_stale", agentAction: "Refresh the Project file picker and retry.", requiresManual: false, retryable: true, explain: "The search catalog was stale. The resolver remains authoritative and did not deliver stale content."),
        ErrorSpec("FILE_REFERENCE_WORKER_UNSUPPORTED", ruleId: "file.reference.worker_unsupported", agentAction: "Choose a worker that can receive referenced file text or use a chat worker.", requiresManual: true, retryable: false, explain: "The selected route cannot accept Project file references."),
        ErrorSpec("THREAD_SEND_IDEMPOTENCY_CONFLICT", ruleId: "thread.send.idempotency.conflict", agentAction: "Use a new idempotency key or repeat the original payload.", requiresManual: false, retryable: false, explain: "Same idempotency key reused with a different thread send payload."),
        ErrorSpec("THREAD_NOT_FOUND", ruleId: "thread.not_found", agentAction: "Run `alln history --json` (or create a thread); retry with a valid thread id.", requiresManual: true, retryable: false, explain: "No thread matches the given id, or no threads exist yet. List threads and retry with a valid thread id."),
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
        ErrorSpec("PROJECT_ROOT_UNAVAILABLE", ruleId: "project.root_unavailable", agentAction: "Restore the folder/permissions, then `alln project show <id>` to re-observe.", requiresManual: true, retryable: true, explain: "The project root is missing or permission-denied (rootState != available); mutating dispatch is blocked until the root is restored."),
        ErrorSpec("PROJECT_ARCHIVED", ruleId: "project.archived", agentAction: "Run `alln project unarchive <id>` before new runs.", requiresManual: true, retryable: false, explain: "The project is archived. Unarchive it before starting new runs; reads remain available."),
        ErrorSpec("THREAD_UNASSIGNED", ruleId: "thread.unassigned", agentAction: "Assign the thread/pending item to a project, then retry.", requiresManual: true, retryable: false, explain: "The thread or pending item has no project. Assign it to a project before mutating dispatch."),
        ErrorSpec("WORKER_NOT_READY_IN_PROJECT", ruleId: "project.worker_not_ready", agentAction: "Run `alln project workers <id> --json`; open the CLI in the project folder and complete its trust/login, then recheck.", requiresManual: true, retryable: true, explain: "The target worker's project readiness is not `ready` for this root. Dispatch falls back to reveal or shows setup copy until the worker is ready here."),
        ErrorSpec("MANAGER_MODEL_UNAVAILABLE", ruleId: "project.manager_model_unavailable", agentAction: "Run `alln models --json`; enable a ready planner-capable model.", requiresManual: false, retryable: true, explain: "No ready manager model is available, so the Manager turn is `wait` with a readiness blocker rather than a fabricated answer."),
        ErrorSpec("PROPOSAL_NOT_FOUND", ruleId: "project.proposal_not_found", agentAction: "Run `alln project proposals <id> --json`; retry with a valid proposal id.", requiresManual: true, retryable: false, explain: "No proposal matches the given id."),
        ErrorSpec("PROPOSAL_NOT_APPROVED", ruleId: "project.proposal_not_approved", agentAction: "Approve the proposal (`alln project approve <id>`) before dispatch.", requiresManual: true, retryable: false, explain: "Dispatch was attempted on an unapproved proposal or work order. Approval is required first."),
        ErrorSpec("BASE_HEAD_CHANGED", ruleId: "project.base_head_changed", agentAction: "Revalidate the proposal against the current head, then dispatch.", requiresManual: true, retryable: false, explain: "The approved baseGitHead differs from the current head. Revalidate scope before dispatching."),
        ErrorSpec("DIRTY_SCOPE_CONFLICT", ruleId: "project.dirty_scope_conflict", agentAction: "Acknowledge including the dirty files or clean them, then dispatch.", requiresManual: true, retryable: false, explain: "Dirty files overlap the proposal's likely scope. Acknowledge them as preexisting context or clean them first."),
        ErrorSpec("DISPATCH_GATE_FAILED", ruleId: "project.dispatch_gate_failed", agentAction: "Read the named failing gate(s) and resolve each, then retry dispatch.", requiresManual: true, retryable: false, explain: "One or more dispatch gates failed. The failing gate(s) are named in the message."),
        ErrorSpec("VERIFICATION_REQUIRED", ruleId: "project.verification_required", agentAction: "Run `alln project verify <id>`; a worker claim cannot mark work done.", requiresManual: false, retryable: false, explain: "A completion claim was advanced to done without a VerificationRecord. Verification (proof + git observation) or an explicit waiver is required."),
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
        DoctorCheckSpec("source.<sourceId>.smoke", meaning: "Bounded smoke test when --full."),
        DoctorCheckSpec("benchReadyCount", meaning: "At least one model is ready."),
        DoctorCheckSpec("defaultTeamValid", meaning: "Default team has runnable workers."),
        DoctorCheckSpec("planWriterReady", meaning: "Default team has a ready plan worker."),
        DoctorCheckSpec("coordinator", meaning: "Resident coordinator state; may be degraded in M1."),
        DoctorCheckSpec("journal.incrementalDurable", meaning: "Async run journal persists worker/status transitions incrementally."),
        DoctorCheckSpec("journal.orphanRecovery", meaning: "Orphaned async runs resolve to interrupted."),
        DoctorCheckSpec("pending.storeReadable", meaning: "Pending store can be read."),
        DoctorCheckSpec("pending.storeWritable", meaning: "Pending store can be mutated."),
        DoctorCheckSpec("mcpDescriptorsCurrent", meaning: "Deferred until MCP scope, but registry name reserved."),
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
        ExampleRecipe("models_json", title: "List model catalog and Bench state", command: "alln models --json"),
        ExampleRecipe("team_show_json", title: "Show the current team", command: "alln team show --json"),
        ExampleRecipe("teams_build_json", title: "List Build teams", command: "alln teams --lane build --json"),
        ExampleRecipe("skills_build_json", title: "List Build skills", command: "alln skills --lane build --json"),
        ExampleRecipe("skills_show_json", title: "Show a Build skill", command: "alln skills show bug_reproducer --json"),
        ExampleRecipe("team_preflight", title: "Preflight a team", command: "alln team preflight --lane build --team code_bug_hunt --effort high"),
        ExampleRecipe("team_basic", title: "Ask the team", command: "alln team --lane build --team code_bug_hunt \"Why does run history disappear?\""),
        ExampleRecipe("team_json", title: "Machine team run", command: "alln team --json \"Give me one small naming test.\""),
        ExampleRecipe("team_stream", title: "Streamed team run", command: "alln team --stream \"Give me one tiny event-stream test.\""),
        ExampleRecipe("team_start_json", title: "Start async team run", command: "alln team start --json --lane build --team code_bug_hunt --effort low \"tiny async sanity\""),
        ExampleRecipe("show_latest_json", title: "Show the latest run", command: "alln show latest --json"),
        ExampleRecipe("spec_full", title: "Retrieve the full result packet", command: "alln spec latest --detail full --json"),
        ExampleRecipe("export_md", title: "Export the latest result", command: "alln export latest --format md"),
        ExampleRecipe("export_contracts_check", title: "Verify no contract drift", command: "alln dev export-contracts --check"),
        ExampleRecipe("thread_send_json", title: "Send message with image and file reference to thread", command: "alln thread send latest \"describe this\" --image ./shot.png --ref Sources/App.swift:10-80 --json"),
        ExampleRecipe("serve_health_json", title: "Coordinator health", command: "alln serve --health --json"),
        ExampleRecipe("pending_add_json", title: "Create a Draft Pending item", command: "alln pending add --worker claude --when ready --json \"Review this patch when Claude is available.\""),
        ExampleRecipe("pending_list_json", title: "List Pending items", command: "alln pending list --json"),
    ]
}
