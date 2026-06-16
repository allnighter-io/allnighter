# CLI Implementation Contract

Status: Draft implementation contract for CLI milestone 1
Owner: Shared Core + CLI + Mac
Updated: 2026-06-15

## Authority

This doc is subordinate to `CLI_Product_Spine.md` (product spine) and
`Work_Order_Team_Model.md` (vocabulary contract).

It owns the implementation detail those docs should not carry: schemas, command
surface, generated artifacts, doctor checks, error codes, streaming events, and
proof gates for making `alln` the first-class product contract.

## First Principles

```text
The team run is the artifact.
alln is the standard.
The workers are the proof.
```

CLI, GUI, MCP, local API, and iOS must be projections of the same command
contract. No transport gets private semantics. No generated help or examples
invent behavior. No GUI field translation hides old vocabulary.

## Milestone Boundary

Milestone 1 proves the team-run CLI contract. It does not need resident mode,
iOS, dispatch, skill-library CRUD, or MCP advertising.

In scope:

- `alln docs`
- `alln doctor`, `alln doctor --json`, `alln doctor explain <code> --json`
- `alln models --json`
- `alln team show --json`
- `alln team "prompt"`
- `alln team --json "prompt"`
- `alln team --stream "prompt"`
- `alln show latest --json`
- `alln export latest --format md`
- `alln dev export-contracts --check`

Out of scope for milestone 1:

- public MCP launch
- `alln serve`
- `alln pending`
- iOS pairing
- dispatch that edits/kills sessions
- `alln work`
- standalone `alln skills`
- lane shortcut commands such as `alln build`

## Existing Foundation

The implementation is not starting from zero. The current code already has useful
pieces:

- `alln` executable target exists.
- Team service/coordinator/run-store shapes exist or are emerging.
- Run events and persisted run records exist.
- Doctor/detector/model health probes exist.
- MCP has a prototype path.
- Recursion and governor ideas exist.

Treat those as throw-forward parts, not as public contract authority. The public
M1 contract is the new `TeamRunJSON` shape and generated command registry.

## Contract Registry

Add a Core-owned command/contract registry before broad CLI wiring.

The registry owns:

- commands and subcommands
- flags, argument types, defaults, mutual exclusions, and examples
- output schema references
- NDJSON event definitions
- doctor check descriptors
- error codes and recovery metadata
- generated docs/help sections
- MCP tool descriptors when MCP enters scope
- example recipe IDs

Derived from the registry:

```text
alln --help / alln <command> --help
alln docs
alln docs <topic>
alln docs --errors
alln docs --schema
alln docs --examples
alln doctor explain <code>
alln dev export-contracts
alln dev export-contracts --check
MCP tool descriptors
checked-in schema/example artifacts
```

Rule: change the registry first, regenerate, then patch runtime behavior. Do not
hand-edit generated artifacts.

## Generated Artifacts

Committed generated artifacts should live under one generated folder, for
discoverability and drift checks:

```text
docs/generated/alln/help_alln_cli_spec.md
docs/generated/alln/alln-contract.json
docs/generated/alln/team-run.schema.json
docs/generated/alln/doctor-result.schema.json
docs/generated/alln/error-codes.json
docs/generated/alln/ndjson-events.json
docs/generated/alln/example-recipes.json
docs/generated/alln/mcp-tools.json        # generated once MCP is in scope
```

`alln dev export-contracts --check` fails when generated output differs from the
registry. `alln doctor --json` reports `docsVersionMatchesBinary: false` when
the installed binary and generated docs snapshot do not match.

## CLI Grammar

Milestone 1 grammar:

```bash
alln docs [topic] [--errors] [--schema] [--examples]
alln doctor [--json] [--quiet] [--full] [--auto-fix]
alln doctor explain <code> [--json]
alln models [--json]
alln team show [--json]
alln team [prompt] [--file <path>] [--lane <lane>] [--type <type>] [--effort <effort>] [--preset <id>] [--json | --stream]
alln show <run-id|latest> [--json]
alln export <run-id|latest> --format md
alln dev export-contracts [--check]
```

Named but deferred:

```bash
alln team start [prompt]
alln team status <run-id>
alln team result <run-id>
alln team edit
alln models add
alln work
alln pending add [prompt]
alln pending list
alln pending show <pending-id>
alln pending submit <pending-id>
alln pending edit <pending-id>
alln pending cancel <pending-id>
alln pending run <pending-id>
alln pending stop <pending-id>
alln dispatch
alln pair
alln mcp serve --stdio
alln mcp install
alln serve
```

