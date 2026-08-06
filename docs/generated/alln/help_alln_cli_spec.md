# alln — Agent-Facing CLI Reference

Generated from the contract registry (contractVersion 9.5.0, schemaVersion 1).
Do not hand-edit — run `alln dev export-contracts`.

## Commands (milestone 1)

### `alln docs`

Generated AI-facing command reference.

Arguments:
- `topic` (optional) — Limit docs to one command family.

Flags:
- `--errors` — Print the error/recovery table.
- `--schema` — Print JSON/NDJSON schemas.
- `--examples` — Print example recipes.

Output schema: `contractDoc`.

Examples: `docs_all`.

### `alln menu`

Live compact agent menu: public commands, teams, models, recipes, effects, and defaults.

Flags:
- `--json` — Emit MenuJSON (default; always machine JSON).

Output schema: `menuJSON`.

### `alln menu show`

Hydrate one typed menu ref (command:/team:/model:/recipe:) into Tier-2 detail.

Arguments:
- `ref` (required) — Typed ref, e.g. command:run, team:code_growth, model:model_sonnet.

Flags:
- `--json` — Emit MenuShowJSON (default; always machine JSON).

Output schema: `menuShowJSON`.

### `alln doctor`

Check sources, models, auth, and coordinator.

Flags:
- `--json` — Structured DoctorResult for agents/GUI.
- `--quiet` — Failed checks only.
- `--full` — Deeper probes, bounded timeout.
- `--auto-fix` — Apply safe Allnighter-owned fixes.
- `--agent <sourceId>` — Limit probes and checks to one source (e.g. cursor_agent).
- `--pilot` — Include a `pilot` summary check (can pilot start on this project?).
- `--project <id>` — Project for `--pilot` (default: cwd).

Output schema: `doctorResult`.

Examples: `doctor_json`.

### `alln doctor explain`

Explain one failure/recovery code, bridged to the help topic that documents it.

Arguments:
- `code` (required) — Error code to explain.

Flags:
- `--json` — Structured explanation (ErrorExplainJSON: the catalog row + helpRef + recovery plan).

Output schema: `errorExplainJSON`.

Examples: `doctor_explain`.

### `alln doctor handoff`

Check whether work handed off from this terminal will actually be run by the Allnighter app. Drops one liveness ping in the hand-off mailbox; starts no worker and spends no quota. Distinguishes nothing-claimed-it from claimed-and-went-silent — never guesses.

Flags:
- `--json` — Structured HandoffDoctorJSON verdict.

Output schema: `handoffDoctorJSON`.

### `alln doctor silence`

Mine run journals for idle-timeout (`timeoutKind: idle`) events into per-driver silence-duration histograms. Read-only telemetry for IDLE-HF floor decisions; spends no quota.

Flags:
- `--json` — Structured RunJournalSilenceTelemetry.Report.

Output schema: `idleSilenceReportJSON`.

### `alln detect`

Headless first-run CLI detection — probes sources, assembles the Bench/default team from ready ones, and persists the result.

### `alln capacity`

Show the seven-row vendor capacity/quota table. When the user asks to print/show/display capacity, run bare `alln capacity` and paste the COMPLETE human stdout table verbatim in the final response — never a summary, highlights, JSON, or "shown above". Bare is live cold PTY (no disk/history hydrate-as-live); --refresh is a legacy no-op; --json only on explicit JSON/machine request.

Flags:
- `--json` — Emit JSON instead of the human-readable strip. Use only when the user explicitly requests JSON/machine-readable output or a program needs the schema.
- `--refresh` — Legacy no-op; bare `alln capacity` is already a live cold PTY acquire. Kept for existing scripts.
- `--source <value>` — Target one seat for the live probe (still returns the full seven-row strip). Valid: codex, claude_code, cursor_agent, grok, kimi, agy, opencode_go, bailian_token_plan.
- `--dogfood` — Developer-only direct OpenCode Go dashboard scrape (bypasses the normal bench; requires --source opencode_go). Omit for normal use — opencode_go is a regular bench member without it.

Output schema: `capacityStripJSON`.

### `alln opencode-go configure`

Save encrypted OpenCode Go dashboard credentials for the capacity scrape. Writes a secret to the macOS Keychain — never prints it. The safe non-interactive form pipes the cookie via stdin with --workspace-id; --cookie also works but exposes the value in shell history.

Flags:
- `--workspace-id <string>` — Workspace ID from the dashboard URL (wrk_…). Required in non-interactive stdin mode.
- `--cookie <string>` — Auth cookie value (WARNING: exposes the session token in shell history and process listings — prefer piping via stdin).
- `--json` — Emit structured output.

### `alln opencode-go status`

Check whether OpenCode Go dashboard credentials are configured and usable. Distinguishes not-configured from configured-but-unusable (different recovery paths).

Flags:
- `--json` — Emit structured status JSON (configured, workspaceId, credentialSource, error).

### `alln bootstrap`

Print a paste-ready agent-activation snippet for a host's context file (never edits files).

Flags:
- `--host <claude|cursor|codex|generic|hermes|openclaw>` — claude | cursor | codex | generic | hermes | openclaw (default generic).
- `--json` — Structured { host, pasteTarget, snippet, binaryPath, onPath }.

Output schema: `bootstrapJSON`.

Examples: `bootstrap_json`.

### `alln version`

Print the running binary version and contract hash.

Flags:
- `--json` — Structured VersionJSON.

Output schema: `versionJSON`.

Examples: `version_json`.

### `alln update`

Show whether a newer alln release is available (soft-announce only; never downloads).

Flags:
- `--check` — Same as bare update — print current, latest, and the install one-liner.
- `--json` — Structured { available, current, latest?, command }.

Examples: `update_check`.

### `alln install-cli`

Symlink the running `alln` binary onto PATH (running the command is consent).

Flags:
- `--path <path>` — Install directory override (default /usr/local/bin if writable, else ~/.local/bin).
- `--print` — Print install instructions only (legacy print-only behavior).
- `--json` — Structured { action, path, target, onPath }.

Output schema: `installCLIJSON`.

Examples: `install_cli_json`.

### `alln models`

List model catalog and Bench state (catalog ids). Prefer `alln menu --json` to discover selectable models.

Flags:
- `--json` — Structured ModelListJSON.
- `--driver <driverId>` — Filter to one source.
- `--bench` — Show only enabled Bench models.

Output schema: `modelListJSON`.

Examples: `models_json`.

### `alln drivers`

List headless CLIs and park state. Parked CLIs are ignored (no probe, no seats) until unparked.

Flags:
- `--json` — Structured DriverListJSON (parked listed last).

Output schema: `driverListJSON`.

Examples: `drivers_json`.

### `alln drivers park`

Park a CLI — stop probing it, hide it from Ready, and keep it out of seating until unparked.

Arguments:
- `driver-id` (required) — Driver id (see `alln drivers --json`).

Flags:
- `--json` — Return refreshed DriverListJSON.

Output schema: `driverListJSON`.

### `alln drivers unpark`

Put a parked CLI back on the bench (does not auto-probe; run re-check or `alln detect`).

Arguments:
- `driver-id` (required) — Driver id (see `alln drivers --json`).

Flags:
- `--json` — Return refreshed DriverListJSON.

Output schema: `driverListJSON`.

### `alln catalog validate`

Validate bundled AgentOS catalog and Allnighter overlay (schema + effort consistency).

Flags:
- `--json` — Structured validation summary.

Output schema: `catalogValidateJSON`.

### `alln models enable`

Enable a model on the Bench.

Arguments:
- `model-id` (required) — Model id to enable.

Flags:
- `--json` — Return refreshed ModelListJSON.

Output schema: `modelListJSON`.

### `alln models disable`

Remove a model from the Bench.

Arguments:
- `model-id` (required) — Model id to disable.

Flags:
- `--json` — Return refreshed ModelListJSON.

Output schema: `modelListJSON`.

### `alln models add`

Add a custom model (saved unverified; run `alln models verify` before enable).

Flags:
- `--driver <driverId>` — Source driver id.
- `--name <string>` — Display name.
- `--model-label <string>` — Label passed to the CLI.
- `--role <answerer|planWriter|both>` — answerer|planWriter|both (default answerer).
- `--disabled` — Create off-Bench.
- `--json` — Return refreshed ModelListJSON.

Output schema: `modelListJSON`.

### `alln models verify`

Smoke-verify a custom model label via AgentOS (AGENTOS_MODEL_OK).

Arguments:
- `model-id` (required) — Custom model id to verify.

Flags:
- `--json` — Structured { id, status, detail, driverId, label }.

### `alln models update`

Update a custom model definition.

Arguments:
- `model-id` (required) — Custom model id.

Flags:
- `--name <string>` — New display name.
- `--model-label <string>` — New CLI model label.
- `--role <answerer|planWriter|both>` — New role.
- `--json` — Return refreshed ModelListJSON.

Output schema: `modelListJSON`.

### `alln models delete`

Delete a custom model definition.

Arguments:
- `model-id` (required) — Custom model id.

Flags:
- `--json` — Return refreshed ModelListJSON.

Output schema: `modelListJSON`.

### `alln teams`

List the lane-scoped team catalog. Prefer `alln menu --json` / `alln teams show <id>` over guessing ids.

Flags:
- `--lane <code|design|copy|signal>` — Filter to one lane.
- `--all` — Include inactive (switched-OFF) teams.
- `--json` — Structured catalog summary.

Output schema: `teamCatalogJSON`.

Examples: `teams_code_json`.

### `alln thread send`

Send a message and/or images to a work thread.

Arguments:
- `thread-id` (required) — Thread id or `latest`.
- `message` (optional) — User message text.

Flags:
- `--image <path>` — Attach an image (repeatable).
- `--ref <path[:start-end]>` — Reference a project file or line range (repeatable).
- `--model <string>` — Requested model id.
- `--idempotency-key <string>` — Idempotency key (24h).
- `--json` — Structured send result.

Examples: `thread_send_json`.

### `alln thread get`

Fetch one work thread snapshot.

Arguments:
- `thread-id` (required) — Thread id or `latest`.

Flags:
- `--json` — Structured thread JSON.

Output schema: `threadGetJSON`.

Examples: `thread_get_json`.

### `alln thread rename`

Rename a work thread (same SSOT as the inbox double-click rename).

Arguments:
- `thread-id` (required) — Thread id or `latest`.
- `title` (required) — New non-empty thread title.

Flags:
- `--title <string>` — Alias for the positional new title.
- `--json` — Structured thread JSON.

Output schema: `threadGetJSON`.

Examples: `thread_rename_json`.

