# CLI Implementation Contract

Status: CLI M1 BUILT (2026-06-15) — full wall green; `--stream` emits live
run-lifecycle events, not worker answer deltas; MCP `serve --stdio` projects
from the registry. **Pending0/1 BUILT** (2026-06-17):
`alln pending` CRUD + `PendingItemJSON`; WTK-S02a added workerChat
`pending run` execution/settlement through `PendingRunExecutor`. WTK-S00/S01a/S01b
added `CapacityObservation`, Pending capacity JSON, MCP Pending registry specs,
and WorkerRunner capacity capture. A1/WTK-S02c added live MCP Pending
`pending_list`/`pending_show`/`pending_run` handlers. WTK-S03/S02b/S04 and
SWW-S00-S03 added resident one-shot wake, non-mutating teamRun Pending execution,
stalled-work contracts/detector, and read-only CLI/MCP stalled projections.
Remaining (still owned here): SWW-S04/S05 product attention commands/projections,
`pending stop`, safe followUp/returnReview Pending execution, remaining MCP
Pending write tools, and generated contract cleanup. Broad native Pending drain
is parked; one-shot Wake Tickets are scoped by `Stalled_Work_Watchdog.md`.
Owner: Shared Core + CLI + Mac
Updated: 2026-06-19

## Authority

This doc is subordinate to `CLI_Product_Spine.md` (product spine) and
`Work_Order_Team_Model.md` (vocabulary contract).

It owns the implementation detail those docs should not carry: schemas, command
surface, generated artifacts, doctor checks, error codes, streaming events, and
proof gates for making `alln` the first-class product contract.

> **P0 lifecycle gate (2026-07-19):** `Run_Lifecycle_Reliability.md` owns the
> forward accepted-run/status/blocker/activity/kill/retry contract. Existing
> paths emit some live events, but tool activity, durable blocker state, and
> externally killable foreground-worker ownership are not yet complete. Until
> RLR-S06, do not describe `--stream`, status, or kill as the full trust loop.

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
- `alln teams --json`
- `alln team "prompt"`
- `alln team --json "prompt"`
- `alln team --stream "prompt"`
- `alln show latest --json`
- `alln history "<query>" --json`
- `alln export latest --format md`
- `alln dev export-contracts --check`

> **TOMBSTONE:** MCP transport is **out of product scope** (retired 2026-07-16).
> Do not treat historical `mcp serve` / `mcp install` lines as milestone work —
> see `docs/archive/phases/MCP_Retirement.md`. Live agent activation is
> `alln bootstrap`.

Out of scope for milestone 1:

- MCP advertising / install / async MCP tools — **retired entirely** (not deferred)
- `alln serve`
- `alln pending stop`
- iOS pairing
- dispatch that edits/kills sessions
- `alln work`
- standalone `alln skills`
- craft shortcut commands such as `alln code`

## Existing Foundation

The implementation is not starting from zero. The current code already has useful
pieces:

- `alln` executable target exists.
- Team service/coordinator/run-store shapes exist or are emerging.
- Run events and persisted run records exist.
- Doctor/detector/model health probes exist.
- Recursion and governor ideas exist.
  (MCP prototype path: **deleted** at retirement — do not restore.)

Treat those as throw-forward parts, not as public contract authority. The public
M1 contract is the new `TeamRunJSON` shape and generated command registry.

## Contract Registry

Add a Core-owned command/contract registry before broad CLI wiring.

The registry owns:

- commands and subcommands
- flags, argument types, defaults, mutual exclusions, companion constraints
  (`requires` / `onlyWith`), and examples
- closed flag value domains keyed by `valueType` (`effort` → `low|med|high`,
  etc.); open types (`path`, `id`, `string`, …) stay open
- output schema references
- NDJSON event definitions
- doctor check descriptors
- error codes and recovery metadata
- generated docs/help sections
- ~~MCP tool descriptors~~ **retired** — do not re-add
- example recipe IDs

Every behavior-affecting flag constraint and every closed enum domain must
project onto usage (`alln <cmd> --help`), per-command docs (`alln docs <cmd>`),
`menu show` detail, and generated schema from that registry — never a second
hand-maintained enum list (Law 6 / SH-S10).

Derived from the registry:

```text
alln --help / alln <command> --help
alln docs
alln docs <topic>
alln docs --errors
alln docs --schema
alln docs --examples
alln doctor explain <code|check>
alln dev export-contracts
alln dev export-contracts --check
MCP tool descriptors
checked-in schema/example artifacts
```

Rule: change the registry first, regenerate, then patch runtime behavior. Do not
hand-edit generated artifacts.

### Sharpening laws (promoted from archived Alln_Sharpening)

Durable product laws now owned here + code (do not re-decide mid-slice):

1. **Cost ∝ ask** — one-worker results do not embed global catalogs; one-worker
   envelope overhead budget is **4096** bytes (`FixtureRoundTripTests`).
2. **Canonical answer once** — `TeamRunJSON.answer` is the stable result path;
   selected worker/plan markdown is moved there, not duplicated.
3. **Preview = run** — dry-run and execution share one `ResolvedRunInvocation`
   (Engine); selectors and mode-valid flags survive teaching templates.
4. **Flags honor-or-fail** — registry `mutuallyExclusiveFlags` + `flagConstraints`
   gate before run/provider; the same data projects to usage/docs/menu
   (`CommandProjection`).