`alln pending` is deferred from team-run milestone 1, but it is not optional for
the Pending/Utilization feature. It is the first public surface for Pending and
must land before GUI Pending promises app-closed execution.

Deferred `alln dispatch` inherits the send-mode rule from
`CLI_Product_Spine.md`: running the command is the explicit action. Do not add an
interactive second confirmation for normal dispatch/execute; expose reveal/dry-run
flags for inspection instead.

Parsing rules:

- `--json` and `--stream` are mutually exclusive.
- `--file` and positional prompt may not both provide body text unless the
  registry explicitly defines concatenation later.
- Human mode can print compact prose to stdout.
- JSON mode prints exactly one JSON object to stdout.
- Stream mode prints only NDJSON events to stdout.
- Progress, banners, warnings, and human recovery guidance go to stderr in
  machine modes.
- Non-TTY output has no ANSI, spinners, or progress animation.

## TeamRunJSON

`TeamRunJSON` is the first public machine contract. It is not the same as the
internal persistence model, though it may project from it.

Top-level fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | integer | Public machine schema version. Starts at `1`. |
| `contractVersion` | string | CLI contract version, independent from app version. |
| `teamRun` | object | Run identity, status, origin, prompt, and run metadata. |
| `models` | array | Bench models referenced by this run. Models at rest. |
| `workers` | array | Runtime workers: one model wearing one skill. |
| `workerAnswers` | array | One answer or failure per answer worker. |
| `stages` | array | Planner/review/reduce stages. |
| `plan` | object or null | Final synthesized result, if produced. |
| `usage` | object | Observed usage only. No estimates. |
| `warnings` | array | Non-fatal warnings. |
| `errors` | array | Structured errors encountered during the run. |
| `nextActions` | array | Typed follow-up actions and exact commands. |
| `audit` | object | Trace/run journal pointers. |

Required `teamRun` fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Stable run id. |
| `status` | enum | `queued`, `running`, `done`, `failed`, `timedOut`, `cancelled`, or `skipped`. |
| `origin` | enum | `cli`, `gui`, `mcp`, `ios`, `localApi`, or `system`. |
| `originAgent` | string/null | MCP/client/agent name when known. |
| `lane` | string/null | `build`, `design`, `copy`, or null when unspecified. |
| `type` | string/null | Lane subtype. |
| `effort` | string/null | `quick`, `standard`, `deep`, or null. |
| `prompt` | string | User prompt after file loading. |
| `promptSource` | object | Positional/file/stdin provenance; no secret content. |
| `createdAt` | string | ISO 8601 timestamp. |
| `startedAt` | string/null | ISO 8601 timestamp. |
| `completedAt` | string/null | ISO 8601 timestamp. |
| `threadId` | string/null | Owning work thread, if linked. |
| `teamPresetId` | string/null | Default/custom team preset id. |
| `planWriterWorkerId` | string/null | Worker responsible for final plan and default linked-thread reply target. |
| `reproduceCommand` | string/null | Redacted exact `alln team ...` command when safe. |

Model fields:

```json
{
  "id": "model_opus",
  "displayName": "Opus 4.8",
  "sourceId": "claude_code",
  "sourceName": "Claude Code",
  "status": "ready"
}
```

Worker fields:

```json
{
  "id": "worker_first_principles_opus",
  "skillId": "first_principles",
  "skillName": "First Principles",
  "modelId": "model_opus",
  "modelName": "Opus 4.8",
  "sourceId": "claude_code",
  "purpose": "answer",
  "instanceIndex": 0
}
```

Allowed worker `purpose` values for milestone 1:

```text
answer
plan
review
```

Plan writer rule:

- The plan writer is a worker in the team snapshot.
- `teamRun.planWriterWorkerId` and `plan.writerWorkerId` point to that worker.
- When `plan.status == "done"`, both writer fields must be non-null and equal.
- When this run is attached to a work thread, that worker is the default
  follow-up reply target for the team result.
- Answer workers are never inferred as user-facing reply targets. They remain
  `workerAnswers` evidence unless the user explicitly chooses one for a new turn.
- Human output may say `Plan written by Opus 4.8.`
- Do not expose `synthesizer`, `judge`, or `masterPlan`.

Usage rule:

- `usage.cliCalls` may count actual spawned source/model calls.
- Provider-reported token/cost/quota data may be included only when directly
  observed from a source.
- Do not estimate future cost, quota burn, or task complexity.

Forbidden new public fields:

```text
CouncilRun
panelSeats
memberResponses
masterPlan
council_ask
panel
seat
```

