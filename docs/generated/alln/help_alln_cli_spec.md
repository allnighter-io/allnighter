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

Output schema: `errorEnvelope`.

Examples: `doctor_explain`.

### `alln models`

List ready/known models on the Bench.

Flags:
- `--json` — Structured model list.

Examples: `models_json`.

### `alln team show`

Show the default team for each lane.

Flags:
- `--lane <lane>` — Limit to one lane.
- `--json` — Structured team snapshot.

Examples: `team_show_json`.

### `alln team teams`

List the lane-scoped team catalog.

Flags:
- `--lane <lane>` — Filter to one lane.
- `--json` — Structured catalog summary.

Examples: `teams_build_json`.

### `alln team hello`

Agent bootstrap: readiness + ready teams + next action (quota-free).

### `alln team preflight`

Validate lane/team/effort against the ready bench without running.

Flags:
- `--lane <lane>` — build | design | copy.
- `--team <id>` — Team id.
- `--effort <effort>` — low | med | high.
- `--type <type>` — Copy-only routing sugar.

### `alln team`

Run a lane team on a prompt, foreground.

Arguments:
- `prompt` (optional) — The prompt (or use --file).

Flags:
- `--file <path>` — Read the prompt from a file.
- `--lane <lane>` — build | design | copy.
- `--team <id>` — Team id (the public Fan out selector).
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

Output schema: `teamRunJSON`.

Examples: `show_latest_json`.

### `alln spec`

Retrieve a run's spec/result packet (summary|full|artifactRefsOnly).

Arguments:
- `run-id|latest` (optional) — A run id or `latest` (default latest).

Flags:
- `--detail <detail>` (default: summary) — summary | full | artifactRefsOnly.
- `--json` — Structured SpecRetrieval result.

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

## Commands (named but deferred)

- `alln team start` — Start a resumable/asynchronous team run.
- `alln team status` — Show live state for a team run.
- `alln team result` — Show the final result for a team run.
- `alln team edit` — Edit the team lineup.
- `alln models add` — Add/configure a model.
- `alln work` — Create a work order.
- `alln pending add` — Queue a Pending item.
- `alln pending list` — List Pending items.
- `alln pending show` — Show one Pending item.
- `alln pending submit` — Move a Draft item to Pending.
- `alln pending edit` — Edit a Pending item.
- `alln pending reorder` — Reorder Pending Execute items in one lane.
- `alln pending cancel` — Cancel a Pending item.
- `alln pending run` — Run a Pending item now.
- `alln pending stop` — Stop a running Pending item.
- `alln dispatch` — Send a work order/spec to an execution target.
- `alln pair` — Approve iOS/Mac pairing.
- `alln mcp serve` — Run the MCP stdio server.
- `alln mcp install` — Write MCP config with user consent.

## Error codes

| Code | Manual | Retryable | Agent action |
| --- | --- | --- | --- |
| `CLI_USAGE_ERROR` | yes | no | Re-run `alln docs <command>` and fix arguments. |
| `CONTRACT_DRIFT` | yes | no | Run `alln dev export-contracts`, then rebuild. |
| `DOCTOR_CHECK_FAILED` | no | yes | Run `alln doctor --json`. |
| `SOURCE_NOT_FOUND` | yes | no | Run `alln doctor --json`; add/configure the missing source. |
| `SOURCE_AUTH_EXPIRED` | yes | no | Re-authenticate the named source. |
| `MODEL_UNAVAILABLE` | no | yes | Choose a ready model or run `alln models --json`. |
| `DEFAULT_TEAM_INVALID` | yes | no | Run `alln team show --json`; fix unavailable workers. |
| `WORKER_FAILED` | no | yes | Inspect `workerId` and source error; failed worker remains visible. |
| `PLAN_WRITER_FAILED` | no | yes | Retry with a ready plan writer or export worker answers. |
| `TEAM_RUN_TIMEOUT` | no | yes | Retry with lower effort or fewer workers. |
| `TEAM_RUN_FAILED` | no | yes | Inspect failed workers and stages; retry or adjust the team. |
| `NESTED_TEAM_BLOCKED` | yes | no | Do not recursively spawn teams without explicit depth budget. |
| `TEAM_GOVERNOR_BUSY` | no | yes | Wait or retry after current team run completes. |
| `PENDING_MUTATION_DEFERRED` | yes | no | Keep item Draft/Pending; mutating dispatch is outside Pending M1. |
| `PENDING_REORDER_INVALID` | yes | no | Keep order unchanged; reorder only Pending Execute items in the same execution lane. |
| `RUN_NOT_FOUND` | yes | no | Run `alln history --json`. |
| `COORDINATOR_UNAVAILABLE` | no | yes | Use foreground CLI or start resident mode when available. |
| `JSON_SCHEMA_VIOLATION` | yes | no | Treat as implementation bug; run export-contracts check. |
| `PERMISSION_REQUIRED` | yes | no | Ask the user for the named permission. |
| `MCP_CLIENT_UNAPPROVED` | yes | no | Approve or configure the MCP client before retrying. |

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

## Next-action kinds

- `showRun` — Show the full run.
- `export` — Export the result bundle.
- `showHistory` — List recent runs.

## Example recipes

- `docs_all` — Generate the full reference: `alln docs`
- `doctor_json` — Structured diagnostics: `alln doctor --json`
- `doctor_explain` — Explain an error code: `alln doctor explain SOURCE_AUTH_EXPIRED --json`
- `models_json` — List bench models: `alln models --json`
- `team_show_json` — Show the current team: `alln team show --json`
- `teams_build_json` — List Build teams: `alln team teams --lane build --json`
- `team_preflight` — Preflight a team: `alln team preflight --lane build --team build_bug_hunt --effort high`
- `team_basic` — Ask the team: `alln team --lane build --team build_bug_hunt "Why does run history disappear?"`
- `team_json` — Machine team run: `alln team --json "Give me one small naming test."`
- `team_stream` — Streamed team run: `alln team --stream "Give me one tiny event-stream test."`
- `show_latest_json` — Show the latest run: `alln show latest --json`
- `spec_full` — Retrieve the full result packet: `alln spec latest --detail full --json`
- `export_md` — Export the latest result: `alln export latest --format md`
- `export_contracts_check` — Verify no contract drift: `alln dev export-contracts --check`
- `serve_health_json` — Coordinator health: `alln serve --health --json`

