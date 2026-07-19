# alln — Agent-Facing CLI Reference

Generated from the contract registry (contractVersion 1.0.0, schemaVersion 1).
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

### `alln bootstrap`

Print a paste-ready agent-activation snippet for a host's context file (never edits files).

Flags:
- `--host <host>` — claude | cursor | codex | generic (default generic).
- `--json` — Structured { host, pasteTarget, snippet, binaryPath, onPath }.

Output schema: `bootstrapJSON`.

Examples: `bootstrap_json`.

### `alln version`

Print the running binary version and contract hash.

Flags:
- `--json` — Structured VersionJSON.

Output schema: `versionJSON`.

Examples: `version_json`.

### `alln install-cli`

Symlink the running `alln` binary onto PATH (running the command is consent).

Flags:
- `--path <path>` — Install directory override (default /usr/local/bin if writable, else ~/.local/bin).
- `--print` — Print install instructions only (legacy print-only behavior).
- `--json` — Structured { action, path, target, onPath }.

Output schema: `installCLIJSON`.

Examples: `install_cli_json`.

### `alln models`

List model catalog and Bench state.

Flags:
- `--json` — Structured ModelListJSON.
- `--driver <driverId>` — Filter to one source.
- `--bench` — Show only enabled Bench models.

Output schema: `modelListJSON`.

Examples: `models_json`.

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

Add a custom model for a source.

Flags:
- `--driver <driverId>` — Source driver id.
- `--name <string>` — Display name.
- `--model-label <string>` — Label passed to the CLI.
- `--role <modelRole>` — answerer|planWriter|both (default answerer).
- `--disabled` — Create off-Bench.
- `--json` — Return refreshed ModelListJSON.

Output schema: `modelListJSON`.

### `alln models update`

Update a custom model definition.

Arguments:
- `model-id` (required) — Custom model id.

Flags:
- `--name <string>` — New display name.
- `--model-label <string>` — New CLI model label.
- `--role <modelRole>` — New role.
- `--json` — Return refreshed ModelListJSON.

Output schema: `modelListJSON`.

### `alln models delete`

Delete a custom model definition.

Arguments:
- `model-id` (required) — Custom model id.

Flags:
- `--json` — Return refreshed ModelListJSON.

Output schema: `modelListJSON`.

### `alln team show`

Show the default team for each lane.

Flags:
- `--lane <lane>` — Limit to one lane.
- `--json` — Structured team snapshot.

Examples: `team_show_json`.

### `alln teams`

List the lane-scoped team catalog.

Flags:
- `--lane <lane>` — Filter to one lane.
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
- `--worker <string>` — Requested worker/model id.
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
- `--lane <lane>` — Filter to one lane.
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

Show one team definition including worker rows.

Arguments:
- `team-id` (required) — Team id.

Flags:
- `--json` — Structured team detail.

Examples: `teams_show_json`.

### `alln teams definition`

Full TeamPreset JSON round-trippable through teams edit/save.

Arguments:
- `team-id` (required) — Team id.

Flags:
- `--json` — Structured team definition.

Examples: `teams_definition_json`.

### `alln teams duplicate`

Duplicate a built-in team into a custom team.

Arguments:
- `team-id` (required) — Source team id.

Flags:
- `--name <string>` — Display name for the copy.
- `--json` — Structured team detail.

Examples: `teams_duplicate_json`.

### `alln teams edit`

Edit a custom team definition (full replacement).

Arguments:
- `team-id` (required) — Team id.

Flags:
- `--file <path>` — TeamPreset JSON file.
- `--json` — Structured team detail.

Examples: `teams_edit_json`.

### `alln teams set-default`

Set the default team for a lane.

Arguments:
- `team-id` (required) — Team id.

Flags:
- `--json` — Structured team detail.

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
- `--lane <lane>` — build | design | copy.
- `--name <string>` — Display name.
- `--purpose <purpose>` — answer | review | planWriter.
- `--template-file <path>` — Skill template text file.
- `--json` — Structured skill detail.

Examples: `skills_new_json`.

### `alln skills edit`

Edit a custom skill definition.

Arguments:
- `skill-id` (required) — Skill id.

Flags:
- `--name <string>` — New display name.
- `--template-file <path>` — Replacement template file.
- `--json` — Structured skill detail.

Examples: `skills_edit_json`.

### `alln skills delete`

Delete a custom skill.

Arguments:
- `skill-id` (required) — Skill id.

Flags:
- `--json` — Deletion acknowledgement JSON.

Examples: `skills_delete_json`.

### `alln team hello`

Agent bootstrap: readiness + ready teams + next action (quota-free). With --for, resolve intent to a recommended team/primitive + runnable command.

Flags:
- `--for <string>` — Intent phrase to route (e.g. "harden this spec"). Omitting keeps the static readiness report.
- `--json` — Structured hello / intent-route JSON (default).

### `alln team preflight`

Validate lane/team/effort against the ready bench without running.