5. **Permission ≠ outcome** — dry-run `writePolicy` / `effects.repoWrite` are
   permission after resolve; only terminal `repoDelta` reports observed writes.
6. **One seat count** — public `seatCount` includes lead/scout and row
   multiplicity; `workerCount` is retired.
7. **No self-rating** — mechanical pass/fail gates only; agents rate alln
   externally (`scripts/agent_eval.sh --suite sharpening`).
8. **Vendor CLI boundary** — no `--temperature` / `--max-tokens` on `alln run`;
   closed enums and stream framing are taught, not second registries.

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
# (mcp-tools.json removed — MCP transport retired; do not regenerate)
```

`alln dev export-contracts --check` fails when generated output differs from the
registry. `alln doctor --json` reports `docsVersionMatchesBinary: false` when
the installed binary and generated docs snapshot do not match.

## CLI Grammar

Milestone 1 grammar:

```bash
alln docs [topic] [--errors] [--schema] [--examples]
alln doctor [--json] [--quiet] [--full] [--auto-fix] [--agent <agent>]
alln doctor explain <code|check> [--json] [--agent <agent>]
alln models [--json]
alln teams [--json]
alln team [prompt] [--file <path>] [--lane <lane>] [--team <id>] [--type <type>] [--preset <id>] [--json | --stream]
alln show <run-id|latest> [--json]
alln export <run-id|latest> --format md
alln dev export-contracts [--check]
```

Named but deferred:

```bash
alln run --detach [prompt]
alln run --dry-run [prompt]
alln team status <run-id>
alln team result <run-id>
alln team cancel <run-id>
alln team edit
alln team deployables
alln team deployable show <id>
alln team deployable preflight <id> --project <project> [prompt]
alln team deploy <id> --project <project> [prompt]
alln team deploy-pending <id> --project <project> [prompt]
alln models add
alln work
alln pending add --project <project> [prompt]
alln pending list (--project <project> | --all)
alln pending show <pending-id>
alln pending submit <pending-id>
alln pending edit <pending-id>
alln pending reorder <pending-id>
alln pending cancel <pending-id>
alln pending run <pending-id>
alln pending stop <pending-id>
alln dispatch
alln pair
alln serve
```

> **TOMBSTONE:** historical `mcp serve` / `mcp install` verbs are **void** —
> MCP retired 2026-07-16 (`docs/archive/phases/MCP_Retirement.md`). Do not
> reintroduce them into this command list. Agent activation is `alln bootstrap`.

`alln pending` is deferred from team-run milestone 1, but it is not optional for
Project-scoped Pending. It must land before GUI Pending promises editable Draft
and Pending state. App-closed drain/native scheduling is not a v1 promise.

Deferred `alln dispatch` inherits the send-mode rule from
`CLI_Product_Spine.md`: running the command is the explicit action. Do not add an
interactive second confirmation for normal dispatch/execute; expose reveal/dry-run
flags for inspection instead.

Parsing rules:

- `--json` and `--stream` are mutually exclusive.
- `--file` and positional prompt may not both provide body text unless the
  registry explicitly defines concatenation later.
- New Send-to-team work uses `--team`; `--preset` is retired compatibility
  language and must not be reintroduced.
- Do not expose a generic team-depth `--effort` flag in new CLI/MCP contracts.
  If lineup, review, output count, proof bar, or research changes, choose a
  different Team or deployable team job.
- Provider/model reasoning effort may be added later as an explicit
  model/worker setting. It must not mutate the team shape.
- `--type` is optional metadata or Copy compatibility routing. It must not
  compete with `--team`; a conflicting type/team pair is rejected before running.
- Human mode can print compact prose to stdout.
- JSON mode prints exactly one JSON object to stdout.
- Stream mode prints only NDJSON events to stdout.
- Progress, banners, warnings, and human recovery guidance go to stderr in
  machine modes.
- Non-TTY output has no ANSI, spinners, or progress animation.

## TeamRunJSON

`TeamRunJSON` is the first public machine contract. It is not the same as the
internal persistence model, though it may project from it.

**Schema v2 / contract 3.0.0 (SH-S02):** catalog-free and answer-first. Top-level
`models` is removed (`menu` / `models` own catalogs). Canonical result text lives
exactly once on `answer` (JSON `null` while non-terminal or when no canonical
result exists). When `answer` is derived from a completed plan or a successful
one-worker seat, that source's markdown is cleared so bytes are not duplicated.

Top-level fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | integer | Public machine schema version. Current: `2`. |
| `contractVersion` | string | CLI contract version, independent from app version. Current: `3.0.0`. |
| `teamRun` | object | Run identity, status, origin, prompt, and run metadata. |
| `workers` | array | Runtime workers: one model wearing one skill (includes run-relevant model/source snapshots). |
| `workerAnswers` | array | One answer or failure per answer worker (status/model/timing; markdown may be null when moved to `answer`). |
| `answer` | object or null | Canonical result. Always serialized. |
| `stages` | array | Planner/review/reduce stages. |
| `plan` | object or null | Synthesized-plan provenance/status; `markdown` is null when moved to `answer`. |
| `outcome` | object or null | Terminal mechanical summary (`status`, `committed`, `headline`, optional `timing`). |
| `usage` | object | Observed usage only. No forecasts. |
| `warnings` | array | Non-fatal warnings. |
| `errors` | array | Structured errors encountered during the run. |
| `nextActions` | array | Typed follow-up actions and exact commands. |
| `audit` | object | Trace/run journal pointers. |

`answer` fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `status` | enum | Closed status set (usually `done` when present). |
| `outputKind` | string/null | Team output kind when known. |
| `markdown` | string/null | Canonical result text (exactly once). |
| `source.kind` | enum | `plan`, `worker`, or `typed`. |
| `source.workerId` | string/null | Provenance worker when applicable. |
| `source.modelId` | string/null | Provenance model when applicable. |
| `source.stageId` | string/null | Plan stage id when `kind == plan`. |
| `typedResultField` | string/null | Owning top-level typed field (e.g. `designBoard`) when `kind == typed`. |

Derivation (deterministic):

1. Completed synthesized plan → `answer` from plan; plan keeps provenance/status, no duplicate markdown.
2. Successful one-worker → `answer` from that worker; `workerAnswers[]` row keeps status/model/timing, no duplicate markdown.
3. Typed board → `typedResultField` + optional lead summary; typed payload stays in its typed field.
4. Partial multi-seat without synthesis → `answer: null`; seat markdowns remain.
5. Failed/cancelled/timed-out → `answer: null`.

`workerAnswers[]` observed timing (null = driver did not report):

| Field | Type | Clock boundary |
| --- | --- | --- |
| `queueMs` | integer/null | Run request accepted → this seat's CLI spawn. |
| `ttftMs` | integer/null | CLI spawn → first visible streamed delta. |
| `durationMs` | integer/null | CLI spawn → process exit (work-time). |

Terminal `outcome.timing`:

| Field | Type | Clock boundary |
| --- | --- | --- |
| `wallMs` | integer/null | Run `createdAt` → latest worker `finishedAt`. |

These are recorded clocks only. A single-worker `outcome.headline` may list the
observed phases; do not invent an orchestration tax by subtracting duration from
wall, and do not assign blame across parallel seats. No forecasts or targets.

Required `teamRun` fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Stable run id. |
| `status` | enum | `queued`, `running`, `done`, `failed`, `timedOut`, `cancelled`, or `interrupted`. |
| `origin` | enum | `cli`, `gui`, `mcp`, `ios`, `localApi`, or `system`. |
| `originAgent` | string/null | MCP/client/agent name when known. |
| `lane` | string/null | `code`, `design`, `copy`, or null when unspecified. |
| `type` | string/null | Optional lane subtype metadata. Copy compatibility may populate this when type routed to a Copy team; Code/Design Send-to-team runs usually leave it null. |
| `reasoningEffort` | string/null | Per-worker model reasoning level (`low`/`med`/`high`) where the worker's source supports it, summarized at run level only when uniform across workers; `null` when no worker exposes it or workers differ. It is the model's reasoning setting (routed per CLI: Claude `--effort`, Codex `-c model_reasoning_effort`, Antigravity model-name variant, Grok none), never a team-shape control. |
| `prompt` | string | User prompt after file loading. |
| `promptSource` | object | Positional/file/stdin provenance; no secret content. |
| `createdAt` | string | ISO 8601 timestamp. |
| `startedAt` | string/null | ISO 8601 timestamp. |
| `completedAt` | string/null | ISO 8601 timestamp. |
| `threadId` | string/null | Owning work thread, if linked. |
| `teamPresetId` | string/null | Default/custom team preset id. |
| `teamDisplayName` | string/null | User-facing team name at run start. |
| `outputKind` | string/null | Team output kind, e.g. `plan`, `bugPacket`, `designBoard`, `copyBoard`. |
| `planWriterWorkerId` | string/null | Worker responsible for final plan and default linked-thread reply target. |
| `reproduceCommand` | string/null | Redacted exact `alln team ...` command when safe. |

Status vocabulary note: `TeamRunJSON.teamRun.status` is the archived record status.
Live polling (`team_status`, `team_start` response) uses a superset that includes
two transient statuses not present in the archived record:

| Live status | Archived mapping | Notes |
| --- | --- | --- |
| `accepted` | `queued` | Run accepted before workers start. |
| `running` | `running` | One or more workers active. |
| `synthesizing` | `running` | Plan-writer phase; sub-state of `running` in the archive. |
| `completed` | `done` | All stages finished, result available. |
| `failed` | `failed` | One or more required workers failed. |
| `timedOut` | `timedOut` | Run exceeded the configured timeout. |
| `cancelled` | `cancelled` | Cancelled by user or agent. |
| `interrupted` | `interrupted` | Coordinator stopped unexpectedly; run is orphaned and unrecoverable. |

`skipped` appears in archived `TeamRunJSON` only for individual worker records, not
for the top-level run status.

Model fields (DoctorResult / menu catalogs — **not** on TeamRunJSON v2):

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
  "skillVersion": 1,
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
- When the plan is the canonical result, its markdown moves to `answer` and
  `plan.markdown` is null (SH-S02 Law 2).
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
- Do not invent future cost, quota burn, or task complexity.

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
- A final stream must end with `teamRunCompleted`, `teamRunFailed`, or `error`
  (exactly one terminal; `NDJSONStreamProjector.terminalEventNames` is the code
  SSOT).
- NDJSON is one JSON object per stdout line; human progress never mixes into
  stdout in stream mode.
- NDJSON `error.error` uses the same error envelope as JSON mode.
- On `run`, `--stream` is mutually exclusive with `--json`, `--dry-run`, and
  `--detach` (registry constraints; invalid combinations exit 2 before any
  provider start).

### Model controls (vendor CLI boundary)

`alln run` drives subscription CLIs the user already pays for. It does **not**
expose model-API knobs such as `--temperature` or `--max-tokens` — Alln cannot
enforce those through every vendor CLI. Use `--effort` (`low|med|high`),
`--worker`, and each driver's supported flags (via manifests) for controls that
actually reach the selected CLI.

> **Historical M1 boundary, now superseded by the RLR gate:** M1 projected a
> faithful settled event log. Some current paths now expose `RunEvent`s live,
> including answer/reasoning deltas, but the lifecycle is still incomplete:
> foreground admission can be silent and `.started`/tool/raw activity is not
> fully projected or durably pollable. `Run_Lifecycle_Reliability.md` RLR-S03
> owns the complete live contract. Generated docs/help may call a specific
> event live only when its source path is proven; they must not imply the whole
> run remains observable until RLR-S06.

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

Agent-first error envelope upgrade:

```json
{
  "schemaVersion": 2,
  "success": false,
  "error": {
    "code": "INVALID_ENUM",
    "ruleId": "tool.input.invalid_enum",
    "message": "Invalid team value.",
    "tool": "team_start",
    "field": "team",
    "allowedValues": ["code_plan", "code_bug_hunt", "code_release_proof"],
    "agentAction": "Retry once with one of the allowed values.",
    "remedyTier": "agent_executable",
    "whoCanFix": "agent",
    "fixCommand": null,
    "humanAction": null,
    "requiresManual": false,
    "retryable": true,
    "traceId": "trace_...",
    "runId": null,
    "sourceId": null,
    "modelId": null,
    "workerId": null
  }
}
```

Schema v2 keeps the v1 fields and adds:

| Field | Meaning |
| --- | --- |
| `tool` | Tool/command that rejected or failed. |
| `field` | Input field when the error is field-specific. |
| `allowedValues` | Valid enum values when applicable. |
| `remedyTier` | `alln_auto_fixable`, `agent_executable`, `user_interactive`, or `cannot_fix`. |
| `whoCanFix` | `alln`, `agent`, `user`, `external`, or `unknown`. |
| `humanAction` | Optional structured action safe to present in chat. |
| `approval` | Optional reveal-only approval object for risky actions. |

Recovery ladder:

1. Parse `error.code`.
2. If `remedyTier == alln_auto_fixable`, run `alln doctor --auto-fix --json`
   once, then re-run doctor before retrying the original command.
3. If `remedyTier == agent_executable` and the metadata gives one exact safe
   correction, the calling agent may retry once under its own policy.
4. If `remedyTier == user_interactive`, present `humanAction` or `agentAction`
   and stop until the user says the action is complete.
5. If no fix exists, run `alln doctor explain <code|check> --json` or the MCP
   `error_explain` tool.
6. Escalate only after safe auto-fixes, exact retries, and required human actions
   have failed.

Starter error catalog:

| Code | Default action |
| --- | --- |
| `CLI_USAGE_ERROR` | Re-run `alln docs <command>` and fix arguments. |
| `INVALID_ENUM` | Use `allowedValues`; retry once only if the intended value is unambiguous. |
| `CONTENT_TOO_LARGE` | Pass context as an artifact/ref or reduce payload. |
| `IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD` | Generate a new key or reuse the original payload. |
| `CONTRACT_DRIFT` | Run `alln dev export-contracts`, then rebuild. |
| `DOCTOR_CHECK_FAILED` | Run `alln doctor --json`. |
| `SOURCE_NOT_FOUND` | Run `alln doctor --json`; add/configure the missing source. |
| `SOURCE_AUTH_EXPIRED` | Re-authenticate the named source. |
| `MODEL_UNAVAILABLE` | Choose a ready model or run `alln models --json`. |
| `DEFAULT_TEAM_INVALID` | Run `alln teams --json`; fix unavailable workers. |
| `WORKER_FAILED` | Inspect `workerId` and source error; failed worker remains visible. |
| `PLAN_WRITER_FAILED` | Retry with a ready plan writer or export worker answers. |
| `TEAM_RUN_TIMEOUT` | Retry with a smaller/simpler Team or inspect failed worker/source state. |
| `NESTED_TEAM_BLOCKED` | Do not recursively spawn teams without explicit depth budget. |
| `TEAM_GOVERNOR_BUSY` | Wait or retry after current team run completes. |
| `TEAM_GOVERNOR_UNAVAILABLE` | Run `alln doctor --json`; ensure the support directory is writable, or set a writable support root for MCP/eval runs. |
| `EXECUTION_TEAM_MIXED_SOURCES` | Choose one execution source or run a non-mutating review/proposal team first. |
| `PENDING_MUTATION_DEFERRED` | Keep item Draft/Pending; mutating dispatch is outside Pending M1. |
| `PENDING_REORDER_INVALID` | Keep order unchanged; reorder only Pending Execute items in the same execution lane. |
| `RUN_NOT_FOUND` | Run `alln history --json`. |
| `COORDINATOR_UNAVAILABLE` | Use foreground CLI or start resident mode when available. |
| `JSON_SCHEMA_VIOLATION` | Treat as implementation bug; run export-contracts check. |
| `PERMISSION_REQUIRED` | Ask the user for the named permission. |
| `MCP_CLIENT_UNAPPROVED` | Approve or configure the MCP client before retrying. |
| `ENTITLEMENT_BLOCKED` | Show upgrade/recovery action; do not start a run. |

Every code must have default `agentAction`, `requiresManual`, `retryable`,
`remedyTier`, `whoCanFix`, and doctor/error-explain text in the registry before
it can be emitted.

### Process exit codes

Every `alln` invocation returns a deterministic process exit code so shells and
non-JSON callers can branch without parsing output. **Stable table (PO-F3) —
never renumber silently.** Truth lives in `ExitCode.stableTable` and is exported
to `docs/generated/alln/exit-codes.json`; a drift test freezes the numbers.

| Exit code | Name | Meaning | Examples |
| --- | --- | --- | --- |
| `0` | `success` | Success. The command completed; under `--json` the envelope is a success payload. | A team run finished; `doctor` ran and reported a status; `models --json` printed the roster; `team status --wait-for` reached its target. |
| `1` | `runFailed` | Operational / run-failed. The command was well-formed but the operation failed or the requested entity/state was unavailable. | `RUN_NOT_FOUND`, `SOURCE_NOT_FOUND`, `SOURCE_AUTH_EXPIRED`, `MODEL_UNAVAILABLE`, `WORKER_FAILED`, `COORDINATOR_UNAVAILABLE`, `ENTITLEMENT_BLOCKED`. |
| `2` | `usageError` | Usage error. The command, subcommand, flag, or argument was invalid before any work started. | `CLI_USAGE_ERROR`, `INVALID_ENUM`, unknown command/flag, missing required argument. |
| `3` | `timeout` | A bounded wait expired before the target condition. | `TEAM_RUN_TIMEOUT`, `STATUS_WAIT_TIMEOUT` (`team status --wait-for` past `--timeout`). |
| `4` | `laneBusy` | Per-root execution/write lane stayed busy past the wait bound. | `EXECUTION_LANE_BUSY`, `RUN_WRITE_LOCK_BUSY`. |

Rules:

- A `doctor` run whose checks fail but which itself executed correctly exits `0`
  with a non-`ok` `status` (doctor succeeded at diagnosing). Reserve exit `1` for
  doctor failing to run at all.
- Under `--json`, failures still print the full error envelope on stdout; the exit
  code is the class, the envelope `code` is the specific reason.
- All `CLI_USAGE_ERROR` paths must exit `2`. (The current build has a few usage
  paths that exit `1`; normalize them to `2`.)
- Exit classes map via `ErrorSpec.exitClass` → `ErrorExitClass.processExitCode`.
  Adding a new numeric exit code requires extending `ExitCode.stableTable`, this
  table, and the drift test together — never renumber an existing code.

## Doctor Contract

M1 may return schema version 1. Agent-first upgrades doctor to schema version 2.
`alln doctor --json` and MCP `doctor` must then return:

```json
{
  "schemaVersion": 2,
  "status": "ok",
  "binaryVersion": "0.1.0",
  "contractVersion": "1.0.0",
  "docsVersionMatchesBinary": true,
  "canStartTeamRun": true,
  "readyTeams": [
    {"lane": "code", "team": "code_plan", "displayName": "Plan"}
  ],
  "blockedReason": null,
  "nextAction": {
    "kind": "startTeamRun",
    "tool": "team_start"
  },
  "checks": [],
  "fixes": [],
  "appliedFixes": [],
  "humanActions": [],
  "models": [],
  "entitlement": {
    "canStartTeamRun": true,
    "blockedReason": null
  },
  "coordinator": {
    "available": false,
    "detail": "foreground CLI only"
  },
  "observedAt": "2026-06-16T08:00:00Z",
  "staleAfter": "2026-06-16T08:00:30Z",
  "traceId": "trace_..."
}
```

MCP `doctor` input shape:

```json
{
  "agent": "openclaw",
  "full": false,
  "autoFix": false,
  "quiet": false,
  "check": null
}
```

- `agent`: names the calling agent; doctor includes agent-specific checks such as
  `mcp.clientApproved.<agent>` and `agent.<agent>.configPresent`.
- `full`: runs deeper bounded probes; provider smoke tests that spend quota require
  `full: true` and must still be bounded by a timeout.
- `autoFix`: applies all `alln_auto_fixable` fixes and populates `appliedFixes` in
  the response; run once, then call doctor again to confirm convergence.
- `quiet`: returns only failing checks; reduces payload for polling.
- `check`: scopes `autoFix` to one named check; omit to fix all auto-fixable issues.

`observedAt` and `staleAfter` are advisory metadata for client-side cache
decisions. An agent may call `doctor` again at any time; `staleAfter` is not a
server-side rate limit.

Overall status:

- `critical`: no runnable default team, contract drift, corrupted config, or no
  source can run.
- `degraded`: at least one source/model/check is failing but a minimal team can
  run.
- `ok`: all required milestone checks pass.

Agents branch on `canStartTeamRun`, not prose. If `canStartTeamRun` is false,
`nextAction` must name a deterministic next step: run doctor, run auto-fix,
perform human action, approve MCP client, install/auth source, wait for
admission, or upgrade entitlement.

Fixes must declare remedy tier:

```text
alln_auto_fixable
agent_executable
user_interactive
cannot_fix
```

Only `alln_auto_fixable` fixes may run under `--auto-fix`.

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
| `mcp.descriptorsCurrent` | Deferred until MCP scope, but registry name reserved. |
| `mcp.serverReachable` | MCP server accepts a request and returns registry-backed descriptors. |
| `mcp.clientApproved.<agent>` | Named MCP/agent client is approved by local policy. |
| `mcp.docsCurrent` | Generated MCP/tool docs match binary contract. |
| `agent.<agent>.configPresent` | Named agent install/config instructions exist or can be printed. |
| `agent.<agent>.binaryOnPath` | Named agent binary is present when detectable. |
| `journal.incrementalDurable` | Async run journal persists worker/status transitions incrementally. |
| `journal.orphanRecovery` | Orphaned async runs resolve to `interrupted`. |
| `pending.storeReadable` | Pending store can be read. |
| `pending.storeWritable` | Pending store can be mutated. |
| `admission.parsersHealthy` | Source/admission parsers load and return sourced block reasons. |
| `catalog.team.<team>.valid` | Selected team exists, owns one lane, and resolves to startable workers. |
| `entitlement.canStartTeamRun` | Entitlement preflight would allow a team start. |

Auto-fix may only touch Allnighter-owned files:

- create config/run/log dirs
- repair permissions on Allnighter-owned dirs
- regenerate generated docs/contracts in a dev checkout when explicitly run
- clean stale Allnighter temp files
- re-run source discovery and repair the cached `ResolvedInvocation` when binary
  paths are unchanged (this fixes the PATH/alias detection gap without touching
  external CLIs or shell profiles)

Auto-fix must not:

- install external CLIs
- log into providers
- change Keychain/API keys
- spend quota
- kill sessions
- delete run history

`fixes[]` item shape:

```json
{
  "id": "fix_create_runs_dir",
  "title": "Create the Allnighter runs directory",
  "tier": "alln_auto_fixable",
  "safeToAutoFix": true,
  "fixesChecks": ["runsDir"],
  "command": "alln doctor --auto-fix --check runsDir",
  "tool": "doctor",
  "params": {"autoFix": true, "check": "runsDir"},
  "requiresHuman": false,
  "requiresApproval": false,
  "verifyCommand": "alln doctor --json",
  "why": "Team runs need a writable journal directory.",
  "trustTier": "alln_owned_state"
}
```

`humanActions[]` item shape:

```json
{
  "id": "human_auth_claude",
  "title": "Reconnect Claude Code",
  "source": "claude",
  "kind": "terminalLogin",
  "message": "Claude Code authentication expired. Run claude auth login on the Mac, then say done.",
  "command": "claude auth login",
  "authUrl": null,
  "userCode": null,
  "expiresAt": null,
  "why": "Bug Hunt needs at least one ready Code worker.",
  "recheckCommand": "alln doctor --agent openclaw --json",
  "relatedChecks": ["source.claude.auth"]
}
```

`kind` is one of: `deviceAuth`, `browserLogin`, `terminalLogin`, `keychainApproval`,
`macosPermission`, `manualCommand`, `wait`. The example above shows `terminalLogin`
(no device/browser flow available). When a device flow IS available, set
`kind: "deviceAuth"` and populate `authUrl`, `userCode`, and `expiresAt`.

Auth handoff data must use official provider flows only, must not include
secrets/tokens/cookies, and must not be persisted beyond non-secret metadata.

## MCP Projection — RETIRED (tombstone)

> **TOMBSTONE (2026-07-16):** MCP is **not** a live product surface. The `mcp`
> CLI verb family, tool-descriptor projection, and install path were deleted.
> See `docs/archive/phases/MCP_Retirement.md`. Agents speak **CLI verbs only**
> (`alln run --detach`, `alln bootstrap`, `alln help …`). Do not reintroduce a
> parallel underscore-tool-id grammar beside runnable `alln …` commands.
>
> Historical labels (`team_start`, `help_get`, `mcp_hello`, …) exist only in
> archives and this tombstone. Live next-action envelopes carry full
> `command: "alln …"` strings (`AgentSurfaceNextAction` / ASF-S02).

Async CLI lifecycle (the replacement for the retired MCP async tools):

```bash
alln run --dry-run --team <id> --json
alln run --detach --team <id> --json "…"
alln team status <run-id> --json
alln team result <run-id> --json
alln team cancel <run-id> --json
```

Activation (replaces install):

```bash
alln bootstrap [--host claude|cursor|codex|generic]
```

## Recursion And Governor

Default recursion policy:

- Top-level run starts at depth `0`.
- A worker environment receives the current depth.
- A nested team request increments depth.
- Default max depth is `1` unless config explicitly allows more.
- Refusal emits `NESTED_TEAM_BLOCKED`.

Governor policy:

- Config owns `maxConcurrentTeamRuns`.
- Refusal emits `TEAM_GOVERNOR_BUSY` only when slots are actually locked.
- Slot-store creation/open/lock failure emits `TEAM_GOVERNOR_UNAVAILABLE`.
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
alln teams --json
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
10. ~~Project MCP from the same registry~~ **Closed** — MCP retired; CLI is the
    only agent surface (`docs/archive/phases/MCP_Retirement.md`).
11. ~~Land `mcp_hello` / MCP help tools~~ **Closed** — help is CLI-only
    (`alln help get` / `alln help search` / `alln docs`).
12. Add `alln run --dry-run` before async `alln run --detach` so setup/auth/entitlement
    blockers are caught before any "started" acknowledgement.
13. Add idempotency, `nextPollAfterMs`, payload caps, and cursor contracts before
    exposing OpenClaw/Hermes generated examples.

Journal boundary: M1's foreground synchronous runs may keep the current
one-shot-at-end journal write. Before any async `alln run --detach/status/result`
or the Mac background coordinator, the run journal MUST be hardened to incremental
writes (per worker answer / status change), with an orphaned run resolving to
`interrupted` on read — never silently absent, never a false `running`. See the
journal-durability note at the top of `CLI_Product_Spine.md` and the Lifecycle
Rules in `Mac_Standalone_App_And_Background_Coordinator.md`.

### Post-Journal Implementation Bridge

Once `Journal0` is green, implementation resumes in this order. Do not skip ahead
to Pending or GUI work before the owning prerequisite is real.

| Order | Slice | Owner doc | Done when |
| --- | --- | --- | --- |
| 1 | `Serve0` coordinator skeleton | `Mac_Standalone_App_And_Background_Coordinator.md` | `alln serve --health --json` reports coordinator identity, pid, start time, journal health, and loopback state without starting work. |
| 2 | `A0` async team loop | `Agent_First_MCP_And_Messaging_Workflows.md` | `team_start/status/result/cancel` return an immediate run id, poll from journal/coordinator truth, and retrieve `TeamRunJSON`. |
| 3 | `Pending0`/`Pending1` | `Pending_Work_And_Drain.md` | `alln pending` can create/list/show/submit/edit/cancel local Draft/Pending items; no drain promise yet. |
| 4 | `Pending1a` Wake Tickets | `Pending_Work_And_Drain.md` + `Stalled_Work_Watchdog.md` | Capture CLI-to-CLI capacity observations, update Pending JSON/schema/fixtures, write workerChat `PendingResume`, and execute/settle workerChat Pending through WTK-S02a. Live MCP parity and remaining execution seams come before `alln serve` may make one same-work wake resume. No broad drain. |
| 5 | `A1` Pending over MCP | `Agent_First_MCP_And_Messaging_Workflows.md` | List/show/run handlers expose Pending and Wake Ticket facts through the same schemas/error envelope as CLI; remaining write/edit tools follow later. |
| 6 | `Pending2` | `Pending_Work_And_Drain.md` + parked admission policy | Parked: broad native drain/scheduling waits until explicitly revived. External agents may trigger Pending through CLI/MCP. |

`Serve0` must stay deliberately small: no LaunchAgent, no start-at-login, no GUI
handoff, no iOS pairing, no remote listener beyond explicit loopback health, no
Pending drain. Its job is to create the resident-process seam and doctor-visible
health shape that A0 can depend on.

`A0` may use the existing synchronous team runner internally, but the public
contract is async: accepted run id first, status/result later, idempotency before
duplicate work, and orphan recovery from the incremental journal.

Status note (2026-06-19): `Journal0`, `Serve0`, `A0`, **Pending0/Pending1**, and
WTK-S02a workerChat `pending run` execution/settlement are built. **A1/WTK-S02c**
Pending list/show/run over MCP is built. WTK-S03/S02b/S04 and SWW-S00-S03 are
built. Next is SWW-S04/S05 product attention: deterministic Project Manager wait
nudges, typed actions, resident periodic stalled scans, and notification/menu
integration. **Pending2** broad drain/native scheduling is parked; do not promise
app-closed broad Pending execution until that work is explicitly revived.

## Pending CLI Contract

Authority:

- `Pending_Work_And_Drain.md` owns Pending semantics.
- Admission states and retry policy are parked; Pending M1 must not depend on
  admission-ledger automation.
- This doc owns CLI grammar, JSON projection, events, and proof gates.

Grammar:

Target grammar. Code reality on 2026-06-19: workerChat `pending run` is real;
MCP `pending_list`/`pending_show`/`pending_run` are real; `--project`, `--all`,
`pending stop`, remaining MCP Pending write/edit tools, stream attempt events,
and teamRun/mutating Pending execution are not all implemented yet. Do not cite
this grammar as shipped behavior without checking
`ContractRegistry+Milestone1.swift`, `PendingCLI`, and `MCPServer`.

```bash
alln pending add --project <project> [prompt] [--file <path>] [--worker <id>] [--team <id>] [--fallback <id>] [--when ready|away|manual] [--submit] [--json]
alln pending list (--project <project> | --all) [--json]
alln pending show <pending-id> [--json]
alln pending submit <pending-id> [--json]
alln pending edit <pending-id> [--prompt <text> | --file <path>] [--worker <id>] [--team <id>] [--fallback <id>] [--when ready|away|manual] [--json]
alln pending reorder <pending-id> [--before <pending-id> | --after <pending-id> | --position <n>] [--json]
alln pending cancel <pending-id> [--json]
alln pending run <pending-id> [--json | --stream]
alln pending stop <pending-id> [--json]
```

Rules:

- `alln pending add` creates a Draft `PendingItem`; it does not imply the worker
  is available and it is not runnable until submitted.
- `alln pending add` requires `--project` unless invoked from a Project-bound
  thread/manager command that supplies the Project.
- `alln pending list` requires either `--project` or `--all`. `--all` is an
  aggregate floor view grouped by Project, not a global durable queue.
- `--submit` creates the item and immediately moves it to Pending.
- `alln pending submit` moves Draft to Pending.
- `alln pending edit` changes the item and returns it to Draft when it was
  Pending.
- `alln pending reorder` changes execution-lane order only. It does not edit the
  prompt, target, safety context, or lifecycle status.
- Reorder is valid only for Pending Execute items in the same execution lane. A
  Running item cannot be reordered. Cross-Project reorder is invalid.
- Reorder is atomic: it takes a short execution-lane `editLock`, writes the new
  order, emits audit, and releases the lock. `alln serve` must not start the next
  item from that execution lane while the lock is open.
- Native `--when ready` / `--when away` scheduling flags are parked. V1 Pending
  runs only through explicit user/CLI/GUI/MCP/external-agent triggers.
- If a legacy `drainMode` field exists in fixtures, treat it as parked metadata
  unless native scheduling is explicitly revived.
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
- The GUI and iOS must be able to render Pending from
  `alln pending list --project <project> --json` and
  `alln pending list --all --json` without field translation.

`PendingItemJSON` top-level fields:

```text
schemaVersion
contractVersion
pendingItem
target
policy
execution
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
| `projectId` | string | Owning Project. Required for drainable items. |
| `status` | enum | `draft`, `pending`, `running`, `done`, `failed`, or `cancelled`. |
| `title` | string | User-visible row title. |
| `kind` | enum | `workerChat`, `teamRun`, `workOrder`, `dispatch`, `returnReview`, or `followUp`. |
| `origin` | enum | `cli`, `gui`, `ios`, `mcp`, `localApi`, `system`, or `preset`. |
| `threadId` | string/null | Owning thread, if linked. |
| `promptExcerpt` | string | Redacted/excerpted prompt for lists. |
| `createdAt` | string | ISO 8601 timestamp. |
| `updatedAt` | string | ISO 8601 timestamp. |
| `nextWakeAt` | string/null | Observed reset or externally requested recheck time, never guessed. |
| `blockedReason` | string/null | Current sourced reason when Pending cannot run yet. |
| `needsAttention` | boolean | Derived flag from `blockedReason`/manual action; not a lifecycle status. |

