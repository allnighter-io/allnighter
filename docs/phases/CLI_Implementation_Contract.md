# CLI Implementation Contract

Status: CLI M1 BUILT (2026-06-15) — full wall green; live `--stream` real; MCP
`serve --stdio` projects from the registry. **Pending0/1 BUILT** (2026-06-17):
`alln pending` CRUD + `PendingItemJSON`. Remaining (still owned here): MCP
advertising/auto-install + async tools and `pending stop`. Native Pending drain
is parked.
Owner: Shared Core + CLI + Mac
Updated: 2026-06-17

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
- `alln history "<query>" --json`
- `alln export latest --format md`
- `alln dev export-contracts --check`
- `alln mcp serve --stdio` (descriptors projected from the registry)

Out of scope for milestone 1:

- public MCP advertising / auto-install (`alln mcp serve --stdio` is built and
  projects descriptors from the registry; `alln mcp install` stays consent-gated —
  it prints config, never edits client files)
- async MCP tools (`team_start`/`team_status`/`team_result`) — need async runs first
- `alln serve`
- `alln pending stop`
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
alln doctor explain <code|check>
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
alln doctor [--json] [--quiet] [--full] [--auto-fix] [--agent <agent>]
alln doctor explain <code|check> [--json] [--agent <agent>]
alln models [--json]
alln team show [--json]
alln team [prompt] [--file <path>] [--lane <lane>] [--team <id>] [--type <type>] [--preset <id>] [--json | --stream]
alln show <run-id|latest> [--json]
alln export <run-id|latest> --format md
alln dev export-contracts [--check]
```

Named but deferred:

```bash
alln team start [prompt]
alln team preflight [prompt]
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
alln mcp serve --stdio
alln mcp install
alln serve
```

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
- New Fan out work uses `--team`; `--preset` is a deprecated compatibility alias.
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
| `status` | enum | `queued`, `running`, `done`, `failed`, `timedOut`, `cancelled`, or `interrupted`. |
| `origin` | enum | `cli`, `gui`, `mcp`, `ios`, `localApi`, or `system`. |
| `originAgent` | string/null | MCP/client/agent name when known. |
| `lane` | string/null | `build`, `design`, `copy`, or null when unspecified. |
| `type` | string/null | Optional lane subtype metadata. Copy compatibility may populate this when type routed to a Copy team; Build/Design Fan out usually leave it null. |
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

> **M1 boundary (follow-up):** `--stream` currently emits a *faithful event log
> projected from the settled run* (real `seq`/timestamps, terminal event last),
> not a live incremental feed. True live/incremental streaming requires exposing
> the coordinator's `RunEvent` stream (and the post-fan-out plan-stage events)
> through `TeamService`; that is a later engine follow-up. Generated docs/help
> must not describe `--stream` as live until that exists.

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
    "allowedValues": ["build_core", "build_bug_hunt", "build_release_proof"],
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
| `DEFAULT_TEAM_INVALID` | Run `alln team show --json`; fix unavailable workers. |
| `WORKER_FAILED` | Inspect `workerId` and source error; failed worker remains visible. |
| `PLAN_WRITER_FAILED` | Retry with a ready plan writer or export worker answers. |
| `TEAM_RUN_TIMEOUT` | Retry with a smaller/simpler Team or inspect failed worker/source state. |
| `NESTED_TEAM_BLOCKED` | Do not recursively spawn teams without explicit depth budget. |
| `TEAM_GOVERNOR_BUSY` | Wait or retry after current team run completes. |
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
non-JSON callers can branch without parsing output:

| Exit code | Meaning | Examples |
| --- | --- | --- |
| `0` | Success. The command completed; under `--json` the envelope is a success payload. | A team run finished; `doctor` ran and reported a status; `models --json` printed the roster. |
| `1` | Operational failure. The command was well-formed but the operation failed or the requested entity/state was unavailable. | `RUN_NOT_FOUND`, `SOURCE_NOT_FOUND`, `SOURCE_AUTH_EXPIRED`, `MODEL_UNAVAILABLE`, `WORKER_FAILED`, `TEAM_RUN_TIMEOUT`, `COORDINATOR_UNAVAILABLE`, `ENTITLEMENT_BLOCKED`. |
| `2` | Usage error. The command, subcommand, flag, or argument was invalid before any work started. | `CLI_USAGE_ERROR`, `INVALID_ENUM`, unknown command/flag, missing required argument. |

Rules:

- A `doctor` run whose checks fail but which itself executed correctly exits `0`
  with a non-`ok` `status` (doctor succeeded at diagnosing). Reserve exit `1` for
  doctor failing to run at all.
- Under `--json`, failures still print the full error envelope on stdout; the exit
  code is the class, the envelope `code` is the specific reason.
- All `CLI_USAGE_ERROR` paths must exit `2`. (The current build has a few usage
  paths that exit `1`; normalize them to `2`.)
- Exit codes above `2` are reserved; do not introduce new ones without updating
  this table.

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
    {"lane": "code", "team": "code_core", "displayName": "Code Lab"}
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
  "why": "Bug Hunt needs at least one ready Build worker.",
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

## MCP Projection

MCP is milestone 2 unless explicitly pulled forward. When it ships:

```bash
alln mcp serve --stdio
alln mcp install
```

Current M1 tool names (live, derived from registry):

```text
team_ask      # alln team            — DELETED when agent-first lands
team_show     # alln team show
history       # alln history         — DELETED when agent-first lands
show          # alln show            — DELETED when agent-first lands
doctor        # alln doctor --json
```

`team_ask`, `history`, and `show` are **deleted** when the agent-first tool set
lands. No aliases. No backwards-compatibility shims. Hard delete from the
registry. All callers must use the agent-first names below.

Agent-first tool names (replace the registry when this phase lands):

```text
mcp_hello
help_get
doctor
doctor_explain
error_explain
models_list
teams_list
team_show
team_deployable_list
team_deployable_get
team_deployable_preflight
team_deploy
team_deploy_pending
team_deploy_result
team_preflight
team_start
team_status
team_result
team_cancel
run_show
run_export
spec_get
history_search
```

Deferred tool names (named, not yet derived — they need async/Pending first):

```text
pending_add / pending_submit / pending_edit / pending_reorder /
pending_list / pending_show / pending_cancel / pending_run / pending_stop
```

`team_recall` is **retired** — Step 8 retired the `recall` grammar; MCP retrieval
is `history_search`, `run_show`, `run_export`, or `spec_get`. Do not reintroduce
`team_recall` or `team_presets`.

Rules:

- Tool descriptors derive from the registry.
- Tool results use `TeamRunJSON` and the shared error envelope.
- No MCP-only flags or schemas.
- Every MCP call records `origin: "mcp"` and `originAgent` when available.
- `originAgent` is provenance only; it is not authorization or approval.
- `team_start` and `pending_add` accept idempotency keys and reject reused keys
  with changed canonical payloads.
- `team_status` returns `nextPollAfterMs` and never reports fake percentages.
- List/history tools support `limit` and `cursor`.
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
11. Before agent-first MCP expansion, land `mcp_hello`, `help_get`,
    doctor schema v2, `doctor_explain`, and `error_explain`.
12. Add `team_preflight` before async `team_start` so setup/auth/entitlement
    blockers are caught before any "started" acknowledgement.
13. Add idempotency, `nextPollAfterMs`, payload caps, and cursor contracts before
    exposing OpenClaw/Hermes generated examples.

Journal boundary: M1's foreground synchronous runs may keep the current
one-shot-at-end journal write. Before any async `alln team start/status/result`
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
| 4 | `Pending2` | `Pending_Work_And_Drain.md` + parked admission policy | Parked: native drain/scheduling waits until explicitly revived. External agents may trigger Pending through CLI/MCP. |
| 5 | `A1` Pending over MCP | `Agent_First_MCP_And_Messaging_Workflows.md` | MCP exposes Pending without raw scheduler language and preserves CLI semantics. |

`Serve0` must stay deliberately small: no LaunchAgent, no start-at-login, no GUI
handoff, no iOS pairing, no remote listener beyond explicit loopback health, no
Pending drain. Its job is to create the resident-process seam and doctor-visible
health shape that A0 can depend on.

`A0` may use the existing synchronous team runner internally, but the public
contract is async: accepted run id first, status/result later, idempotency before
duplicate work, and orphan recovery from the incremental journal.

Status note (2026-06-17): `Journal0`, `Serve0`, `A0`, and **Pending0/Pending1**
are built. **Pending2** drain/native scheduling is parked; do not promise
app-closed Pending execution until that work is explicitly revived. OpenClaw,
Hermes, cron, or another external loop owner can call CLI/MCP to run Pending
items.

## Pending CLI Contract

Authority:

- `Pending_Work_And_Drain.md` owns Pending semantics.
- Admission states and retry policy are parked; Pending M1 must not depend on
  admission-ledger automation.
- This doc owns CLI grammar, JSON projection, events, and proof gates.

Grammar:

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
- `alln pending add` stores `projectId`; unassigned migrated items are not
  runnable.
- Editing a Pending item returns it to Draft.
- Reordering a Pending Execute item changes execution-lane order without changing
  lifecycle status or prompt.
- Invalid reorder returns `PENDING_REORDER_INVALID` and leaves order unchanged.
- `alln pending run` returns Pending with `blockedReason` when admission blocks.
- `alln pending stop` returns Running to Pending.
- Same-execution-lane Execute fixture proves a later item reports
  `executionLaneBusy` and does not start before the head item completes or is
  cancelled.
- `alln serve` does not promise native Pending drain while the GUI is closed.
- Fake-clock wakeup tests are parked with native scheduling.
- Mutation-deferred test proves unattended mutating dispatch does not run through
  Pending M1.
- `alln doctor --json` reports coordinator and admission-parser health.
- `alln dev export-contracts --check` passes.
- `swift test` passes or missing proof is explicitly waived.

Pending Works Test:

```bash
alln serve
alln pending add --project Allnighter --worker claude --when ready --json "Review this patch when Claude is available."
alln pending submit <pending-id> --json
alln pending add --project Allnighter --submit --worker claude --when ready --json "Continue security review."
alln pending list --project Allnighter --json
alln pending list --all --json
alln pending show <pending-id> --json
alln pending reorder <pending-id> --before <other-pending-id> --json
alln pending run <pending-id> --json
alln pending stop <pending-id> --json
alln doctor --json
alln dev export-contracts --check
```
