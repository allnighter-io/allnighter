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

Output schema: `doctorResult`.

Examples: `doctor_json`.

### `alln doctor explain`

Explain one failure/recovery code.

Arguments:
- `code` (required) — Error code to explain.

Flags:
- `--json` — Structured explanation.

Examples: `doctor_explain`.

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
- `--json` — Structured catalog summary.

Output schema: `teamCatalogJSON`.

Examples: `teams_build_json`.

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
- `thread-id` (required) — Thread id.

Flags:
- `--json` — Structured thread JSON.

Examples: `thread_get_json`.

### `alln thread status`

Poll thread running/attention state.

Arguments:
- `thread-id` (required) — Thread id.

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

Examples: `skills_build_json`.

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

Delete a custom team.

Arguments:
- `team-id` (required) — Team id.

Flags:
- `--json` — Deletion acknowledgement JSON.

Examples: `teams_delete_json`.

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

Agent bootstrap: readiness + ready teams + next action (quota-free).

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

Poll live state for an async team run.

Arguments:
- `run-id` (required) — The run id from team start.

Flags:
- `--json` — Structured TeamStatusResponse.

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

### `alln team`

Run a lane team on a prompt, foreground.

Arguments:
- `prompt` (optional) — The prompt (or use --file).

Flags:
- `--file <path>` — Read the prompt from a file.
- `--lane <lane>` — build | design | copy.
- `--team <id>` — Team id (the public team selector).
- `--type <type>` — Copy-only routing sugar.
- `--effort <effort>` — low | med | high.
- `--preset <id>` — Deprecated alias for --team.
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
- `--worker <id>` — Target worker id or alias.
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
- `--worker <id>` — Target worker id or alias.
- `--team <id>` — Team preset id.
- `--fallback <id>` — Fallback worker id.
- `--when <when>` — ready | away | manual.
- `--cwd <path>` — Working directory context.
- `--json` — Emit one PendingItemJSON object.

Output schema: `pendingItemJSON`.

### `alln pending reorder`

Reorder Pending items (execution-lane or floor order).

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

### `alln mcp serve`

Run the MCP stdio server.

Flags:
- `--stdio` — Use stdio transport (default).

### `alln project list`

List projects (active by default; --all includes archived).

Flags:
- `--all` — Include archived projects.
- `--json` — Emit a ProjectListJSON object.

### `alln project add`

Add (or return the existing) project for a local root. Idempotent on normalized root.

Arguments:
- `path` (required) — Local folder / git repo root.

Flags:
- `--name <string>` — Display name (defaults to the folder name).
- `--json` — Emit a ProjectJSON object.

### `alln project show`

Show one project; re-observes root/git so output reflects current truth.

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectJSON object.

### `alln project archive`

Archive a project (hides it; never deletes local files or threads).

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectJSON object.

### `alln project unarchive`

Restore an archived project to the active roster.

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectJSON object.

### `alln project threads`

List the work threads bound to one project.

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectThreadsJSON object.

### `alln project pending`

List the pending work bound to one project (a filtered view of the one Pending store).

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectPendingJSON object.

### `alln project context`

Generate the on-demand, source-labeled context packet for a project (a receipt, never durable truth).

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectContextJSON object.

### `alln project workers`

Show cached per-project worker readiness (read-only; never probes).

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectWorkersJSON object.

### `alln project recheck-workers`

Rerun driver-declared safe probes for a project and refresh the readiness cache. No auto-config/auth.

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectWorkersJSON object.

### `alln project chat`

Ask the Project Manager (a model invocation over the project context). Answers only; never auto-creates work. No ready model → a wait turn.

Arguments:
- `project` (required) — Project id or name.
- `message` (optional) — The chat message (or use --file).

Flags:
- `--file <path>` — Read the message from a file.
- `--json` — Emit a ProjectManagerTurnJSON object.

### `alln project propose`

Ask the Project Manager for ONE bounded next move (or one visible blocker). The model authors the proposal; Allnighter stamps the durable fields. Never dispatches or approves.

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectProposalJSON object.

### `alln project proposals`

List a project's proposals.

Arguments:
- `project` (required) — Project id or name.

Flags:
- `--json` — Emit a ProjectProposalsJSON object.

### `alln project approve`