Execution projection:

```text
intent: ask | execute
executionLaneKey?
executionLaneKeyVersion?
executionLanePolicy: fifo | userOrdered
executionLaneOrder?
executionLaneHeadItemId?
executionLaneBlockedByItemId?
executionLanePausedReason?: user | editLock
```

Rules:

- `Pending_Work_And_Drain.md` owns the execution-lane semantics.
- `executionLaneKey` is internal scheduling/audit truth. Human copy should say
  "prior execute order" or "execution lane," not unqualified "lane."
- `executionLaneBusy` is a valid `blockedReason` when a later
  same-execution-lane Execute item is Pending behind the current head item.
- FIFO is the default execution-lane policy.
- Manual reorder sets `executionLanePolicy: userOrdered` and records
  `userReorderedExecutionLane` in audit.
- CLI flags must not expose LIFO until the phase spec does.

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
pendingReordered
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
- `alln pending list --project <project> --json` and
  `alln pending list --all --json` contain no quota/cost/runtime/token estimates.
- `alln pending add` creates Draft unless `--submit` is provided.
- `alln pending add` stores `projectId`; unassigned local/dev items are
  repair-only/disposable and not runnable.
- Editing a Pending item returns it to Draft.
- Reordering a Pending Execute item changes execution-lane order without changing
  lifecycle status or prompt.
