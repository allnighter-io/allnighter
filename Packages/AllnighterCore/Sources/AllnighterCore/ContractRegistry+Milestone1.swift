import Foundation

/// The milestone-1 `alln` contract, transcribed from
/// docs/archive/phases/CLI_Implementation_Contract.md (§Milestone Boundary, §CLI Grammar,
/// §NDJSON Stream, §Error Envelope, §Doctor Contract). This is the data; the
/// generators that project docs/schemas from it are step 3.
public extension ContractRegistry {
    /// Agent-facing compatibility number (AE-S11): removing/renaming a command or
    /// flag = major; adding a command/flag/error = minor. Distinct from
    /// `binaryVersion` (human release label) and `gitSha`/`buildTime` (build identity).
    // ORS-S03c: major cut — delete public audit.runJournalPath (filesystem escape hatch).
    // LOOP-REG: minor — declare the seven already-implemented `alln loop` verbs.
    // ORS-P2-NULL: minor — Observation.required gains always-present nullable
    // `lastActivityAt` (key never omitted; null when unobserved). Additive optional
    // `workerActivity.data.tool` is wire-only and does not change EventSpec.
    // CAP-PRINT: patch — capacity command trigger/summary/antiExample/example teach
    // verbatim human-table delivery; --json only on explicit machine request.
    // HY-S04: patch — retired pair pilot handoff summary drops false loop step --no-wait.
    // OCG-S09: minor — capacity six→seven seats; --dogfood no longer gates opencode_go;
    // register opencode-go configure + status commands; new help topic.
    // CWB-S01c: minor — register capacity --enable and --disable flags with
    // mutually-exclusive constraint; repoWrite effect. saveEnabled throws.
    // QDR-S01: minor — show gains --answer (durable answer retrieval for
    // in-flight/killed/failed runs), showAnswer nextAction kind, RUN_NO_ANSWER.
    static let contractVersion = "9.10.0"

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
            "menu",
            summary: "Live compact agent menu: public commands, teams, models, recipes, effects, and defaults.",
            milestone: .m1,
            trigger: "Use before first Allnighter spend in a session to discover runnable commands, teams, and models.",
            example: "alln menu --json",
            antiExample: "Do NOT use this to start work — choose a command/team/model from the menu, then validate with its template.",
            flags: [
                FlagSpec("json", summary: "Emit MenuJSON (default; always machine JSON)."),
                FlagSpec("detailed", summary: "Add per-model ref, capability tags, and invocation templates, and list off-bench seats. Tier-1 omits these."),
            ],
            outputSchema: .menuJSON,
            spendsQuota: false,
            effects: EffectProfile()
        ),
        CommandSpec(
            "menu show",
            summary: "Hydrate one typed menu ref (command:/team:/model:/recipe:) into Tier-2 detail.",
            milestone: .m1,
            trigger: "Use when a Tier-1 menu row is not enough and you need flags, prose, or full recipe body.",
            example: "alln menu show command:run --json",
            antiExample: "Do NOT use this to discover the catalog — call `alln menu --json` first.",
            args: [ArgSpec("ref", required: true, summary: "Typed ref, e.g. command:run, team:code_growth, model:model_sonnet.")],
            flags: [FlagSpec("json", summary: "Emit MenuShowJSON (default; always machine JSON).")],
            outputSchema: .menuShowJSON,
            spendsQuota: false,
            effects: EffectProfile()
        ),
        CommandSpec(
            "doctor", summary: "Check sources, models, auth, and coordinator.", milestone: .m1,
            flags: [
                FlagSpec("json", summary: "Structured DoctorResult for agents/GUI."),
                FlagSpec("quiet", summary: "Failed checks only."),
                FlagSpec("full", summary: "Deeper probes, bounded timeout."),
                FlagSpec("auto-fix", summary: "Apply safe Allnighter-owned fixes."),
                FlagSpec("agent", takesValue: true, valueType: "sourceId", summary: "Limit probes and checks to one source (e.g. cursor_agent)."),
                FlagSpec("pilot", summary: "Include a `pilot` summary check (can pilot start on this project?)."),
                FlagSpec("project", takesValue: true, valueType: "id", summary: "Project for `--pilot` (default: cwd)."),
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
            "doctor handoff",
            summary: "Check whether work handed off from this terminal will actually be run by the Allnighter app. Drops one liveness ping in the hand-off mailbox; starts no worker and spends no quota. Distinguishes nothing-claimed-it from claimed-and-went-silent — never guesses.",
            milestone: .m1,
            flags: [FlagSpec("json", summary: "Structured HandoffDoctorJSON verdict.")],
            outputSchema: .handoffDoctorJSON
        ),
        CommandSpec(
            "doctor silence",
            summary: "Mine run journals for idle-timeout (`timeoutKind: idle`) events into per-driver silence-duration histograms. Read-only telemetry for IDLE-HF floor decisions; spends no quota.",
            milestone: .m1,
            flags: [FlagSpec("json", summary: "Structured RunJournalSilenceTelemetry.Report.")],
            outputSchema: .idleSilenceReportJSON
        ),
        CommandSpec(
            "detect", summary: "Headless first-run CLI detection — probes sources, assembles the Bench/default team from ready ones, and persists the result.", milestone: .m1,
            outputSchema: .none
        ),
        CommandSpec(
            "capacity",
            summary: "Show the seven-row vendor capacity/quota table. When the user asks to print/show/display capacity, run bare `alln capacity` and paste the COMPLETE human stdout table verbatim in the final response — never a summary, highlights, JSON, or \"shown above\". Bare is live cold PTY (no disk/history hydrate-as-live); --refresh is a legacy no-op; --json only on explicit JSON/machine request.",
            milestone: .m1,
            trigger: "Use when the user asks to print, show, or display `alln capacity` / quota headroom — run bare `alln capacity` and include the complete human-readable stdout table verbatim in your final response.",
            example: "alln capacity",
            antiExample: "Do NOT summarize the table, pick highlights, reply with JSON, or say \"shown above\" when the user asked to print capacity — hosts often hide shell tool output. Do NOT default to `alln capacity --json` unless the user explicitly requested JSON/machine-readable output or a program needs the schema.",
            flags: [
                FlagSpec("json", summary: "Emit JSON instead of the human-readable strip. Use only when the user explicitly requests JSON/machine-readable output or a program needs the schema."),
                FlagSpec("refresh", summary: "Legacy no-op; bare `alln capacity` is already a live cold PTY acquire. Kept for existing scripts."),
                FlagSpec("source", takesValue: true, summary: "Target one seat for the live probe (still returns the full seven-row strip). Valid: \(CapacityAcquisition.validRefreshSourceIds.joined(separator: ", "))."),
                FlagSpec("enable", summary: "Turn the capacity feature ON and exit. Writes a setting; probes nothing. Default for a new install is already ON."),
                FlagSpec("disable", summary: "Turn the capacity feature OFF and exit. Writes a setting; probes nothing. While OFF no seat is probed from any trigger."),
                FlagSpec("dogfood", summary: "Developer-only direct OpenCode Go dashboard scrape (bypasses the normal bench; requires --source opencode_go). Omit for normal use — opencode_go is a regular bench member without it."),
            ],
            mutuallyExclusiveFlags: [["enable", "disable"]],
            outputSchema: .capacityStripJSON,
            spendsQuota: false,
            effects: EffectProfile(repoWrite: .dependsOnFlags)
        ),
        CommandSpec(
            "opencode-go configure",
            summary: "Save encrypted OpenCode Go dashboard credentials for the capacity scrape. Writes a secret to the macOS Keychain — never prints it. The safe non-interactive form pipes the cookie via stdin with --workspace-id; --cookie also works but exposes the value in shell history.",
            milestone: .m1,
            trigger: "Use before first `alln capacity --source opencode_go` to configure the dashboard seat. The cookie comes from a logged-in browser: DevTools → Application → Cookies → copy the `auth` value.",
            example: "echo '<cookie>' | alln opencode-go configure --workspace-id wrk_…",
            antiExample: "Do NOT pass --cookie with the raw auth value — it lands in shell history and process listings. Pipe via stdin or let the interactive prompt read it with echo disabled.",
            flags: [
                FlagSpec("workspace-id", takesValue: true, valueType: "string", summary: "Workspace ID from the dashboard URL (wrk_…). Required in non-interactive stdin mode."),
                FlagSpec("cookie", takesValue: true, valueType: "string", summary: "Auth cookie value (WARNING: exposes the session token in shell history and process listings — prefer piping via stdin)."),
                FlagSpec("json", summary: "Emit structured output."),
            ],
            spendsQuota: false,
            effects: EffectProfile(
                workerStart: .never,
                quotaSpend: .never,
                repoWrite: .never,
                destructive: .never,
                humanInteraction: .dependsOnSelection
            )
        ),
        CommandSpec(
            "opencode-go status",
            summary: "Check whether OpenCode Go dashboard credentials are configured and usable. Distinguishes not-configured from configured-but-unusable (different recovery paths).",
            milestone: .m1,
            trigger: "Use to diagnose why `alln capacity` shows opencode_go as neverSampled or authRequired — the status output names the exact recovery path.",
            example: "alln opencode-go status",
            antiExample: "Do NOT guess the status from the capacity strip alone — run status for the exact failure reason and recovery action.",
            flags: [
                FlagSpec("json", summary: "Emit structured status JSON (configured, workspaceId, credentialSource, error)."),
            ],
            spendsQuota: false
        ),
        CommandSpec(
            "bootstrap", summary: "Print a paste-ready agent-activation snippet for a host's context file (never edits files).", milestone: .m1,
            flags: [
                FlagSpec("host", takesValue: true, valueType: "host", summary: "claude | cursor | codex | generic | hermes | openclaw (default generic)."),
                FlagSpec("json", summary: "Structured { host, pasteTarget, snippet, binaryPath, onPath }."),
            ],
            outputSchema: .bootstrapJSON, exampleIds: ["bootstrap_json"]
        ),
        CommandSpec(
            "version", summary: "Print the running binary version and contract hash.", milestone: .m1,
            flags: [FlagSpec("json", summary: "Structured VersionJSON.")],
            outputSchema: .versionJSON, exampleIds: ["version_json"]
        ),
        CommandSpec(
            "update",
            summary: "Show whether a newer alln release is available (soft-announce only; never downloads).",
            milestone: .m1,
            flags: [
                FlagSpec("check", summary: "Same as bare update — print current, latest, and the install one-liner."),
                FlagSpec("json", summary: "Structured { available, current, latest?, command }."),
            ],
            exampleIds: ["update_check"]
        ),
        CommandSpec(
            "install-cli", summary: "Symlink the running `alln` binary onto PATH (running the command is consent).", milestone: .m1,
            flags: [
                FlagSpec("path", takesValue: true, valueType: "path", summary: "Install directory override (default /usr/local/bin if writable, else ~/.local/bin)."),
                FlagSpec("print", summary: "Print install instructions only (legacy print-only behavior)."),
                FlagSpec("json", summary: "Structured { action, path, target, onPath }."),
            ],
            outputSchema: .installCLIJSON, exampleIds: ["install_cli_json"]
        ),
        CommandSpec(
            "models", summary: "List model catalog and Bench state (catalog ids). Prefer `alln menu --json` to discover selectable models.", milestone: .m1,
            flags: [
                FlagSpec("json", summary: "Structured ModelListJSON."),
                FlagSpec("driver", takesValue: true, valueType: "driverId", summary: "Filter to one source."),
                FlagSpec("bench", summary: "Show only enabled Bench models."),
            ],
            outputSchema: .modelListJSON, exampleIds: ["models_json"],
            menuAction: true
        ),
        CommandSpec(
            "drivers", summary: "List headless CLIs and park state. Parked CLIs are ignored (no probe, no seats) until unparked.", milestone: .m1,
            flags: [FlagSpec("json", summary: "Structured DriverListJSON (parked listed last).")],
            outputSchema: .driverListJSON, exampleIds: ["drivers_json"],
            menuAction: true
        ),
        CommandSpec(
            "drivers park", summary: "Park a CLI — stop probing it, hide it from Ready, and keep it out of seating until unparked.", milestone: .m1,
            args: [ArgSpec("driver-id", required: true, summary: "Driver id (see `alln drivers --json`).")],
            flags: [FlagSpec("json", summary: "Return refreshed DriverListJSON.")],
            outputSchema: .driverListJSON
        ),
        CommandSpec(
            "drivers unpark", summary: "Put a parked CLI back on the bench (does not auto-probe; run re-check or `alln detect`).", milestone: .m1,
            args: [ArgSpec("driver-id", required: true, summary: "Driver id (see `alln drivers --json`).")],
            flags: [FlagSpec("json", summary: "Return refreshed DriverListJSON.")],
            outputSchema: .driverListJSON
        ),
        CommandSpec(
            "catalog validate", summary: "Validate bundled AgentOS catalog and Allnighter overlay (schema + effort consistency).", milestone: .m1,
            flags: [FlagSpec("json", summary: "Structured validation summary.")],
            outputSchema: .catalogValidateJSON
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
            "models add", summary: "Add a custom model (saved unverified; run `alln models verify` before enable).", milestone: .m1,
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
            "models verify", summary: "Smoke-verify a custom model label via AgentOS (AGENTOS_MODEL_OK).", milestone: .m1,
            args: [ArgSpec("model-id", required: true, summary: "Custom model id to verify.")],
            flags: [FlagSpec("json", summary: "Structured { id, status, detail, driverId, label }.")],
            spendsQuota: true,
            freeTwinCommand: "alln models"
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
            "teams", summary: "List the lane-scoped team catalog. Prefer `alln menu --json` / `alln teams show <id>` over guessing ids.", milestone: .m1,
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
                FlagSpec("model", takesValue: true, valueType: "string", summary: "Requested model id."),
                FlagSpec("idempotency-key", takesValue: true, valueType: "string", summary: "Idempotency key (24h)."),
                FlagSpec("json", summary: "Structured send result."),
            ],
            exampleIds: ["thread_send_json"],
            spendsQuota: true,
            freeTwinCommand: "alln menu --json"
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
            flags: [
                FlagSpec("title", takesValue: true, valueType: "string", summary: "Alias for the positional new title."),
                FlagSpec("json", summary: "Structured thread JSON."),
            ],
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
            "teams show", summary: "Show one team with crew, optional scout, lead, and seatCount (not the round-trip manifest — use teams definition).", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "Team id.")],
            flags: [FlagSpec("json", summary: "Structured team detail with crew/scout/lead and seatCount.")],
            outputSchema: .teamShowJSON,
            exampleIds: ["teams_show_json"]
        ),
        CommandSpec(
            "teams definition", summary: "Full TeamPreset JSON round-trippable through teams edit/save.", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "Team id.")],
            flags: [FlagSpec("json", summary: "Structured team definition (TeamPreset).")],
            outputSchema: .teamPreset,
            exampleIds: ["teams_definition_json"]
        ),
        CommandSpec(
            "teams duplicate", summary: "Copy a shipped team (prefer Bug Hunt) into a custom variant; then edit. Omit --id for a generated id. --json returns the editable TeamPreset (feed straight to teams edit).", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "Source built-in team id.")],
            flags: [
                FlagSpec("id", takesValue: true, valueType: "string", summary: "Caller-chosen custom team id (deterministic; rejects collisions)."),
                FlagSpec("name", takesValue: true, valueType: "string", summary: "Display name for the copy."),
                FlagSpec("json", summary: "Editable TeamPreset JSON (same shape as teams definition / teams edit)."),
            ],
            outputSchema: .teamPreset,
            exampleIds: ["teams_duplicate_json"],
            menuAction: true
        ),
        CommandSpec(
            "teams new", summary: "Create a novel custom team from a TeamPreset file. Fails if id exists or file id ≠ positional id. To copy a shipped team instead, use teams duplicate. --json returns the editable TeamPreset.", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "New team id (must match file definition.id).")],
            flags: [
                FlagSpec("file", takesValue: true, valueType: "path", summary: "TeamPreset JSON file (or CatalogEnvelope)."),
                FlagSpec("json", summary: "Editable TeamPreset JSON (same shape as teams definition / teams duplicate)."),
            ],
            outputSchema: .teamPreset,
            exampleIds: ["teams_new_json"]
        ),
        CommandSpec(
            "teams edit", summary: "Replace a custom (or overridden) team definition from JSON after duplicate or new. --json returns the persisted TeamPreset (round-trippable).", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "Team id.")],
            flags: [FlagSpec("file", takesValue: true, valueType: "path", summary: "TeamPreset JSON file."),
                    FlagSpec("json", summary: "Editable TeamPreset JSON that was saved.")],
            outputSchema: .teamPreset,
            exampleIds: ["teams_edit_json"],
            menuAction: true
        ),
        CommandSpec(
            "teams set-default", summary: "Set the default team for a lane.", milestone: .m1,
            args: [ArgSpec("team-id", required: true, summary: "Team id.")],
            flags: [FlagSpec("json", summary: "Structured team detail (show projection — catalog-state receipt, not the edit manifest).")],
            outputSchema: .teamShowJSON,
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
                FlagSpec("lane", takesValue: true, valueType: "lane", summary: "code | design | copy | signal."),
                FlagSpec("name", takesValue: true, valueType: "string", summary: "Display name."),
                FlagSpec("purpose", takesValue: true, valueType: "purpose", summary: "answer | review | planWriter."),
                FlagSpec("template-file", takesValue: true, valueType: "path", summary: "Skill template text file."),
                FlagSpec("json", summary: "Structured skill detail."),
            ],
            exampleIds: ["skills_new_json"]
        ),
        CommandSpec(
            "skills edit", summary: "Edit a skill or write a same-ID built-in override.", milestone: .m1,
            args: [ArgSpec("skill-id", required: true, summary: "Skill id.")],
            flags: [
                FlagSpec("name", takesValue: true, valueType: "string", summary: "New display name."),
                FlagSpec("template-file", takesValue: true, valueType: "path", summary: "Replacement template file."),
                FlagSpec("json", summary: "Structured skill detail."),
            ],
            exampleIds: ["skills_edit_json"]
        ),
        CommandSpec(
            "skills restore", summary: "Restore a built-in skill to its shipped version (remove override).", milestone: .m1,
            args: [ArgSpec("skill-id", required: true, summary: "Built-in skill id.")],
            flags: [FlagSpec("json", summary: "Restore acknowledgement JSON.")],
            exampleIds: ["skills_restore_json"]
        ),
        CommandSpec(
            "skills delete", summary: "Delete a custom skill.", milestone: .m1,
            args: [ArgSpec("skill-id", required: true, summary: "Skill id.")],
            flags: [FlagSpec("json", summary: "Deletion acknowledgement JSON.")],
            exampleIds: ["skills_delete_json"]
        ),
        CommandSpec(
            "skills gc", summary: "Purge retired lab skills and delete unreferenced custom skills.", milestone: .m1,
            flags: [FlagSpec("json", summary: "JSON with deleted skill ids and count.")],
            exampleIds: ["skills_gc_json"]
        ),
        CommandSpec(
            "team cancel", summary: "Cancel an active async team run.", milestone: .m1,
            args: [ArgSpec("run-id", required: true, summary: "The run id of an accepted async run.")],
            flags: [FlagSpec("json", summary: "Structured TeamCancelResponse.")],
            outputSchema: .teamCancelResponse
        ),
        CommandSpec(
            "team reconcile", summary: "Explicit ownership reconcile: identity-dead async runs are reaped (PG-kill recorded pgid when present) and stamped endReason=reconciledOrphan. An exact run-id may target any project; the bare sweep is scoped to the caller's canonical project root (fail closed on unresolved roots) — machine-wide only via the explicit --all-projects.", milestone: .m1,
            args: [ArgSpec("run-id", required: false, summary: "Optional run id; omit to sweep the caller's project scope.")],
            flags: [
                FlagSpec("all-projects", summary: "Machine-wide fleet sweep instead of the caller's project scope."),
                FlagSpec("json", summary: "Structured reaped-run list."),
            ]
        ),
        // Process ownership observability (docs/phases/Process_Ownership.md PO-S05)
        CommandSpec(
            "ps", summary: "List owned process trees (runs, loops, proofs). Reconciles identity-dead owners on read (CLP-S02) — no manual `team reconcile` on the happy path. PRIMARY liveness is stream silence (`run.lastActivityAt`), same as `alln loop status` — not relay heartbeat/pgid. Default shows alive + needs-action only; `--all` includes terminal history. Scoped to caller's project; `--all-projects` is machine-wide.", milestone: .m1,
            flags: [
                FlagSpec("all", summary: "Include terminal/history rows (museum view). Default is alive + needs-action floor only."),
                FlagSpec("all-projects", summary: "Machine-wide fleet view instead of the caller's project scope."),
                FlagSpec("json", summary: "Structured OwnershipPsJSON inventory."),
            ],
            outputSchema: .ownershipPsJSON
        ),
        CommandSpec(
            "kill", summary: "Identity-checked total group kill of one owned tree (or --all identity-alive trees in the caller's project scope) and stamp endReason=killed. Refuses on identity mismatch (never signals a recycled pid). An exact id may target any project.", milestone: .m1,
            args: [ArgSpec("id", required: false, summary: "Owned process id (run/relay/pilot/proof). Required unless --all.")],
            flags: [
                FlagSpec("all", summary: "Kill every identity-alive owned tree in the caller's project scope (skips identity-mismatched and already-terminal; unresolved roots are never swept)."),
                FlagSpec("all-projects", summary: "With --all: machine-wide fleet kill instead of the caller's project scope."),
                FlagSpec("json", summary: "Structured OwnershipKillJSON."),
            ],
            outputSchema: .ownershipKillJSON
        ),
        CommandSpec(
            "gc", summary: "Prune old identity-dead terminal run/relay records beyond retention. Keeps identity-alive, non-terminal, recent, and thread-referenced records.", milestone: .m1,
            flags: [
                FlagSpec("dry-run", summary: "Report what would be pruned without deleting."),
                FlagSpec("json", summary: "Structured OwnershipGarbageCollectionJSON summary with every keep reason."),
            ],
            outputSchema: .ownershipGarbageCollectionJSON
        ),
        CommandSpec(
            "run",
            summary: "Unified run: message + optional Team + agent in the registered repository root. Research Teams are observational and execution Teams use one selected agent. TeamRunJSON reports agent terminal states and Git observation, never a correctness verdict.",
            milestone: .m1,
            trigger: "Use when the user wants one agent or team to answer or act in a project repo root (chat / named-model ask / Default Team / --no-wait to keep going after you step away).",
            example: "alln run \"summarize AGENTS.md\" --project . --json",
            antiExample: "Do NOT use this to explore shapes — prefer `alln run --dry-run` or `alln menu --json` first; this spends quota.",
            args: [ArgSpec("message", required: true, summary: "The user's prompt.")],
            flags: [
                FlagSpec("project", takesValue: true, valueType: "id", summary: "Project id, name, or repo path. When omitted, walk to the git root and match a registered project (AE-S05)."),
                FlagSpec("team", takesValue: true, valueType: "id", summary: "Team preset id; omit for Default Team."),
                FlagSpec("model", takesValue: true, valueType: "id", summary: "Override model id."),
                FlagSpec("seat", takesValue: true, valueType: "id", summary: "Override one crew seat model id (repeatable, crew order; requires --team; judgment teams only)."),
                FlagSpec("message", takesValue: true, valueType: "string", summary: "Alias for the positional message."),
                FlagSpec("effort", takesValue: true, valueType: "effort", summary: "low | med | high."),
                FlagSpec("lane", takesValue: true, valueType: "lane", summary: "Lane tags the run for context and filtering; `--team` routes."),
                FlagSpec("type", takesValue: true, valueType: "type", summary: "Copy routing sugar."),
                FlagSpec("context", takesValue: true, valueType: "string", summary: "Bounded context snippet."),
                FlagSpec("idle-timeout", takesValue: true, valueType: "integer", summary: "Override the worker idle-stall budget in seconds (default = driver manifest invoke.timeoutSeconds, commonly 1800s for agent CLIs). Resets on streaming stdout/stderr bytes, attributable process-group activity (child spawn, CPU under the recorded pgid), and durable recordProgress heartbeats; wall is the hard ceiling (--wall-timeout, default 3600)."),
                FlagSpec("handshake-timeout", takesValue: true, valueType: "integer", summary: "Runner-ready handshake bound in seconds (default 60; RLR-L8). Finite positive required."),
                FlagSpec("first-activity-timeout", takesValue: true, valueType: "integer", summary: "First post-spawn activity bound in seconds (default 120; RLR-L8). Finite positive required."),
                FlagSpec("wall-timeout", takesValue: true, valueType: "integer", summary: "Total wall-clock ceiling in seconds (default 3600; RLR-L8). Finite positive required."),
                FlagSpec("idempotency-key", takesValue: true, valueType: "string", summary: "Transport idempotency key (24h replay window). Same key+payload replays the original run; conflict/expired refuse."),
                FlagSpec("retry-of", takesValue: true, valueType: "id", summary: "Intentional retry of a prior run id (new key). Requires prior tree verified stopped, or --accept-survivors."),
                FlagSpec("accept-survivors", summary: "Allow --retry-of when the prior run still has identity-alive recorded workers."),
                FlagSpec("commit-message", takesValue: true, valueType: "string", summary: "Exact commit message for the worker (FR12 instruct + verify; Allnighter does no git)."),
                FlagSpec("no-commit", summary: "Instruct the worker to leave work uncommitted for PM review (mutually exclusive with --commit-message). Still mutating and still takes the per-root write lock — does not skip the queue. For parallel feedback use --read-only --model."),
                FlagSpec("read-only", summary: "Lock policy only: same one-model chat as --model, with writePolicy readOnly and no write-lock queue. Requires --model. Not a team path; not FS isolation. Mutually exclusive with --team and mutator-only flags (--no-commit, --commit-message, --try-fix, --proof)."),
                FlagSpec("proof", takesValue: true, valueType: "string", summary: "Run a bounded proof command after the worker settles; surface pass/fail (never blocks git)."),
                FlagSpec("try-fix", summary: "Bug Hunt diagnosis → danger-not-doubt gate → one bounded fix attempt."),
                FlagSpec("executor", takesValue: true, valueType: "id", summary: "Mutating executor team id (default build_slice)."),
                FlagSpec("agent", takesValue: true, valueType: "id", summary: "Origin agent id for attribution (does not select the worker)."),
                FlagSpec("thread-id", takesValue: true, valueType: "id", summary: "Owning work thread id."),
                FlagSpec("conversation-id", takesValue: true, valueType: "id", summary: "Origin conversation id."),
                FlagSpec("message-id", takesValue: true, valueType: "id", summary: "Origin message id."),
                FlagSpec("dry-run", summary: "Resolve project/worker/auth/writePolicy/effects/write-lock and return canStart + counts; exit 0, no dispatch. Research Teams are observational in the canonical repository; terminal repoDelta reports whether a mutating run wrote."),
                FlagSpec("json", summary: "Emit TeamRunJSON (blocking run), RunDryRunJSON v2 with --dry-run, or a detached acknowledgement with one nextAction.command (`alln show <id> --stream`) with --no-wait."),
                FlagSpec("stream", summary: CommandProjection.streamFlagSummary),
                FlagSpec("no-wait", summary: "Hand the run to a detached child of the same registered `alln run` verb; return only after the child durably accepts with one nextAction.command = `alln show <id> --stream` (real run id, including idempotency replay). A child refusal fails loud. Mutually exclusive with --stream / --dry-run / --try-fix."),
                FlagSpec("delivery", takesValue: true, valueType: "string", summary: "Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command."),
            ],
            mutuallyExclusiveFlags: [
                ["json", "stream"],
                ["no-commit", "commit-message"],
                ["model", "seat"],
                ["dry-run", "stream"],
                ["dry-run", "try-fix"],
                ["no-wait", "stream"],
                ["no-wait", "dry-run"],
                ["no-wait", "try-fix"],
                ["read-only", "team"],
                ["read-only", "no-commit"],
                ["read-only", "commit-message"],
                ["read-only", "try-fix"],
                ["read-only", "proof"],
            ],
            flagConstraints: [
                FlagConstraint(.onlyWith, "executor", "try-fix"),
                FlagConstraint(.requires, "accept-survivors", "retry-of"),
                FlagConstraint(.requires, "seat", "team"),
                FlagConstraint(.requires, "delivery", "no-wait"),
                FlagConstraint(.requires, "read-only", "model"),
            ],
            outputSchema: .teamRunJSON,
            exampleIds: ["run_foreground_json"],
            spendsQuota: true,
            freeTwinCommand: "alln run --dry-run",
            menuAction: true
        ),
        CommandSpec(
            "run resume", summary: "Resume a run parked on vendor capacity (same run id, in-process).", milestone: .m1,
            args: [ArgSpec("runId", required: true, summary: "Parked run id.")],
            flags: [FlagSpec("json", summary: "Emit TeamRunJSON.")],
            outputSchema: .teamRunJSON
        ),
        CommandSpec(
            "continuity receipt", summary: "Local observed-facts summary of vendor waits covered and automatic resumes (last 24h).", milestone: .m1,
            flags: [FlagSpec("json", summary: "Emit MorningReceipt JSON.")],
            outputSchema: .none
        ),
        CommandSpec(
            "loop start",
            summary: "Start a durable PM↔dev loop. The brief is the only required input — both seats default by tier. `--pm caller` reviews every round yourself; `--pm <agent-id>` (or the default) spawns that agent as PM and runs unattended.",
            milestone: .m1,
            trigger: "Use when the user wants a multi-round PM↔dev loop that reviews real commits round after round until the work is done — with or without naming who sits in which chair.",
            example: "alln loop start \"execute this doc\" --spec docs/phases/Loop_Verb_Cutover.md --pm caller --dev model_grok",
            antiExample: "Do NOT use this to explore shapes — use `alln loop start --dry-run` first; this spends quota.",
            args: [
                ArgSpec("brief", required: true, summary: "What you want done. The brief handed to the PM at round 1 — no other flag is required."),
            ],
            flags: [
                FlagSpec("spec", takesValue: true, valueType: "path", summary: "Repo-relative spec doc path — a shortcut for when the brief would be three paragraphs, not the shape. The PM re-reads it fresh each round."),
                FlagSpec("pm", takesValue: true, valueType: "id", summary: "PM occupant: `caller` (this session reviews every round) or a canonical agent id (that agent is spawned as PM and the loop runs unattended). Omitted → the Frontier-tier default."),
                FlagSpec("dev", takesValue: true, valueType: "id", summary: "Dev seat canonical agent id. Omitted → the Balanced-tier default."),
                FlagSpec("project", takesValue: true, valueType: "id", summary: "Project id, name, or repo path. Omitted → resolved from the current working directory."),
                FlagSpec("dry-run", summary: "Resolve the brief/spec/both seats/project and report readiness; exit 0, create nothing, spend nothing."),
                FlagSpec("no-wait", summary: "Spawn the same registered `loop start` verb in a detached child; return only after the child durably claims delivery."),
                FlagSpec("json", summary: "Emit structured JSON (LoopStartDryRunJSON with --dry-run; LoopJSON otherwise)."),
            ],
            outputSchema: .relayJSON,
            spendsQuota: true,
            freeTwinCommand: "alln loop start --dry-run"
        ),
        CommandSpec(
            "loop list",
            summary: "List durable PM↔dev loops for the resolved project (id, status, brief/spec, seats, updatedAt).",
            milestone: .m1,
            args: [],
            flags: [
                FlagSpec("project", takesValue: true, valueType: "id", summary: "Project id, name, or repo path. Omitted → resolved from the current working directory."),
                FlagSpec("json", summary: "Emit LoopListJSON."),
            ],
            outputSchema: .none,
            spendsQuota: false,
            effects: EffectProfile()
        ),
        CommandSpec(
            "loop status",
            summary: "Read a loop's durable state, or wait for its parked or terminal PM boundary. Reconciles identity-dead `.running` owners on read (no manual reconcile).",
            milestone: .m1,
            args: [
                ArgSpec("loop-id", required: true, summary: "Loop id."),
            ],
            flags: [
                FlagSpec("wait-for", takesValue: true, valueType: "string", summary: "Wait for parked (awaitingPM|escalated) or terminal (done|stopped); requires --timeout."),
                FlagSpec("timeout", takesValue: true, valueType: "number", summary: "Non-negative wait limit in seconds; required with --wait-for."),
                FlagSpec("json", summary: "Emit LoopJSON (plus additive live usage fields while running)."),
            ],
            flagConstraints: [
                FlagConstraint(.requires, "wait-for", "timeout"),
                FlagConstraint(.requires, "timeout", "wait-for"),
            ],
            outputSchema: .relayJSON,
            spendsQuota: false,
            effects: EffectProfile()
        ),
        CommandSpec(
            "loop stop",
            summary: "Founder stop of a Loop: identity-checked teardown, durable stopped status with reason \"founder stopped\", and a PM Turn on transition. Idempotent on already done/stopped. Not ownership kill.",
            milestone: .m1,
            args: [
                ArgSpec("loop-id", required: true, summary: "Loop id."),
            ],
            flags: [
                FlagSpec("json", summary: "Emit LoopJSON (status=stopped, stoppedReason=\"founder stopped\" on transition)."),
            ],
            outputSchema: .relayJSON,
            spendsQuota: false,
            effects: EffectProfile(
                workerStart: .never,
                quotaSpend: .never,
                repoWrite: .never,
                destructive: .always,
                humanInteraction: .never
            )
        ),
        CommandSpec(
            "loop resume",
            summary: "Resume an escalated loop with the founder's answer, then continue rounds (may dispatch dev turns).",
            milestone: .m1,
            args: [
                ArgSpec("loop-id", required: true, summary: "Loop id."),
            ],
            flags: [
                FlagSpec("answer", takesValue: true, valueType: "string", summary: "The founder's answer to the escalation (required)."),
                FlagSpec("until", takesValue: true, valueType: "time", summary: "Hard stop HH:MM (local) for the resumed stretch."),
                FlagSpec("max-rounds", takesValue: true, valueType: "integer", summary: "Round ceiling for the resumed stretch (default 20)."),
                FlagSpec("no-auto-serve", summary: "Do not auto-start the background notifier (alln serve) for this dispatch."),
                FlagSpec("dry-run", summary: "Resolve the loop id, founder answer, seats, and readiness; report LoopStartDryRunJSON; exit 0; spend nothing, start no worker, mutate no durable state."),
                FlagSpec("no-wait", summary: "Spawn the same registered `loop resume` verb in a detached child; return only after the child durably claims with delivery.path=wait and the exact terminal status waiter. A refusal fails loud. Mutually exclusive with --dry-run."),
                FlagSpec("delivery", takesValue: true, valueType: "string", summary: "Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command. Mutually exclusive with --dry-run."),
                FlagSpec("json", summary: "Emit structured JSON (LoopStartDryRunJSON with --dry-run; NDJSON progress + final LoopJSON otherwise; detached ack with --no-wait)."),
            ],
            mutuallyExclusiveFlags: [
                ["no-wait", "dry-run"],
                ["delivery", "dry-run"],
            ],
            flagConstraints: [FlagConstraint(.requires, "delivery", "no-wait")],
            outputSchema: .relayJSON,
            spendsQuota: true,
            freeTwinCommand: "alln loop resume <loop-id> --answer <text> --dry-run"
        ),
        CommandSpec(
            "loop wait",
            summary: "Optional interactive waiter: blocks until the in-flight round settles. Disposable — death ≠ job failure; prefer `loop status` for agents. Emits heartbeats while running; SIGTERM/SIGINT prints stillRunning goodbye.",
            milestone: .m1,
            args: [
                ArgSpec("loop-id", required: true, summary: "Loop id."),
            ],
            flags: [
                FlagSpec("max-wait", takesValue: true, valueType: "integer", summary: "Stop waiting after N seconds while still running; exit with stillRunning and reattach to loop status (default 1800 when stdout is not a TTY; interactive TTY waits until settled unless set)."),
                FlagSpec("json", summary: "Emit PilotWatchJSON (final single-line envelope; NDJSON heartbeats while waiting)."),
            ],
            outputSchema: .relayJSON,
            spendsQuota: false,
            effects: EffectProfile()
        ),
        CommandSpec(
            "loop step",
            summary: "Submit this round's PM decision while the loop is awaitingPM: a message continues the dev turn; `--done <summary>` settles the loop. Blocks through the dev turn by default.",
            milestone: .m1,
            args: [
                ArgSpec("loop-id", required: true, summary: "Loop id."),
                ArgSpec("message", required: false, summary: "Order for the dev seat (continue). Mutually exclusive with --done."),
            ],
            flags: [
                FlagSpec("done", takesValue: true, valueType: "string", summary: "Close the loop with a done summary instead of dispatching a continue message."),
                FlagSpec("dry-run", summary: "Resolve the loop id, step payload, seats, and readiness; report LoopStartDryRunJSON; exit 0; spend nothing, start no worker, mutate no durable state."),
                FlagSpec("json", summary: "Emit structured JSON (LoopStartDryRunJSON with --dry-run; handoff/result + progress NDJSON otherwise)."),
            ],
            outputSchema: .relayJSON,
            spendsQuota: true,
            freeTwinCommand: "alln loop step <loop-id> <message> --dry-run"
        ),
        CommandSpec(
            "loop pm",
            summary: "Reassign the PM chair mid-loop. `<agent-id>` converts a parked caller-held loop (awaitingPM|escalated) to a spawned PM and continues (dispatches). `caller` hands a parked spawned loop back to this session (status flip, no dispatch).",
            milestone: .m1,
            args: [
                ArgSpec("loop-id", required: true, summary: "Loop id."),
                ArgSpec("occupant", required: true, summary: "`caller` or a canonical agent id."),
            ],
            flags: [
                FlagSpec("max-rounds", takesValue: true, valueType: "integer", summary: "Round ceiling for the adopted agent-PM stretch — counts TOTAL rounds including prior ones (default 20). Ignored for `caller`."),
                FlagSpec("until", takesValue: true, valueType: "time", summary: "Hard stop HH:MM (local) for the adopted agent-PM stretch. Ignored for `caller`."),
                FlagSpec("no-auto-serve", summary: "Do not auto-start the background notifier (alln serve) for this dispatch (agent-PM path)."),
                FlagSpec("dry-run", summary: "Resolve the loop id, requested PM occupant, seats, and readiness; report LoopStartDryRunJSON; exit 0; spend nothing, start no worker, mutate no durable state (no occupant change)."),
                FlagSpec("no-wait", summary: "Spawn the same registered `loop pm` verb in a detached child (agent-PM path); return only after the child durably claims delivery. A refusal fails loud. Mutually exclusive with --dry-run."),
                FlagSpec("delivery", takesValue: true, valueType: "string", summary: "Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command. Mutually exclusive with --dry-run."),
                FlagSpec("json", summary: "Emit structured JSON (LoopStartDryRunJSON with --dry-run; NDJSON progress + final LoopJSON otherwise; detached ack with --no-wait)."),
            ],
            mutuallyExclusiveFlags: [
                ["no-wait", "dry-run"],
                ["delivery", "dry-run"],
            ],
            flagConstraints: [FlagConstraint(.requires, "delivery", "no-wait")],
            outputSchema: .relayJSON,
            spendsQuota: true,
            freeTwinCommand: "alln loop pm <loop-id> <occupant> --dry-run"
        ),
        CommandSpec(
            "pair relay", summary: "Retired — use `alln loop start \"<what you want done>\"` instead. Runs the PM↔dev loop unattended: a PM seat reviews the repo and a dev seat builds, round after round, until done/escalate/a ceiling.", milestone: .m1,
            flags: [
                FlagSpec("doc", takesValue: true, valueType: "path", summary: "Repo-relative spec doc path (required) — the PM re-reads it fresh each round."),
                FlagSpec("project", takesValue: true, valueType: "id", summary: "Project id, name, or repo path (required)."),
                FlagSpec("pm-model", takesValue: true, valueType: "id", summary: "PM seat model id (required)."),
                FlagSpec("dev-model", takesValue: true, valueType: "id", summary: "Dev seat model id (required)."),
                FlagSpec("message", takesValue: true, valueType: "string", summary: "Kickoff brief body (one-shot, first PM assemble only). Mutually exclusive with --message-file."),
                FlagSpec("message-file", takesValue: true, valueType: "path", summary: "Read a UTF-8 file as the kickoff brief (one-shot, first PM assemble only). Mutually exclusive with --message."),
                FlagSpec("until", takesValue: true, valueType: "time", summary: "Hard stop HH:MM (local)."),
                FlagSpec("max-rounds", takesValue: true, valueType: "integer", summary: "Round ceiling (default 20)."),
                FlagSpec("idle-timeout", takesValue: true, valueType: "integer", summary: "Override the dev seat's per-turn worker idle-stall budget in seconds (default = driver manifest timeout). Reuses PO-F5's `alln run --idle-timeout` plumbing (PO-F7)."),
                FlagSpec("no-auto-serve", summary: "Do not auto-start the background notifier (alln serve) for this dispatch."),
                FlagSpec("no-wait", summary: "Spawn the same registered `pair relay` verb in a detached child; return only after the child durably claims with delivery.path=wait and the exact terminal status waiter. A refusal fails loud and spawns nothing."),
                FlagSpec("delivery", takesValue: true, valueType: "string", summary: "Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command."),
                FlagSpec("json", summary: "Emit NDJSON RelayProgressJSON events, then a final LoopJSON envelope (or, with --no-wait, a single delivery acknowledgement)."),
            ],
            mutuallyExclusiveFlags: [["message", "message-file"]],
            flagConstraints: [FlagConstraint(.requires, "delivery", "no-wait")],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair relay-status", summary: "Retired — use `alln loop status <loop-id>` instead. Reads a loop's durable state, or waits for its parked or terminal PM boundary. Reconciles identity-dead `.running` owners on read (no manual reconcile).", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("wait-for", takesValue: true, valueType: "string", summary: "Wait for parked (awaitingPM|escalated) or terminal (done|stopped); requires --timeout."),
                FlagSpec("timeout", takesValue: true, valueType: "number", summary: "Non-negative wait limit in seconds; required with --wait-for."),
                FlagSpec("json", summary: "Emit LoopJSON."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair relay-resume", summary: "Retired — use `alln loop resume <loop-id>` instead. Resumes an escalated loop with the founder's answer, then continues.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("answer", takesValue: true, valueType: "string", summary: "The founder's answer to the escalation (required)."),
                FlagSpec("until", takesValue: true, valueType: "time", summary: "Hard stop HH:MM (local) for the resumed stretch."),
                FlagSpec("max-rounds", takesValue: true, valueType: "integer", summary: "Round ceiling for the resumed stretch (default 20)."),
                FlagSpec("no-auto-serve", summary: "Do not auto-start the background notifier (alln serve) for this dispatch."),
                FlagSpec("no-wait", summary: "Spawn the same registered `relay-resume` verb in a detached child; return only after the child durably claims with delivery.path=wait and the exact terminal status waiter. A refusal (e.g. RELAY_ROUND_IN_FLIGHT) fails loud."),
                FlagSpec("delivery", takesValue: true, valueType: "string", summary: "Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command."),
                FlagSpec("json", summary: "Emit NDJSON RelayProgressJSON events, then a final LoopJSON envelope (or, with --no-wait, a single delivery acknowledgement)."),
            ],
            flagConstraints: [FlagConstraint(.requires, "delivery", "no-wait")],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair relay adopt", summary: "Retired — use `alln loop pm <loop-id> <agent-id>` instead. Converts a parked caller-held loop (awaitingPM or escalated) to a spawned PM and continues from the durable round log.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("pm-model", takesValue: true, valueType: "id", summary: "The spawned PM seat's model id (required)."),
                FlagSpec("max-rounds", takesValue: true, valueType: "integer", summary: "Round ceiling for the adopted stretch — counts TOTAL rounds including the piloted ones already on the log (default 20)."),
                FlagSpec("until", takesValue: true, valueType: "time", summary: "Hard stop HH:MM (local) for the adopted stretch."),
                FlagSpec("no-auto-serve", summary: "Do not auto-start the background notifier (alln serve) for this dispatch."),
                FlagSpec("no-wait", summary: "Spawn the same registered `relay adopt` verb in a detached child; return only after the child durably claims with delivery.path=wait and the exact terminal status waiter. A refusal fails loud."),
                FlagSpec("delivery", takesValue: true, valueType: "string", summary: "Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command."),
                FlagSpec("json", summary: "Emit NDJSON RelayProgressJSON events, then a final LoopJSON envelope (or, with --no-wait, a single delivery acknowledgement)."),
            ],
            flagConstraints: [FlagConstraint(.requires, "delivery", "no-wait")],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair relay stop", summary: "Retired — use `alln loop stop <loop-id>` instead. Founder stop of a Loop: identity-checked teardown, durable stopped status with reason \"founder stopped\", and a PM Turn on transition. Idempotent on already done/stopped.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("json", summary: "Emit LoopJSON (status=stopped, stoppedReason=\"founder stopped\" on transition)."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair pilot start", summary: "Retired — use `alln loop start \"<what you want done>\" --pm caller` instead. Starts a loop with this session as PM; Allnighter runs the crew (dev seat + rails). Parks awaitingPM.", milestone: .m1,
            flags: [
                FlagSpec("doc", takesValue: true, valueType: "path", summary: "Repo-relative spec doc path (required) — the piloting session re-reads it fresh each round."),
                FlagSpec("project", takesValue: true, valueType: "id", summary: "Project id, name, or repo path (required)."),
                FlagSpec("dev-model", takesValue: true, valueType: "id|alias", summary: "Dev seat model id or alias (optional when a seat was remembered for this project)."),
                FlagSpec("max-rounds", takesValue: true, valueType: "integer", summary: "Round ceiling, set once here — Pilot has no long-lived process to re-supply it per handoff (default 20)."),
                FlagSpec("idle-timeout", takesValue: true, valueType: "integer", summary: "Override the dev seat's per-turn worker idle-stall budget in seconds (default = driver manifest timeout), set once here and re-read from durable state at every later `pilot handoff`. Reuses PO-F5's `alln run --idle-timeout` plumbing (PO-F7)."),
                FlagSpec("json", summary: "Emit PilotStartJSON (relay + shell-quoted nextCommand for paste + raw scaffoldPath + nextCommandArgv for programmatic handoff)."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair pilot handoff", summary: "Retired — use `alln loop step <loop-id>` instead. Submits this round's review (LoopVerdict tail or --verdict + handover file); loop step blocks by default; after step use `loop wait <loop-id>` or `loop status <loop-id> --wait-for parked`. `--no-wait` is NOT on loop step.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("file", takesValue: true, valueType: "path", summary: "Read the full submission markdown from a file (verdict tail included; omit to read stdin)."),
                FlagSpec("verdict", takesValue: true, valueType: "verdict", summary: "Required with --handover-file/--handover-stdin; synthesizes the LoopVerdict tail internally."),
                FlagSpec("handover-file", takesValue: true, valueType: "path", summary: "Raw order markdown for the dev seat (mutually exclusive with --file)."),
                FlagSpec("handover-stdin", summary: "Read the handover markdown from stdin (mutually exclusive with --file)."),
                FlagSpec("note", takesValue: true, valueType: "string", summary: "Optional closing note for done/escalate verdicts."),
                FlagSpec("no-wait", summary: "Return after dispatch with delivery.path=wait and an exact `pilot status --wait-for parked` command. Run it once for the parked PM Turn; a killed `pilot watch` is not failure."),
                FlagSpec("delivery", takesValue: true, valueType: "string", summary: "Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command."),
                FlagSpec("no-auto-serve", summary: "Do not auto-start the background notifier (alln serve) for this dispatch."),
                FlagSpec("json", summary: "Emit NDJSON RelayProgressJSON events, then a final PilotHandoffJSON envelope (or, with --no-wait, a single delivery acknowledgement)."),
            ],
            mutuallyExclusiveFlags: [["file", "handover-file"], ["file", "handover-stdin"], ["handover-file", "handover-stdin"]],
            flagConstraints: [FlagConstraint(.requires, "delivery", "no-wait")],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair pilot status", summary: "Retired — use `alln loop status <loop-id>` instead. Reads a caller-held loop's durable state, or waits for its parked PM boundary (awaitingPM|escalated). While running: elapsedSeconds, ownerAlive, lastProgressAt/silenceAgeSeconds (PRIMARY stream liveness — same truth as alln ps; not relay heartbeat/pgid), streamSilenceWarning when silence > 6×waitHint, commitsSinceBaseline (SUPPLEMENTARY only — not liveness), waitHintSeconds 45, watcherDisposable. Prefer over wait for agents.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("wait-for", takesValue: true, valueType: "string", summary: "Wait for parked (awaitingPM|escalated); requires --timeout. terminal is not valid for Pilot."),
                FlagSpec("timeout", takesValue: true, valueType: "number", summary: "Non-negative wait limit in seconds; required with --wait-for."),
                FlagSpec("json", summary: "Emit PilotStatusJSON (relay + recovery nextActions; while running adds elapsedSeconds, ownerAlive, lastProgressAt/silenceAgeSeconds as primary stream liveness, streamSilenceWarning when silence > 6×waitHint, commitsSinceBaseline as supplementary/not liveness, waitHintSeconds 45, watcherDisposable)."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair pilot watch", summary: "Retired — use `alln loop wait <loop-id>` instead. Optional interactive waiter: blocks until the in-flight round settles. Disposable — death ≠ job failure; prefer `loop status` for agents. Emits heartbeats while running; SIGTERM/SIGINT prints stillRunning goodbye.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("max-wait", takesValue: true, valueType: "integer", summary: "Stop waiting after N seconds while still running; exit with stillRunning and reattach to pilot status (default 1800 when stdout is not a TTY; interactive TTY waits until settled unless set)."),
                FlagSpec("json", summary: "Emit PilotWatchJSON (final single-line envelope; NDJSON pilotWatchHeartbeat lines while waiting)."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair pilot adopt", summary: "Retired — use `alln loop pm <loop-id> caller` instead. Hands a parked spawned loop's PM seat to the caller session (status → awaitingPM). No dispatch.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("json", summary: "Emit LoopJSON."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "pair pilot scaffold-handover", summary: "Retired alongside `pair pilot`. Writes or re-emits a suggested PM handover markdown template for a loop round; the underlying auto-seed template is unaffected.", milestone: .m1,
            flags: [
                FlagSpec("relay", takesValue: true, valueType: "id", summary: "Relay id (required)."),
                FlagSpec("round", takesValue: true, valueType: "integer", summary: "Round number for the filename (default 1)."),
                FlagSpec("json", summary: "Emit scaffold path as JSON."),
            ],
            outputSchema: .relayJSON
        ),
        CommandSpec(
            "show", summary: "Show one run. Snapshot (`--json`), reattachable stream (`--stream`), or the answer text alone (`--answer`). Stream: immediate snapshot, bounded replay, live follow, exactly one terminal; terminal exit class propagates unconditionally.", milestone: .m1,
            args: [ArgSpec("run-id|latest", required: true, summary: "A run id or `latest`.")],
            flags: [FlagSpec("json", summary: "Emit the run as TeamRunJSON."),
                    FlagSpec("full", summary: "Include resolved worker prompt snapshots (audit). Mutually exclusive with --stream."),
                    FlagSpec("stream", summary: CommandProjection.streamFlagSummary),
                    FlagSpec("answer", summary: "Print only the run's answer text and exit — the recovery path for in-flight, killed, or failed runs whose work is in the record (durable partial included). A partial is labeled on stderr; stdout stays clean for redirection. Fails loud with RUN_NO_ANSWER when the run holds no answer text. Mutually exclusive with --json, --full, and --stream.")],
            mutuallyExclusiveFlags: [["full", "stream"], ["answer", "json"], ["answer", "full"], ["answer", "stream"]],
            outputSchema: .teamRunJSON, exampleIds: ["show_latest_json"],
            spendsQuota: false,
            effects: EffectProfile()
        ),
        CommandSpec(
            "floor show", summary: "Show the inspectable Floor for one team run (worker lanes, artifacts, typed return, timeline, Execute requirements). For the polished HTML receipt, use `alln artifact show <id>`.", milestone: .m1,
            args: [ArgSpec("run-id|latest", required: false, summary: "A run id or `latest` (default latest).")],
            flags: [FlagSpec("json", summary: "Emit the FloorRun projection.")],
            outputSchema: .floorRun
        ),
        CommandSpec(
            "artifact show",
            summary: "Regenerate and open the private HTML team artifact for a terminal run.",
            milestone: .m1,
            trigger: "After a terminal team run, open the polished private receipt (not the Factory Floor).",
            example: "alln artifact show latest",
            antiExample: "Do NOT use this while a run is still running — it fails closed with RUN_NOT_TERMINAL. Do NOT confuse with `alln floor show`, `alln export`, or `alln continuity receipt`.",
            args: [ArgSpec("run-id|latest", required: false, summary: "A run id or `latest` (default latest).")],
            flags: [
                FlagSpec("no-open", summary: "Print the absolute path only; do not open the default browser."),
                FlagSpec("json", summary: "Emit path, run id, and honesty string only (no HTML body)."),
            ],
            outputSchema: .markdown,
            spendsQuota: false
        ),
        CommandSpec(
            "artifact export",
            summary: "Export the styled HTML team artifact to a user-chosen path for offline reading.",
            milestone: .m1,
            trigger: "When you need the team receipt outside the run journal (archive, share, open offline).",
            example: "alln artifact export latest --out ~/Desktop/team-receipt.html",
            antiExample: "Do NOT use this for markdown export — use `alln export --format md`. Do NOT use while a run is still running.",
            args: [ArgSpec("run-id|latest", required: false, summary: "A run id or `latest` (default latest).")],
            flags: [
                FlagSpec("out", takesValue: true, valueType: "path", summary: "Destination file path for the HTML export (required)."),
                FlagSpec("json", summary: "Emit path, run id, and honesty string only (no HTML body)."),
            ],
            outputSchema: .markdown,
            spendsQuota: false
        ),
        CommandSpec(
            "spec", summary: "Retrieve a run's spec/result packet (summary|full|artifactRefsOnly).", milestone: .m1,
            args: [ArgSpec("run-id|latest", required: false, summary: "A run id or `latest` (default latest).")],
            flags: [FlagSpec("detail", takesValue: true, valueType: "detail", defaultValue: "summary", summary: "summary | full | artifactRefsOnly."),
                    FlagSpec("json", summary: "Structured SpecRetrieval result.")],
            outputSchema: .specResult, exampleIds: ["spec_full"]
        ),
        CommandSpec(
            "export", summary: "Export a run result as markdown (not the styled HTML artifact — use `alln artifact export` for that).", milestone: .m1,
            args: [ArgSpec("run-id|latest", required: true, summary: "A run id or `latest`.")],
            flags: [FlagSpec("format", takesValue: true, valueType: "format", defaultValue: "md", allowedValues: ["md"], summary: "Export format (md).")],
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
            "serve", summary: "Optional background scheduler (Pending wake, Boost seeding, vendor-backoff continuation, cloud relay) — and posts local notifications when a run, team run, or Delivery Loop round lands or needs an answer. It owns no run semantics: `alln run` never needs it. Start it in a terminal; Ctrl+C stops it. `alln loop step`/`start`/`resume`/`pm` auto-start it in the background unless `--no-auto-serve`/`ALLN_NO_AUTO_SERVE` is set.", milestone: .m1,
            flags: [
                FlagSpec("health", summary: "Read-only serve health; does not start serve."),
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
                FlagSpec("model", takesValue: true, valueType: "id", summary: "Target model id."),
                FlagSpec("team", takesValue: true, valueType: "id", summary: "Team preset id."),
                FlagSpec("fallback", takesValue: true, valueType: "id", summary: "Fallback model id."),
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
                FlagSpec("model", takesValue: true, valueType: "id", summary: "Target model id."),
                FlagSpec("team", takesValue: true, valueType: "id", summary: "Team preset id."),
                FlagSpec("fallback", takesValue: true, valueType: "id", summary: "Fallback model id."),
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
            outputSchema: .pendingItemJSON,
            spendsQuota: true,
            freeTwinCommand: "alln pending show"
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
            "project models", summary: "Show cached per-project worker readiness (read-only; never probes).", milestone: .m1,
            args: [ArgSpec("project", required: true, summary: "Project id or name.")],
            flags: [FlagSpec("json", summary: "Emit a ProjectWorkersJSON object.")],
            outputSchema: .projectWorkersJSON
        ),
        CommandSpec(
            "project recheck-models", summary: "Rerun driver-declared safe probes for a project and refresh the readiness cache. No auto-config/auth.", milestone: .m1,
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
            "defaults tier", summary: "Set which tier Auto draws from (frontier|balanced|economy).", milestone: .m1,
            args: [ArgSpec("tier", required: true, summary: "frontier | balanced | economy.")],
            flags: [FlagSpec("json", summary: "Emit a DefaultSettingsJSON object.")],
            outputSchema: .defaultSettingsJSON
        ),
        CommandSpec(
            "defaults assign", summary: "Add a model to a tier (or move it within that tier). Membership is many-to-many — assigning to one tier never removes it from another.", milestone: .m1,
            args: [ArgSpec("model", required: true, summary: "Model id (see `alln models --json`).")],
            flags: [
                FlagSpec("tier", takesValue: true, valueType: "tier", summary: "frontier | balanced | economy (required)."),
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
            "help search", summary: "Lexical retrieval over MenuCatalog — returns zero or many menu cards (no selected/confidence/recommended fields).", milestone: .m1,
            args: [ArgSpec("query", required: true, summary: "Natural-language question or keywords.")],
            flags: [
                FlagSpec("limit", takesValue: true, valueType: "int", defaultValue: "5", summary: "Max results."),
                FlagSpec("json", summary: "Emit a HelpSearchJSON object of menu cards."),
            ],
            outputSchema: .helpSearchJSON
        ),
        CommandSpec(
            "help get", summary: "Retrieve one help topic by id, alln:// ref, or --error. Unknown selectors return close matches + the sitemap.", milestone: .m1,
            args: [ArgSpec("topic", required: false, summary: "Topic id or alln:// ref (omit when using --ref/--error).")],
            flags: [
                FlagSpec("ref", takesValue: true, valueType: "string", summary: "An alln:// ref (help/schema/error)."),
                FlagSpec("error", takesValue: true, valueType: "string", summary: "Find the topic for this error code."),
                FlagSpec("format", takesValue: true, valueType: "format", defaultValue: "json", allowedValues: ["json", "md"], summary: "json | md."),
                FlagSpec("json", summary: "Emit a HelpGetJSON object."),
            ],
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
        ErrorSpec(
            "UNKNOWN_FLAG",
            ruleId: "cli.flag.unknown",
            agentAction: "Re-run `alln <command> --help` or `alln docs <command>`; fix or remove the unknown flag.",
            requiresManual: true,
            retryable: false,
            explain: "The invocation included a flag not declared for this command. Near-matches are listed in the error message. Unknown flags never no-op — a misspelled safety flag must not dispatch a real run.",
            exitClass: .usage
        ),
        ErrorSpec("INSTALL_CLI_TARGET_UNWRITABLE", ruleId: "install_cli.target.unwritable", agentAction: "Retry with `alln install-cli --path ~/.local/bin` or choose a writable directory.", requiresManual: true, retryable: true, explain: "The install-cli target directory is missing or not writable. Use --path to a writable directory (e.g. ~/.local/bin) or fix permissions on /usr/local/bin."),
        ErrorSpec("SUPPORT_MIGRATION_FAILED", ruleId: "support.migration.failed", agentAction: "Inspect the migration error, back up ~/Library/Application Support/Allnighter if needed, then retry.", requiresManual: true, retryable: false, explain: "The one-time retired worker-key migration under the support root failed. Fix the reported filesystem/JSON issue before continuing."),
        ErrorSpec("CONTRACT_DRIFT", ruleId: "contract.drift", agentAction: "Run `alln dev export-contracts`, then rebuild.", requiresManual: true, retryable: false, explain: "Generated artifacts no longer match the registry. Regenerate and rebuild before relying on output."),
        ErrorSpec(
            "CONTRACT_VERSION_NOT_BUMPED",
            ruleId: "contract.version.not_bumped",
            agentAction: "Bump `ContractRegistry.contractVersion` (minor for additions, major for removals/renames), then run `alln dev export-contracts`.",
            requiresManual: true,
            retryable: false,
            explain: "The agent-facing contract surface hash changed but contractVersion was not bumped. Surface edits cannot ship without an explicit compatibility bump (AE-S11).",
            exitClass: .usage
        ),
        ErrorSpec("CONTRACT_ARTIFACTS_NOT_FOUND", ruleId: "contract.artifacts.not_found", agentAction: "Run `alln dev export-contracts` from inside the repo (repo root or a subdirectory).", requiresManual: true, retryable: false, explain: "The repo root, the generated artifacts dir, or an individual artifact file could not be found. This is not content drift — it means the artifacts were never generated at the resolved location, or the command ran outside the repo."),
        ErrorSpec("DEFAULTS_TIER_INVALID", ruleId: "defaults.tier.invalid", agentAction: "Use one of frontier | balanced | economy.", requiresManual: true, retryable: false, explain: "The tier name was not frontier, balanced, or economy. Legacy names flagship and fast still parse but are retired.", exitClass: .usage),
        ErrorSpec("DEFAULTS_MODEL_UNKNOWN", ruleId: "defaults.model.unknown", agentAction: "Run `alln models --json` and pass a known model id.", requiresManual: true, retryable: false, explain: "The model id is not in the catalog, so it cannot be assigned to a tier. List models and use a real id."),
        ErrorSpec("STALL_EPISODE_NOT_FOUND", ruleId: "stall.episode.not_found", agentAction: "Run `alln stalled list --all --json` and use a current episode id.", requiresManual: false, retryable: false, explain: "No stall episode matches the given id (it may have cleared). List stalled work and retry with a live episode id."),
        ErrorSpec("DOCTOR_CHECK_FAILED", ruleId: "doctor.check.failed", agentAction: "Run `alln doctor --json`.", requiresManual: false, retryable: true, explain: "A required doctor check failed. Inspect the structured report and address the named check, then retry."),
        ErrorSpec("SOURCE_NOT_FOUND", ruleId: "source.not_found", agentAction: "Run `alln doctor --json`; add/configure the missing source.", requiresManual: true, retryable: false, explain: "A required source CLI/runtime was not resolved on this machine. Install or locate it, then re-probe."),
        ErrorSpec("SOURCE_AUTH_EXPIRED", ruleId: "source.auth.expired", agentAction: "Re-authenticate the named source.", requiresManual: true, retryable: false, explain: "The source resolved but its authentication is invalid or expired. Sign in via the source's own login flow."),
        ErrorSpec("SOURCE_KEYCHAIN_UNAVAILABLE", ruleId: "source.auth.keychain", agentAction: "Open the provider app once, run its login command in Terminal, then `alln doctor --full --agent <source>`.", requiresManual: true, retryable: true, explain: "The source CLI could not read credentials from the macOS Keychain (SecItemCopyMatching failed). Common when Allnighter or the CLI is launched outside Terminal. Open the provider app, complete sign-in, then re-probe."),
        ErrorSpec("MODEL_UNAVAILABLE", ruleId: "model.unavailable", agentAction: "Run `alln models --json`; pick an on-Bench ready model or enable one.", requiresManual: false, retryable: true, explain: "The requested model is not runnable: it may be off-Bench, its source may not be ready, or it may not exist. Use `alln models --json` to see available vs on-Bench vs ready state."),
        ErrorSpec(
            "AGENT_NOT_AVAILABLE",
            ruleId: "run.agent_not_available",
            agentAction: "Run `alln menu --json` (or `alln menu show model:<id>`); pass a canonical model_* id. Never substitute a display name.",
            requiresManual: true,
            retryable: true,
            explain: "An explicit `--model` / `--dev-model` request named a model that is disabled, notReady, unknown, or a display name. Allnighter never silently substitutes a different model behind an explicit worker id (Process_Ownership.md PO-F10 / Menu_Not_Router MR-S04)."
        ),
        ErrorSpec("DEFAULT_TEAM_INVALID", ruleId: "team.default.invalid", agentAction: "Run `alln menu --json` / `alln teams show <id> --json`; fix unavailable workers.", requiresManual: true, retryable: false, explain: "The default team has no runnable workers. Inspect and repair the team lineup before running."),
        ErrorSpec("AGENT_FAILED", ruleId: "agent.failed", agentAction: "Inspect `agentId` and source error; failed agent remains visible.", requiresManual: false, retryable: true, explain: "One agent failed. The failure is shown, never hidden; other agents may still have answered. Retry the agent or proceed with partial results."),
        ErrorSpec("PLAN_WRITER_FAILED", ruleId: "plan_writer.failed", agentAction: "Retry with a ready plan writer or export worker answers.", requiresManual: false, retryable: true, explain: "The plan-writer stage failed. Retry with a ready plan writer, or export the worker answers and synthesize later."),
        ErrorSpec("TEAM_RUN_TIMEOUT", ruleId: "team.run.timeout", agentAction: "Retry with lower effort or fewer workers.", requiresManual: false, retryable: true, explain: "The team run exceeded its time budget. Reduce effort or the worker count and retry.", exitClass: .timeout),
        ErrorSpec("PM_TURN_WAIT_TIMEOUT", ruleId: "pm_turn.status.wait_timeout", agentAction: "Re-run the same `pilot status` or `relay-status` waiter with a longer --timeout; do not switch to a polling loop or resume command.", requiresManual: false, retryable: true, explain: "The relay PM boundary did not reach the requested target before --timeout. The status response carries waitOutcome: timedOut.", exitClass: .timeout),
        ErrorSpec("PM_TURN_WAKE_UNCONFIGURED", ruleId: "pm_turn.wake.unconfigured", agentAction: "Configure machine-level pmTurnWake.command, then retry `--no-wait --delivery wake`; or omit --delivery and run the returned status waiter.", requiresManual: true, retryable: true, explain: "Wake delivery was requested, but this Mac has no PM Turn receiver command configured. Nothing was dispatched."),
        ErrorSpec("PM_TURN_WAKE_FAILED", ruleId: "pm_turn.wake.failed", agentAction: "Read status JSON for pmTurnDelivery, fix the receiver, then use the terminal/parked status waiter to recover the durable pmTurn.", requiresManual: true, retryable: true, explain: "The configured PM Turn receiver did not acknowledge the durable turn before its retry window ended. The PM turn remains on disk and status projects the failure."),
        ErrorSpec("RELAY_WAIT_TIMEOUT", ruleId: "relay.status.wait_timeout", agentAction: "Alias of PM_TURN_WAIT_TIMEOUT: re-run the same waiter with a longer --timeout.", requiresManual: false, retryable: true, explain: "Compatibility alias for PM_TURN_WAIT_TIMEOUT.", exitClass: .timeout),
        ErrorSpec("TEAM_RUN_FAILED", ruleId: "team.run.failed", agentAction: "Inspect failed workers and stages; retry or adjust the team.", requiresManual: false, retryable: true, explain: "The team run ended without a usable result (e.g. failed or cancelled). Inspect the failed workers/stages in the run, then retry or change the team."),
        ErrorSpec("NESTED_TEAM_BLOCKED", ruleId: "team.nested.blocked", agentAction: "Do not recursively spawn teams without explicit depth budget.", requiresManual: true, retryable: false, explain: "A worker tried to start another team run beyond the allowed depth. Set an explicit depth budget if nesting is intended."),
        ErrorSpec("TEAM_GOVERNOR_BUSY", ruleId: "team.governor.busy", agentAction: "Wait or retry after current team run completes.", requiresManual: false, retryable: true, explain: "The concurrency governor is at capacity. Wait for a slot and retry; this is a real busy state, not a fake queue."),
        ErrorSpec("TEAM_GOVERNOR_UNAVAILABLE", ruleId: "team.governor.unavailable", agentAction: "Run `alln doctor --json`; ensure Allnighter's support directory is writable, or set a writable support root for eval runs.", requiresManual: true, retryable: true, explain: "The team-run governor could not create, open, or lock its slot store. This is a storage/permission/configuration problem, not a capacity limit."),
        ErrorSpec("PENDING_MUTATION_DEFERRED", ruleId: "pending.mutation.deferred", agentAction: "Keep item Draft/Pending; mutating pending runs are outside Pending M1.", requiresManual: true, retryable: false, explain: "Mutating pending runs are not enabled in this milestone. Keep the item Draft/Pending."),
        ErrorSpec("PENDING_REORDER_INVALID", ruleId: "pending.reorder.invalid", agentAction: "Keep order unchanged; reorder only Pending items in the same serialized group.", requiresManual: true, retryable: false, explain: "The requested Pending reorder was rejected because the item and anchor do not share the same serialized group."),
        ErrorSpec("IDEMPOTENCY_CONFLICT", ruleId: "idempotency.conflict", agentAction: "Generate a new key or reuse the original payload.", requiresManual: false, retryable: false, explain: "The same idempotency key was reused with a different canonical payload. Use a new key or repeat the original request. (Public RLR-L9 name; alias of legacy IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD.)"),
        ErrorSpec("IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD", ruleId: "idempotency.key.reused", agentAction: "Generate a new key or reuse the original payload.", requiresManual: false, retryable: false, explain: "Legacy alias of IDEMPOTENCY_CONFLICT — same key reused with a different canonical payload."),
        ErrorSpec("IDEMPOTENCY_EXPIRED", ruleId: "idempotency.expired", agentAction: "Generate a new idempotency key.", requiresManual: false, retryable: false, explain: "The idempotency key's 24h replay window has elapsed. The key is a tombstone — never silently re-execute; mint a new key."),
        ErrorSpec("RETRY_OF_SURVIVORS", ruleId: "retryOf.survivors", agentAction: "Wait for verified stop, or pass --accept-survivors.", requiresManual: false, retryable: true, explain: "`--retry-of` refused because the prior run still has identity-alive recorded workers. Pass --accept-survivors to proceed anyway."),
        ErrorSpec("RUN_NOT_TERMINAL", ruleId: "run.not_terminal", agentAction: "Re-run `alln run resume <runId>` once the host is running again, or read the partial record with `alln show <runId> --json`.", requiresManual: true, retryable: true, explain: "The run has not finished and this process stopped waiting for it. Either nothing claimed the hand-off (open Allnighter) or the host that claimed it stopped without finishing. The run id stays valid; the answer is collectable if a host completes it."),
        ErrorSpec("HANDOFF_HOST_NOT_RUNNING", ruleId: "handoff.host.not_running", agentAction: "Open the Allnighter app (install it first if the message says it is missing) and re-run the same command — or lift the restriction for this terminal session only with `codex --sandbox danger-full-access`.", requiresManual: true, retryable: true, explain: "A sandboxed terminal tried to hand work to the Allnighter app, but the readiness ping was never claimed: no host is watching the mailbox. Nothing was queued, so there is no run id to resume — fix the host and re-run. (CAR-S03a)"),
        ErrorSpec("HANDOFF_CLAIMED_BUT_SILENT", ruleId: "handoff.host.claimed_but_silent", agentAction: "Restart the Allnighter app so its hand-off host recovers, then re-run the same command. Do not just open it — something already claimed the ping.", requiresManual: true, retryable: true, explain: "A host claimed the hand-off readiness ping and never answered it: something is watching the mailbox without completing work. Nothing was queued; the stuck host named in the message must be restarted. (CAR-S03a)"),
        ErrorSpec("HANDOFF_MAILBOX_UNWRITABLE", ruleId: "handoff.mailbox.unwritable", agentAction: "Make the hand-off mailbox directory named in the message writable, then re-run the same command.", requiresManual: true, retryable: true, explain: "The readiness ping could not even be written to the hand-off mailbox at the named path, so no hand-off is possible from this terminal regardless of what the app is doing. Nothing was queued. (CAR-S03a)"),
        ErrorSpec("RUN_NOT_FOUND", ruleId: "run.not_found", agentAction: "Run `alln history --json`.", requiresManual: true, retryable: false, explain: "No run matches the given id. List history and pick a valid run id or `latest`."),
        ErrorSpec("RUN_NO_ANSWER", ruleId: "run.no_answer", agentAction: "Check liveness with `alln show <run-id> --json` (observation.ownerState, answers). If the run is still working, reattach with `alln show <run-id> --stream` or wait, then retry `--answer`.", requiresManual: true, retryable: true, explain: "`--answer` found no answer text in the run record — either nothing has been produced yet or every seat ended without output. The record stays the source of truth: `alln show <run-id> --json`. Nothing was deleted; a run that later produces text answers `--answer` normally."),
        ErrorSpec(
            "VENDOR_WAKE_NOT_CLAIMED",
            ruleId: "run.vendor_wake.not_claimed",
            agentAction: "Confirm the run is parked (`waitingForVendor`) via `alln show <runId> --json`, then retry `alln run resume <runId>`.",
            requiresManual: true,
            retryable: true,
            explain: "Vendor-wake resume could not claim the run — it is not parked waiting for a vendor, or another coordinator already holds the wake lease."
        ),
        ErrorSpec(
            "RUN_JOURNAL_UNAVAILABLE",
            ruleId: "run.journal.unavailable",
            agentAction: "Check the support dir is writable (disk space / permissions), then retry the run.",
            requiresManual: true,
            retryable: true,
            explain: "An authoritative run journal write failed. At mint time (RLR-L2) this refuses to hand back an id without a durable, pollable journal, so no run was started. At terminal settlement (CR-S02) the worker may have run, but its result could not be durably persisted — the run is reported as failed rather than returning success over a lost journal. Either way the durable record is unavailable; check disk space / permissions on the support dir and retry."
        ),
        ErrorSpec(
            "JOURNAL_CORRUPT",
            ruleId: "run.journal.corrupt",
            agentAction: "Do not retry the same run id; confirm via `alln show <id> --json` (typed error), then start a new run if the work still matters. Never inspect private journal paths by hand — a corrupt journal is never silently treated as not-found or coerced to an invented status.",
            requiresManual: true,
            retryable: false,
            explain: "A durable journal exists for the id but failed to decode (e.g. an unknown/legacy status raw value). Distinct from RUN_NOT_FOUND, which means no journal was ever found at all (RLR-L8)."
        ),
        ErrorSpec("STREAM_JOURNAL_FAILED", ruleId: "stream.journal.failed", agentAction: "Fix the local run journal/storage failure, then rerun the foreground command.", requiresManual: true, retryable: true, explain: "A stream event could not be durably stamped, so Allnighter stopped the stream rather than emitting an unjournaled event."),
        ErrorSpec("RESIDENT_REQUEST_CONFLICT", ruleId: "resident.request.conflict", agentAction: "Reuse the original payload for this idempotency key, or submit a new key for new work.", requiresManual: false, retryable: false, explain: "A request reused an idempotency key with a different semantic payload."),
        ErrorSpec("RESIDENT_ACCEPT_TIMEOUT", ruleId: "resident.accept.timeout", agentAction: "Retry the same idempotency key and payload; do not create a second direct run.", requiresManual: false, retryable: true, explain: "The client did not observe a durable resident acceptance receipt before its timeout."),
        ErrorSpec("SKILL_NOT_FOUND", ruleId: "skill.not_found", agentAction: "Run `alln skills --lane <lane> --json` and pick a valid skill id.", requiresManual: true, retryable: false, explain: "No skill matches the given id. List skills for the lane and retry with a valid SkillID."),
        ErrorSpec("TEAM_NOT_FOUND", ruleId: "team.not_found", agentAction: "Run `alln menu --json` (or `alln menu show team:<id>`) and retry with a canonical team id — never a display name.", requiresManual: true, retryable: false, explain: "No team matches the given id (or a display name was passed). List the live menu and retry with a valid TeamID."),
        ErrorSpec("TEAM_BUILTIN_IMMUTABLE", ruleId: "team.builtin.immutable", agentAction: "Edit the team with `teams edit` instead; only delete an edited built-in (which restores the shipped version).", requiresManual: true, retryable: false, explain: "A built-in team that was never edited has nothing to delete. Edit it in place with `teams edit`, or use `teams restore` to revert prior edits."),
        ErrorSpec("TEAM_RESTORE_UNSUPPORTED", ruleId: "team.restore.unsupported", agentAction: "Only built-in teams can be restored; for a custom team, edit or delete it instead.", requiresManual: true, retryable: false, explain: "Restore reverts a built-in team to its shipped version. A custom team has no shipped version to restore to."),
        ErrorSpec("SKILL_BUILTIN_IMMUTABLE", ruleId: "skill.builtin.immutable", agentAction: "Built-in skills cannot be deleted. Use `skills restore` to drop an override, or `skills duplicate` for a separate copy.", requiresManual: true, retryable: false, explain: "Built-in skill seeds cannot be deleted. Restore removes a same-ID override; duplicate mints a new custom id."),
        ErrorSpec("SKILL_RESTORE_UNSUPPORTED", ruleId: "skill.restore.unsupported", agentAction: "Only built-in skills can be restored; for a custom skill, edit or delete it instead.", requiresManual: true, retryable: false, explain: "Restore reverts a built-in skill to its shipped seed. A custom skill has no shipped version to restore to."),
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
        ErrorSpec("FILE_REFERENCE_AGENT_UNSUPPORTED", ruleId: "file.reference.agent_unsupported", agentAction: "Choose a worker that can receive referenced file text or use a chat worker.", requiresManual: true, retryable: false, explain: "The selected route cannot accept Project file references."),
        ErrorSpec("THREAD_SEND_IDEMPOTENCY_CONFLICT", ruleId: "thread.send.idempotency.conflict", agentAction: "Use a new idempotency key or repeat the original payload.", requiresManual: false, retryable: false, explain: "Same idempotency key reused with a different thread send payload."),
        ErrorSpec("THREAD_NOT_FOUND", ruleId: "thread.not_found", agentAction: "Run `alln history --json` (or create a thread); retry with a valid thread id.", requiresManual: true, retryable: false, explain: "No thread matches the given id, or no threads exist yet. List threads and retry with a valid thread id."),
        ErrorSpec("TRY_FIX_PACKET_MISSING", ruleId: "try_fix.packet.missing", agentAction: "Re-run the Bug Hunt diagnosis; the fix attempt needs a typed fix packet.", requiresManual: false, retryable: true, explain: "The Bug Hunt answer run produced no typed fix packet (the writer emitted no fenced fix-packet block), so there is no hypothesis to try. Re-run the diagnosis with a sharper report."),
        ErrorSpec("TRY_FIX_PACKET_UNSAFE", ruleId: "try_fix.packet.unsafe", agentAction: "Read the gate reason; resolve the danger flag / add an actionable hypothesis + proof, then retry.", requiresManual: true, retryable: false, explain: "The fix packet is not safe to execute: it carries a danger flag (credentials, deletion, deploy…), lacks an actionable hypothesis (a fix within a boundary), names no truth owner, or its proof method is incomplete. Danger blocks; doubt does not."),
        ErrorSpec("TRY_FIX_EXECUTOR_INVALID", ruleId: "try_fix.executor.invalid", agentAction: "Pass --executor a single mutating team that is runnable on this bench (default build_slice).", requiresManual: true, retryable: false, explain: "The chosen fix executor is not a single, mutating, runnable team. The fix attempt must resolve to exactly one mutating worker."),
        ErrorSpec("RELAY_NOT_FOUND", ruleId: "relay.not_found", agentAction: "Run `alln loop status <id> --json` with a valid loop id, or start a new loop with `alln loop start \"<what you want done>\"`.", requiresManual: true, retryable: false, explain: "No Loop matches the given id."),
        ErrorSpec("RELAY_STATE_DECODE_FAILED", ruleId: "relay.state.decode_failed", agentAction: "The relay folder exists but relay.json cannot be read by this binary — rebuild from the current branch (`swift build --package-path Packages/AllnighterCore` + `alln install-cli`). If the file uses retired devWorkerId/pmWorkerId keys, delete the relay folder or rewrite seat keys to devModelId/pmModelId.", requiresManual: true, retryable: false, explain: "A relay.json is present on disk but failed to decode — not the same as a missing id. Common during dogfood when a stale on-PATH alln binary predates the WTA seat-key rename."),
        ErrorSpec("RELAY_INVALID_STATE", ruleId: "relay.invalid_state", agentAction: "Check status with `alln loop status <id>`; only resume/pm-eligible statuses accept those transitions. Founder stop uses `alln loop stop` and does not use this code.", requiresManual: true, retryable: false, explain: "The requested resume/pm-reassignment transition is not valid for the loop's current status — not a founder-stop error."),
        ErrorSpec("RELAY_HANDOVER_UNSAFE", ruleId: "relay.handover.unsafe", agentAction: "The PM's handover named a danger instruction (credentials, signing, destructive git, sandbox/TCC, mass deletion); the relay escalated instead of dispatching it. Answer the escalation or rewrite the round's intent.", requiresManual: true, retryable: false, explain: "HandoverGate blocked a PM handover before it reached the dev seat — danger blocks, doubt does not."),
        ErrorSpec("RELAY_ALREADY_ACTIVE", ruleId: "relay.already_active", agentAction: "Read it with `alln loop status <id> --json`, resume it or reassign the PM with `alln loop pm`, or wait — do not start a second loop on the same doc.", requiresManual: true, retryable: false, explain: "a loop is already running for this project + doc"),
        ErrorSpec("RELAY_JOURNAL_UNAVAILABLE", ruleId: "relay.journal.unavailable", agentAction: "The relay claim could not be written durably — check disk space and permissions under the support root, then retry the relay verb.", requiresManual: true, retryable: true, explain: "Relay dispatch could not persist its claim to the journal."),
        ErrorSpec("RELAY_ROUND_IN_FLIGHT", ruleId: "relay.round.in_flight", agentAction: "Wait with `alln loop status <id> --wait-for parked --timeout 7200 --json`; do not re-dispatch while running. A killed `alln loop wait` is not a failed round. Once parked, retry `alln loop step` if still needed.", requiresManual: false, retryable: true, explain: "A loop round is already dispatching (status == running) — one mutating dev turn at a time, unchanged law. A concurrent dispatch (step, or a resume/pm-reassignment racing another) on the same loop is refused rather than racing a second dev turn onto one repo root. Founder stop never uses this code."),
        ErrorSpec("RELAY_STOP_FAILED", ruleId: "relay.stop.failed", agentAction: "Inspect with `alln ps --json`; retry `alln loop stop <id> --json`. Do not invent resume while live trees remain.", requiresManual: true, retryable: true, explain: "Founder stop could not honestly settle: a signalled owner or turn tree is still identity-alive. Status is left non-terminal rather than stamping stopped over known-live work."),
        ErrorSpec("RUN_ID_IN_USE", ruleId: "run.id.in_use", agentAction: "Attach with `alln run resume <id> --json`, or omit an explicit id.", requiresManual: true, retryable: false, explain: "a run already exists with this id"),
        ErrorSpec("RELAY_NOT_AWAITING_PM", ruleId: "relay.not_awaiting_pm", agentAction: "Run `alln loop status <id> --json`; a loop only accepts `alln loop step` while its status is `awaitingPM` (done/escalated/stopped have nothing left to hand off to).", requiresManual: true, retryable: false, explain: "`loop step` was called against a loop that isn't parked at `awaitingPM` — it already reached a terminal status, or isn't a caller-held loop's normal between-rounds state."),
        ErrorSpec("RELAY_VERDICT_UNPARSEABLE", ruleId: "relay.verdict.unparseable", agentAction: "The PM's submission needs exactly one trailing ```json LoopVerdict block (verdict: continue|done|escalate; handover required for continue). Fix the tail and resubmit `alln loop step` — the loop is still `awaitingPM`, no re-ask machinery runs.", requiresManual: true, retryable: true, explain: "A `loop step` submission didn't end with a parseable LoopVerdict tail (missing entirely, an unknown verdict value, or `continue` with no handover). Unlike a spawned PM turn, there is no automatic re-ask — the caller session is live and just resubmits."),
        ErrorSpec("OWNERSHIP_NOT_FOUND", ruleId: "ownership.not_found", agentAction: "Run `alln ps --json` and pick a current owned id, or omit and use `alln kill --all` for every identity-alive tree.", requiresManual: false, retryable: false, explain: "No owned process tree matches the given id in durable state (run dirs, relay dirs, lane holders)."),
        ErrorSpec("OWNERSHIP_ALREADY_TERMINAL", ruleId: "ownership.already_terminal", agentAction: "No action required; the tree already carries a stamped endReason. Inspect with `alln ps --json`.", requiresManual: false, retryable: false, explain: "`alln kill` refused because the named work is already terminal — kill never clobbers an existing terminal endReason."),
        ErrorSpec("OWNERSHIP_IDENTITY_MISMATCH", ruleId: "ownership.identity.mismatch", agentAction: "Do not retry the same kill against this pid; the recorded identity no longer matches the live process (pid reuse). Run `alln ps --json` and `alln team reconcile` for identity-dead orphans instead.", requiresManual: true, retryable: false, explain: "Kill refused: the recorded owner identity has a live pid whose start time does not match (recycled pid). Signalling would hit the wrong process."),
        ErrorSpec("KILL_PARTIAL", ruleId: "kill.partial", agentAction: "The run stays non-terminal with survivors named. Inspect them with `alln ps --json`, then retry `alln kill <id>` or escalate manually; the tool refuses to stamp `killed` over live work.", requiresManual: false, retryable: true, explain: "`alln kill`/`team cancel` signalled the recorded tree but ≥1 recorded member is still identity-alive (or its group non-empty) after the grace. The verdict is `killOutcome: partial` — the lifecycle is left non-terminal (RLR-L5), never a false `killed` stamp."),
        ErrorSpec("KILL_REFUSED", ruleId: "kill.refused", agentAction: "No recorded member could be signalled (all identity-mismatched or non-PG-killable). Run `alln ps --json` and `alln team reconcile` for identity-dead orphans; do not re-signal a recycled pid.", requiresManual: true, retryable: false, explain: "`alln kill`/`team cancel` found recorded members but could signal none of them — every candidate was a recycled pid or a non-group-killable owner. Nothing was stopped; the verdict is `killOutcome: refused` and the lifecycle stays non-terminal."),
        ErrorSpec("KILL_VERIFICATION_UNAVAILABLE", ruleId: "kill.verification_unavailable", agentAction: "The run records no killable worker `runtimeOwnership` (warm workers or unrecorded legacy). The stop cannot be verified — read `alln show <run-id> --json` or stop the worker at its source; the tool will not stamp `killed` unverified.", requiresManual: true, retryable: false, explain: "The executing run carries no recorded worker identity to verify against (the warm-driver exclusion seam — warm pools record nothing). `killOutcome: verificationUnavailable`: a stop cannot be proven, so no terminal `killed` is stamped (RLR-L5)."),
        ErrorSpec("THREAD_SEND_FAILED", ruleId: "thread.send.failed", agentAction: "Inspect the error detail; retry the send or fix the worker.", requiresManual: false, retryable: true, explain: "The thread send did not complete (worker or transport failure). Inspect the detail, then retry."),
        ErrorSpec("MODEL_NOT_FOUND", ruleId: "model.not_found", agentAction: "List ids with `alln menu --json` or `alln models --json` and retry with a valid ModelID.", requiresManual: true, retryable: false, explain: "No model matches the given id. Use `alln menu --json` / `alln models --json` for catalog ModelIDs."),
        ErrorSpec("MODEL_BUILTIN_IMMUTABLE", ruleId: "model.builtin.immutable", agentAction: "Duplicate the built-in model, then edit the custom copy.", requiresManual: true, retryable: false, explain: "Built-in models cannot be edited or deleted. Duplicate to a custom model and edit that copy."),
        ErrorSpec("MODEL_ID_COLLISION", ruleId: "model.id.collision", agentAction: "Pick a different model id or delete the conflicting custom model.", requiresManual: true, retryable: false, explain: "A model with this id already exists."),
        ErrorSpec("MODEL_INVALID", ruleId: "model.invalid", agentAction: "Fix the model definition and retry the edit.", requiresManual: true, retryable: false, explain: "The model definition or id is invalid (bad id, missing fields, or unknown driver mapping)."),
        ErrorSpec("MODEL_DRIVER_MISSING", ruleId: "model.driver.missing", agentAction: "Reference a known driver id, or add the driver manifest first.", requiresManual: true, retryable: false, explain: "The model references a driver that is not registered. Use a known driver id or add its manifest."),
        ErrorSpec("INTERNAL_ERROR", ruleId: "internal.error", agentAction: "Capture the message and `traceId`; retry once, then report if it persists.", requiresManual: true, retryable: false, explain: "An unexpected internal failure occurred (not a usage error). The detail is in the message; this is a defensive catch-all, not a routine condition."),
        // Project foundation (PRJ-S07+). The full set is registered up front so the
        // recovery ladder and doctor explain cover them as the later slices emit them.
        ErrorSpec("PROJECT_NOT_FOUND", ruleId: "project.not_found", agentAction: "If cwd is an unregistered git root, run `alln project add <path>`. Otherwise `alln project list --json` and retry with a valid id or path.", requiresManual: true, retryable: false, explain: "No project matches the given id/path, or cwd's git root is not registered. Add the project or pick a valid identifier."),
        ErrorSpec("NO_PROJECT_SELECTED", ruleId: "project.none_selected", agentAction: "Select or add a project, then re-run the mutating action.", requiresManual: true, retryable: false, explain: "A mutating action was attempted with no project selected. Mutating work is always scoped to one project root.", exitClass: .usage),
        ErrorSpec("DUPLICATE_PROJECT_ROOT", ruleId: "project.duplicate_root", agentAction: "Use the existing project that owns this normalized root.", requiresManual: false, retryable: false, explain: "The path resolves to an existing project's normalized root; the existing project is returned rather than a duplicate."),
        ErrorSpec("PROJECT_ROOT_UNAVAILABLE", ruleId: "project.root_unavailable", agentAction: "Restore the folder/permissions, then `alln project show <id>` to re-observe.", requiresManual: true, retryable: true, explain: "The project root is missing or permission-denied (rootState != available); mutating runs are blocked until the root is restored."),
        ErrorSpec("PROJECT_ARCHIVED", ruleId: "project.archived", agentAction: "Run `alln project unarchive <id>` before new runs.", requiresManual: true, retryable: false, explain: "The project is archived. Unarchive it before starting new runs; reads remain available."),
        ErrorSpec("THREAD_UNASSIGNED", ruleId: "thread.unassigned", agentAction: "Assign the thread/pending item to a project, then retry.", requiresManual: true, retryable: false, explain: "The thread or pending item has no project. Assign it to a project before a mutating run."),
        ErrorSpec("AGENT_NOT_READY_IN_PROJECT", ruleId: "project.agent_not_ready", agentAction: "Run `alln project models <id> --json`; open the CLI in the project folder and complete its trust/login, then recheck.", requiresManual: true, retryable: true, explain: "The target worker's project readiness is not `ready` for this root. The run waits until the worker is ready here."),
        ErrorSpec("RUN_WRITE_LOCK_BUSY", ruleId: "run.write_lock_busy", agentAction: "The active mutating run on this repo root looks stuck (the wait bound elapsed); wait for it to finish or stop it, then retry.", requiresManual: false, retryable: true, explain: "At most one mutating run per canonical repo root. A second mutating run normally QUEUES (FIFO) behind the active one and runs when it finishes; this error is the safety valve — it fires only when the active run is still holding the lock after the wait bound (it is wedged), so the queued run is refused instead of hanging forever.", exitClass: .laneBusy),
        ErrorSpec(
            "EXECUTION_LANE_BUSY",
            ruleId: "execution.lane.busy",
            agentAction: "Do not busy-loop or invent a private retry cadence. The harness owns the wait: poll relay/pilot status for laneBlocked (position, holder identity/kind/id, heldSinceSeconds) until the ticket clears, or let the harness grant the lane. Never start a second concurrent build-class turn on the same root.",
            requiresManual: false,
            retryable: true,
            explain: "The per-root execution lane is held. Busy callers receive a FIFO ticket naming position and holder; silent queueing without a ticket is forbidden (Process_Ownership.md PO-S03).",
            exitClass: .laneBusy
        ),
        ErrorSpec(
            "WRITE_SCOPE_VIOLATION",
            ruleId: "execution.write_scope.violation",
            agentAction: "Inspect roundLog.scopeViolation (declared writeScope + outOfScopePaths). The harness rejected the turn's work fail-closed; endReason stays reported. Do not auto-revert — the PM decides whether to keep, amend, or reverse the commits. Next turn: stay inside the declared prefixes or re-declare a broader writeScope.",
            requiresManual: true,
            retryable: false,
            explain: "A dev turn declared writeScope path prefixes and the harness found commits (baseline..head) outside that scope. Work is rejected with scopeViolation on roundLog/status; Allnighter never touches git (Process_Ownership.md PO-S06)."
        ),
        ErrorSpec(
            "STANDING_INVARIANT_FAILED",
            ruleId: "execution.standing_invariant.failed",
            agentAction: "Inspect roundLog.standingFailed and proofResults entries with standing:true. For contractDrift: rebuild the turn tree, run `alln dev export-contracts` (regenerate docs/generated/alln/*), commit the artifacts, and re-run. The harness never auto-regenerates or auto-commits (Process_Ownership.md PO-F4).",
            requiresManual: true,
            retryable: false,
            explain: "A harness standing invariant failed after the dev turn (e.g. contractDrift: registry changed without regenerating published contract artifacts). The turn is not clean; endReason stays reported; standingFailed names the invariant ids."
        ),
        ErrorSpec("NO_PROJECT_ROOT", ruleId: "run.no_project_root", agentAction: "Restore the project folder or pick an available project root, then retry.", requiresManual: true, retryable: true, explain: "The project repo root is missing or unreadable; runs require a real cwd in the repo."),
        ErrorSpec("AGENT_NOT_READY", ruleId: "run.agent_not_ready", agentAction: "Pick a ready worker or run setup health, then retry.", requiresManual: true, retryable: true, explain: "No runnable worker resolved for this run (missing CLI, wrong driver, or bench not ready)."),
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
        DoctorCheckSpec("binary.onPath", meaning: "`alln` resolves on PATH to this binary."),
        DoctorCheckSpec("release.update", meaning: "Whether a newer alln release is available (ReleaseChannel cache)."),
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
        DoctorCheckSpec("defaultTeamValid", meaning: "Default team has runnable agents."),
        DoctorCheckSpec("planWriterReady", meaning: "Default team has a ready plan agent."),
        DoctorCheckSpec("coordinator", meaning: "Resident coordinator state; may be degraded in M1."),
        DoctorCheckSpec("journal.incrementalDurable", meaning: "Async run journal persists agent/status transitions incrementally."),
        DoctorCheckSpec("journal.orphanRecovery", meaning: "Orphaned async runs resolve to interrupted."),
        DoctorCheckSpec("pending.storeReadable", meaning: "Pending store can be read."),
        DoctorCheckSpec("pending.storeWritable", meaning: "Pending store can be mutated."),
        DoctorCheckSpec(
            "teaching.installed",
            meaning: "Global host teaching snippet (marker + schema version + content hash) is installed / absent / stale / modified / malformed per supported target; Codex unsupported in v1."
        ),
    ]

    // MARK: - NDJSON events

    static let m1Events: [EventSpec] = [
        EventSpec("teamRunStarted", requiredData: ["status", "origin", "teamPresetId"]),
        EventSpec("workerStarted", requiredData: ["agentId", "modelId", "skillId"]),
        EventSpec("workerAnswered", requiredData: ["agentId", "durationMs"]),
        EventSpec("workerFailed", requiredData: ["agentId", "error"]),
        EventSpec("planStarted", requiredData: ["agentId", "stageId"]),
        EventSpec("planWritten", requiredData: ["agentId", "stageId", "durationMs"]),
        // RLR-S03c: bounded projection of the live worker delta/output stream
        // (RunActivity.activityKind) — never the raw text (non-goal). Additive;
        // unknown-event-tolerant consumers skip it safely.
        EventSpec("workerActivity", requiredData: ["agentId", "activityKind"]),
        EventSpec("stageActivity", requiredData: ["stageId", "activityKind"]),
        // ORS-S02b1: immediate snapshot frame on `show --stream` (before replay).
        EventSpec("teamRunSnapshot", requiredData: ["teamRun"]),
        // ORS-S02b2: attention-required observer boundary (not a run terminal).
        EventSpec("attentionRequired", requiredData: ["reason", "activityMode", "message"]),
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
        NextActionKindSpec("showArtifact", summary: "Open the polished HTML team artifact for a terminal run."),
        NextActionKindSpec("showRun", summary: "Show the full run."),
        NextActionKindSpec("export", summary: "Export the result bundle."),
        NextActionKindSpec("showHistory", summary: "List recent runs."),
        NextActionKindSpec("showAnswer", summary: "Print the run's answer text (durable partial included) — retrieval for in-flight, killed, or failed runs whose work is in the record."),
        /// ORS: attention-required recovery after a stream budget/vendor/blocker exit.
        /// Must never be `showRun` (self-referential poll loop).
        NextActionKindSpec("inspectBlocker", summary: "Inspect a sourced blocker, vendor wait, or attention-required stream exit; not a stream reattach."),
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
        ExampleRecipe("install_cli_json", title: "Install the running binary onto PATH", command: "alln install-cli --json"),
        ExampleRecipe("version_json", title: "Print binary and contract identity", command: "alln version --json"),
        ExampleRecipe("update_check", title: "Soft-announce a newer release", command: "alln update --check"),
        ExampleRecipe("models_json", title: "List model catalog and Bench state", command: "alln models --json"),
        ExampleRecipe("drivers_json", title: "List CLIs and park state", command: "alln drivers --json"),
        ExampleRecipe("drivers_park", title: "Park a CLI you are not using", command: "alln drivers park opencode"),
        ExampleRecipe("drivers_unpark", title: "Put a parked CLI back on the bench", command: "alln drivers unpark opencode"),
        ExampleRecipe("teams_code_json", title: "List Code teams", command: "alln teams --lane code --json"),
        ExampleRecipe("teams_definition_json", title: "Full team definition for edit or novel new", command: "alln teams definition code_bug_hunt --json"),
        ExampleRecipe("teams_duplicate_json", title: "Deterministic Bug Hunt variant", command: "alln teams duplicate code_bug_hunt --id custom_code_my_bug_hunt --name \"My Bug Hunt\" --json"),
        ExampleRecipe("teams_new_json", title: "Create novel team from manifest", command: "alln teams new custom_code_novel --file ./TeamPreset.json --json"),
        ExampleRecipe("skills_code_json", title: "List Code skills", command: "alln skills --lane code --json"),
        ExampleRecipe("skills_show_json", title: "Show a Code skill", command: "alln skills show bug_reproducer --json"),
        ExampleRecipe("skills_restore_json", title: "Restore a built-in skill override", command: "alln skills restore bug_reproducer --json"),
        ExampleRecipe("skills_gc_json", title: "Purge lab and orphan custom skills", command: "alln skills gc --json"),
        ExampleRecipe("run_foreground_json", title: "Run in foreground", command: "alln run --json --lane code --team code_bug_hunt --effort low \"tiny foreground sanity\""),
        ExampleRecipe("try_fix_bug", title: "Auto Fix: Bug Hunt then one bounded fix", command: "alln run \"The history view loses finished runs after restart.\" --project <id> --team code_bug_hunt --try-fix --executor build_slice --json"),
        ExampleRecipe("show_latest_json", title: "Show one run by id", command: "alln show <run-id> --json"),
        ExampleRecipe("spec_full", title: "Retrieve the full result packet", command: "alln spec latest --detail full --json"),
        ExampleRecipe("export_md", title: "Export the latest result", command: "alln export latest --format md"),
        ExampleRecipe("export_contracts_check", title: "Verify no contract drift", command: "alln dev export-contracts --check"),
        ExampleRecipe("thread_send_json", title: "Send message with image and file reference to thread", command: "alln thread send latest \"describe this\" --image ./shot.png --ref Sources/App.swift:10-80 --json"),
        ExampleRecipe("thread_rename_json", title: "Rename a work thread", command: "alln thread rename latest \"Paste-image bug\" --json"),
        ExampleRecipe("serve_health_json", title: "Coordinator health", command: "alln serve --health --json"),
        ExampleRecipe("pending_add_json", title: "Create a Draft Pending item", command: "alln pending add --model model_opus --when ready --json \"Review this patch when Claude is available.\""),
        ExampleRecipe("pending_list_json", title: "List Pending items", command: "alln pending list --json"),
        ExampleRecipe("boost_window_show_json", title: "Show Boost window settings", command: "alln boost-window show --json"),
        ExampleRecipe("boost_window_set_json", title: "Enable Boost window for Claude and Codex", command: "alln boost-window set --enabled true --window-start 08:00 --applies-to claude_code,codex --json"),
    ]
}