Approve a proposal: record approver/time/content-hash + observed base head, and derive a reveal-mode WorkOrder. Does not dispatch.

Arguments:
- `proposal-id` (required) — Proposal id.

Flags:
- `--by <string>` — Approver identity (default cli-user).
- `--json` — Emit a ProjectWorkOrderJSON object.

### `alln project edit`

Edit a proposal's content before approval via a JSON patch (--patch or stdin). Clears any prior approval and returns it to proposed.

Arguments:
- `proposal-id` (required) — Proposal id.

Flags:
- `--patch <json>` — JSON object patch (or pipe via stdin).
- `--json` — Emit a ProjectProposalsJSON object.

### `alln project postpone`

Postpone a proposal (stays visible; does not block new proposals unless it conflicts).

Arguments:
- `proposal-id` (required) — Proposal id.

Flags:
- `--json` — Emit a ProjectProposalsJSON object.

## Commands (named but deferred)

- `alln work` — Create a work order.
- `alln pending stop` — Stop a running Pending item.
- `alln dispatch` — Send a work order/spec to an execution target.
- `alln pair` — Approve iOS/Mac pairing.
- `alln mcp install` — Write MCP config with user consent.

## Error codes

| Code | Manual | Retryable | Agent action |
| --- | --- | --- | --- |
| `CLI_USAGE_ERROR` | yes | no | Re-run `alln docs <command>` and fix arguments. |
| `CONTRACT_DRIFT` | yes | no | Run `alln dev export-contracts`, then rebuild. |
| `DOCTOR_CHECK_FAILED` | no | yes | Run `alln doctor --json`. |
| `SOURCE_NOT_FOUND` | yes | no | Run `alln doctor --json`; add/configure the missing source. |
| `SOURCE_AUTH_EXPIRED` | yes | no | Re-authenticate the named source. |
| `MODEL_UNAVAILABLE` | no | yes | Run `alln models --json`; pick an on-Bench ready model or enable one. |
| `DEFAULT_TEAM_INVALID` | yes | no | Run `alln team show --json`; fix unavailable workers. |
| `WORKER_FAILED` | no | yes | Inspect `workerId` and source error; failed worker remains visible. |
| `PLAN_WRITER_FAILED` | no | yes | Retry with a ready plan writer or export worker answers. |
| `TEAM_RUN_TIMEOUT` | no | yes | Retry with lower effort or fewer workers. |
| `TEAM_RUN_FAILED` | no | yes | Inspect failed workers and stages; retry or adjust the team. |
| `NESTED_TEAM_BLOCKED` | yes | no | Do not recursively spawn teams without explicit depth budget. |
| `TEAM_GOVERNOR_BUSY` | no | yes | Wait or retry after current team run completes. |
| `PENDING_MUTATION_DEFERRED` | yes | no | Keep item Draft/Pending; mutating dispatch is outside Pending M1. |
| `PENDING_REORDER_INVALID` | yes | no | Keep order unchanged; reorder only Pending Execute items in the same execution lane. |
| `IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD` | no | no | Generate a new key or reuse the original payload. |
| `RESULT_NOT_READY` | no | yes | Poll team status using nextPollAfterMs, then call team result again. |
| `RUN_NOT_FOUND` | yes | no | Run `alln history --json`. |
| `COORDINATOR_UNAVAILABLE` | no | yes | Use foreground CLI or start resident mode when available. |
| `SKILL_NOT_FOUND` | yes | no | Run `alln skills --lane <lane> --json` and pick a valid skill id. |
| `TEAM_NOT_FOUND` | yes | no | Run `alln teams --lane <lane> --json` and pick a valid team id. |
| `TEAM_BUILTIN_IMMUTABLE` | yes | no | Duplicate the built-in team, then edit the custom copy. |
| `SKILL_BUILTIN_IMMUTABLE` | yes | no | Duplicate the built-in skill, then edit the custom copy. |
| `TEAM_ID_COLLISION` | yes | no | Pick a different team id or delete the conflicting custom team. |
| `SKILL_ID_COLLISION` | yes | no | Pick a different skill id or delete the conflicting custom skill. |
| `TEAM_INVALID` | yes | no | Fix the team definition and retry `alln teams edit`. |
| `SKILL_INVALID` | yes | no | Fix the skill definition and retry `alln skills edit`. |
| `TEAM_DEFAULT_INVALID` | yes | no | Set another default team before deleting or changing the lane default. |
| `SKILL_IN_USE` | yes | no | Remove the skill from team definitions before deleting. |
| `SKILL_LANE_MISMATCH` | yes | no | Pick a skill from the same lane as the team. |
| `CATALOG_ID_INVALID` | yes | no | Use a canonical lowercase id matching the catalog rules. |
| `JSON_SCHEMA_VIOLATION` | yes | no | Treat as implementation bug; run export-contracts check. |
| `PERMISSION_REQUIRED` | yes | no | Ask the user for the named permission. |
| `MCP_CLIENT_UNAPPROVED` | yes | no | Approve or configure the MCP client before retrying. |
| `ATTACHMENT_HASH_MISMATCH` | yes | no | Re-ingest or re-send the attachment; do not retry with stale bytes. |
| `ATTACHMENT_TOO_MANY` | yes | no | Remove attachments until within the count cap. |
| `ATTACHMENT_TOO_LARGE` | yes | no | Use a smaller image or fewer attachments. |
| `ATTACHMENT_UNSUPPORTED_TYPE` | yes | no | Send PNG/JPEG/GIF/WebP only. |
| `ATTACHMENT_DECODE_FAILED` | yes | no | Fix or replace the corrupt image file. |
| `ATTACHMENT_BASE64_INVALID` | yes | no | Fix the base64 payload. |
| `ATTACHMENT_STAGE_FAILED` | yes | yes | Check workingDir permissions and disk space. |
| `ATTACHMENT_STAGE_UNIGNORED` | yes | no | Add `.allnighter/` to gitignore or info/exclude manually. |
| `CONTEXT_ATTACHMENT_CAP_EXCEEDED` | yes | no | Reduce message or attachment count; never silently trim current send. |
| `FILE_REFERENCE_PROJECT_ROOT_MISSING` | yes | no | Bind the thread to a project/working directory, then retry. |
| `FILE_REFERENCE_OUTSIDE_PROJECT` | yes | no | Pick a path inside the project root. |
| `FILE_REFERENCE_NOT_FOUND` | yes | no | Refresh the file picker or choose an existing project file. |
| `FILE_REFERENCE_UNREADABLE` | yes | no | Check file permissions or choose another file. |
| `FILE_REFERENCE_BINARY_UNSUPPORTED` | yes | no | Reference text files only in v1. |
| `FILE_REFERENCE_TOO_LARGE` | yes | no | Reference a smaller file or a line range. |
| `FILE_REFERENCE_TOO_MANY` | yes | no | Remove file references until within the cap. |
| `FILE_REFERENCE_SENSITIVE_BLOCKED` | yes | no | Do not attach secrets; summarize the needed config manually. |
| `FILE_REFERENCE_LINE_RANGE_INVALID` | yes | no | Choose a valid 1-based line range inside the file. |
| `FILE_REFERENCE_CHANGED_BEFORE_INVOKE` | yes | no | Refresh the reference and re-approve the changed file before dispatch. |
| `FILE_REFERENCE_CATALOG_STALE` | no | yes | Refresh the Project file picker and retry. |
| `FILE_REFERENCE_WORKER_UNSUPPORTED` | yes | no | Choose a worker that can receive referenced file text or use a chat worker. |
| `THREAD_SEND_IDEMPOTENCY_CONFLICT` | no | no | Use a new idempotency key or repeat the original payload. |
| `THREAD_NOT_FOUND` | yes | no | Run `alln history --json` (or create a thread); retry with a valid thread id. |
| `THREAD_SEND_FAILED` | no | yes | Inspect the error detail; retry the send or fix the worker. |
| `MODEL_NOT_FOUND` | yes | no | Run `alln models --json` and retry with a valid model id. |
| `MODEL_BUILTIN_IMMUTABLE` | yes | no | Duplicate the built-in model, then edit the custom copy. |
| `MODEL_ID_COLLISION` | yes | no | Pick a different model id or delete the conflicting custom model. |
| `MODEL_INVALID` | yes | no | Fix the model definition and retry the edit. |
| `MODEL_DRIVER_MISSING` | yes | no | Reference a known driver id, or add the driver manifest first. |
| `INTERNAL_ERROR` | yes | no | Capture the message and `traceId`; retry once, then report if it persists. |
| `PROJECT_NOT_FOUND` | yes | no | Run `alln project list --json`; retry with a valid id or name. |
| `NO_PROJECT_SELECTED` | yes | no | Select or add a project, then re-run the mutating action. |
| `DUPLICATE_PROJECT_ROOT` | no | no | Use the existing project that owns this normalized root. |
| `PROJECT_ROOT_UNAVAILABLE` | yes | yes | Restore the folder/permissions, then `alln project show <id>` to re-observe. |
| `PROJECT_ARCHIVED` | yes | no | Run `alln project unarchive <id>` before new runs. |
| `THREAD_UNASSIGNED` | yes | no | Assign the thread/pending item to a project, then retry. |
| `WORKER_NOT_READY_IN_PROJECT` | yes | yes | Run `alln project workers <id> --json`; open the CLI in the project folder and complete its trust/login, then recheck. |
| `MANAGER_MODEL_UNAVAILABLE` | no | yes | Run `alln models --json`; enable a ready planner-capable model. |
| `PROPOSAL_NOT_FOUND` | yes | no | Run `alln project proposals <id> --json`; retry with a valid proposal id. |
| `PROPOSAL_INVALID_STATE` | yes | no | Check the proposal's status with `alln project proposals <project> --json`; the requested transition is not legal from its current state. |
| `WORK_ORDER_NOT_FOUND` | yes | no | Approve a proposal first, or list work orders; retry with a valid work-order id. |
| `PROPOSAL_NOT_APPROVED` | yes | no | Approve the proposal (`alln project approve <id>`) before dispatch. |
| `BASE_HEAD_CHANGED` | yes | no | Revalidate the proposal against the current head, then dispatch. |
| `DIRTY_SCOPE_CONFLICT` | yes | no | Acknowledge including the dirty files or clean them, then dispatch. |
| `DISPATCH_GATE_FAILED` | yes | no | Read the named failing gate(s) and resolve each, then retry dispatch. |
| `VERIFICATION_REQUIRED` | no | no | Run `alln project verify <id>`; a worker claim cannot mark work done. |