### `alln thread attachment`

Fetch one thread attachment by id.

Arguments:
- `thread-id` (required) — Thread id or `latest`.
- `attachment-id` (required) — Attachment id.

Flags:
- `--json` — Structured attachment JSON.

Output schema: `threadAttachmentJSON`.

### `alln thread status`

Poll thread running/attention state.

Arguments:
- `thread-id` (required) — Thread id or `latest`.

Flags:
- `--json` — Structured status JSON.

Output schema: `threadStatus`.

Examples: `thread_status_json`.

### `alln skills`

List the lane-scoped skill catalog.

Flags:
- `--lane <code|design|copy|signal>` — Filter to one lane.
- `--json` — Structured catalog summary (no templates).

Output schema: `skillCatalogJSON`.

Examples: `skills_code_json`.

### `alln skills show`

Show one skill definition including template.

Arguments:
- `skill-id` (required) — Skill id.

Flags:
- `--json` — Structured skill detail.

Examples: `skills_show_json`.

### `alln teams show`

Show one team with crew, optional scout, lead, and seatCount (not the round-trip manifest — use teams definition).

Arguments:
- `team-id` (required) — Team id.

Flags:
- `--json` — Structured team detail with crew/scout/lead and seatCount.

Output schema: `teamShowJSON`.

Examples: `teams_show_json`.

### `alln teams definition`

Full TeamPreset JSON round-trippable through teams edit/save.

Arguments:
- `team-id` (required) — Team id.

Flags:
- `--json` — Structured team definition (TeamPreset).

Output schema: `teamPreset`.

Examples: `teams_definition_json`.

### `alln teams duplicate`

Copy a shipped team (prefer Bug Hunt) into a custom variant; then edit. Omit --id for a generated id. --json returns the editable TeamPreset (feed straight to teams edit).

Arguments:
- `team-id` (required) — Source built-in team id.

Flags:
- `--id <string>` — Caller-chosen custom team id (deterministic; rejects collisions).
- `--name <string>` — Display name for the copy.
- `--json` — Editable TeamPreset JSON (same shape as teams definition / teams edit).

Output schema: `teamPreset`.

Examples: `teams_duplicate_json`.

### `alln teams new`

Create a novel custom team from a TeamPreset file. Fails if id exists or file id ≠ positional id. To copy a shipped team instead, use teams duplicate. --json returns the editable TeamPreset.

Arguments:
- `team-id` (required) — New team id (must match file definition.id).

Flags:
- `--file <path>` — TeamPreset JSON file (or CatalogEnvelope).
- `--json` — Editable TeamPreset JSON (same shape as teams definition / teams duplicate).

Output schema: `teamPreset`.

Examples: `teams_new_json`.

### `alln teams edit`

Replace a custom (or overridden) team definition from JSON after duplicate or new. --json returns the persisted TeamPreset (round-trippable).

Arguments:
- `team-id` (required) — Team id.

Flags:
- `--file <path>` — TeamPreset JSON file.
- `--json` — Editable TeamPreset JSON that was saved.

Output schema: `teamPreset`.

Examples: `teams_edit_json`.

### `alln teams set-default`

Set the default team for a lane.

Arguments:
- `team-id` (required) — Team id.

Flags:
- `--json` — Structured team detail (show projection — catalog-state receipt, not the edit manifest).

Output schema: `teamShowJSON`.

Examples: `teams_set_default_json`.

### `alln teams delete`

Delete a custom team (or restore a built-in to shipped).

Arguments:
- `team-id` (required) — Team id.

Flags:
- `--json` — Deletion acknowledgement JSON.

Examples: `teams_delete_json`.

### `alln teams restore`

Restore a built-in team to its shipped version (remove edits).

Arguments:
- `team-id` (required) — Team id.

Flags:
- `--json` — Restore acknowledgement JSON.

Examples: `teams_restore_json`.

### `alln skills duplicate`

Duplicate a built-in skill into a custom skill.

Arguments:
- `skill-id` (required) — Source skill id.

Flags:
- `--name <string>` — Display name for the copy.
- `--json` — Structured skill detail.

Examples: `skills_duplicate_json`.

### `alln skills new`

Create a custom skill.

Flags:
- `--lane <code|design|copy|signal>` — code | design | copy | signal.
- `--name <string>` — Display name.
- `--purpose <answer|review|planWriter>` — answer | review | planWriter.
- `--template-file <path>` — Skill template text file.
- `--json` — Structured skill detail.

Examples: `skills_new_json`.

### `alln skills edit`

Edit a skill or write a same-ID built-in override.

Arguments:
- `skill-id` (required) — Skill id.

Flags:
- `--name <string>` — New display name.
- `--template-file <path>` — Replacement template file.
- `--json` — Structured skill detail.

Examples: `skills_edit_json`.

### `alln skills restore`

Restore a built-in skill to its shipped version (remove override).

Arguments:
- `skill-id` (required) — Built-in skill id.

Flags:
- `--json` — Restore acknowledgement JSON.

Examples: `skills_restore_json`.

### `alln skills delete`

Delete a custom skill.

Arguments:
- `skill-id` (required) — Skill id.

Flags:
- `--json` — Deletion acknowledgement JSON.

Examples: `skills_delete_json`.

### `alln skills gc`

Purge retired lab skills and delete unreferenced custom skills.

Flags:
- `--json` — JSON with deleted skill ids and count.

Examples: `skills_gc_json`.

### `alln team cancel`

Cancel an active async team run.

Arguments:
- `run-id` (required) — The run id of an accepted async run.

Flags:
- `--json` — Structured TeamCancelResponse.

Output schema: `teamCancelResponse`.

### `alln team reconcile`

Explicit ownership reconcile: identity-dead async runs are reaped (PG-kill recorded pgid when present) and stamped endReason=reconciledOrphan. An exact run-id may target any project; the bare sweep is scoped to the caller's canonical project root (fail closed on unresolved roots) — machine-wide only via the explicit --all-projects.

Arguments:
- `run-id` (optional) — Optional run id; omit to sweep the caller's project scope.

Flags:
- `--all-projects` — Machine-wide fleet sweep instead of the caller's project scope.
- `--json` — Structured reaped-run list.

### `alln ps`

List owned process trees (runs, loops, proofs). Reconciles identity-dead owners on read (CLP-S02) — no manual `team reconcile` on the happy path. PRIMARY liveness is stream silence (`run.lastActivityAt`), same as `alln loop status` — not relay heartbeat/pgid. Default shows alive + needs-action only; `--all` includes terminal history. Scoped to caller's project; `--all-projects` is machine-wide.

Flags:
- `--all` — Include terminal/history rows (museum view). Default is alive + needs-action floor only.
- `--all-projects` — Machine-wide fleet view instead of the caller's project scope.
- `--json` — Structured OwnershipPsJSON inventory.

Output schema: `ownershipPsJSON`.

### `alln kill`