Flags:
- `--lane <lane>` — build | design | copy.
- `--team <id>` — Team id.
- `--effort <effort>` — low | med | high.
- `--type <type>` — Copy-only routing sugar.

### `alln team start`

Start a resumable/asynchronous team run.

Arguments:
- `prompt` (optional) — The prompt (or use --file).

Flags:
- `--lane <lane>` — build | design | copy.
- `--team <id>` — Team id.
- `--effort <effort>` — low | med | high.
- `--type <type>` — Copy-only routing sugar.
- `--json` — Structured TeamStartResponse.
- `--idempotency-key <id>` — Client idempotency key.
- `--conversation-id <id>` — Origin conversation id.
- `--message-id <id>` — Origin message id.
- `--thread-id <id>` — Owning work thread id.

Output schema: `teamStartResponse`.

Examples: `team_start_json`.

### `alln team status`

Poll live state for an async team run. With --wait-for, blocks in-process until the target live state (or any terminal when waiting for a non-matching state) or --timeout, then returns nextAction + waitHintSeconds (no external poll spin).

Arguments:
- `run-id` (required) — The run id from team start.

Flags:
- `--json` — Structured TeamStatusResponse.
- `--wait-for <state>` — Block until this RunLifecycle (queued|running|done|failed|timedOut|cancelled) or the alias `terminal`.
- `--timeout <seconds>` — Max seconds to wait when --wait-for is set (required with --wait-for). Exit 3 (timeout) if the target is not reached.

Output schema: `teamStatusResponse`.

### `alln team result`

Fetch TeamRunJSON when an async run is terminal.

Arguments:
- `run-id` (required) — The run id from team start.

Flags:
- `--json` — TeamRunJSON or not-ready envelope.

Output schema: `teamRunJSON`.

### `alln team cancel`

Cancel an active async team run.

Arguments:
- `run-id` (required) — The run id from team start.

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

List the process trees Allnighter owns (runs, relays, pilots, proofs) from durable state. Read-only: reports what reconcile WOULD reap; kills nothing, writes nothing. Defaults to the caller's project scope; --all-projects is the explicit machine-wide fleet view.

Flags:
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
- `--json` — Structured OwnershipGarbageCollectionJSON summary with every keep reason.

Output schema: `ownershipGarbageCollectionJSON`.

### `alln run`

Unified run: message + optional team + worker in a project repo root. `--lane` tags the run for context and filtering; `--team` routes. TeamRunJSON includes a mechanical `outcome` block (worker terminal states + repo delta) — never a correctness verdict.

Arguments:
- `message` (required) — The user's prompt.

Flags:
- `--project <id>` — Project id, name, or repo path (required).
- `--team <id>` — Team preset id; omit for Default Team.
- `--worker <id>` — Override worker model id.
- `--effort <effort>` — low | med | high.
- `--lane <lane>` — Lane tags the run for context and filtering; `--team` routes.
- `--type <type>` — Copy routing sugar.
- `--context <string>` — Bounded context snippet.
- `--idle-timeout <integer>` — Override the worker idle-stall budget in seconds (default = driver manifest timeout, typically 300). Resets on any streaming progress (tool-call/reasoning/stderr/child activity), not only answer tokens (PO-F5).
- `--commit-message <string>` — Exact commit message for the worker (FR12 instruct + verify; Allnighter does no git).
- `--no-commit` — Instruct the worker to leave work uncommitted for PM review (mutually exclusive with --commit-message).
- `--proof <string>` — Run a bounded proof command after the worker settles; surface pass/fail (never blocks git).
- `--try-fix` — Bug Hunt diagnosis → danger-not-doubt gate → one bounded fix attempt.
- `--executor <id>` — Mutating executor team id (default build_slice).
- `--json` — Emit TeamRunJSON.
- `--stream` — Emit NDJSON events.

Mutually exclusive: `--json`, `--stream`.

Mutually exclusive: `--no-commit`, `--commit-message`.

Output schema: `teamRunJSON`.

### `alln pair relay`

Run the PM Relay unattended: a PM seat reviews the repo and a dev seat builds, round after round, until done/escalate/a ceiling.

Flags:
- `--doc <path>` — Repo-relative spec doc path (required) — the PM re-reads it fresh each round.
- `--project <id>` — Project id, name, or repo path (required).
- `--pm-worker <id>` — PM seat model id (required).
- `--dev-worker <id>` — Dev seat model id (required).
- `--until <time>` — Hard stop HH:MM (local).
- `--max-rounds <integer>` — Round ceiling (default 20).
- `--idle-timeout <integer>` — Override the dev seat's per-turn worker idle-stall budget in seconds (default = driver manifest timeout). Reuses PO-F5's `alln run --idle-timeout` plumbing (PO-F7).
- `--json` — Emit NDJSON RelayProgressJSON events, then a final RelayJSON envelope.

Output schema: `relayJSON`.

### `alln pair relay-status`

Read a PM Relay's durable state — rounds, verdicts, gate decisions.