## NDJSON events

| Event | Required data |
| --- | --- |
| `teamRunStarted` | `status`, `origin`, `teamPresetId` |
| `workerStarted` | `workerId`, `modelId`, `skillId` |
| `workerAnswered` | `workerId`, `durationMs` |
| `workerFailed` | `workerId`, `error` |
| `planStarted` | `workerId`, `stageId` |
| `planWritten` | `workerId`, `stageId`, `durationMs` |
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
- `models_json` — List model catalog and Bench state: `alln models --json`
- `team_show_json` — Show the current team: `alln team show --json`
- `teams_build_json` — List Build teams: `alln teams --lane build --json`
- `skills_build_json` — List Build skills: `alln skills --lane build --json`
- `skills_show_json` — Show a Build skill: `alln skills show bug_reproducer --json`
- `team_preflight` — Preflight a team: `alln team preflight --lane build --team code_bug_hunt --effort high`
- `team_basic` — Ask the team: `alln team --lane build --team code_bug_hunt "Why does run history disappear?"`
- `team_json` — Machine team run: `alln team --json "Give me one small naming test."`
- `team_stream` — Streamed team run: `alln team --stream "Give me one tiny event-stream test."`
- `team_start_json` — Start async team run: `alln team start --json --lane build --team code_bug_hunt --effort low "tiny async sanity"`
- `show_latest_json` — Show the latest run: `alln show latest --json`
- `spec_full` — Retrieve the full result packet: `alln spec latest --detail full --json`
- `export_md` — Export the latest result: `alln export latest --format md`
- `export_contracts_check` — Verify no contract drift: `alln dev export-contracts --check`
- `thread_send_json` — Send message with image and file reference to thread: `alln thread send latest "describe this" --image ./shot.png --ref Sources/App.swift:10-80 --json`
- `serve_health_json` — Coordinator health: `alln serve --health --json`
- `pending_add_json` — Create a Draft Pending item: `alln pending add --worker claude --when ready --json "Review this patch when Claude is available."`
- `pending_list_json` — List Pending items: `alln pending list --json`