Identity-checked total group kill of one owned tree (or --all identity-alive trees in the caller's project scope) and stamp endReason=killed. Refuses on identity mismatch (never signals a recycled pid). An exact id may target any project.

Arguments:
- `id` (optional) — Owned process id (run/relay/pilot/proof). Required unless --all.

Flags:
- `--all` — Kill every identity-alive owned tree in the caller's project scope (skips identity-mismatched and already-terminal; unresolved roots are never swept).
- `--all-projects` — With --all: machine-wide fleet kill instead of the caller's project scope.
- `--json` — Structured OwnershipKillJSON.

Output schema: `ownershipKillJSON`.

### `alln gc`

Prune old identity-dead terminal run/relay records beyond retention. Keeps identity-alive, non-terminal, recent, and thread-referenced records.

Flags:
- `--dry-run` — Report what would be pruned without deleting.
- `--json` — Structured OwnershipGarbageCollectionJSON summary with every keep reason.

Output schema: `ownershipGarbageCollectionJSON`.

### `alln run`

Unified run: message + optional Team + agent in the registered repository root. Research Teams are observational and execution Teams use one selected agent. TeamRunJSON reports agent terminal states and Git observation, never a correctness verdict.

Arguments:
- `message` (required) — The user's prompt.

Flags:
- `--project <id>` — Project id, name, or repo path. When omitted, walk to the git root and match a registered project (AE-S05).
- `--team <id>` — Team preset id; omit for Default Team.
- `--model <id>` — Override model id.
- `--seat <id>` — Override one crew seat model id (repeatable, crew order; requires --team; judgment teams only).
- `--message <string>` — Alias for the positional message.
- `--effort <low|med|high>` — low | med | high.
- `--lane <code|design|copy|signal>` — Lane tags the run for context and filtering; `--team` routes.
- `--type <type>` — Copy routing sugar.
- `--context <string>` — Bounded context snippet.
- `--idle-timeout <integer>` — Override the worker idle-stall budget in seconds (default = driver manifest invoke.timeoutSeconds, commonly 1800s for agent CLIs). Resets on streaming stdout/stderr bytes, attributable process-group activity (child spawn, CPU under the recorded pgid), and durable recordProgress heartbeats; wall is the hard ceiling (--wall-timeout, default 3600).
- `--handshake-timeout <integer>` — Runner-ready handshake bound in seconds (default 60; RLR-L8). Finite positive required.
- `--first-activity-timeout <integer>` — First post-spawn activity bound in seconds (default 120; RLR-L8). Finite positive required.
- `--wall-timeout <integer>` — Total wall-clock ceiling in seconds (default 3600; RLR-L8). Finite positive required.
- `--idempotency-key <string>` — Transport idempotency key (24h replay window). Same key+payload replays the original run; conflict/expired refuse.
- `--retry-of <id>` — Intentional retry of a prior run id (new key). Requires prior tree verified stopped, or --accept-survivors.
- `--accept-survivors` — Allow --retry-of when the prior run still has identity-alive recorded workers.
- `--commit-message <string>` — Exact commit message for the worker (FR12 instruct + verify; Allnighter does no git).
- `--no-commit` — Instruct the worker to leave work uncommitted for PM review (mutually exclusive with --commit-message). Still mutating and still takes the per-root write lock — does not skip the queue. For parallel feedback use --read-only --model.
- `--read-only` — Lock policy only: same one-model chat as --model, with writePolicy readOnly and no write-lock queue. Requires --model. Not a team path; not FS isolation. Mutually exclusive with --team and mutator-only flags (--no-commit, --commit-message, --try-fix, --proof).
- `--proof <string>` — Run a bounded proof command after the worker settles; surface pass/fail (never blocks git).
- `--try-fix` — Bug Hunt diagnosis → danger-not-doubt gate → one bounded fix attempt.
- `--executor <id>` — Mutating executor team id (default build_slice).
- `--agent <id>` — Origin agent id for attribution (does not select the worker).
- `--thread-id <id>` — Owning work thread id.
- `--conversation-id <id>` — Origin conversation id.
- `--message-id <id>` — Origin message id.
- `--dry-run` — Resolve project/worker/auth/writePolicy/effects/write-lock and return canStart + counts; exit 0, no dispatch. Research Teams are observational in the canonical repository; terminal repoDelta reports whether a mutating run wrote.
- `--json` — Emit TeamRunJSON (blocking run), RunDryRunJSON v2 with --dry-run, or a detached acknowledgement with one nextAction.command (`alln show <id> --stream`) with --no-wait.
- `--stream` — Emit NDJSON events (one JSON object per stdout line; ends with teamRunCompleted, teamRunFailed, or error). Shared framing: immediate snapshot first, bounded replay, live follow of new events, exactly one terminal frame. Ends at terminal or attention-required boundary; terminal exit class propagates unconditionally (no opt-in). Mutually exclusive with conflicting mode flags.
- `--no-wait` — Hand the run to a detached child of the same registered `alln run` verb; return only after the child durably accepts with one nextAction.command = `alln show <id> --stream` (real run id, including idempotency replay). A child refusal fails loud. Mutually exclusive with --stream / --dry-run / --try-fix.
- `--delivery <string>` — Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command.

Mutually exclusive: `--json`, `--stream`.

Mutually exclusive: `--no-commit`, `--commit-message`.

Mutually exclusive: `--model`, `--seat`.

Mutually exclusive: `--dry-run`, `--stream`.

Mutually exclusive: `--dry-run`, `--try-fix`.

Mutually exclusive: `--no-wait`, `--stream`.

Mutually exclusive: `--no-wait`, `--dry-run`.

Mutually exclusive: `--no-wait`, `--try-fix`.

Mutually exclusive: `--read-only`, `--team`.

Mutually exclusive: `--read-only`, `--no-commit`.

Mutually exclusive: `--read-only`, `--commit-message`.

Mutually exclusive: `--read-only`, `--try-fix`.

Mutually exclusive: `--read-only`, `--proof`.

Only with: `--executor` only with `--try-fix`.

Requires: `--accept-survivors` requires `--retry-of`.

Requires: `--seat` requires `--team`.

Requires: `--delivery` requires `--no-wait`.

Requires: `--read-only` requires `--model`.

Output schema: `teamRunJSON`.

Examples: `run_foreground_json`.

### `alln run resume`

Resume a run parked on vendor capacity (same run id, in-process).

Arguments:
- `runId` (required) — Parked run id.

Flags:
- `--json` — Emit TeamRunJSON.

Output schema: `teamRunJSON`.

### `alln continuity receipt`

Local observed-facts summary of vendor waits covered and automatic resumes (last 24h).

Flags:
- `--json` — Emit MorningReceipt JSON.

### `alln loop start`

Start a durable PM↔dev loop. The brief is the only required input — both seats default by tier. `--pm caller` reviews every round yourself; `--pm <agent-id>` (or the default) spawns that agent as PM and runs unattended.

Arguments:
- `brief` (required) — What you want done. The brief handed to the PM at round 1 — no other flag is required.

Flags:
- `--spec <path>` — Repo-relative spec doc path — a shortcut for when the brief would be three paragraphs, not the shape. The PM re-reads it fresh each round.
- `--pm <id>` — PM occupant: `caller` (this session reviews every round) or a canonical agent id (that agent is spawned as PM and the loop runs unattended). Omitted → the Frontier-tier default.
- `--dev <id>` — Dev seat canonical agent id. Omitted → the Balanced-tier default.
- `--project <id>` — Project id, name, or repo path. Omitted → resolved from the current working directory.
- `--dry-run` — Resolve the brief/spec/both seats/project and report readiness; exit 0, create nothing, spend nothing.
- `--no-wait` — Spawn the same registered `loop start` verb in a detached child; return only after the child durably claims delivery.
- `--json` — Emit structured JSON (LoopStartDryRunJSON with --dry-run; LoopJSON otherwise).

Output schema: `relayJSON`.

### `alln loop list`

List durable PM↔dev loops for the resolved project (id, status, brief/spec, seats, updatedAt).

Flags:
- `--project <id>` — Project id, name, or repo path. Omitted → resolved from the current working directory.
- `--json` — Emit LoopListJSON.

### `alln loop status`

Read a loop's durable state, or wait for its parked or terminal PM boundary. Reconciles identity-dead `.running` owners on read (no manual reconcile).

Arguments:
- `loop-id` (required) — Loop id.

Flags:
- `--wait-for <string>` — Wait for parked (awaitingPM|escalated) or terminal (done|stopped); requires --timeout.
- `--timeout <number>` — Non-negative wait limit in seconds; required with --wait-for.
- `--json` — Emit LoopJSON (plus additive live usage fields while running).

Requires: `--wait-for` requires `--timeout`.

Requires: `--timeout` requires `--wait-for`.

Output schema: `relayJSON`.

### `alln loop stop`

Founder stop of a Loop: identity-checked teardown, durable stopped status with reason "founder stopped", and a PM Turn on transition. Idempotent on already done/stopped. Not ownership kill.

Arguments:
- `loop-id` (required) — Loop id.

Flags:
- `--json` — Emit LoopJSON (status=stopped, stoppedReason="founder stopped" on transition).

Output schema: `relayJSON`.

### `alln loop resume`

Resume an escalated loop with the founder's answer, then continue rounds (may dispatch dev turns).

Arguments:
- `loop-id` (required) — Loop id.

Flags:
- `--answer <string>` — The founder's answer to the escalation (required).
- `--until <time>` — Hard stop HH:MM (local) for the resumed stretch.
- `--max-rounds <integer>` — Round ceiling for the resumed stretch (default 20).
- `--no-auto-serve` — Do not auto-start the background notifier (alln serve) for this dispatch.
- `--dry-run` — Resolve the loop id, founder answer, seats, and readiness; report LoopStartDryRunJSON; exit 0; spend nothing, start no worker, mutate no durable state.
- `--no-wait` — Spawn the same registered `loop resume` verb in a detached child; return only after the child durably claims with delivery.path=wait and the exact terminal status waiter. A refusal fails loud. Mutually exclusive with --dry-run.
- `--delivery <string>` — Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command. Mutually exclusive with --dry-run.
- `--json` — Emit structured JSON (LoopStartDryRunJSON with --dry-run; NDJSON progress + final LoopJSON otherwise; detached ack with --no-wait).

Mutually exclusive: `--no-wait`, `--dry-run`.

Mutually exclusive: `--delivery`, `--dry-run`.

Requires: `--delivery` requires `--no-wait`.

Output schema: `relayJSON`.

### `alln loop wait`

Optional interactive waiter: blocks until the in-flight round settles. Disposable — death ≠ job failure; prefer `loop status` for agents. Emits heartbeats while running; SIGTERM/SIGINT prints stillRunning goodbye.

Arguments:
- `loop-id` (required) — Loop id.

Flags:
- `--max-wait <integer>` — Stop waiting after N seconds while still running; exit with stillRunning and reattach to loop status (default 1800 when stdout is not a TTY; interactive TTY waits until settled unless set).
- `--json` — Emit PilotWatchJSON (final single-line envelope; NDJSON heartbeats while waiting).

Output schema: `relayJSON`.

### `alln loop step`

Submit this round's PM decision while the loop is awaitingPM: a message continues the dev turn; `--done <summary>` settles the loop. Blocks through the dev turn by default.

Arguments:
- `loop-id` (required) — Loop id.
- `message` (optional) — Order for the dev seat (continue). Mutually exclusive with --done.

Flags:
- `--done <string>` — Close the loop with a done summary instead of dispatching a continue message.
- `--dry-run` — Resolve the loop id, step payload, seats, and readiness; report LoopStartDryRunJSON; exit 0; spend nothing, start no worker, mutate no durable state.
- `--json` — Emit structured JSON (LoopStartDryRunJSON with --dry-run; handoff/result + progress NDJSON otherwise).

Output schema: `relayJSON`.

### `alln loop pm`

Reassign the PM chair mid-loop. `<agent-id>` converts a parked caller-held loop (awaitingPM|escalated) to a spawned PM and continues (dispatches). `caller` hands a parked spawned loop back to this session (status flip, no dispatch).

Arguments:
- `loop-id` (required) — Loop id.
- `occupant` (required) — `caller` or a canonical agent id.

Flags:
- `--max-rounds <integer>` — Round ceiling for the adopted agent-PM stretch — counts TOTAL rounds including prior ones (default 20). Ignored for `caller`.
- `--until <time>` — Hard stop HH:MM (local) for the adopted agent-PM stretch. Ignored for `caller`.
- `--no-auto-serve` — Do not auto-start the background notifier (alln serve) for this dispatch (agent-PM path).
- `--dry-run` — Resolve the loop id, requested PM occupant, seats, and readiness; report LoopStartDryRunJSON; exit 0; spend nothing, start no worker, mutate no durable state (no occupant change).
- `--no-wait` — Spawn the same registered `loop pm` verb in a detached child (agent-PM path); return only after the child durably claims delivery. A refusal fails loud. Mutually exclusive with --dry-run.
- `--delivery <string>` — Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command. Mutually exclusive with --dry-run.
- `--json` — Emit structured JSON (LoopStartDryRunJSON with --dry-run; NDJSON progress + final LoopJSON otherwise; detached ack with --no-wait).

Mutually exclusive: `--no-wait`, `--dry-run`.

Mutually exclusive: `--delivery`, `--dry-run`.

Requires: `--delivery` requires `--no-wait`.

Output schema: `relayJSON`.

### `alln pair relay`

Retired — use `alln loop start "<what you want done>"` instead. Runs the PM↔dev loop unattended: a PM seat reviews the repo and a dev seat builds, round after round, until done/escalate/a ceiling.

Flags:
- `--doc <path>` — Repo-relative spec doc path (required) — the PM re-reads it fresh each round.
- `--project <id>` — Project id, name, or repo path (required).
- `--pm-model <id>` — PM seat model id (required).
- `--dev-model <id>` — Dev seat model id (required).
- `--message <string>` — Kickoff brief body (one-shot, first PM assemble only). Mutually exclusive with --message-file.
- `--message-file <path>` — Read a UTF-8 file as the kickoff brief (one-shot, first PM assemble only). Mutually exclusive with --message.
- `--until <time>` — Hard stop HH:MM (local).
- `--max-rounds <integer>` — Round ceiling (default 20).
- `--idle-timeout <integer>` — Override the dev seat's per-turn worker idle-stall budget in seconds (default = driver manifest timeout). Reuses PO-F5's `alln run --idle-timeout` plumbing (PO-F7).
- `--no-auto-serve` — Do not auto-start the background notifier (alln serve) for this dispatch.
- `--no-wait` — Spawn the same registered `pair relay` verb in a detached child; return only after the child durably claims with delivery.path=wait and the exact terminal status waiter. A refusal fails loud and spawns nothing.
- `--delivery <string>` — Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command.
- `--json` — Emit NDJSON RelayProgressJSON events, then a final LoopJSON envelope (or, with --no-wait, a single delivery acknowledgement).

Mutually exclusive: `--message`, `--message-file`.

Requires: `--delivery` requires `--no-wait`.

Output schema: `relayJSON`.

### `alln pair relay-status`

Retired — use `alln loop status <loop-id>` instead. Reads a loop's durable state, or waits for its parked or terminal PM boundary. Reconciles identity-dead `.running` owners on read (no manual reconcile).

Flags:
- `--relay <id>` — Relay id (required).
- `--wait-for <string>` — Wait for parked (awaitingPM|escalated) or terminal (done|stopped); requires --timeout.
- `--timeout <number>` — Non-negative wait limit in seconds; required with --wait-for.
- `--json` — Emit LoopJSON.

Output schema: `relayJSON`.

### `alln pair relay-resume`

Retired — use `alln loop resume <loop-id>` instead. Resumes an escalated loop with the founder's answer, then continues.

Flags:
- `--relay <id>` — Relay id (required).
- `--answer <string>` — The founder's answer to the escalation (required).
- `--until <time>` — Hard stop HH:MM (local) for the resumed stretch.
- `--max-rounds <integer>` — Round ceiling for the resumed stretch (default 20).
- `--no-auto-serve` — Do not auto-start the background notifier (alln serve) for this dispatch.
- `--no-wait` — Spawn the same registered `relay-resume` verb in a detached child; return only after the child durably claims with delivery.path=wait and the exact terminal status waiter. A refusal (e.g. RELAY_ROUND_IN_FLIGHT) fails loud.
- `--delivery <string>` — Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command.
- `--json` — Emit NDJSON RelayProgressJSON events, then a final LoopJSON envelope (or, with --no-wait, a single delivery acknowledgement).

Requires: `--delivery` requires `--no-wait`.

Output schema: `relayJSON`.

### `alln pair relay adopt`

Retired — use `alln loop pm <loop-id> <agent-id>` instead. Converts a parked caller-held loop (awaitingPM or escalated) to a spawned PM and continues from the durable round log.

Flags:
- `--relay <id>` — Relay id (required).
- `--pm-model <id>` — The spawned PM seat's model id (required).
- `--max-rounds <integer>` — Round ceiling for the adopted stretch — counts TOTAL rounds including the piloted ones already on the log (default 20).
- `--until <time>` — Hard stop HH:MM (local) for the adopted stretch.
- `--no-auto-serve` — Do not auto-start the background notifier (alln serve) for this dispatch.
- `--no-wait` — Spawn the same registered `relay adopt` verb in a detached child; return only after the child durably claims with delivery.path=wait and the exact terminal status waiter. A refusal fails loud.
- `--delivery <string>` — Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command.
- `--json` — Emit NDJSON RelayProgressJSON events, then a final LoopJSON envelope (or, with --no-wait, a single delivery acknowledgement).

Requires: `--delivery` requires `--no-wait`.

Output schema: `relayJSON`.

### `alln pair relay stop`

Retired — use `alln loop stop <loop-id>` instead. Founder stop of a Loop: identity-checked teardown, durable stopped status with reason "founder stopped", and a PM Turn on transition. Idempotent on already done/stopped.

Flags:
- `--relay <id>` — Relay id (required).
- `--json` — Emit LoopJSON (status=stopped, stoppedReason="founder stopped" on transition).

Output schema: `relayJSON`.

### `alln pair pilot start`

Retired — use `alln loop start "<what you want done>" --pm caller` instead. Starts a loop with this session as PM; Allnighter runs the crew (dev seat + rails). Parks awaitingPM.

Flags:
- `--doc <path>` — Repo-relative spec doc path (required) — the piloting session re-reads it fresh each round.
- `--project <id>` — Project id, name, or repo path (required).
- `--dev-model <id|alias>` — Dev seat model id or alias (optional when a seat was remembered for this project).
- `--max-rounds <integer>` — Round ceiling, set once here — Pilot has no long-lived process to re-supply it per handoff (default 20).
- `--idle-timeout <integer>` — Override the dev seat's per-turn worker idle-stall budget in seconds (default = driver manifest timeout), set once here and re-read from durable state at every later `pilot handoff`. Reuses PO-F5's `alln run --idle-timeout` plumbing (PO-F7).
- `--json` — Emit PilotStartJSON (relay + shell-quoted nextCommand for paste + raw scaffoldPath + nextCommandArgv for programmatic handoff).

Output schema: `relayJSON`.

### `alln pair pilot handoff`

Retired — use `alln loop step <loop-id>` instead. Submits this round's review (LoopVerdict tail or --verdict + handover file); loop step blocks by default; after step use `loop wait <loop-id>` or `loop status <loop-id> --wait-for parked`. `--no-wait` is NOT on loop step.

Flags:
- `--relay <id>` — Relay id (required).
- `--file <path>` — Read the full submission markdown from a file (verdict tail included; omit to read stdin).
- `--verdict <continue|done|escalate>` — Required with --handover-file/--handover-stdin; synthesizes the LoopVerdict tail internally.
- `--handover-file <path>` — Raw order markdown for the dev seat (mutually exclusive with --file).
- `--handover-stdin` — Read the handover markdown from stdin (mutually exclusive with --file).
- `--note <string>` — Optional closing note for done/escalate verdicts.
- `--no-wait` — Return after dispatch with delivery.path=wait and an exact `pilot status --wait-for parked` command. Run it once for the parked PM Turn; a killed `pilot watch` is not failure.
- `--delivery <string>` — Detached delivery path. Only `wake` is supported and requires machine-level pmTurnWake.command.
- `--no-auto-serve` — Do not auto-start the background notifier (alln serve) for this dispatch.
- `--json` — Emit NDJSON RelayProgressJSON events, then a final PilotHandoffJSON envelope (or, with --no-wait, a single delivery acknowledgement).

Mutually exclusive: `--file`, `--handover-file`.

Mutually exclusive: `--file`, `--handover-stdin`.

Mutually exclusive: `--handover-file`, `--handover-stdin`.

Requires: `--delivery` requires `--no-wait`.

Output schema: `relayJSON`.

### `alln pair pilot status`

Retired — use `alln loop status <loop-id>` instead. Reads a caller-held loop's durable state, or waits for its parked PM boundary (awaitingPM|escalated). While running: elapsedSeconds, ownerAlive, lastProgressAt/silenceAgeSeconds (PRIMARY stream liveness — same truth as alln ps; not relay heartbeat/pgid), streamSilenceWarning when silence > 6×waitHint, commitsSinceBaseline (SUPPLEMENTARY only — not liveness), waitHintSeconds 45, watcherDisposable. Prefer over wait for agents.

Flags:
- `--relay <id>` — Relay id (required).
- `--wait-for <string>` — Wait for parked (awaitingPM|escalated); requires --timeout. terminal is not valid for Pilot.
- `--timeout <number>` — Non-negative wait limit in seconds; required with --wait-for.
- `--json` — Emit PilotStatusJSON (relay + recovery nextActions; while running adds elapsedSeconds, ownerAlive, lastProgressAt/silenceAgeSeconds as primary stream liveness, streamSilenceWarning when silence > 6×waitHint, commitsSinceBaseline as supplementary/not liveness, waitHintSeconds 45, watcherDisposable).

Output schema: `relayJSON`.

### `alln pair pilot watch`

Retired — use `alln loop wait <loop-id>` instead. Optional interactive waiter: blocks until the in-flight round settles. Disposable — death ≠ job failure; prefer `loop status` for agents. Emits heartbeats while running; SIGTERM/SIGINT prints stillRunning goodbye.

Flags:
- `--relay <id>` — Relay id (required).
- `--max-wait <integer>` — Stop waiting after N seconds while still running; exit with stillRunning and reattach to pilot status (default 1800 when stdout is not a TTY; interactive TTY waits until settled unless set).
- `--json` — Emit PilotWatchJSON (final single-line envelope; NDJSON pilotWatchHeartbeat lines while waiting).

Output schema: `relayJSON`.

### `alln pair pilot adopt`

Retired — use `alln loop pm <loop-id> caller` instead. Hands a parked spawned loop's PM seat to the caller session (status → awaitingPM). No dispatch.

Flags:
- `--relay <id>` — Relay id (required).
- `--json` — Emit LoopJSON.

Output schema: `relayJSON`.

### `alln pair pilot scaffold-handover`

Retired alongside `pair pilot`. Writes or re-emits a suggested PM handover markdown template for a loop round; the underlying auto-seed template is unaffected.

Flags:
- `--relay <id>` — Relay id (required).
- `--round <integer>` — Round number for the filename (default 1).
- `--json` — Emit scaffold path as JSON.

Output schema: `relayJSON`.

### `alln show`

Show one run. Snapshot (`--json`) or reattachable stream (`--stream`): immediate snapshot, bounded replay, live follow, exactly one terminal; terminal exit class propagates unconditionally.

Arguments:
- `run-id|latest` (required) — A run id or `latest`.

Flags:
- `--json` — Emit the run as TeamRunJSON.
- `--full` — Include resolved worker prompt snapshots (audit). Mutually exclusive with --stream.
- `--stream` — Emit NDJSON events (one JSON object per stdout line; ends with teamRunCompleted, teamRunFailed, or error). Shared framing: immediate snapshot first, bounded replay, live follow of new events, exactly one terminal frame. Ends at terminal or attention-required boundary; terminal exit class propagates unconditionally (no opt-in). Mutually exclusive with conflicting mode flags.

Mutually exclusive: `--full`, `--stream`.

Output schema: `teamRunJSON`.

Examples: `show_latest_json`.

### `alln floor show`

Show the inspectable Floor for one team run (worker lanes, artifacts, typed return, timeline, Execute requirements). For the polished HTML receipt, use `alln artifact show <id>`.

Arguments:
- `run-id|latest` (optional) — A run id or `latest` (default latest).

Flags:
- `--json` — Emit the FloorRun projection.

Output schema: `floorRun`.

### `alln artifact show`

Regenerate and open the private HTML team artifact for a terminal run.

Arguments:
- `run-id|latest` (optional) — A run id or `latest` (default latest).

Flags:
- `--no-open` — Print the absolute path only; do not open the default browser.
- `--json` — Emit path, run id, and honesty string only (no HTML body).

Output schema: `markdown`.

### `alln artifact export`

Export the styled HTML team artifact to a user-chosen path for offline reading.

Arguments:
- `run-id|latest` (optional) — A run id or `latest` (default latest).

Flags:
- `--out <path>` — Destination file path for the HTML export (required).
- `--json` — Emit path, run id, and honesty string only (no HTML body).

Output schema: `markdown`.

### `alln spec`

Retrieve a run's spec/result packet (summary|full|artifactRefsOnly).

Arguments:
- `run-id|latest` (optional) — A run id or `latest` (default latest).

Flags:
- `--detail <summary|full|artifactRefsOnly>` (default: summary) — summary | full | artifactRefsOnly.
- `--json` — Structured SpecRetrieval result.

Output schema: `specResult`.

Examples: `spec_full`.

### `alln export`

Export a run result as markdown (not the styled HTML artifact — use `alln artifact export` for that).

Arguments:
- `run-id|latest` (required) — A run id or `latest`.

Flags:
- `--format <md>` (default: md) — Export format (md).

Output schema: `markdown`.

Examples: `export_md`.

### `alln history`

Search prior team runs (read-only).

Arguments:
- `query` (required) — Search text.

Flags:
- `--json` — Structured results.

Output schema: `historyJSON`.

### `alln dev export-contracts`

Regenerate or verify generated artifacts.

Flags:
- `--check` — Fail when generated output drifts from the registry.

Examples: `export_contracts_check`.

### `alln serve`

Optional background scheduler (Pending wake, Boost seeding, vendor-backoff continuation, cloud relay) — and posts local notifications when a run, team run, or Delivery Loop round lands or needs an answer. It owns no run semantics: `alln run` never needs it. Start it in a terminal; Ctrl+C stops it. `alln loop step`/`start`/`resume`/`pm` auto-start it in the background unless `--no-auto-serve`/`ALLN_NO_AUTO_SERVE` is set.

Flags:
- `--health` — Read-only serve health; does not start serve.
- `--json` — Structured CoordinatorHealth output.

Output schema: `coordinatorHealth`.

Examples: `serve_health_json`.

### `alln pending add`

Create a Draft Pending item.

Arguments:
- `prompt` (optional) — Work prompt (or use --file).

Flags:
- `--file <path>` — Read prompt from a file.
- `--model <id>` — Target model id.
- `--team <id>` — Team preset id.
- `--fallback <id>` — Fallback model id.
- `--when <when>` — ready | away | manual.
- `--cwd <path>` — Working directory context.
- `--submit` — Create directly as Pending.
- `--json` — Emit one PendingItemJSON object.

Output schema: `pendingItemJSON`.

Examples: `pending_add_json`.

### `alln pending list`

List Pending items.

Flags:
- `--json` — Structured PendingListJSON.

Output schema: `pendingListJSON`.

Examples: `pending_list_json`.

### `alln pending queue`

Render-ready Pending queue (armed items grouped by project, in order, headed by the running item) + total armed count for the pending pill.

Flags:
- `--json` — Emit a PendingQueueJSON object.

Output schema: `pendingQueueJSON`.

### `alln pending show`

Show one Pending item.

Arguments:
- `pending-id` (required) — Pending item id.

Flags:
- `--json` — Emit one PendingItemJSON object.

Output schema: `pendingItemJSON`.

### `alln pending submit`

Move a Draft item to Pending.

Arguments:
- `pending-id` (required) — Pending item id.

Flags:
- `--json` — Emit one PendingItemJSON object.

Output schema: `pendingItemJSON`.

### `alln pending edit`

Edit a Pending item (Pending returns to Draft).

Arguments:
- `pending-id` (required) — Pending item id.

Flags:
- `--prompt <string>` — Replacement prompt text.
- `--file <path>` — Replacement prompt file.
- `--model <id>` — Target model id.
- `--team <id>` — Team preset id.
- `--fallback <id>` — Fallback model id.
- `--when <when>` — ready | away | manual.
- `--cwd <path>` — Working directory context.
- `--json` — Emit one PendingItemJSON object.

Output schema: `pendingItemJSON`.

### `alln pending reorder`

Reorder Pending items.

Arguments:
- `pending-id` (required) — Item to move.

Flags:
- `--before <id>` — Move before another item.
- `--after <id>` — Move after another item.
- `--position <integer>` — Move to zero-based position.
- `--json` — Emit one PendingItemJSON object.

Output schema: `pendingItemJSON`.

### `alln pending cancel`

Cancel a Draft or Pending item.

Arguments:
- `pending-id` (required) — Pending item id.

Flags:
- `--json` — Emit one PendingItemJSON object.

Output schema: `pendingItemJSON`.

### `alln pending run`

Run a Pending item now (manual attempt; no drain).

Arguments:
- `pending-id` (required) — Pending item id.

Flags:
- `--json` — Emit one PendingItemJSON object.
- `--stream` — NDJSON attempt events (deferred until async attempts).

Mutually exclusive: `--json`, `--stream`.

Output schema: `pendingItemJSON`.

### `alln project list`

List projects (active by default; --all includes archived).

Flags:
- `--all` — Include archived projects.
- `--json` — Emit a ProjectListJSON object.

Output schema: `projectListJSON`.

### `alln project add`

Add (or return the existing) project for a local root. Idempotent on normalized root.

Arguments:
- `path` (required) — Local folder / git repo root.

Flags:
- `--name <string>` — Display name (defaults to the folder name).
- `--json` — Emit a ProjectJSON object.

Output schema: `projectJSON`.

### `alln project show`

Show one project; re-observes root/git so output reflects current truth.

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectJSON object.

Output schema: `projectJSON`.

### `alln project archive`

Archive a project (hides it; never deletes local files or threads).

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectJSON object.

Output schema: `projectJSON`.

### `alln project unarchive`

Restore an archived project to the active roster.

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectJSON object.

Output schema: `projectJSON`.

### `alln project threads`

List the work threads bound to one project.

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectThreadsJSON object.

Output schema: `projectThreadsJSON`.

### `alln project pending`

List the pending work bound to one project (a filtered view of the one Pending store).

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectPendingJSON object.

Output schema: `projectPendingJSON`.

### `alln project stalled`

Read-only stalled-work episodes for one project.

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a StallEpisodeListJSON object.
- `--include-cleared` — Include cleared episodes.

Output schema: `stallEpisodeListJSON`.

### `alln stalled list`

Aggregate stalled-work episodes grouped by project.

Flags:
- `--all` — Include all projects (required).
- `--json` — Emit a StallListJSON object.

Output schema: `stallListJSON`.

### `alln stalled check`

Re-observe a stall episode's target; clears it if it progressed/terminated.

Arguments:
- `episode-id` (required) — Stall episode id.

Flags:
- `--json` — Emit a StallEpisodeJSON object.

Output schema: `stallEpisodeJSON`.

### `alln stalled wait`

Snooze a stall episode's attention for N minutes (default 30).

Arguments:
- `episode-id` (required) — Stall episode id.

Flags:
- `--minutes <int>` (default: 30) — Snooze minutes.
- `--json` — Emit a StallEpisodeJSON object.

Output schema: `stallEpisodeJSON`.

### `alln stalled dismiss`

Dismiss a stall episode (cleared, user-dismiss). Re-surfaces on the next scan if still stalled.

Arguments:
- `episode-id` (required) — Stall episode id.

Flags:
- `--json` — Emit a StallEpisodeJSON object.

Output schema: `stallEpisodeJSON`.

### `alln project context`

Generate the on-demand, source-labeled context packet for a project (a receipt, never durable truth).

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectContextJSON object.

Output schema: `projectContextJSON`.

### `alln project models`

Show cached per-project worker readiness (read-only; never probes).

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectWorkersJSON object.

Output schema: `projectWorkersJSON`.

### `alln project recheck-models`

Rerun driver-declared safe probes for a project and refresh the readiness cache. No auto-config/auth.

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectWorkersJSON object.

Output schema: `projectWorkersJSON`.

### `alln defaults show`

Show the Default model: Auto's tier, the per-tier rosters, the unassigned shelf, and what Auto resolves to right now.

Flags:
- `--json` — Emit a DefaultSettingsJSON object.

Output schema: `defaultSettingsJSON`.

### `alln defaults tier`

Set which tier Auto draws from (frontier|balanced|economy).

Arguments:
- `tier` (required) — frontier | balanced | economy.

Flags:
- `--json` — Emit a DefaultSettingsJSON object.

Output schema: `defaultSettingsJSON`.

### `alln defaults assign`

Add a model to a tier (or move it within that tier). Membership is many-to-many — assigning to one tier never removes it from another.

Arguments:
- `model` (required) — Model id (see `alln models --json`).

Flags:
- `--tier <tier>` — frontier | balanced | economy (required).
- `--default` — Place at the top of the tier (make it that tier's default).
- `--position <int>` — 0-based index within the tier (default: append).
- `--json` — Emit a DefaultSettingsJSON object.

Mutually exclusive: `--default`, `--position`.

Output schema: `defaultSettingsJSON`.

### `alln defaults unassign`

Remove a model from one tier (--tier) or from all tiers (default). Removing from every tier benches it from Auto & substitution.

Arguments:
- `model` (required) — Model id.

Flags:
- `--tier <tier>` — Limit removal to one tier; omit to remove from all.
- `--json` — Emit a DefaultSettingsJSON object.

Output schema: `defaultSettingsJSON`.

### `alln defaults substitutions`

Turn healthy substitutions on or off. ON: a down model falls back to a ready model on the same tier. OFF: Auto uses only the tier default and waits if it's down.

Arguments:
- `state` (required) — on | off.

Flags:
- `--json` — Emit a DefaultSettingsJSON object.

Output schema: `defaultSettingsJSON`.

### `alln defaults reset`

Restore the fresh-install tier seed and substitutions ON.

Flags:
- `--json` — Emit a DefaultSettingsJSON object.

Output schema: `defaultSettingsJSON`.

### `alln boost-window show`

Show Boost window settings, derived seed/reset times, provider rows, and display state.

Flags:
- `--json` — Emit a BoostWindowSettingsJSON object.

Output schema: `boostWindowSettingsJSON`.

### `alln boost-window set`

Set Boost window master toggle, 5h window start, and applies-to sources.

Flags:
- `--enabled <bool>` — true | false.
- `--window-start <time>` — HH:MM (snapped to 15m).
- `--applies-to <string>` — Comma-separated source ids.
- `--json` — Emit a BoostWindowSettingsJSON object.

Output schema: `boostWindowSettingsJSON`.

### `alln boost-window seed`

Force one Boost window seed for a configured source.

Arguments:
- `source-id` (required) — Driver id (e.g. claude_code, codex).

Flags:
- `--json` — Emit a UtilizationSeedEvent object.

Output schema: `utilizationSeedEventJSON`.

### `alln boost-window observations clear`

Clear local Boost window seed observations.

Flags:
- `--source <sourceId>` — Limit clear to one source.
- `--json` — Emit a UtilizationObservationsClearJSON object.

Output schema: `utilizationObservationsClearJSON`.

### `alln help search`

Lexical retrieval over MenuCatalog — returns zero or many menu cards (no selected/confidence/recommended fields).

Arguments:
- `query` (required) — Natural-language question or keywords.

Flags:
- `--limit <int>` (default: 5) — Max results.
- `--json` — Emit a HelpSearchJSON object of menu cards.

Output schema: `helpSearchJSON`.

### `alln help get`

Retrieve one help topic by id, alln:// ref, or --error. Unknown selectors return close matches + the sitemap.

Arguments:
- `topic` (optional) — Topic id or alln:// ref (omit when using --ref/--error).

Flags:
- `--ref <string>` — An alln:// ref (help/schema/error).
- `--error <string>` — Find the topic for this error code.
- `--format <json|md>` (default: json) — json | md.
- `--json` — Emit a HelpGetJSON object.

Output schema: `helpGetJSON`.

### `alln help topics`

List the installed help topic sitemap + the help-first routing law.

Flags:
- `--json` — Emit a HelpTopicsJSON object.

Output schema: `helpTopicsJSON`.

## Commands (named but deferred)

- `alln pending stop` — Stop a running Pending item.
- `alln pair` — Approve iOS/Mac pairing.

## Process exit codes

Stable table (PO-F3 / M-C). Never renumber silently — drift is gated.

| Exit code | Name | Meaning |
| --- | --- | --- |
| `0` | `success` | Command completed; under --json the envelope is a success payload. |
| `1` | `runFailed` | Well-formed command, but the operation failed or the requested entity/state was unavailable. |
| `2` | `usageError` | Command/subcommand/flag/argument was invalid before any work started. |
| `3` | `timeout` | A bounded wait expired before the target condition (loop status --wait-for, team-run time budget). |
| `4` | `laneBusy` | Per-root execution/write lane stayed busy past the wait bound (EXECUTION_LANE_BUSY / RUN_WRITE_LOCK_BUSY). |

## Error codes

| Code | Manual | Retryable | Exit class | Agent action |
| --- | --- | --- | --- | --- |
| `CLI_USAGE_ERROR` | yes | no | `usage` | Re-run `alln docs <command>` and fix arguments. |
| `UNKNOWN_FLAG` | yes | no | `usage` | Re-run `alln <command> --help` or `alln docs <command>`; fix or remove the unknown flag. |
| `INSTALL_CLI_TARGET_UNWRITABLE` | yes | yes | `operational` | Retry with `alln install-cli --path ~/.local/bin` or choose a writable directory. |
| `SUPPORT_MIGRATION_FAILED` | yes | no | `operational` | Inspect the migration error, back up ~/Library/Application Support/Allnighter if needed, then retry. |
| `CONTRACT_DRIFT` | yes | no | `operational` | Run `alln dev export-contracts`, then rebuild. |
| `CONTRACT_VERSION_NOT_BUMPED` | yes | no | `usage` | Bump `ContractRegistry.contractVersion` (minor for additions, major for removals/renames), then run `alln dev export-contracts`. |
| `CONTRACT_ARTIFACTS_NOT_FOUND` | yes | no | `operational` | Run `alln dev export-contracts` from inside the repo (repo root or a subdirectory). |
| `DEFAULTS_TIER_INVALID` | yes | no | `usage` | Use one of frontier | balanced | economy. |
| `DEFAULTS_MODEL_UNKNOWN` | yes | no | `operational` | Run `alln models --json` and pass a known model id. |
| `STALL_EPISODE_NOT_FOUND` | no | no | `operational` | Run `alln stalled list --all --json` and use a current episode id. |
| `DOCTOR_CHECK_FAILED` | no | yes | `operational` | Run `alln doctor --json`. |
| `SOURCE_NOT_FOUND` | yes | no | `operational` | Run `alln doctor --json`; add/configure the missing source. |
| `SOURCE_AUTH_EXPIRED` | yes | no | `operational` | Re-authenticate the named source. |
| `SOURCE_KEYCHAIN_UNAVAILABLE` | yes | yes | `operational` | Open the provider app once, run its login command in Terminal, then `alln doctor --full --agent <source>`. |
| `MODEL_UNAVAILABLE` | no | yes | `operational` | Run `alln models --json`; pick an on-Bench ready model or enable one. |
| `AGENT_NOT_AVAILABLE` | yes | yes | `operational` | Run `alln menu --json` (or `alln menu show model:<id>`); pass a canonical model_* id. Never substitute a display name. |
| `DEFAULT_TEAM_INVALID` | yes | no | `operational` | Run `alln menu --json` / `alln teams show <id> --json`; fix unavailable workers. |
| `AGENT_FAILED` | no | yes | `operational` | Inspect `agentId` and source error; failed agent remains visible. |
| `PLAN_WRITER_FAILED` | no | yes | `operational` | Retry with a ready plan writer or export worker answers. |
| `TEAM_RUN_TIMEOUT` | no | yes | `timeout` | Retry with lower effort or fewer workers. |
| `PM_TURN_WAIT_TIMEOUT` | no | yes | `timeout` | Re-run the same `pilot status` or `relay-status` waiter with a longer --timeout; do not switch to a polling loop or resume command. |
| `PM_TURN_WAKE_UNCONFIGURED` | yes | yes | `operational` | Configure machine-level pmTurnWake.command, then retry `--no-wait --delivery wake`; or omit --delivery and run the returned status waiter. |
| `PM_TURN_WAKE_FAILED` | yes | yes | `operational` | Read status JSON for pmTurnDelivery, fix the receiver, then use the terminal/parked status waiter to recover the durable pmTurn. |
| `RELAY_WAIT_TIMEOUT` | no | yes | `timeout` | Alias of PM_TURN_WAIT_TIMEOUT: re-run the same waiter with a longer --timeout. |
| `TEAM_RUN_FAILED` | no | yes | `operational` | Inspect failed workers and stages; retry or adjust the team. |
| `NESTED_TEAM_BLOCKED` | yes | no | `operational` | Do not recursively spawn teams without explicit depth budget. |
| `TEAM_GOVERNOR_BUSY` | no | yes | `operational` | Wait or retry after current team run completes. |
| `TEAM_GOVERNOR_UNAVAILABLE` | yes | yes | `operational` | Run `alln doctor --json`; ensure Allnighter's support directory is writable, or set a writable support root for eval runs. |
| `PENDING_MUTATION_DEFERRED` | yes | no | `operational` | Keep item Draft/Pending; mutating pending runs are outside Pending M1. |
| `PENDING_REORDER_INVALID` | yes | no | `operational` | Keep order unchanged; reorder only Pending items in the same serialized group. |
| `IDEMPOTENCY_CONFLICT` | no | no | `operational` | Generate a new key or reuse the original payload. |
| `IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD` | no | no | `operational` | Generate a new key or reuse the original payload. |
| `IDEMPOTENCY_EXPIRED` | no | no | `operational` | Generate a new idempotency key. |
| `RETRY_OF_SURVIVORS` | no | yes | `operational` | Wait for verified stop, or pass --accept-survivors. |
| `RUN_NOT_TERMINAL` | yes | yes | `operational` | Re-run `alln run resume <runId>` once the host is running again, or read the partial record with `alln show <runId> --json`. |
| `HANDOFF_HOST_NOT_RUNNING` | yes | yes | `operational` | Open the Allnighter app (install it first if the message says it is missing) and re-run the same command — or lift the restriction for this terminal session only with `codex --sandbox danger-full-access`. |
| `HANDOFF_CLAIMED_BUT_SILENT` | yes | yes | `operational` | Restart the Allnighter app so its hand-off host recovers, then re-run the same command. Do not just open it — something already claimed the ping. |
| `HANDOFF_MAILBOX_UNWRITABLE` | yes | yes | `operational` | Make the hand-off mailbox directory named in the message writable, then re-run the same command. |
| `RUN_NOT_FOUND` | yes | no | `operational` | Run `alln history --json`. |
| `VENDOR_WAKE_NOT_CLAIMED` | yes | yes | `operational` | Confirm the run is parked (`waitingForVendor`) via `alln show <runId> --json`, then retry `alln run resume <runId>`. |
| `RUN_JOURNAL_UNAVAILABLE` | yes | yes | `operational` | Check the support dir is writable (disk space / permissions), then retry the run. |
| `JOURNAL_CORRUPT` | yes | no | `operational` | Do not retry the same run id; confirm via `alln show <id> --json` (typed error), then start a new run if the work still matters. Never inspect private journal paths by hand — a corrupt journal is never silently treated as not-found or coerced to an invented status. |
| `STREAM_JOURNAL_FAILED` | yes | yes | `operational` | Fix the local run journal/storage failure, then rerun the foreground command. |
| `RESIDENT_REQUEST_CONFLICT` | no | no | `operational` | Reuse the original payload for this idempotency key, or submit a new key for new work. |
| `RESIDENT_ACCEPT_TIMEOUT` | no | yes | `operational` | Retry the same idempotency key and payload; do not create a second direct run. |
| `SKILL_NOT_FOUND` | yes | no | `operational` | Run `alln skills --lane <lane> --json` and pick a valid skill id. |
| `TEAM_NOT_FOUND` | yes | no | `operational` | Run `alln menu --json` (or `alln menu show team:<id>`) and retry with a canonical team id — never a display name. |
| `TEAM_BUILTIN_IMMUTABLE` | yes | no | `operational` | Edit the team with `teams edit` instead; only delete an edited built-in (which restores the shipped version). |
| `TEAM_RESTORE_UNSUPPORTED` | yes | no | `operational` | Only built-in teams can be restored; for a custom team, edit or delete it instead. |
| `SKILL_BUILTIN_IMMUTABLE` | yes | no | `operational` | Built-in skills cannot be deleted. Use `skills restore` to drop an override, or `skills duplicate` for a separate copy. |
| `SKILL_RESTORE_UNSUPPORTED` | yes | no | `operational` | Only built-in skills can be restored; for a custom skill, edit or delete it instead. |
| `TEAM_ID_COLLISION` | yes | no | `operational` | Pick a different team id or delete the conflicting custom team. |
| `SKILL_ID_COLLISION` | yes | no | `operational` | Pick a different skill id or delete the conflicting custom skill. |
| `TEAM_INVALID` | yes | no | `operational` | Fix the team definition and retry `alln teams edit`. |
| `SKILL_INVALID` | yes | no | `operational` | Fix the skill definition and retry `alln skills edit`. |
| `TEAM_DEFAULT_INVALID` | yes | no | `operational` | Set another default team before deleting or changing the lane default. |
| `SKILL_IN_USE` | yes | no | `operational` | Remove the skill from team definitions before deleting. |
| `SKILL_LANE_MISMATCH` | yes | no | `operational` | Pick a skill from the same lane as the team. |
| `CATALOG_ID_INVALID` | yes | no | `operational` | Use a canonical lowercase id matching the catalog rules. |
| `JSON_SCHEMA_VIOLATION` | yes | no | `operational` | Treat as implementation bug; run export-contracts check. |
| `PERMISSION_REQUIRED` | yes | no | `operational` | Ask the user for the named permission. |
| `ATTACHMENT_HASH_MISMATCH` | yes | no | `operational` | Re-ingest or re-send the attachment; do not retry with stale bytes. |
| `ATTACHMENT_NOT_FOUND` | no | no | `operational` | Use thread_get to list resolved attachments for the turn. |
| `ATTACHMENT_TOO_MANY` | yes | no | `operational` | Remove attachments until within the count cap. |
| `ATTACHMENT_TOO_LARGE` | yes | no | `operational` | Use a smaller image or fewer attachments. |
| `ATTACHMENT_UNSUPPORTED_TYPE` | yes | no | `operational` | Send PNG/JPEG/GIF/WebP only. |
| `ATTACHMENT_DECODE_FAILED` | yes | no | `operational` | Fix or replace the corrupt image file. |
| `ATTACHMENT_BASE64_INVALID` | yes | no | `operational` | Fix the base64 payload. |
| `ATTACHMENT_STAGE_FAILED` | yes | yes | `operational` | Check workingDir permissions and disk space. |
| `ATTACHMENT_STAGE_UNIGNORED` | yes | no | `operational` | Add `.allnighter/` to gitignore or info/exclude manually. |
| `CONTEXT_ATTACHMENT_CAP_EXCEEDED` | yes | no | `operational` | Reduce message or attachment count; never silently trim current send. |
| `FILE_REFERENCE_PROJECT_ROOT_MISSING` | yes | no | `operational` | Bind the thread to a project/working directory, then retry. |
| `FILE_REFERENCE_OUTSIDE_PROJECT` | yes | no | `operational` | Pick a path inside the project root. |
| `FILE_REFERENCE_NOT_FOUND` | yes | no | `operational` | Refresh the file picker or choose an existing project file. |
| `FILE_REFERENCE_UNREADABLE` | yes | no | `operational` | Check file permissions or choose another file. |
| `FILE_REFERENCE_BINARY_UNSUPPORTED` | yes | no | `operational` | Reference text files only in v1. |
| `FILE_REFERENCE_TOO_LARGE` | yes | no | `operational` | Reference a smaller file or a line range. |
| `FILE_REFERENCE_TOO_MANY` | yes | no | `operational` | Remove file references until within the cap. |
| `FILE_REFERENCE_SENSITIVE_BLOCKED` | yes | no | `operational` | Do not attach secrets; summarize the needed config manually. |
| `FILE_REFERENCE_LINE_RANGE_INVALID` | yes | no | `operational` | Choose a valid 1-based line range inside the file. |
| `FILE_REFERENCE_CHANGED_BEFORE_INVOKE` | yes | no | `operational` | Refresh the reference and re-approve the changed file before running. |
| `FILE_REFERENCE_CATALOG_STALE` | no | yes | `operational` | Refresh the Project file picker and retry. |
| `FILE_REFERENCE_AGENT_UNSUPPORTED` | yes | no | `operational` | Choose a worker that can receive referenced file text or use a chat worker. |
| `THREAD_SEND_IDEMPOTENCY_CONFLICT` | no | no | `operational` | Use a new idempotency key or repeat the original payload. |
| `THREAD_NOT_FOUND` | yes | no | `operational` | Run `alln history --json` (or create a thread); retry with a valid thread id. |
| `TRY_FIX_PACKET_MISSING` | no | yes | `operational` | Re-run the Bug Hunt diagnosis; the fix attempt needs a typed fix packet. |
| `TRY_FIX_PACKET_UNSAFE` | yes | no | `operational` | Read the gate reason; resolve the danger flag / add an actionable hypothesis + proof, then retry. |
| `TRY_FIX_EXECUTOR_INVALID` | yes | no | `operational` | Pass --executor a single mutating team that is runnable on this bench (default build_slice). |
| `RELAY_NOT_FOUND` | yes | no | `operational` | Run `alln loop status <id> --json` with a valid loop id, or start a new loop with `alln loop start "<what you want done>"`. |
| `RELAY_STATE_DECODE_FAILED` | yes | no | `operational` | The relay folder exists but relay.json cannot be read by this binary — rebuild from the current branch (`swift build --package-path Packages/AllnighterCore` + `alln install-cli`). If the file uses retired devWorkerId/pmWorkerId keys, delete the relay folder or rewrite seat keys to devModelId/pmModelId. |
| `RELAY_INVALID_STATE` | yes | no | `operational` | Check status with `alln loop status <id>`; only resume/pm-eligible statuses accept those transitions. Founder stop uses `alln loop stop` and does not use this code. |
| `RELAY_HANDOVER_UNSAFE` | yes | no | `operational` | The PM's handover named a danger instruction (credentials, signing, destructive git, sandbox/TCC, mass deletion); the relay escalated instead of dispatching it. Answer the escalation or rewrite the round's intent. |
| `RELAY_ALREADY_ACTIVE` | yes | no | `operational` | Read it with `alln loop status <id> --json`, resume it or reassign the PM with `alln loop pm`, or wait — do not start a second loop on the same doc. |
| `RELAY_JOURNAL_UNAVAILABLE` | yes | yes | `operational` | The relay claim could not be written durably — check disk space and permissions under the support root, then retry the relay verb. |
| `RELAY_ROUND_IN_FLIGHT` | no | yes | `operational` | Wait with `alln loop status <id> --wait-for parked --timeout 7200 --json`; do not re-dispatch while running. A killed `alln loop wait` is not a failed round. Once parked, retry `alln loop step` if still needed. |
| `RELAY_STOP_FAILED` | yes | yes | `operational` | Inspect with `alln ps --json`; retry `alln loop stop <id> --json`. Do not invent resume while live trees remain. |
| `RUN_ID_IN_USE` | yes | no | `operational` | Attach with `alln run resume <id> --json`, or omit an explicit id. |
| `RELAY_NOT_AWAITING_PM` | yes | no | `operational` | Run `alln loop status <id> --json`; a loop only accepts `alln loop step` while its status is `awaitingPM` (done/escalated/stopped have nothing left to hand off to). |
| `RELAY_VERDICT_UNPARSEABLE` | yes | yes | `operational` | The PM's submission needs exactly one trailing ```json LoopVerdict block (verdict: continue|done|escalate; handover required for continue). Fix the tail and resubmit `alln loop step` — the loop is still `awaitingPM`, no re-ask machinery runs. |
| `OWNERSHIP_NOT_FOUND` | no | no | `operational` | Run `alln ps --json` and pick a current owned id, or omit and use `alln kill --all` for every identity-alive tree. |
| `OWNERSHIP_ALREADY_TERMINAL` | no | no | `operational` | No action required; the tree already carries a stamped endReason. Inspect with `alln ps --json`. |
| `OWNERSHIP_IDENTITY_MISMATCH` | yes | no | `operational` | Do not retry the same kill against this pid; the recorded identity no longer matches the live process (pid reuse). Run `alln ps --json` and `alln team reconcile` for identity-dead orphans instead. |
| `KILL_PARTIAL` | no | yes | `operational` | The run stays non-terminal with survivors named. Inspect them with `alln ps --json`, then retry `alln kill <id>` or escalate manually; the tool refuses to stamp `killed` over live work. |
| `KILL_REFUSED` | yes | no | `operational` | No recorded member could be signalled (all identity-mismatched or non-PG-killable). Run `alln ps --json` and `alln team reconcile` for identity-dead orphans; do not re-signal a recycled pid. |
| `KILL_VERIFICATION_UNAVAILABLE` | yes | no | `operational` | The run records no killable worker `runtimeOwnership` (warm workers or unrecorded legacy). The stop cannot be verified — read `alln show <run-id> --json` or stop the worker at its source; the tool will not stamp `killed` unverified. |
| `THREAD_SEND_FAILED` | no | yes | `operational` | Inspect the error detail; retry the send or fix the worker. |
| `MODEL_NOT_FOUND` | yes | no | `operational` | List ids with `alln menu --json` or `alln models --json` and retry with a valid ModelID. |
| `MODEL_BUILTIN_IMMUTABLE` | yes | no | `operational` | Duplicate the built-in model, then edit the custom copy. |
| `MODEL_ID_COLLISION` | yes | no | `operational` | Pick a different model id or delete the conflicting custom model. |
| `MODEL_INVALID` | yes | no | `operational` | Fix the model definition and retry the edit. |
| `MODEL_DRIVER_MISSING` | yes | no | `operational` | Reference a known driver id, or add the driver manifest first. |
| `INTERNAL_ERROR` | yes | no | `operational` | Capture the message and `traceId`; retry once, then report if it persists. |
| `PROJECT_NOT_FOUND` | yes | no | `operational` | If cwd is an unregistered git root, run `alln project add <path>`. Otherwise `alln project list --json` and retry with a valid id or path. |
| `NO_PROJECT_SELECTED` | yes | no | `usage` | Select or add a project, then re-run the mutating action. |
| `DUPLICATE_PROJECT_ROOT` | no | no | `operational` | Use the existing project that owns this normalized root. |
| `PROJECT_ROOT_UNAVAILABLE` | yes | yes | `operational` | Restore the folder/permissions, then `alln project show <id>` to re-observe. |
| `PROJECT_ARCHIVED` | yes | no | `operational` | Run `alln project unarchive <id>` before new runs. |
| `THREAD_UNASSIGNED` | yes | no | `operational` | Assign the thread/pending item to a project, then retry. |
| `AGENT_NOT_READY_IN_PROJECT` | yes | yes | `operational` | Run `alln project models <id> --json`; open the CLI in the project folder and complete its trust/login, then recheck. |
| `RUN_WRITE_LOCK_BUSY` | no | yes | `laneBusy` | The active mutating run on this repo root looks stuck (the wait bound elapsed); wait for it to finish or stop it, then retry. |
| `EXECUTION_LANE_BUSY` | no | yes | `laneBusy` | Do not busy-loop or invent a private retry cadence. The harness owns the wait: poll relay/pilot status for laneBlocked (position, holder identity/kind/id, heldSinceSeconds) until the ticket clears, or let the harness grant the lane. Never start a second concurrent build-class turn on the same root. |
| `WRITE_SCOPE_VIOLATION` | yes | no | `operational` | Inspect roundLog.scopeViolation (declared writeScope + outOfScopePaths). The harness rejected the turn's work fail-closed; endReason stays reported. Do not auto-revert — the PM decides whether to keep, amend, or reverse the commits. Next turn: stay inside the declared prefixes or re-declare a broader writeScope. |
| `STANDING_INVARIANT_FAILED` | yes | no | `operational` | Inspect roundLog.standingFailed and proofResults entries with standing:true. For contractDrift: rebuild the turn tree, run `alln dev export-contracts` (regenerate docs/generated/alln/*), commit the artifacts, and re-run. The harness never auto-regenerates or auto-commits (Process_Ownership.md PO-F4). |
| `NO_PROJECT_ROOT` | yes | yes | `operational` | Restore the project folder or pick an available project root, then retry. |
| `AGENT_NOT_READY` | yes | yes | `operational` | Pick a ready worker or run setup health, then retry. |
| `EXECUTION_TEAM_MIXED_SOURCES` | yes | no | `operational` | Pick one execution source, run as non-mutating review/propose, or split into judgment then execution. |
| `UTILIZATION_SOURCE_NOT_FOUND` | yes | no | `usage` | Run `alln models --json`; use a known driver id in appliesTo. |
| `UTILIZATION_SOURCE_UNCONFIGURED` | yes | no | `usage` | Add the source to Boost window appliesTo, then retry. |
| `UTILIZATION_AUTH_REQUIRED` | yes | no | `operational` | Sign in to the named CLI, then retry the seed. |
| `UTILIZATION_BILLING_PROMPT` | yes | no | `operational` | Resolve billing on the provider, then retry. |

## NDJSON events

| Event | Required data |
| --- | --- |
| `teamRunStarted` | `status`, `origin`, `teamPresetId` |
| `workerStarted` | `agentId`, `modelId`, `skillId` |
| `workerAnswered` | `agentId`, `durationMs` |
| `workerFailed` | `agentId`, `error` |
| `planStarted` | `agentId`, `stageId` |
| `planWritten` | `agentId`, `stageId`, `durationMs` |
| `workerActivity` | `agentId`, `activityKind` |
| `stageActivity` | `stageId`, `activityKind` |
| `teamRunSnapshot` | `teamRun` |
| `attentionRequired` | `reason`, `activityMode`, `message` |
| `teamRunCompleted` | `status`, `planStageId`, `durationMs` |
| `teamRunFailed` | `status`, `error` |
| `error` | `error` |
| `pendingAdded` | `pendingItemId`, `status` |
| `pendingSubmitted` | `pendingItemId`, `status` |
| `pendingEdited` | `pendingItemId`, `status` |
| `pendingReordered` | `pendingItemId` |
| `pendingCancelled` | `pendingItemId`, `status` |

## Run stream mode (`--stream`)

`--stream` emits **NDJSON**: one JSON object per line on stdout. Human progress
never mixes into stdout. Events are ordered by durable `seq`. `run --stream` and
`show --stream` share **one** frame schema.

Frame order on `show --stream`:
1. **Immediate snapshot first** — current run snapshot (`TeamRunJSON`, including
   observation) before any replay, for every lifecycle state including queued.
2. **Bounded replay** of recent durable activity (marked `replayed: true`).
3. **Live follow** of new run events (when the run is still live).
4. Exactly one terminal frame among `error`, `teamRunCompleted`, `teamRunFailed` carrying the terminal
   `TeamRunJSON` and `pmTurn`, then exit.

A stream ends at terminal **or** at an **attention-required** boundary (sourced
blocker, vendor wait, or observer budget on a terminalOnly driver). It never
blocks forever. On `terminalOnly`, the observer budget is the run's wall-clock
fact when present, else 7200s (replacing the deleted waiter timeout); on
`incremental`, follow until terminal or a sourced attention cause — no
wall-clock budget on healthy long work. Recovery nextAction is never `showRun`
(self-referential poll loop). Observer is disposable: killing `show --stream`
leaves the run untouched.

**Terminal exit class propagates unconditionally** — no `--exit-status` opt-in.
Agents chain with `;`, not `&&`.

On `run`, `--stream` is mutually exclusive with `--json`, `--dry-run`, and `--no-wait`
(registry constraints; invalid combinations exit 2 before any provider start).
On `show`, `--stream` is mutually exclusive with `--full`.
## Model controls (vendor CLI boundary)

`alln run` drives **subscription CLIs** the user already pays for. It does **not**
expose model-API knobs such as `--temperature` or `--max-tokens` — Alln cannot
enforce those through every vendor CLI. Use `--effort` (`low|med|high`), `--model`,
and the driver's own supported flags (via manifests) for controls that actually reach
the selected CLI.
## Next-action kinds

- `showArtifact` — Open the polished HTML team artifact for a terminal run.
- `showRun` — Show the full run.
- `export` — Export the result bundle.
- `showHistory` — List recent runs.
- `inspectBlocker` — Inspect a sourced blocker, vendor wait, or attention-required stream exit; not a stream reattach.
- `submitPending` — Submit a Draft item to Pending.
- `runPending` — Run a Pending item now.
- `showPending` — Show one Pending item.
- `cancelPending` — Cancel a Pending item.

## Example recipes

- `docs_all` — Generate the full reference: `alln docs`
- `doctor_json` — Structured diagnostics: `alln doctor --json`
- `doctor_explain` — Explain an error code: `alln doctor explain SOURCE_AUTH_EXPIRED --json`
- `bootstrap_json` — Agent activation snippet for Claude Code: `alln bootstrap --host claude --json`
- `install_cli_json` — Install the running binary onto PATH: `alln install-cli --json`
- `version_json` — Print binary and contract identity: `alln version --json`
- `update_check` — Soft-announce a newer release: `alln update --check`
- `models_json` — List model catalog and Bench state: `alln models --json`
- `drivers_json` — List CLIs and park state: `alln drivers --json`
- `drivers_park` — Park a CLI you are not using: `alln drivers park opencode`
- `drivers_unpark` — Put a parked CLI back on the bench: `alln drivers unpark opencode`
- `teams_code_json` — List Code teams: `alln teams --lane code --json`
- `teams_definition_json` — Full team definition for edit or novel new: `alln teams definition code_bug_hunt --json`
- `teams_duplicate_json` — Deterministic Bug Hunt variant: `alln teams duplicate code_bug_hunt --id custom_code_my_bug_hunt --name "My Bug Hunt" --json`
- `teams_new_json` — Create novel team from manifest: `alln teams new custom_code_novel --file ./TeamPreset.json --json`
- `skills_code_json` — List Code skills: `alln skills --lane code --json`
- `skills_show_json` — Show a Code skill: `alln skills show bug_reproducer --json`
- `skills_restore_json` — Restore a built-in skill override: `alln skills restore bug_reproducer --json`
- `skills_gc_json` — Purge lab and orphan custom skills: `alln skills gc --json`
- `run_foreground_json` — Run in foreground: `alln run --json --lane code --team code_bug_hunt --effort low "tiny foreground sanity"`
- `try_fix_bug` — Auto Fix: Bug Hunt then one bounded fix: `alln run "The history view loses finished runs after restart." --project <id> --team code_bug_hunt --try-fix --executor build_slice --json`
- `show_latest_json` — Show one run by id: `alln show <run-id> --json`
- `spec_full` — Retrieve the full result packet: `alln spec latest --detail full --json`
- `export_md` — Export the latest result: `alln export latest --format md`
- `export_contracts_check` — Verify no contract drift: `alln dev export-contracts --check`
- `thread_send_json` — Send message with image and file reference to thread: `alln thread send latest "describe this" --image ./shot.png --ref Sources/App.swift:10-80 --json`
- `thread_rename_json` — Rename a work thread: `alln thread rename latest "Paste-image bug" --json`
- `serve_health_json` — Coordinator health: `alln serve --health --json`
- `pending_add_json` — Create a Draft Pending item: `alln pending add --model model_opus --when ready --json "Review this patch when Claude is available."`
- `pending_list_json` — List Pending items: `alln pending list --json`
- `boost_window_show_json` — Show Boost window settings: `alln boost-window show --json`
- `boost_window_set_json` — Enable Boost window for Claude and Codex: `alln boost-window set --enabled true --window-start 08:00 --applies-to claude_code,codex --json`

## Run dry-run write policy

`alln run --dry-run --json` returns `writePolicy` (`readOnly` | `mutating`) and an `effects` block:
`workerStart`, `quotaSpend`, `repoWrite`, `destructive`, `humanInteraction`.

- `effects.repoWrite` is **permission** after selectors resolve — the invocation *may* write and therefore uses write safety. It is not a prediction from prompt prose, and it is not an observed git delta.
- Terminal `TeamRunJSON.repoDelta` reports whether a mutating run *did* write.
- Research Teams are observational in the registered repository; they do not use copied files or vendor permission flags. Default Team and explicit `--model` may be mutating.
- Dry-run itself starts no worker and spends no quota; `effects.workerStart` / `effects.quotaSpend` describe the spend twin `nextAction` would run.

## Observed run timing

Terminal `TeamRunJSON` projects observed clocks only — null means the driver did not report that observation. No forecasts or targets.

Per-worker on `answers[]`:

- `queueMs` — run request accepted → this seat's CLI spawn (lock / lane / resolution / staging).
- `ttftMs` — CLI spawn → first visible streamed delta (null off the streaming path).
- `durationMs` — CLI spawn → process exit (worker work-time).

Terminal `outcome.timing.wallMs` — run `createdAt` → latest worker `finishedAt`.

Clock boundaries are named above. A single-worker `outcome.headline` may list those observed phases; do not invent an orchestration tax by subtracting duration from wall, and do not assign blame across parallel seats.