Flags:
- `--relay <id>` — Relay id (required).
- `--json` — Emit RelayJSON.

Output schema: `relayJSON`.

### `alln pair relay-resume`

Resume an escalated PM Relay with the founder's answer, then continue the loop.

Flags:
- `--relay <id>` — Relay id (required).
- `--answer <string>` — The founder's answer to the escalation (required).
- `--until <time>` — Hard stop HH:MM (local) for the resumed stretch.
- `--max-rounds <integer>` — Round ceiling for the resumed stretch (default 20).
- `--json` — Emit NDJSON RelayProgressJSON events, then a final RelayJSON envelope.

Output schema: `relayJSON`.

### `alln pair relay adopt`

Night-shift handover: converts a parked Pilot relay (awaitingPM or escalated) to a spawned PM relay and continues the loop from the durable round log.

Flags:
- `--relay <id>` — Relay id (required).
- `--pm-worker <id>` — The spawned PM seat's model id (required).
- `--max-rounds <integer>` — Round ceiling for the adopted stretch — counts TOTAL rounds including the piloted ones already on the log (default 20).
- `--until <time>` — Hard stop HH:MM (local) for the adopted stretch.
- `--json` — Emit NDJSON RelayProgressJSON events, then a final RelayJSON envelope.

Output schema: `relayJSON`.

### `alln pair pilot start`

Start a Pilot relay: this session is the PM, Allnighter runs the crew (dev seat + rails). Parks awaitingPM.

Flags:
- `--doc <path>` — Repo-relative spec doc path (required) — the piloting session re-reads it fresh each round.
- `--project <id>` — Project id, name, or repo path (required).
- `--dev-worker <id|alias>` — Dev seat model id or alias (optional when a seat was remembered for this project).
- `--max-rounds <integer>` — Round ceiling, set once here — Pilot has no long-lived process to re-supply it per handoff (default 20).
- `--idle-timeout <integer>` — Override the dev seat's per-turn worker idle-stall budget in seconds (default = driver manifest timeout), set once here and re-read from durable state at every later `pilot handoff`. Reuses PO-F5's `alln run --idle-timeout` plumbing (PO-F7).
- `--json` — Emit PilotStartJSON (relay + nextCommand + scaffoldPath).

Output schema: `relayJSON`.

### `alln pair pilot handoff`

Submit this round's review (RelayVerdict tail or --verdict + handover file); blocks through the dev turn by default and prints the dev's report verbatim.

Flags:
- `--relay <id>` — Relay id (required).
- `--file <path>` — Read the full submission markdown from a file (verdict tail included; omit to read stdin).
- `--verdict <continue|done|escalate>` — Required with --handover-file/--handover-stdin; synthesizes the RelayVerdict tail internally.
- `--handover-file <path>` — Raw order markdown for the dev seat (mutually exclusive with --file).
- `--handover-stdin` — Read the handover markdown from stdin (mutually exclusive with --file).
- `--note <string>` — Optional closing note for done/escalate verdicts.
- `--no-wait` — Return immediately after dispatch instead of blocking through the dev turn.
- `--json` — Emit NDJSON RelayProgressJSON events, then a final PilotHandoffJSON envelope (single-line).

Mutually exclusive: `--file`, `--handover-file`.

Mutually exclusive: `--file`, `--handover-stdin`.

Mutually exclusive: `--handover-file`, `--handover-stdin`.

Output schema: `relayJSON`.

### `alln pair pilot status`

Read a Pilot relay's durable state — rounds, verdicts, gate decisions, dirty-tree snapshots.

Flags:
- `--relay <id>` — Relay id (required).
- `--json` — Emit PilotStatusJSON (relay + recovery nextActions when in flight).

Output schema: `relayJSON`.

### `alln pair pilot watch`

Poll a Pilot relay until its in-flight round settles back to awaitingPM (or a terminal status).

Flags:
- `--relay <id>` — Relay id (required).
- `--json` — Emit PilotWatchJSON (single-line; relay + devReport + note when nothing was in flight).

Output schema: `relayJSON`.

### `alln pair pilot adopt`

Reverse flip: hands a parked spawned relay's PM seat to a piloting session (pmMode → external, status → awaitingPM). No dispatch.

Flags:
- `--relay <id>` — Relay id (required).
- `--json` — Emit RelayJSON.

Output schema: `relayJSON`.

### `alln pair pilot scaffold-handover`

Write or re-emit a suggested PM handover markdown template for a relay round.

Flags:
- `--relay <id>` — Relay id (required).
- `--round <integer>` — Round number for the filename (default 1).
- `--json` — Emit scaffold path as JSON.

Output schema: `relayJSON`.

### `alln panel start`

Start a Panel session: session-led blind jury on any target. Parks awaitingPM with a resolved roster.