- Invalid reorder returns `PENDING_REORDER_INVALID` and leaves order unchanged.
- Current code only records a queued attempt for `alln pending run`; the
  execution/settlement works test belongs to WTK-S02.
- `alln pending stop` returns Running to Pending once that command lands.
- Same-execution-lane Execute fixture proves a later item reports
  `executionLaneBusy` and does not start before the head item completes or is
  cancelled.
- `alln serve` does not promise broad native Pending drain while the GUI is
  closed. One-shot Wake Tickets are the scoped exception.
- Fake-clock Wake Ticket tests cover sourced cooldown resume; broader scheduler
  wakeup tests remain parked with native scheduling.
- Mutation-deferred test proves unattended mutating dispatch does not run through
  Pending M1.
- `alln doctor --json` reports coordinator and admission-parser health.
- `alln dev export-contracts --check` passes.
- `swift test` passes or missing proof is explicitly waived.

Pending Works Test:

```bash
alln serve
alln pending add --project Allnighter --worker model_opus --when ready --json "Review this patch when Claude is available."
alln pending submit <pending-id> --json
alln pending add --project Allnighter --submit --worker model_opus --when ready --json "Continue security review."
alln pending list --project Allnighter --json
alln pending list --all --json
alln pending show <pending-id> --json
alln pending reorder <pending-id> --before <other-pending-id> --json
alln pending run <pending-id> --json
alln pending stop <pending-id> --json
alln doctor --json
alln dev export-contracts --check
```
