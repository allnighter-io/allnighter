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
        MCPToolSpec("mcp_hello", command: "team teams", summary: "Agent bootstrap: whether a team can start now, which teams are ready, and the next action. Cheap, non-mutating, no quota.",
                    params: [.init("agent", summary: "Calling agent id for provenance (advisory only).")]),
        MCPToolSpec("teams_list", command: "team teams", summary: "Lane-scoped team catalog summary (no prompt templates).",
                    params: [.init("lane", summary: "Filter to one lane: build|design|copy (optional).")]),
        MCPToolSpec("team_preflight", command: "team preflight", summary: "Validate lane/team/effort against the ready bench WITHOUT running or spending quota; shows resolved/blocked workers and self-fusion.",
                    params: [.init("lane", summary: "build|design|copy."),
                             .init("team", summary: "Team id (e.g. build_bug_hunt)."),
                             .init("effort", summary: "low|med|high (optional; default is the team's)."),
                             .init("type", summary: "Copy-only routing sugar (optional).")]),
        MCPToolSpec("team_start", command: "team start", summary: "Start an async team run; returns run id after preflight and journal write.",
                    params: [.init("prompt", required: true, summary: "The prompt to run."),
                             .init("lane", summary: "build|design|copy."),
                             .init("team", summary: "Team id."),
                             .init("effort", summary: "low|med|high."),
                             .init("type", summary: "Copy-only routing sugar (optional)."),
                             .init("context", summary: "Bounded inline context (optional)."),
                             .init("threadId", summary: "Owning work thread id (optional)."),
                             .init("originAgent", summary: "Calling agent id for provenance."),
                             .init("originConversationId", summary: "Origin conversation id."),
                             .init("originMessageId", summary: "Origin message id."),
                             .init("idempotencyKey", summary: "Client idempotency key (24h retention).")],
                    outputSchema: .teamStartResponse),
        MCPToolSpec("team_status", command: "team status", summary: "Poll live async run state with nextPollAfterMs.",
                    params: [.init("runId", required: true, summary: "Run id from team_start.")],
                    outputSchema: .teamStatusResponse),
        MCPToolSpec("team_result", command: "team result", summary: "Fetch TeamRunJSON when terminal, or a not-ready envelope.",
                    params: [.init("runId", required: true, summary: "Run id from team_start.")],
                    outputSchema: .teamRunJSON),
        MCPToolSpec("team_cancel", command: "team cancel", summary: "Cancel an active async team run.",
                    params: [.init("runId", required: true, summary: "Run id from team_start.")],
                    outputSchema: .teamCancelResponse),
        MCPToolSpec("team_ask", command: "team", summary: "Run a lane team on a prompt; returns a synthesized result + structured run.",
                    params: [.init("question", required: true, summary: "The prompt to ask the team."),
                             .init("lane", summary: "build|design|copy (explicit; never inferred)."),
                             .init("team", summary: "Team id; `--preset` is a hidden alias."),
                             .init("effort", summary: "low|med|high (optional)."),
                             .init("type", summary: "Copy-only routing sugar (optional)."),
                             .init("context", summary: "Bounded context snippet to consider (optional).")],
                    outputSchema: .teamRunJSON),
        MCPToolSpec("team_show", command: "team show", summary: "Show the default team for each lane."),
        MCPToolSpec("history", command: "history", summary: "Search prior local team runs (read-only, zero cost).",
                    params: [.init("query", required: true, summary: "Search text.")]),
        MCPToolSpec("show", command: "show", summary: "Show one run as TeamRunJSON.",
                    params: [.init("run", required: true, summary: "A run id or `latest`.")],
                    outputSchema: .teamRunJSON),
        MCPToolSpec("doctor", command: "doctor", summary: "Diagnostics report; quota-free unless `full` is set.",
                    params: [.init("full", type: "boolean", summary: "Run smoke probes (spends quota).")],
                    outputSchema: .doctorResult),
        MCPToolSpec("error_explain", command: "doctor explain", summary: "Explain an error/recovery code: cause, who can fix it, and the next action.",
                    params: [.init("code", required: true, summary: "The error code to explain, e.g. SOURCE_AUTH_EXPIRED.")]),
        MCPToolSpec("spec_get", command: "spec", summary: "Retrieve a run's full spec/result packet without opening the GUI. Failed workers and warnings always included in full detail.",
                    params: [.init("run", summary: "Run id or `latest` (default latest)."),
                             .init("detail", summary: "summary | full | artifactRefsOnly (default summary).")],
                    outputSchema: .teamRunJSON),
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
            outputSchema: .errorEnvelope, exampleIds: ["doctor_explain"]
        ),
        CommandSpec(
            "models", summary: "List ready/known models on the Bench.", milestone: .m1,
            flags: [FlagSpec("json", summary: "Structured model list.")],
            exampleIds: ["models_json"]
        ),
        CommandSpec(
            "team show", summary: "Show the default team for each lane.", milestone: .m1,
            flags: [FlagSpec("lane", takesValue: true, valueType: "lane", summary: "Limit to one lane."),
                    FlagSpec("json", summary: "Structured team snapshot.")],
            exampleIds: ["team_show_json"]
        ),
        CommandSpec(
            "team teams", summary: "List the lane-scoped team catalog.", milestone: .m1,
            flags: [FlagSpec("lane", takesValue: true, valueType: "lane", summary: "Filter to one lane."),
                    FlagSpec("json", summary: "Structured catalog summary.")],
            exampleIds: ["teams_build_json"]
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
                FlagSpec("team", takesValue: true, valueType: "id", summary: "Team id (the public Fan out selector)."),
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
            flags: [FlagSpec("json", summary: "Emit the run as TeamRunJSON.")],
            outputSchema: .teamRunJSON, exampleIds: ["show_latest_json"]
        ),
        CommandSpec(
            "spec", summary: "Retrieve a run's spec/result packet (summary|full|artifactRefsOnly).", milestone: .m1,
            args: [ArgSpec("run-id|latest", required: false, summary: "A run id or `latest` (default latest).")],
            flags: [FlagSpec("detail", takesValue: true, valueType: "detail", defaultValue: "summary", summary: "summary | full | artifactRefsOnly."),
                    FlagSpec("json", summary: "Structured SpecRetrieval result.")],
            exampleIds: ["spec_full"]
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
            flags: [FlagSpec("json", summary: "Structured results.")]
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
            "mcp serve", summary: "Run the MCP stdio server.", milestone: .m1,
            flags: [FlagSpec("stdio", summary: "Use stdio transport (default).")]
        ),
    ]

    // MARK: - Commands (named but deferred past M1)

    static let deferredCommands: [CommandSpec] = [
        CommandSpec("team edit", summary: "Edit the team lineup.", milestone: .deferred),
        CommandSpec("models add", summary: "Add/configure a model.", milestone: .deferred),
        CommandSpec("work", summary: "Create a work order.", milestone: .deferred),
        CommandSpec("pending add", summary: "Queue a Pending item.", milestone: .deferred),
        CommandSpec("pending list", summary: "List Pending items.", milestone: .deferred),
        CommandSpec("pending show", summary: "Show one Pending item.", milestone: .deferred),
        CommandSpec("pending submit", summary: "Move a Draft item to Pending.", milestone: .deferred),
        CommandSpec("pending edit", summary: "Edit a Pending item.", milestone: .deferred),
        CommandSpec("pending reorder", summary: "Reorder Pending Execute items in one lane.", milestone: .deferred),
        CommandSpec("pending cancel", summary: "Cancel a Pending item.", milestone: .deferred),
        CommandSpec("pending run", summary: "Run a Pending item now.", milestone: .deferred),
        CommandSpec("pending stop", summary: "Stop a running Pending item.", milestone: .deferred),
        CommandSpec("dispatch", summary: "Send a work order/spec to an execution target.", milestone: .deferred),
        CommandSpec("pair", summary: "Approve iOS/Mac pairing.", milestone: .deferred),
        CommandSpec("mcp install", summary: "Write MCP config with user consent.", milestone: .deferred),
    ]

    // MARK: - Error catalog

    static let m1Errors: [ErrorSpec] = [
        ErrorSpec("CLI_USAGE_ERROR", ruleId: "cli.usage.error", agentAction: "Re-run `alln docs <command>` and fix arguments.", requiresManual: true, retryable: false, explain: "The command was called with invalid or conflicting arguments. Consult the generated docs for the command and correct the invocation."),
        ErrorSpec("CONTRACT_DRIFT", ruleId: "contract.drift", agentAction: "Run `alln dev export-contracts`, then rebuild.", requiresManual: true, retryable: false, explain: "Generated artifacts no longer match the registry. Regenerate and rebuild before relying on output."),
        ErrorSpec("DOCTOR_CHECK_FAILED", ruleId: "doctor.check.failed", agentAction: "Run `alln doctor --json`.", requiresManual: false, retryable: true, explain: "A required doctor check failed. Inspect the structured report and address the named check, then retry."),
        ErrorSpec("SOURCE_NOT_FOUND", ruleId: "source.not_found", agentAction: "Run `alln doctor --json`; add/configure the missing source.", requiresManual: true, retryable: false, explain: "A required source CLI/runtime was not resolved on this machine. Install or locate it, then re-probe."),
        ErrorSpec("SOURCE_AUTH_EXPIRED", ruleId: "source.auth.expired", agentAction: "Re-authenticate the named source.", requiresManual: true, retryable: false, explain: "The source resolved but its authentication is invalid or expired. Sign in via the source's own login flow."),
        ErrorSpec("MODEL_UNAVAILABLE", ruleId: "model.unavailable", agentAction: "Choose a ready model or run `alln models --json`.", requiresManual: false, retryable: true, explain: "The requested model is not ready right now. Pick a ready model from the Bench or retry when it recovers."),
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
        ErrorSpec("JSON_SCHEMA_VIOLATION", ruleId: "json.schema.violation", agentAction: "Treat as implementation bug; run export-contracts check.", requiresManual: true, retryable: false, explain: "Output failed to match its declared schema. This is an implementation bug; run the export-contracts drift check."),
        ErrorSpec("PERMISSION_REQUIRED", ruleId: "permission.required", agentAction: "Ask the user for the named permission.", requiresManual: true, retryable: false, explain: "The action needs a user-granted permission that is not present. Request the named permission before retrying."),
        ErrorSpec("MCP_CLIENT_UNAPPROVED", ruleId: "mcp.client.unapproved", agentAction: "Approve or configure the MCP client before retrying.", requiresManual: true, retryable: false, explain: "The calling MCP client is not approved. Approve or configure it, then retry."),
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
    ]

    /// The closed `nextActions.kind` catalog. Must stay in lock-step with
    /// `TeamRunJSON.NextAction.Kind` (a test enforces parity).
    static let m1NextActionKinds: [NextActionKindSpec] = [
        NextActionKindSpec("showRun", summary: "Show the full run."),
        NextActionKindSpec("export", summary: "Export the result bundle."),
        NextActionKindSpec("showHistory", summary: "List recent runs."),
    ]

    // MARK: - Example recipes

    static let m1Examples: [ExampleRecipe] = [
        ExampleRecipe("docs_all", title: "Generate the full reference", command: "alln docs"),
        ExampleRecipe("doctor_json", title: "Structured diagnostics", command: "alln doctor --json"),
        ExampleRecipe("doctor_explain", title: "Explain an error code", command: "alln doctor explain SOURCE_AUTH_EXPIRED --json"),
        ExampleRecipe("models_json", title: "List bench models", command: "alln models --json"),
        ExampleRecipe("team_show_json", title: "Show the current team", command: "alln team show --json"),
        ExampleRecipe("teams_build_json", title: "List Build teams", command: "alln team teams --lane build --json"),
        ExampleRecipe("team_preflight", title: "Preflight a team", command: "alln team preflight --lane build --team build_bug_hunt --effort high"),
        ExampleRecipe("team_basic", title: "Ask the team", command: "alln team --lane build --team build_bug_hunt \"Why does run history disappear?\""),
        ExampleRecipe("team_json", title: "Machine team run", command: "alln team --json \"Give me one small naming test.\""),
        ExampleRecipe("team_stream", title: "Streamed team run", command: "alln team --stream \"Give me one tiny event-stream test.\""),
        ExampleRecipe("team_start_json", title: "Start async team run", command: "alln team start --json --lane build --team build_bug_hunt --effort low \"tiny async sanity\""),
        ExampleRecipe("show_latest_json", title: "Show the latest run", command: "alln show latest --json"),
        ExampleRecipe("spec_full", title: "Retrieve the full result packet", command: "alln spec latest --detail full --json"),
        ExampleRecipe("export_md", title: "Export the latest result", command: "alln export latest --format md"),
        ExampleRecipe("export_contracts_check", title: "Verify no contract drift", command: "alln dev export-contracts --check"),
        ExampleRecipe("serve_health_json", title: "Coordinator health", command: "alln serve --health --json"),
    ]
}