Flags:
- `--doc <path>` — Target path to judge (required) — re-read fresh each round; not hard-coded to docs/phases/.
- `--project <id>` — Project id, name, or repo path (required).
- `--team <alias>` — Team alias (fuzzy); unique match is echoed. Zero-config uses remembered-else-lane-default.
- `--seat <alias:lens>` — Power mode: override/extend a seat as <alias>:<lens>. Alias resolves via PilotSeatResolver at start (real model id stored). Repeatable.
- `--max-rounds <integer>` — Ceiling on new rounds (default 10). Seat reruns are exempt.
- `--json` — Emit PanelStartJSON.

Output schema: `panelJSON`.

### `alln panel round`

Dispatch one panel round (or a --seats subset rerun). Blocks; prints per-seat findings verbatim + statuses; NDJSON progress while running.

Flags:
- `--panel <id>` — Panel id (required).
- `--brief <path>` — Focus brief markdown path, or `-` for stdin. Built-in on round 1 when omitted; required on round 2+.
- `--seats <list>` — Comma-separated worker ids to rerun on the SAME round (new attempt; replaces those seats only).
- `--no-wait` — Dispatch in the background; poll with panel status/watch.
- `--json` — Emit NDJSON progress events, then a final PanelRoundJSON envelope (single-line).

Output schema: `panelRoundJSON`.

### `alln panel status`

Read a Panel session's durable state — roster, rounds, target hash, recovery nextActions when in flight.

Flags:
- `--panel <id>` — Panel id (required).
- `--json` — Emit PanelJSON (+ recovery when in flight).

Output schema: `panelJSON`.

### `alln panel watch`

Poll a Panel until its in-flight round settles back to awaitingPM (or a terminal status). Dead-owner → run panel watch (DX5).

Flags:
- `--panel <id>` — Panel id (required).
- `--json` — Emit PanelJSON + optional note.

Output schema: `panelJSON`.

### `alln panel scaffold-brief`

Write or re-emit a suggested focus-brief template (rejection-carry + stance lines) for a panel round.

Flags:
- `--panel <id>` — Panel id (required).
- `--round <integer>` — Round number for the template (default 1).
- `--json` — Emit JSON with the template text.

Output schema: `panelJSON`.

### `alln panel done`

Declare a Panel session done (session judgment only — never auto-converges). Optional survivors note.

Flags:
- `--panel <id>` — Panel id (required).
- `--note <string>` — Optional done note (survivors / MEMORY fodder).
- `--json` — Emit PanelJSON.

Output schema: `panelJSON`.

### `alln team`

Run a lane team on a prompt, foreground.

Arguments:
- `prompt` (optional) — The prompt (or use --file).

Flags:
- `--file <path>` — Read the prompt from a file.
- `--lane <lane>` — code | design | copy | signal.
- `--team <id>` — Team id (the public team selector).
- `--type <type>` — Copy-only routing sugar.
- `--effort <effort>` — low | med | high.
- `--json` — Emit one TeamRunJSON object.
- `--stream` — Emit NDJSON events.

Mutually exclusive: `--json`, `--stream`.

Output schema: `teamRunJSON`.

Examples: `team_basic`, `team_json`, `team_stream`.

### `alln show`

Show one run.

Arguments:
- `run-id|latest` (required) — A run id or `latest`.

Flags:
- `--json` — Emit the run as TeamRunJSON.
- `--full` — Include resolved worker prompt snapshots (audit).

Output schema: `teamRunJSON`.

Examples: `show_latest_json`.

### `alln floor show`

Show the inspectable Floor for one team run (worker lanes, artifacts, typed return, timeline, Execute requirements).

Arguments:
- `run-id|latest` (optional) — A run id or `latest` (default latest).

Flags:
- `--json` — Emit the FloorRun projection.

Output schema: `floorRun`.

### `alln spec`

Retrieve a run's spec/result packet (summary|full|artifactRefsOnly).

Arguments:
- `run-id|latest` (optional) — A run id or `latest` (default latest).

Flags:
- `--detail <detail>` (default: summary) — summary | full | artifactRefsOnly.
- `--json` — Structured SpecRetrieval result.

Output schema: `specResult`.

Examples: `spec_full`.

### `alln export`

Export a result bundle.

Arguments:
- `run-id|latest` (required) — A run id or `latest`.

Flags:
- `--format <format>` (default: md) — Export format (md).

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

Resident Mac coordinator (foreground skeleton).

Flags:
- `--health` — Read-only coordinator health; does not start serve.
- `--json` — Structured CoordinatorHealth output.

Output schema: `coordinatorHealth`.

Examples: `serve_health_json`.

### `alln pending add`

Create a Draft Pending item.

Arguments:
- `prompt` (optional) — Work prompt (or use --file).

Flags:
- `--file <path>` — Read prompt from a file.
- `--worker <id>` — Target worker model id.
- `--team <id>` — Team preset id.
- `--fallback <id>` — Fallback worker id.
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
- `--worker <id>` — Target worker model id.
- `--team <id>` — Team preset id.
- `--fallback <id>` — Fallback worker id.
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

### `alln project workers`

Show cached per-project worker readiness (read-only; never probes).

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectWorkersJSON object.