## NDJSON Stream

Every stream event has:

```json
{
  "schemaVersion": 1,
  "seq": 1,
  "ts": "2026-06-15T22:14:00Z",
  "event": "teamRunStarted",
  "teamRunId": "run_...",
  "data": {}
}
```

Milestone 1 event catalog:

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

Rules:

- Events are ordered by `seq`.
- A final stream must end with `teamRunCompleted`, `teamRunFailed`, or `error`.
- NDJSON `error.error` uses the same error envelope as JSON mode.
- Human progress is never mixed into stdout in stream mode.

## Error Envelope

Machine command failure shape:

```json
{
  "schemaVersion": 1,
  "success": false,
  "error": {
    "code": "SOURCE_AUTH_EXPIRED",
    "ruleId": "source.auth.expired",
    "message": "Claude Code authentication expired.",
    "agentAction": "Run `alln doctor --json`, then follow the Claude Code fix.",
    "fixCommand": "claude auth login",
    "requiresManual": true,
    "retryable": false,
    "traceId": "trace_...",
    "runId": null,
    "sourceId": "claude_code",
    "modelId": null,
    "workerId": null
  }
}
```

Recovery ladder:

1. Parse `error.code`.
2. If `requiresManual == false` and `fixCommand` is present, run the command once
   and retry once.
3. If `requiresManual == true`, present `agentAction` and stop.
4. If no fix exists, run `alln doctor explain <code> --json`.
5. Escalate only after `agentAction`, safe auto-fixes, and required manual fixes
   have failed.

Starter error catalog:

| Code | Default action |
| --- | --- |
| `CLI_USAGE_ERROR` | Re-run `alln docs <command>` and fix arguments. |
| `CONTRACT_DRIFT` | Run `alln dev export-contracts`, then rebuild. |
| `DOCTOR_CHECK_FAILED` | Run `alln doctor --json`. |
| `SOURCE_NOT_FOUND` | Run `alln doctor --json`; add/configure the missing source. |
| `SOURCE_AUTH_EXPIRED` | Re-authenticate the named source. |
| `MODEL_UNAVAILABLE` | Choose a ready model or run `alln models --json`. |
| `DEFAULT_TEAM_INVALID` | Run `alln team show --json`; fix unavailable workers. |
| `WORKER_FAILED` | Inspect `workerId` and source error; failed worker remains visible. |
| `PLAN_WRITER_FAILED` | Retry with a ready plan writer or export worker answers. |
| `TEAM_RUN_TIMEOUT` | Retry with lower effort or fewer workers. |
| `NESTED_TEAM_BLOCKED` | Do not recursively spawn teams without explicit depth budget. |
| `TEAM_GOVERNOR_BUSY` | Wait or retry after current team run completes. |
| `PENDING_MUTATION_DEFERRED` | Keep item Draft/Pending; mutating dispatch is outside Pending M1. |
| `RUN_NOT_FOUND` | Run `alln history --json`. |
| `COORDINATOR_UNAVAILABLE` | Use foreground CLI or start resident mode when available. |
| `JSON_SCHEMA_VIOLATION` | Treat as implementation bug; run export-contracts check. |
| `PERMISSION_REQUIRED` | Ask the user for the named permission. |
| `MCP_CLIENT_UNAPPROVED` | Approve or configure the MCP client before retrying. |

Every code must have default `agentAction`, `requiresManual`, `retryable`, and
doctor-explain text in the registry before it can be emitted.

## Doctor Contract

`alln doctor --json` returns:

```json
{
  "schemaVersion": 1,
  "status": "ok",
  "binaryVersion": "0.1.0",
  "contractVersion": "1.0.0",
  "docsVersionMatchesBinary": true,
  "checks": [],
  "fixes": [],
  "models": [],
  "coordinator": {
    "available": false,
    "detail": "foreground CLI only"
  }
}
```

Overall status:

- `critical`: no runnable default team, contract drift, corrupted config, or no
  source can run.
- `degraded`: at least one source/model/check is failing but a minimal team can
  run.
- `ok`: all required milestone checks pass.

Stable check names for milestone 1:

| Check | Meaning |
| --- | --- |
| `binaryVersion` | CLI binary reports version. |
| `docsVersion` | Generated docs match binary contract. |
| `configDir` | Allnighter config dir exists and is writable. |
| `runsDir` | Run journal dir exists and is writable. |
| `sources` | Known source manifests load. |
| `source.<sourceId>.installed` | Source CLI/runtime exists. |
| `source.<sourceId>.auth` | Source auth appears valid when safely probeable. |
| `source.<sourceId>.smoke` | Bounded smoke test when `--full`. |
| `benchReadyCount` | At least one model is ready. |
| `defaultTeamValid` | Default team has runnable workers. |
| `planWriterReady` | Default team has a ready plan worker. |
| `coordinator` | Resident coordinator state; may be `degraded` in M1. |
| `mcpDescriptorsCurrent` | Deferred until MCP scope, but registry name reserved. |

Auto-fix may only touch Allnighter-owned files:

- create config/run/log dirs
- repair permissions on Allnighter-owned dirs
- regenerate generated docs/contracts in a dev checkout when explicitly run
- clean stale Allnighter temp files

Auto-fix must not:

- install external CLIs
- log into providers
- change Keychain/API keys
- spend quota
- kill sessions
- delete run history

## MCP Projection

MCP is milestone 2 unless explicitly pulled forward. When it ships:

```bash
alln mcp serve --stdio
alln mcp install
```

Tool names:

```text
team_show
team_ask
team_start
team_status
team_result
pending_add
pending_submit
pending_edit
pending_list
pending_show
pending_cancel
pending_run
pending_stop
team_recall
doctor
```

Rules:

- Tool descriptors derive from the registry.
- Tool results use `TeamRunJSON` and the shared error envelope.
- No MCP-only flags or schemas.
- Every MCP call records `origin: "mcp"` and `originAgent`.
- Long-running work should prefer foreground CLI or async start/status/result
  when coordinator support exists.
- First-use MCP install/config remains consent-gated.

## Recursion And Governor

Default recursion policy:

- Top-level run starts at depth `0`.
- A worker environment receives the current depth.
- A nested team request increments depth.
- Default max depth is `1` unless config explicitly allows more.
- Refusal emits `NESTED_TEAM_BLOCKED`.

Governor policy:

- Config owns `maxConcurrentTeamRuns`.
- Refusal emits `TEAM_GOVERNOR_BUSY`.
- Refusal writes an audit event.
- The user sees a real busy state, not a fake queued worker.

## Completion Gate

A CLI slice is not done until:

- registry updated
- `TeamRunJSON` fixture updated
- Doctor result fixture updated
- Error envelope fixture updated
- `alln docs` regenerated
- `alln doctor explain` bindings regenerated
- `alln dev export-contracts --check` passes
- output contract tests prove no human prose leaks into JSON/NDJSON stdout
- NDJSON stream lines parse independently
- every emitted error code has default recovery metadata
- failed workers remain visible in JSON, stream, and human output
- vocabulary grep has no new public old words
- `swift test` passes or missing proof is explicitly waived

Works Test:

```bash
alln docs > /tmp/alln-docs.md
alln docs team > /tmp/alln-team-docs.md
alln docs --errors > /tmp/alln-errors.md
alln docs --schema > /tmp/alln-schema.md
alln doctor --json
alln models --json
alln team show --json
alln team "Give me three ways to simplify the Allnighter CLI."
alln show latest --json
alln export latest --format md
alln team --json "Give me one small naming test."
alln team --stream "Give me one tiny event-stream test."
alln dev export-contracts --check
```

## Implementation Order

1. Create `TeamRunJSON`, DoctorResult, and error-envelope fixtures.
2. Add the command/contract registry.
3. Add generated docs/export/check plumbing.
4. Add structured doctor and doctor explain.
5. Cut `alln team --json` to the fixture.
6. Add NDJSON stream projection from run events.
7. Add stdout/stderr and exit-code tests.
8. Rename/remove legacy public grammar and fields.
9. Wire GUI presenter tests to the same fixture.
10. Project MCP from the registry only after the CLI contract is boring.

Journal boundary: M1's foreground synchronous runs may keep the current
one-shot-at-end journal write. Before any async `alln team start/status/result`
or the Mac background coordinator, the run journal MUST be hardened to incremental
writes (per worker answer / status change), with an orphaned run resolving to
`interrupted` on read — never silently absent, never a false `running`. See the
journal-durability note at the top of `CLI_Product_Spine.md` and the Lifecycle
Rules in `Mac_Standalone_App_And_Background_Coordinator.md`.

## Pending CLI Contract

Authority:

- `Pending_Work_And_Drain.md` owns Pending semantics.
- `Utilization_Admission_Control.md` owns admission states and retry policy.
- This doc owns CLI grammar, JSON projection, events, and proof gates.

Grammar:

```bash
alln pending add [prompt] [--file <path>] [--worker <id>] [--team <id>] [--fallback <id>] [--when ready|away|manual] [--cwd <path>] [--submit] [--json]
alln pending list [--json]
alln pending show <pending-id> [--json]
alln pending submit <pending-id> [--json]
alln pending edit <pending-id> [--prompt <text> | --file <path>] [--worker <id>] [--team <id>] [--fallback <id>] [--when ready|away|manual] [--cwd <path>] [--json]
alln pending cancel <pending-id> [--json]
alln pending run <pending-id> [--json | --stream]
alln pending stop <pending-id> [--json]
```

Rules:

- `alln pending add` creates a Draft `PendingItem`; it does not imply the worker
  is available and it is not eligible to drain until submitted.
- `--submit` creates the item and immediately moves it to Pending.
- `alln pending submit` moves Draft to Pending.
- `alln pending edit` changes the item and returns it to Draft when it was
  Pending.
- `--when ready` stores `drainMode: drainWhenReady`.
- `--when away` stores `drainMode: drainAway`.
- `--when manual` stores `drainMode: manualStart`.
- Mutating dispatch is out of Pending M1. A Pending item that would require
  unattended writes returns `PENDING_MUTATION_DEFERRED` until the dispatch phase
  owns that surface.
- `alln pending run` submits Draft first, then attempts now when policy permits;
  if admission blocks, it returns a Pending item with sourced reasons instead of
  guessing.
- `alln pending stop` stops a Running attempt and returns the item to Pending
  with a resume packet. It does not cancel the item.
- `alln pending cancel` cancels Draft or Pending items. Cancelling Running first
  stops the active attempt, then marks the item cancelled.
- JSON mode prints exactly one object to stdout. Stream mode prints only NDJSON
  attempt events to stdout.
- The GUI and iOS must be able to render Pending from `alln pending list --json`
  without field translation.

`PendingItemJSON` top-level fields:

```text
schemaVersion
contractVersion
pendingItem
target
policy
safety
admission
attempts
nextActions
audit
```

Required `pendingItem` fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Stable pending id. |
| `status` | enum | `draft`, `pending`, `running`, `done`, `failed`, or `cancelled`. |
| `title` | string | User-visible row title. |
| `kind` | enum | `workerChat`, `teamRun`, `workOrder`, `dispatch`, `returnReview`, or `followUp`. |
| `origin` | enum | `cli`, `gui`, `ios`, `mcp`, `localApi`, `system`, or `preset`. |
| `threadId` | string/null | Owning thread, if linked. |
| `promptExcerpt` | string | Redacted/excerpted prompt for lists. |
| `createdAt` | string | ISO 8601 timestamp. |
| `updatedAt` | string | ISO 8601 timestamp. |
| `nextWakeAt` | string/null | Observed reset or scheduled recheck time, never guessed. |
| `blockedReason` | string/null | Current sourced reason when Pending cannot run yet. |
| `needsAttention` | boolean | Derived flag from `blockedReason`/manual action; not a lifecycle status. |

Admission projection:

```text
state: available | coolingDown | exhausted | authRequired | degraded | unknown | busy | manualRequired
source
observedAt
resetAt?
confidence
reason
```

NDJSON event names:

```text
pendingAdded
pendingSubmitted
pendingEdited
pendingBlocked
pendingLeased
pendingStarted
pendingStopped
pendingAttemptEvent
pendingCompleted
pendingFailed
pendingCancelled
error
```

Pending completion gate:

- `PendingItemJSON` fixture checked in.
- Pending schema generated.
- `alln pending list --json` contains no quota/cost/runtime/token estimates.
- `alln pending add` creates Draft unless `--submit` is provided.
- Editing a Pending item returns it to Draft.
- `alln pending run` returns Pending with `blockedReason` when admission blocks.
- `alln pending stop` returns Running to Pending.
- `alln serve` drains eligible Pending while the GUI is closed.
- Fake-clock test proves observed `resetAt` wakeup.
- Mutation-deferred test proves unattended mutating dispatch does not run through
  Pending M1.
- `alln doctor --json` reports coordinator and admission-parser health.
- `alln dev export-contracts --check` passes.
- `swift test` passes or missing proof is explicitly waived.

Pending Works Test:

```bash
alln serve
alln pending add --worker claude --when ready --json "Review this patch when Claude is available."
alln pending submit <pending-id> --json
alln pending add --submit --worker claude --when ready --json "Continue security review."
alln pending list --json
alln pending show <pending-id> --json
alln pending run <pending-id> --json
alln pending stop <pending-id> --json
alln doctor --json
alln dev export-contracts --check
```