Output schema: `projectWorkersJSON`.

### `alln project recheck-workers`

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

Set which tier Auto draws from (flagship|balanced|fast).

Arguments:
- `tier` (required) — flagship | balanced | fast.

Flags:
- `--json` — Emit a DefaultSettingsJSON object.

Output schema: `defaultSettingsJSON`.

### `alln defaults assign`

Add a model to a tier (or move it within that tier). Membership is many-to-many — assigning to one tier never removes it from another.

Arguments:
- `model` (required) — Model id (see `alln models --json`).

Flags:
- `--tier <tier>` — flagship | balanced | fast (required).
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

Search the installed help for a product question; returns ranked topics, a suggested answer, and a next-tool plan.

Arguments:
- `query` (required) — Natural-language question or keywords.

Flags:
- `--limit <int>` (default: 5) — Max results.
- `--json` — Emit a HelpSearchJSON object.

Output schema: `helpSearchJSON`.

### `alln help get`

Retrieve one help topic by id, alln:// ref, --tool, or --error. Unknown selectors return close matches + the sitemap.

Arguments:
- `topic` (optional) — Topic id or alln:// ref (omit when using --ref/--tool/--error).

Flags:
- `--ref <string>` — An alln:// ref (help/tool/schema/error).
- `--tool <string>` — Find the topic that documents this tool/action id.
- `--error <string>` — Find the topic for this error code.
- `--format <format>` (default: json) — json | md.
- `--json` — Emit a HelpGetJSON object.

Mutually exclusive: `--tool`, `--error`.

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
| `3` | `timeout` | A bounded wait expired before the target condition (team status --wait-for, team-run time budget). |
| `4` | `laneBusy` | Per-root execution/write lane stayed busy past the wait bound (EXECUTION_LANE_BUSY / RUN_WRITE_LOCK_BUSY). |

## Error codes

| Code | Manual | Retryable | Exit class | Agent action |
| --- | --- | --- | --- | --- |
| `CLI_USAGE_ERROR` | yes | no | `usage` | Re-run `alln docs <command>` and fix arguments. |
| `INSTALL_CLI_TARGET_UNWRITABLE` | yes | yes | `operational` | Retry with `alln install-cli --path ~/.local/bin` or choose a writable directory. |
| `CONTRACT_DRIFT` | yes | no | `operational` | Run `alln dev export-contracts`, then rebuild. |
| `CONTRACT_ARTIFACTS_NOT_FOUND` | yes | no | `operational` | Run `alln dev export-contracts` from inside the repo (repo root or a subdirectory). |
| `DEFAULTS_TIER_INVALID` | yes | no | `usage` | Use one of flagship | balanced | fast. |
| `DEFAULTS_MODEL_UNKNOWN` | yes | no | `operational` | Run `alln models --json` and pass a known model id. |
| `STALL_EPISODE_NOT_FOUND` | no | no | `operational` | Run `alln stalled list --all --json` and use a current episode id. |
| `DOCTOR_CHECK_FAILED` | no | yes | `operational` | Run `alln doctor --json`. |
| `SOURCE_NOT_FOUND` | yes | no | `operational` | Run `alln doctor --json`; add/configure the missing source. |
| `SOURCE_AUTH_EXPIRED` | yes | no | `operational` | Re-authenticate the named source. |
| `SOURCE_KEYCHAIN_UNAVAILABLE` | yes | yes | `operational` | Open the provider app once, run its login command in Terminal, then `alln doctor --full --agent <source>`. |
| `MODEL_UNAVAILABLE` | no | yes | `operational` | Run `alln models --json`; pick an on-Bench ready model or enable one. |
| `WORKER_NOT_AVAILABLE` | yes | yes | `operational` | Run `alln models enable <id>`, or pick a ready worker; see `alln models` / `alln doctor`. |
| `DEFAULT_TEAM_INVALID` | yes | no | `operational` | Run `alln team show --json`; fix unavailable workers. |
| `WORKER_FAILED` | no | yes | `operational` | Inspect `workerId` and source error; failed worker remains visible. |
| `PLAN_WRITER_FAILED` | no | yes | `operational` | Retry with a ready plan writer or export worker answers. |
| `TEAM_RUN_TIMEOUT` | no | yes | `timeout` | Retry with lower effort or fewer workers. |
| `STATUS_WAIT_TIMEOUT` | no | yes | `timeout` | Re-run `alln team status <id> --wait-for <state> --timeout <s> --json` with a longer timeout, or poll with waitHintSeconds; do not busy-loop. |
| `TEAM_RUN_FAILED` | no | yes | `operational` | Inspect failed workers and stages; retry or adjust the team. |
| `NESTED_TEAM_BLOCKED` | yes | no | `operational` | Do not recursively spawn teams without explicit depth budget. |
| `TEAM_GOVERNOR_BUSY` | no | yes | `operational` | Wait or retry after current team run completes. |
| `TEAM_GOVERNOR_UNAVAILABLE` | yes | yes | `operational` | Run `alln doctor --json`; ensure Allnighter's support directory is writable, or set a writable support root for eval runs. |
| `PENDING_MUTATION_DEFERRED` | yes | no | `operational` | Keep item Draft/Pending; mutating pending runs are outside Pending M1. |
| `PENDING_REORDER_INVALID` | yes | no | `operational` | Keep order unchanged; reorder only Pending items in the same serialized group. |
| `IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD` | no | no | `operational` | Generate a new key or reuse the original payload. |
| `RESULT_NOT_READY` | no | yes | `operational` | Poll team status using nextPollAfterMs, then call team result again. |
| `RUN_NOT_FOUND` | yes | no | `operational` | Run `alln history --json`. |
| `RUN_JOURNAL_UNAVAILABLE` | yes | yes | `operational` | Check the support dir is writable (disk space / permissions), then retry the run. |
| `JOURNAL_CORRUPT` | yes | no | `operational` | Do not retry the same run id; inspect run.json under the reported support dir by hand. A corrupt journal is never silently treated as not-found or coerced to an invented status. |
| `COORDINATOR_UNAVAILABLE` | no | yes | `operational` | Use foreground CLI or start resident mode when available. |
| `SKILL_NOT_FOUND` | yes | no | `operational` | Run `alln skills --lane <lane> --json` and pick a valid skill id. |
| `TEAM_NOT_FOUND` | yes | no | `operational` | Run `alln teams --lane <lane> --json` and pick a valid team id. |
| `TEAM_BUILTIN_IMMUTABLE` | yes | no | `operational` | Edit the team with `teams edit` instead; only delete an edited built-in (which restores the shipped version). |
| `TEAM_RESTORE_UNSUPPORTED` | yes | no | `operational` | Only built-in teams can be restored; for a custom team, edit or delete it instead. |
| `SKILL_BUILTIN_IMMUTABLE` | yes | no | `operational` | Duplicate the built-in skill, then edit the custom copy. |
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
| `FILE_REFERENCE_WORKER_UNSUPPORTED` | yes | no | `operational` | Choose a worker that can receive referenced file text or use a chat worker. |
| `THREAD_SEND_IDEMPOTENCY_CONFLICT` | no | no | `operational` | Use a new idempotency key or repeat the original payload. |
| `THREAD_NOT_FOUND` | yes | no | `operational` | Run `alln history --json` (or create a thread); retry with a valid thread id. |
| `TRY_FIX_PACKET_MISSING` | no | yes | `operational` | Re-run the Bug Hunt diagnosis; the fix attempt needs a typed fix packet. |
| `TRY_FIX_PACKET_UNSAFE` | yes | no | `operational` | Read the gate reason; resolve the danger flag / add an actionable hypothesis + proof, then retry. |
| `TRY_FIX_EXECUTOR_INVALID` | yes | no | `operational` | Pass --executor a single mutating team that is runnable on this bench (default build_slice). |
| `RELAY_NOT_FOUND` | yes | no | `operational` | Run `alln pair relay-status --relay <id> --json` with a valid relay id, or start a new relay with `alln pair relay`. |
| `RELAY_INVALID_STATE` | yes | no | `operational` | Only an `escalated` relay can be resumed; check status first with `pair relay-status`. |
| `RELAY_HANDOVER_UNSAFE` | yes | no | `operational` | The PM's handover named a danger instruction (credentials, signing, destructive git, sandbox/TCC, mass deletion); the relay escalated instead of dispatching it. Answer the escalation or rewrite the round's intent. |
| `RELAY_ROUND_IN_FLIGHT` | no | yes | `operational` | Wait for the in-flight round to settle, then run `alln pair pilot status --relay <id> --json` and retry `pilot handoff` once status is `awaitingPM`. |
| `RELAY_NOT_AWAITING_PM` | yes | no | `operational` | Run `alln pair pilot status --relay <id> --json`; a relay only accepts `pilot handoff` while its status is `awaitingPM` (done/escalated/stopped have nothing left to hand off to). |
| `RELAY_VERDICT_UNPARSEABLE` | yes | yes | `operational` | The piloting session's submission needs exactly one trailing ```json RelayVerdict block (verdict: continue|done|escalate; handover required for continue). Fix the tail and resubmit `pilot handoff` — the relay is still `awaitingPM`, no re-ask machinery runs. |
| `PANEL_SEAT_NOT_ISOLATED` | no | yes | `operational` | Retry the panel round. If it persists, free disk space and confirm the project root is readable — clone isolation failed to materialize for a non-RO-enforcing seat. |
| `PANEL_NOT_FOUND` | yes | no | `operational` | Run `alln panel status --panel <id> --json` with a valid panel id, or start a new panel with `alln panel start`. |
| `PANEL_ROUND_IN_FLIGHT` | no | yes | `operational` | Wait for the in-flight round to settle, then run `alln panel status --panel <id> --json` and retry once status is `awaitingPM`. Or poll with `alln panel watch --panel <id>`. |
| `PANEL_TARGET_MISSING` | yes | no | `operational` | Pass `--doc` an existing readable path; the panel pins the target's content hash at dispatch and cannot invent one. |
| `PANEL_NOT_AWAITING` | yes | no | `operational` | Run `alln panel status --panel <id> --json`; a panel only accepts `panel round` while its status is `awaitingPM` (done has nothing left to scrutinize). |
| `OWNERSHIP_NOT_FOUND` | no | no | `operational` | Run `alln ps --json` and pick a current owned id, or omit and use `alln kill --all` for every identity-alive tree. |
| `OWNERSHIP_ALREADY_TERMINAL` | no | no | `operational` | No action required; the tree already carries a stamped endReason. Inspect with `alln ps --json`. |
| `OWNERSHIP_IDENTITY_MISMATCH` | yes | no | `operational` | Do not retry the same kill against this pid; the recorded identity no longer matches the live process (pid reuse). Run `alln ps --json` and `alln team reconcile` for identity-dead orphans instead. |
| `KILL_PARTIAL` | no | yes | `operational` | The run stays non-terminal with survivors named. Inspect them with `alln ps --json`, then retry `alln kill <id>` or escalate manually; the tool refuses to stamp `killed` over live work. |
| `KILL_REFUSED` | yes | no | `operational` | No recorded member could be signalled (all identity-mismatched or non-PG-killable). Run `alln ps --json` and `alln team reconcile` for identity-dead orphans; do not re-signal a recycled pid. |
| `KILL_VERIFICATION_UNAVAILABLE` | yes | no | `operational` | The run records no killable worker `runtimeOwnership` (warm workers or unrecorded legacy). The stop cannot be verified — poll `alln team status` or stop the worker at its source; the tool will not stamp `killed` unverified. |
| `THREAD_SEND_FAILED` | no | yes | `operational` | Inspect the error detail; retry the send or fix the worker. |
| `MODEL_NOT_FOUND` | yes | no | `operational` | Run `alln models --json` and retry with a valid model id. |
| `MODEL_BUILTIN_IMMUTABLE` | yes | no | `operational` | Duplicate the built-in model, then edit the custom copy. |
| `MODEL_ID_COLLISION` | yes | no | `operational` | Pick a different model id or delete the conflicting custom model. |
| `MODEL_INVALID` | yes | no | `operational` | Fix the model definition and retry the edit. |
| `MODEL_DRIVER_MISSING` | yes | no | `operational` | Reference a known driver id, or add the driver manifest first. |
| `INTERNAL_ERROR` | yes | no | `operational` | Capture the message and `traceId`; retry once, then report if it persists. |
| `PROJECT_NOT_FOUND` | yes | no | `operational` | Run `alln project list --json`; retry with a valid id or name. |
| `NO_PROJECT_SELECTED` | yes | no | `usage` | Select or add a project, then re-run the mutating action. |
| `DUPLICATE_PROJECT_ROOT` | no | no | `operational` | Use the existing project that owns this normalized root. |
| `PROJECT_ROOT_UNAVAILABLE` | yes | yes | `operational` | Restore the folder/permissions, then `alln project show <id>` to re-observe. |
| `PROJECT_ARCHIVED` | yes | no | `operational` | Run `alln project unarchive <id>` before new runs. |
| `THREAD_UNASSIGNED` | yes | no | `operational` | Assign the thread/pending item to a project, then retry. |
| `WORKER_NOT_READY_IN_PROJECT` | yes | yes | `operational` | Run `alln project workers <id> --json`; open the CLI in the project folder and complete its trust/login, then recheck. |
| `RUN_WRITE_LOCK_BUSY` | no | yes | `laneBusy` | The active mutating run on this repo root looks stuck (the wait bound elapsed); wait for it to finish or stop it, then retry. |
| `EXECUTION_LANE_BUSY` | no | yes | `laneBusy` | Do not busy-loop or invent a private retry cadence. The harness owns the wait: poll relay/pilot status for laneBlocked (position, holder identity/kind/id, heldSinceSeconds) until the ticket clears, or let the harness grant the lane. Never start a second concurrent build-class turn on the same root. |
| `WRITE_SCOPE_VIOLATION` | yes | no | `operational` | Inspect roundLog.scopeViolation (declared writeScope + outOfScopePaths). The harness rejected the turn's work fail-closed; endReason stays reported. Do not auto-revert — the PM decides whether to keep, amend, or reverse the commits. Next turn: stay inside the declared prefixes or re-declare a broader writeScope. |
| `STANDING_INVARIANT_FAILED` | yes | no | `operational` | Inspect roundLog.standingFailed and proofResults entries with standing:true. For contractDrift: rebuild the turn tree, run `alln dev export-contracts` (regenerate docs/generated/alln/*), commit the artifacts, and re-run. The harness never auto-regenerates or auto-commits (Process_Ownership.md PO-F4). |
| `NO_PROJECT_ROOT` | yes | yes | `operational` | Restore the project folder or pick an available project root, then retry. |
| `WORKER_NOT_READY` | yes | yes | `operational` | Pick a ready worker or run setup health, then retry. |
| `INTENT_NO_MATCH` | no | yes | `operational` | Rephrase the intent, or pick a team id from `alln team show --json` and start it explicitly. |
| `WORKER_NAME_UNKNOWN` | yes | no | `operational` | Run `alln models --json` and retry --for with a known display name or model id. |
| `WORKER_NAME_AMBIGUOUS` | yes | no | `operational` | Disambiguate with a full display name or exact model id from the candidates in nextActions. |
| `WORKER_NAME_POSTURE_UNSAFE` | yes | no | `operational` | Pick a driver that can mechanically enforce the requested safety posture (e.g. Codex for read-only ChatGPT asks), or drop the read-only constraint. |
| `EXECUTION_TEAM_MIXED_SOURCES` | yes | no | `operational` | Pick one execution source, run as non-mutating review/propose, or split into judgment then execution. |
| `UTILIZATION_SOURCE_NOT_FOUND` | yes | no | `usage` | Run `alln models --json`; use a known driver id in appliesTo. |
| `UTILIZATION_SOURCE_UNCONFIGURED` | yes | no | `usage` | Add the source to Boost window appliesTo, then retry. |
| `UTILIZATION_AUTH_REQUIRED` | yes | no | `operational` | Sign in to the named CLI, then retry the seed. |
| `UTILIZATION_BILLING_PROMPT` | yes | no | `operational` | Resolve billing on the provider, then retry. |

## NDJSON events

| Event | Required data |
| --- | --- |
| `teamRunStarted` | `status`, `origin`, `teamPresetId` |
| `workerStarted` | `workerId`, `modelId`, `skillId` |
| `workerAnswered` | `workerId`, `durationMs` |
| `workerFailed` | `workerId`, `error` |
| `planStarted` | `workerId`, `stageId` |
| `planWritten` | `workerId`, `stageId`, `durationMs` |
| `workerActivity` | `workerId`, `activityKind` |
| `stageActivity` | `stageId`, `activityKind` |
| `teamRunCompleted` | `status`, `planStageId`, `durationMs` |
| `teamRunFailed` | `status`, `error` |
| `error` | `error` |
| `pendingAdded` | `pendingItemId`, `status` |
| `pendingSubmitted` | `pendingItemId`, `status` |
| `pendingEdited` | `pendingItemId`, `status` |
| `pendingReordered` | `pendingItemId` |
| `pendingCancelled` | `pendingItemId`, `status` |

## Next-action kinds

- `showRun` — Show the full run.
- `export` — Export the result bundle.
- `showHistory` — List recent runs.
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
- `models_json` — List model catalog and Bench state: `alln models --json`
- `team_show_json` — Show the current team: `alln team show --json`
- `teams_code_json` — List Code teams: `alln teams --lane code --json`
- `teams_definition_json` — Full team definition for edit: `alln teams definition code_bug_hunt --json`
- `skills_code_json` — List Code skills: `alln skills --lane code --json`
- `skills_show_json` — Show a Code skill: `alln skills show bug_reproducer --json`
- `team_preflight` — Preflight a team: `alln team preflight --lane code --team code_bug_hunt --effort high`
- `team_basic` — Ask the team: `alln team --lane code --team code_bug_hunt "Why does run history disappear?"`
- `team_json` — Machine team run: `alln team --json "Give me one small naming test."`
- `team_stream` — Streamed team run: `alln team --stream "Give me one tiny event-stream test."`
- `team_start_json` — Start async team run: `alln team start --json --lane code --team code_bug_hunt --effort low "tiny async sanity"`
- `try_fix_bug` — Auto Fix: Bug Hunt then one bounded fix: `alln run "The history view loses finished runs after restart." --project <id> --team code_bug_hunt --try-fix --executor build_slice --json`
- `show_latest_json` — Show the latest run: `alln show latest --json`
- `spec_full` — Retrieve the full result packet: `alln spec latest --detail full --json`
- `export_md` — Export the latest result: `alln export latest --format md`
- `export_contracts_check` — Verify no contract drift: `alln dev export-contracts --check`
- `thread_send_json` — Send message with image and file reference to thread: `alln thread send latest "describe this" --image ./shot.png --ref Sources/App.swift:10-80 --json`
- `thread_rename_json` — Rename a work thread: `alln thread rename latest "Paste-image bug" --json`
- `serve_health_json` — Coordinator health: `alln serve --health --json`
- `pending_add_json` — Create a Draft Pending item: `alln pending add --worker model_opus --when ready --json "Review this patch when Claude is available."`
- `pending_list_json` — List Pending items: `alln pending list --json`
- `boost_window_show_json` — Show Boost window settings: `alln boost-window show --json`
- `boost_window_set_json` — Enable Boost window for Claude and Codex: `alln boost-window set --enabled true --window-start 08:00 --applies-to claude_code,codex --json`

