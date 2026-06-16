# Agent-First MCP and Messaging Workflows

Status: Draft feature packet, hardened after mentor review
Owner: Founder + Shared Core + CLI + MCP + Mac backend
Updated: 2026-06-16

## Founder Intent

Allnighter should become the default local team engine for agent-first workflows,
not only a native Mac GUI.

The user may never open Claude Desktop, Codex Desktop, or Allnighter's primary
window during a normal day. They may send a 2-5 minute voice-to-text brain dump
through Telegram or another messaging shell, let a persistent agent such as
OpenClaw or Hermes interpret the intent, and expect that agent to call local
tools that do real work.

Allnighter should be one of those default tools.

The aspiration:

```text
Voice brain dump
-> OpenClaw/Hermes
-> Allnighter MCP
-> Fan out / Pending / team result / full spec
-> agent presents the answer back in chat
```

If that path is faster than opening Allnighter, that is not a failure of the GUI.
It is the product winning in the form factor users are moving toward.

## Product Value

Allnighter's value is not the window. The value is:

- local orchestration of the AI CLIs the user already pays for;
- reusable expert teams;
- honest worker/run state;
- Pending work that survives availability gaps;
- full specs/results that other agents can retrieve and present;
- safety boundaries around local execution.

Messaging-first agents are the fastest capture surface for messy human intent.
Allnighter should be the reliable local execution and judgment substrate behind
that surface.

The product promise:

```text
Your messaging agent captures the work.
Allnighter gets the right team working.
```

## Assumptions

This phase assumes these backend efforts are underway or planned by their owning
docs:

- `Fanout_Team_Catalog.md`: lane-scoped teams, `low|med|high`, team resolver,
  one-model self-fusion, `TeamRunJSON` upgrades.
- `CLI_Product_Spine.md` and `CLI_Implementation_Contract.md`: generated CLI
  registry, `TeamRunJSON`, `DoctorResult`, generated docs, MCP descriptors.
- `Pending_Work_And_Drain.md`: public Draft/Pending/Running model and
  `alln pending` command family.
- `Utilization_Admission_Control.md`: admission, cooldown, fallback, and honest
  waiting/blocking reasons.
- `Mac_Standalone_App_And_Background_Coordinator.md`: `alln serve` as resident
  coordinator for long/remote/pending work.

This doc builds on those. It does not replace them.

## Trusted Workflow Slice

First lovable slice:

```text
user sends a voice-to-text brain dump to OpenClaw/Hermes
-> agent calls Allnighter MCP `mcp_hello`
-> agent calls `team_preflight`
-> agent calls `team_start`
-> Allnighter starts Build / Bug Hunt / High
-> agent receives run id immediately
-> agent polls or subscribes to status
-> agent fetches final TeamRunJSON + full spec/packet
-> agent presents concise result and exact next actions in chat
```

Second slice:

```text
user says "put this on Claude's desk when it wakes up"
-> agent calls Allnighter MCP `mcp_hello`
-> agent calls `pending_add`
-> Allnighter stores a Pending item with worker/team policy
-> agent can list/show/cancel the Pending item
-> alln serve drains it when admission allows
-> agent presents Activity Summary or completion packet
```

## Non-goals

- No GUI-first requirement for this workflow.
- No hidden cloud coordination requirement.
- No raw scheduler queue as public product language.
- No silent destructive execution from a messaging agent.
- No automatic lane inference inside Allnighter.
- No pricing bypass for agent callers.
- No official partnership claim with any specific agent project.
- No import/share marketplace for third-party teams in this phase.

## Current State

Existing useful substrate:

- `alln` exists and already has a contract-registry direction.
- MCP stdio exists in a basic form and projects descriptors from the registry.
- `TeamRunJSON` exists as the machine-readable result contract.
- `DoctorResult` exists for recovery.
- Pending has an approved CLI-first phase doc.
- Fanout Team Catalog defines the future lane/team/effort backend.

Current gaps:

- MCP does not yet expose async team start/status/result.
- MCP does not yet expose Pending Draft/Pending/Running operations.
- MCP does not yet expose full spec/result retrieval as a first-class operation.
- MCP does not yet expose an agent bootstrap/hello contract.
- Doctor/auto-fix does not yet form a closed recovery loop for headless agents.
- Doctor results do not yet classify remedies by who can perform them.
- No OpenClaw/Hermes install artifact exists.
- No messaging/voice result contract exists.
- No agent identity/provenance model exists for always-on messaging agents.
- Pricing/entitlement for agent-originated runs is not specified in a billing
  owner doc.

## First-Principles Decision

Agent-first only works if the calling agent can make Allnighter useful from a
cold, stale, or partially broken setup.

The core product question is not:

```text
Can an MCP client call a team tool?
```

The real product question is:

```text
Can a messaging agent discover Allnighter, repair safe local issues, explain
unsafe issues, start the right team, survive long-running status polling, fetch
the full packet, and hand the user one useful answer without opening the GUI?
```

Therefore this phase treats doctor/help/discovery as product-critical runtime
surface, not as support utilities.

Ordering principle:

1. A broken setup must produce a remediation plan, not just a red report.
2. A recoverable setup must become usable through `doctor --auto-fix` plus one
   deterministic recheck.
3. An unrecoverable setup must produce one chat-safe human action list with exact
   commands, auth links, or permission steps.
4. A healthy setup must expose enough schemas and guidance that an agent can use
   Allnighter without guessing tool names, enum values, polling cadence, or when
   to choose Pending.

Agent-first v1 optimizes for:

- cold-start reliability;
- clear handoff when human action is required;
- low-latency acknowledgement for long work;
- durable retrieval of full results;
- same pricing/safety boundaries as GUI/CLI.

It does not optimize for a huge first tool surface. A smaller surface that can
bootstrap, recover, and explain itself beats a broad surface that fails silently.

## Agent Bootstrap And Recovery Loop

This is the make-or-break loop for OpenClaw/Hermes-style usage.

Happy path:

```text
agent connects to MCP
-> calls mcp_hello
-> sees canStartTeamRun true
-> calls team_start or pending_add
-> polls team_status using nextPollAfterMs
-> calls team_result/spec_get
-> presents concise answer plus full packet option
```

Recoverable setup path:

```text
agent connects to MCP
-> calls mcp_hello
-> sees canStartTeamRun false and nextAction runDoctorAutoFix
-> calls doctor(autoFix: true, agent: "openclaw")
-> receives appliedFixes and remaining checks
-> calls doctor(full: false, agent: "openclaw")
-> starts work only if canStartTeamRun is now true
```

Human-action path:

```text
agent connects to MCP
-> calls doctor(full: true, agent: "openclaw")
-> receives humanActions with exact chat-safe instructions
-> presents one compact setup/auth/permission message to the user
-> after user confirms completion, re-runs doctor
```

Invariant:

```text
mcp_hello + doctor + safe auto-fixes + listed human actions must deterministically
reach either canStartTeamRun true or a stable blockedReason that names the exact
external blocker.
```

Allnighter must never leave an agent with only "something is wrong." Every
blocking result needs:

- the failing check;
- why it matters;
- who can fix it;
- the safest fix path;
- how to verify the fix;
- whether the agent may retry automatically.

### `mcp_hello`

`mcp_hello` is the first tool an agent should call after connecting.

It is cheap, non-mutating, and may use cached health data. It must not run smoke
tests that spend provider quota.

Output:

```json
{
  "contractVersion": "1.0.0",
  "binaryVersion": "0.1.0",
  "serverStartedAt": "2026-06-16T08:00:00Z",
  "docsVersionMatchesBinary": true,
  "canStartTeamRun": true,
  "readyTeams": [
    {"lane": "build", "team": "build_bug_hunt", "displayName": "Bug Hunt"},
    {"lane": "design", "team": "design_core", "displayName": "Design Studio"}
  ],
  "blockedReason": null,
  "nextAction": {
    "kind": "startTeamRun",
    "tool": "team_start"
  },
  "tools": [
    {"name": "team_start", "schemaRef": "tool://team_start.schema.json"},
    {"name": "pending_add", "schemaRef": "tool://pending_add.schema.json"},
    {"name": "doctor", "schemaRef": "tool://doctor.schema.json"}
  ],
  "quickstart": {
    "recommendedAfterHello": "team_preflight when canStartTeamRun is true; doctor when false",
    "whenToUseTeamStart": "Use for review, fanout, bug hunt, design, copy, or long work.",
    "whenToUsePending": "Use when the user wants work later or admission blocks.",
    "whenToUseSpecGet": "Use when the user asks for the full packet/spec."
  },
  "traceId": "trace_..."
}
```

If `canStartTeamRun` is false, `nextAction` must be one of:

```text
runDoctor
runDoctorAutoFix
performHumanAction
approveMcpClient
installOrAuthSource
waitForAdmission
upgradeEntitlement
```

### Doctor Verdict Schema

`doctor` and `alln doctor --json` must expose an agent-ready verdict, not only a
list of checks.

Top-level shape:

```json
{
  "schemaVersion": 2,
  "status": "ok|degraded|critical",
  "canStartTeamRun": true,
  "readyTeams": [
    {"lane": "build", "team": "build_core", "displayName": "Build Lab"}
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
  "entitlement": {
    "canStartTeamRun": true,
    "blockedReason": null
  },
  "observedAt": "2026-06-16T08:00:00Z",
  "staleAfter": "2026-06-16T08:00:30Z",
  "traceId": "trace_..."
}
```

`status` meaning:

- `critical`: no useful team run can start until a blocker is resolved.
- `degraded`: at least one team can start, but one or more tools/teams/checks are
  unavailable.
- `ok`: all required checks for the selected milestone pass.

`canStartTeamRun` is the field agents should branch on. Do not force agents to
infer readiness from prose or individual checks.

`readyTeams` must include only teams that are actually startable under current
admission, source, catalog, and entitlement constraints. If only a one-model
self-fusion team can run, it is still valid to return that team as ready.

### Remedy Triage

Every failed check or error with a known recovery must declare a remedy tier:

```text
alln_auto_fixable
agent_executable
user_interactive
cannot_fix
```

Definitions:

| Tier | Meaning | Who may act |
| --- | --- | --- |
| `alln_auto_fixable` | Allnighter can safely repair Allnighter-owned local state. | `alln doctor --auto-fix` or MCP `doctor(autoFix: true)` |
| `agent_executable` | The calling agent may run a whitelisted shell command if it has local execution rights and user policy allows it. | Calling agent, after applying its own approval rules |
| `user_interactive` | Requires a human login, browser/device flow, Keychain approval, macOS permission, or external account action. | User |
| `cannot_fix` | The blocker is external or unsupported; retrying will not help. | None until external state changes |

Allnighter may suggest `agent_executable` commands, but must not run them itself
unless the command is also `alln_auto_fixable`. Installing external CLIs,
changing shell profiles, logging into providers, approving Keychain access,
granting macOS permissions, killing sessions, or spending quota is never an
Allnighter auto-fix.

### `DoctorFix`

Each fix candidate must be structured:

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

`trustTier` values:

```text
alln_owned_state
external_cli_install
provider_auth
macos_permission
filesystem_mutation
unknown
```

Only `alln_owned_state` may be auto-fixed by Allnighter.

### `HumanAction`

Human actions must be chat-safe. They are what a messaging agent can paste back
to the user without inventing instructions.

```json
{
  "id": "human_auth_claude",
  "title": "Reconnect Claude Code",
  "source": "claude",
  "kind": "deviceAuth|browserLogin|terminalLogin|keychainApproval|macosPermission|manualCommand|wait",
  "message": "Claude Code authentication expired. Open the link, enter the code, then say done.",
  "command": "claude auth login",
  "authUrl": null,
  "userCode": null,
  "expiresAt": null,
  "why": "Bug Hunt needs at least one ready Build worker.",
  "recheckCommand": "alln doctor --agent openclaw --json",
  "relatedChecks": ["source.claude.auth"]
}
```

### Auth Handoff

When a provider supports a safe official device/browser flow, Allnighter should
surface it as structured data. This keeps a phone-first workflow from collapsing
into "go sit at the Mac."

Example:

```json
{
  "code": "SOURCE_AUTH_EXPIRED",
  "remedy": {
    "tier": "user_interactive",
    "kind": "deviceAuth",
    "source": "claude",
    "authUrl": "https://example.com/device",
    "userCode": "ABCD-EFGH",
    "timeoutSeconds": 300,
    "recheckCommand": "alln doctor --agent openclaw --json"
  }
}
```

Rules:

- Use official provider flows only.
- Never collect or proxy provider credentials.
- Never print tokens, refresh tokens, cookies, or Keychain secrets.
- If a device/browser flow cannot be captured safely, return a terminal/manual
  login action instead.
- Auth handoff data is time-bounded and must not be stored in durable run logs
  beyond non-secret metadata.

### Doctor Checks For Agent-First

Agent-first readiness requires more than "is a CLI binary installed?"

Required checks once this phase enters implementation:

| Check | Meaning |
| --- | --- |
| `mcp.serverReachable` | MCP stdio server accepted a request and returned registry-backed descriptors. |
| `mcp.clientApproved.<agent>` | This agent/client is approved or configured according to local policy. |
| `mcp.descriptorsCurrent` | MCP tool descriptors match the binary contract version. |
| `mcp.docsCurrent` | Generated tool docs match the binary contract version. |
| `agent.<agent>.configPresent` | Named agent install/config instructions are present or printable. |
| `agent.<agent>.binaryOnPath` | Named agent binary exists when the target has a detectable CLI. |
| `coordinator.available` | Resident coordinator can accept async work, or fallback foreground mode is declared. |
| `journal.incrementalDurable` | Async run journal writes worker/status transitions incrementally. |
| `journal.orphanRecovery` | Interrupted/orphaned async runs resolve to `interrupted`, not false `running`. |
| `pending.storeReadable` | Pending store can be read. |
| `pending.storeWritable` | Pending Draft/Pending mutations can be written. |
| `admission.parsersHealthy` | Source/admission parsers load and return sourced block reasons. |
| `catalog.team.<team>.valid` | Selected team exists, has one lane, and resolves to startable workers. |
| `defaultTeamValid` | The default Build/Design/Copy teams resolve. |
| `entitlement.canStartTeamRun` | Entitlement gate would allow a team start. |

Summary doctor may cache expensive checks for a short period. Full doctor must
refresh checks that are cheap and safe. Provider smoke tests that spend quota
must require `full: true` and still be bounded.

### Explain Tools

Agents need explanation tools because they often recover from errors without a
human reading the docs.

`doctor_explain` input:

```json
{
  "check": "source.claude.auth",
  "agent": "openclaw"
}
```

`error_explain` input:

```json
{
  "code": "INVALID_ENUM",
  "tool": "team_start",
  "field": "effort"
}
```

Output:

```json
{
  "code": "INVALID_ENUM",
  "title": "Invalid effort value",
  "cause": "The effort field only accepts low, med, or high.",
  "whoCanFix": "agent",
  "remedyTier": "agent_executable",
  "allowedValues": ["low", "med", "high"],
  "nextActions": [
    {"kind": "retry", "field": "effort", "value": "med"}
  ],
  "docsRef": "alln://docs/tools/team_start",
  "traceId": "trace_..."
}
```

Every structured error emitted to MCP must include enough metadata for
`error_explain` to return a useful answer. Unknown errors still return
`whoCanFix: "unknown"` and a trace id.

## SSOT

Truth owners:

```text
AllnighterCore owns run, team, Pending, entitlement, and safety semantics.
CLI contract registry owns command/tool descriptors and generated docs.
AllnighterEngine owns worker attempts, admission, and drain scheduling.
MCP/local API are projections of Core/CLI truth.
Mac app renders and configures; it does not own agent workflow truth.
```

Lie-prone layers:

| Layer | Possible lie | Guardrail |
| --- | --- | --- |
| Messaging agent | Treats a long voice dump as permission to execute | Planning/team runs are allowed; destructive Execute requires explicit approved action |
| MCP adapter | Invents private tool semantics | Generated from same registry as CLI |
| Pending adapter | Exposes raw queue attempts as user intent | Expose Draft/Pending/Running items, not scheduler internals |
| Result presenter | Summarizes away failed workers | Always expose failed/timed-out workers in structured result |
| Voice UX | Hides armed mode/team/effort | Acknowledge lane/team/effort/run id clearly |
| Entitlement layer | Lets agent callers bypass paid limits | Agent-originated runs count under the same run entitlement policy |
| Safety gate | Reuses one approval across changed action text | Approval binds to canonical action instance digest, not vague intent |

## Vocabulary

Use existing product words:

```text
Model
Skill
Worker
Team
Team run
Pending
Draft
Running
Plan
Work order
Spec
Thread
```

Avoid public raw scheduler language:

```text
queue
job queue
worker queue
attempt queue
```

MCP may expose `pending_*` tools. It should not expose `queue_*` tools unless
the target is explicitly debug-only.

## Agent-First Product Laws

- Messaging agents are first-class clients.
- CLI, MCP, local API, Mac, and iOS share one semantic contract.
- The fastest path may be voice -> agent -> Allnighter -> chat response.
- GUI remains valuable for setup, floor visibility, review, and settings.
- Allnighter must be pleasant to call from another agent without screen scraping.
- Every machine output has enough structure for an agent to present it well.
- Every long operation can be started, inspected, retrieved, and cancelled.
- Every risky action names why it is risky and how to approve or reveal-only.
- Agent-originated work is priced/entitled the same as GUI-originated work.

## MCP Surface

MCP is the primary integration surface for OpenClaw/Hermes-style agents.

Required tools:

```text
mcp_hello
help_get
doctor
doctor_explain
error_explain
models_list
teams_list
team_show
team_preflight
team_start
team_status
team_result
team_cancel
run_show
run_export
spec_get
pending_add
pending_submit
pending_edit
pending_reorder
pending_list
pending_show
pending_cancel
pending_run
pending_stop
history_search
```

Deferred tools:

```text
dispatch_start
dispatch_reveal
team_edit
skill_edit
entitlement_status
```

First demo minimum:

```text
mcp_hello
help_get
doctor
doctor_explain
error_explain
teams_list
team_show
team_preflight
team_start
team_status
team_result
team_cancel
spec_get
```

Pending tools should ship in the same phase immediately after the async team
loop, because Pending is the agent-first "put it on the desk later" unlock.

`help_get` topics:

```text
quickstart
tool_selection
schemas
teams
lanes
effort
pending
errors
doctor
approval
examples
```

`help_get(topic: "tool_selection")` must return a concise, machine-readable
decision guide. Agents should not infer this from marketing prose.

Tool selection rules:

| User intent | Preferred tool | Notes |
| --- | --- | --- |
| "review this", "hunt bugs", "audit security", "give me options" | `team_preflight` then `team_start` | Use lane/team/effort explicitly. |
| "do this later", "when Claude wakes up", "put this on Codex's desk" | `pending_add(submit: true)` | Preserve user intent without claiming it started. |
| "show the full plan/spec/packet" | `spec_get` | Do not overload chat summaries. |
| "what teams can do this?" | `teams_list` / `team_show` | Return lane-scoped teams only. |
| invalid args or failed tool call | `error_explain` | Retry once only when metadata gives an exact correction. |
| setup/auth/config issue | `doctor` / `doctor_explain` | Auto-fix only Allnighter-owned state. |

Agents must not call `dispatch_start` or any future mutating execution tool
unless a prior tool result returned an explicit approval object for the exact
canonical action digest.

`team_preflight` input:

```json
{
  "lane": "build",
  "team": "build_bug_hunt",
  "effort": "high",
  "prompt": "optional prompt for context sizing and policy checks",
  "contextRefs": ["optional artifact/ref ids"],
  "originAgent": "openclaw",
  "originConversationId": "telegram_chat_12345",
  "originMessageId": "msg_..."
}
```

`team_preflight` output:

```json
{
  "canStart": true,
  "lane": "build",
  "teamPresetId": "build_bug_hunt",
  "teamDisplayName": "Bug Hunt",
  "effort": "high",
  "readyWorkers": [
    {"workerId": "w_claude", "source": "claude", "status": "ready"}
  ],
  "degradedWorkers": [],
  "blockedWorkers": [],
  "selfFusion": {
    "enabled": true,
    "reason": "Only one ready Build source; prompts will run with different lenses."
  },
  "entitlement": {
    "canStartTeamRun": true,
    "blockedReason": null
  },
  "warnings": [],
  "nextAction": {"kind": "startTeamRun", "tool": "team_start"},
  "traceId": "trace_..."
}
```

Preflight rules:

- Preflight never creates a run.
- Preflight never spends provider quota.
- Preflight must validate lane/team/effort, team lane ownership, context caps,
  entitlement readiness, coordinator readiness, and source/admission state.
- Preflight may use cached source health if `observedAt` and `staleAfter` are
  returned.
- A failed `team_start` caused by preflight-detectable setup/auth/config issues
  is a bug in the implementation.

`team_start` input:

```json
{
  "prompt": "string",
  "lane": "build",
  "team": "build_bug_hunt",
  "effort": "high",
  "threadId": "optional",
  "context": "optional bounded inline context",
  "contextRefs": ["optional artifact/ref ids"],
  "originAgent": "openclaw",
  "originConversationId": "telegram_chat_12345",
  "originMessageId": "msg_...",
  "idempotencyKey": "optional client-generated key"
}
```

`team_start` output:

```json
{
  "runId": "run_...",
  "status": "accepted|running",
  "lane": "build",
  "teamPresetId": "build_bug_hunt",
  "teamDisplayName": "Bug Hunt",
  "effort": "high",
  "acceptedAt": "2026-06-16T08:00:00Z",
  "nextPollAfterMs": 2500,
  "nextActions": [
    {"kind": "poll", "tool": "team_status", "runId": "run_..."},
    {"kind": "result", "tool": "team_result", "runId": "run_..."}
  ]
}
```

`team_start` rules:

- Must call the same Core path as CLI/GUI run start.
- Must run preflight internally before returning "started."
- Must not return a run id when entitlement, team resolution, context caps, or
  required source/admission checks block the run.
- Must record origin metadata where provided.
- Must write an incremental run journal before worker execution begins.
- Must be idempotent when `idempotencyKey` is supplied.
- Must return the existing `runId` for the same idempotency key and equivalent
  canonical payload during the idempotency retention window.
- Must reject the same idempotency key with a different canonical payload as
  `IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD`.

`team_status` output:

```json
{
  "runId": "run_...",
  "status": "accepted|running|synthesizing|completed|failed|cancelled|interrupted",
  "lane": "build",
  "teamPresetId": "build_bug_hunt",
  "effort": "high",
  "currentStage": "answer|review|plan|null",
  "workers": [
    {
      "workerId": "w_claude_bug_lens",
      "displayName": "Bug Hunter",
      "status": "waiting|running|completed|failed|timedOut|cancelled",
      "startedAt": "2026-06-16T08:00:01Z",
      "finishedAt": null,
      "warning": null
    }
  ],
  "warnings": [],
  "resultAvailable": false,
  "nextPollAfterMs": 5000,
  "traceId": "trace_..."
}
```

Polling rules:

- Clients should honor `nextPollAfterMs`.
- Server may return larger delays for long-running work.
- Do not expose fake progress percentages.
- Do not report orphaned async runs as still `running`; resolve them to
  `interrupted` with a sourced reason.
- Terminal statuses are `completed`, `failed`, `cancelled`, and `interrupted`.
- `team_result` is valid only when `resultAvailable` is true or the status is
  terminal.

`team_result` returns `TeamRunJSON` or a compact projection selected by a
`detail` parameter:

```text
detail: summary | full | artifactRefsOnly
```

Default for messaging agents should be `summary` plus artifact references. Full
spec retrieval is explicit through `spec_get` or `team_result(detail: full)`.

Payload rules:

- Inline prompt/context payloads must have a documented byte cap.
- Large context must be passed as `contextRefs` or artifacts, not enormous tool
  arguments.
- Large outputs should return `artifactRefs` and short summaries by default.
- `history_search`, `pending_list`, and any list/history tool must support
  `limit` and `cursor`.
- Errors caused by caps must include `maxBytes`, `actualBytes` when safe, and a
  suggested artifact/ref path.

## Pending Over MCP

Expose the simple Pending surface to MCP.

The tool names use Pending, not queue:

```text
pending_add
pending_submit
pending_edit
pending_reorder
pending_list
pending_show
pending_cancel
pending_run
pending_stop
```

`pending_add` creates Draft or Pending work depending on `submit`.

Example:

```json
{
  "prompt": "When Claude is available, have Bug Hunt inspect the latest run-store issue.",
  "kind": "teamRun",
  "lane": "build",
  "team": "build_bug_hunt",
  "effort": "high",
  "submit": true,
  "policy": {
    "drainMode": "drainWhenReady",
    "attentionMode": "away",
    "allowPartialTeam": true
  },
  "originAgent": "openclaw",
  "originConversationId": "telegram_chat_12345",
  "idempotencyKey": "pending-telegram_chat_12345-msg_999"
}
```

`pending_list` returns:

```json
{
  "draft": [],
  "pending": [
    {
      "id": "pending_...",
      "title": "Bug Hunt latest run-store issue",
      "kind": "teamRun",
      "status": "pending",
      "blockedReason": "Claude cooling down until 2:14 AM, observed from Claude",
      "target": {"lane": "build", "team": "build_bug_hunt", "effort": "high"}
    }
  ],
  "running": []
}
```

MCP must not expose internal execution-lane ordering as the user's mental model.
If ordering matters, show it as Pending item order with a sourced reason.

Pending MCP rules:

- `pending_add` must be idempotent when `idempotencyKey` is supplied.
- `pending_add(submit: false)` creates Draft; it does not imply work will run.
- `pending_add(submit: true)` creates Pending; it still does not imply work has
  started.
- `pending_submit` moves Draft to Pending.
- `pending_edit` returns the item to Draft unless the owning Pending doc defines
  a narrower safe edit.
- `pending_reorder` is allowed only for Pending items in the same execution lane.
- `pending_run` starts an eligible item only if admission, source, team, and
  entitlement gates pass.
- `pending_stop` stops a Running attempt and returns the item to Pending with a
  sourced reason.
- `pending_list` must accept `limit`, `cursor`, and optional status filters.
- Every blocked Pending item must include `blockedReason`, `blockedSource`,
  `observedAt`, and, when known, `retryAfter`.

Agent phrasing rules:

- Say "Added to Pending" when the item is waiting.
- Say "Running" only after `pending_show` or `pending_list` returns Running.
- Never say "queued" to the user unless showing debug/internal output.
- Never translate a scheduler/admission block into vague delay language; preserve
  the sourced reason.

## Full Spec Retrieval

Messaging agents must be able to retrieve and present complete outputs without
asking the user to open the Mac app.

`spec_get` inputs:

```json
{
  "runId": "optional",
  "pendingId": "optional",
  "threadId": "optional",
  "selector": "latest|plan|finalSpec|bugPacket|securityRegister|designBoard|copyBoard",
  "detail": "summary|full|artifactRefsOnly",
  "limit": 20,
  "cursor": "optional"
}
```

Rules:

- `summary` is optimized for chat presentation.
- `full` returns complete markdown or structured JSON where available.
- `artifactRefsOnly` returns local paths/ids for agents that will fetch/export.
- Failed workers and warnings are always included in full detail.
- The agent may present a concise answer, but must be able to reveal the full
  packet on request.
- `full` may still return chunked content when size caps require it; the response
  must include `nextCursor` and stable artifact references.
- `spec_get` must not require a running GUI or visible app window.

Example voice-first presentation:

```text
Bug Hunt finished.

Likely owner: RunStore incremental persistence.
Minimal fix: journal every worker/status transition, mark orphaned runs
interrupted on next read.
Proof: interruption test + history reload test.

I can show the full packet or put the fix on Codex's desk.
```

## Messaging / Voice UX Contract

A messaging agent should not stream every intermediate thought. It should make
the run feel fast, controlled, and recoverable.

Start acknowledgement:

```text
Started Bug Hunt / High. Run: run_abc123.
I will bring back the packet when the team finishes.
```

Pending acknowledgement:

```text
Added to Pending for Claude. It will run when admission allows.
Pending: pending_abc123.
```

Completion:

```text
Bug Hunt found a likely fix. I have the full packet.
Want the short version, full spec, or should I create a Pending follow-up?
```

Setup blocked:

```text
Allnighter is almost ready, but Claude Code needs to be reconnected before Bug
Hunt can run.

Run this on the Mac:
claude auth login

Then tell me "done" and I will recheck.
```

Device auth handoff:

```text
Claude Code authentication expired. Open this link on your phone:
https://example.com/device

Enter code: ABCD-EFGH

This code expires in 5 minutes. Say "done" when finished and I will recheck.
```

Wrong arguments recovered:

```text
Allnighter rejected effort="medium"; valid values are low, med, high.
I retried with med.
```

Entitlement blocked:

```text
Allnighter cannot start another team run on the current plan.
Free runs are used up. I can still show existing specs or add Draft work, but a
new team run needs the account upgraded.
```

Still running:

```text
Bug Hunt is still running. Two workers are done, one is still reviewing.
I will check again in about 30 seconds.
```

Risky approval required:

```text
I can prepare that file change, but I need explicit approval before any agent
mutates files.

Action: apply the Bug Hunt fix in /path/to/repo
Approval id: approval_abc123
```

Rules:

- Acknowledge run id or pending id immediately.
- Name lane/team/effort when a team run starts.
- Keep chat summaries short by default.
- Offer full spec retrieval.
- Do not hide failed workers.
- Do not invent progress percentages.
- Do not imply that Pending has started when it is waiting.
- Retry invalid arguments only when the error metadata gives one exact safe
  correction.
- Ask the user before retrying when a correction changes lane, team, target
  directory, dispatch/execute behavior, or risk tier.
- Preserve approval ids and run ids verbatim.
- Prefer "I will recheck" over "it should be fixed" after human actions.

## OpenClaw / Hermes Integration Shape

This phase does not depend on private APIs from any one agent project.

Ship generic artifacts that messaging-first agents can consume:

```text
docs/generated/alln/mcp-tools.json
docs/generated/alln/agent-quickstart.md
docs/generated/alln/agent-tool-selection.md
docs/generated/alln/agent-error-recovery.md
docs/generated/alln/openclaw.example.md
docs/generated/alln/hermes.example.md
```

Install helpers:

```bash
alln mcp install --target openclaw --print
alln mcp install --target hermes --print
alln doctor --agent openclaw --json
alln doctor --agent hermes --json
alln doctor explain mcp.clientApproved.openclaw --json
```

The install helper prints config and instructions first. Editing another
agent's config requires explicit user consent.

Agent prompt guidance:

```text
Use Allnighter when the user's request benefits from multiple perspectives,
review, bug hunting, security review, design options, copy variants, Pending
work, or full spec retrieval.

Prefer team_start for long work.
Use pending_add when the user wants work done later or when admission blocks.
Use spec_get when the user asks to see the full plan/spec/packet.
Never call dispatch/execute tools without explicit user approval.
```

Minimum generated agent instructions:

```text
1. Call mcp_hello before using Allnighter in a new session.
2. If canStartTeamRun is false, call doctor with agent=<your agent id>.
3. If doctor returns alln_auto_fixable fixes, call doctor(autoFix=true) once,
   then re-run doctor.
4. If doctor returns humanActions, present those exact messages and wait for the
   user to say they are done.
5. Use team_preflight before team_start for team runs.
6. Use idempotencyKey for every team_start and pending_add initiated from a chat
   message.
7. Poll using nextPollAfterMs.
8. Use spec_get for full packets instead of asking the user to open the GUI.
9. Never hide failed workers or warnings.
10. Never treat originAgent as proof of identity or approval.
```

Named examples are required, not just generic MCP docs. Generic MCP descriptors
are the source; OpenClaw/Hermes examples are developer-activation material.

## Safety and Provenance

Always-on messaging agents are powerful because they combine memory, tools,
identity, scheduling, and local action. That is also the risk.

Every agent-originated request records:

```text
origin: mcp | localApi
originAgent: openclaw | hermes | codex | claude | other
originConversationId?
originMessageId?
originClientInstallId?
receivedAt
requestedTool
canonicalActionDigest
```

`originAgent` is advisory provenance only. It is useful for logs, generated
instructions, and debugging. It is not authentication, authorization, entitlement,
or approval.

Trust decisions must bind to:

```text
local MCP client approval
installed client/config identity where available
user/account entitlement
explicit approval objects for risky actions
canonical action digest
```

Risk tiers:

```text
Planning/team run/spec retrieval: allowed after agent install.
Pending ask/teamRun: allowed after agent install.
Pending execute/dispatch: requires explicit approval policy.
Mutating filesystem/process/session actions: reveal-only by default.
Credentials/Keychain/permissions/network exposure: high-risk stop.
```

Approval rule:

```text
Approval binds to the canonical action instance, not a vague paraphrase.
```

If the prompt, target worker, working directory, action kind, or risk surface
changes, approval must be requested again.

Reveal-only handoff object:

```json
{
  "approvalRequired": true,
  "approvalId": "approval_abc123",
  "riskTier": "filesystem_mutation",
  "canonicalActionDigest": "sha256:...",
  "actionSummary": "Apply the Bug Hunt fix in /Users/mike/project",
  "revealPayload": {
    "kind": "patch|command|workOrder",
    "contentRef": "artifact://run_abc123/reveal.patch",
    "preview": "Short safe summary for chat"
  },
  "approvalMethods": [
    {"kind": "gui", "label": "Approve in Allnighter"},
    {"kind": "cli", "command": "alln approve approval_abc123"},
    {"kind": "chatConfirm", "phrase": "approve approval_abc123"}
  ],
  "expiresAt": "2026-06-16T09:00:00Z"
}
```

Approval rules:

- Approval must be explicit and unambiguous.
- Approval ids are single-use unless the owning safety doc defines a narrower
  repeatable policy.
- Chat approval is valid only when the MCP client/session has been approved for
  chat-confirm approvals.
- A changed digest invalidates previous approval.
- High-risk stops from `AGENTS.md` still require human confirmation and may be
  GUI/CLI-only even if chat-confirm is enabled.

## Commercial / Entitlement Intent

Founder intent:

```text
Agent-originated runs use the same pricing model as GUI/CLI runs.
Give X free runs, then paid service.
```

This phase does not implement billing or choose the value of X. Exact pricing,
meter definitions, billing provider, receipts, offline grace, and entitlement
enforcement require a dedicated billing/entitlement SSOT before code changes.

Durable rules for this phase:

- Do not make MCP/OpenClaw/Hermes a free bypass.
- Do not let `originAgent` choose pricing or entitlement behavior.
- Do not price by guessed tokens, runtime, or quota burn.
- Count product actions the user understands, such as team runs or completed
  result packets, once the billing SSOT defines them.
- Show entitlement blocks as honest actionable errors.
- Keep local/private data local; billing metadata must not include prompt
  content or worker output.

Suggested future contract shape:

```text
EntitlementStatus
- plan
- freeRunsRemaining?
- periodEndsAt?
- canStartTeamRun
- blockedReason?
- upgradeAction?
```

Recommended future meter for the billing SSOT to consider:

```text
Count one paid/free run when Allnighter delivers a terminal team result packet
with synthesis, or when a Pending item drains into such a result packet.
```

Recommended non-counted actions:

```text
mcp_hello
help_get
doctor / doctor_explain / error_explain
team_preflight
teams_list / team_show / models_list
spec_get for already-created artifacts
pending_add(submit: false)
pending_add(submit: true) before it starts/drains
idempotent retry of an already-counted action
failed starts blocked by setup/auth/admission before worker execution
```

This is not a pricing commitment. It is the product-trust default: users should
not lose free/paid runs because their local CLI auth expired before Allnighter
could do useful orchestration.

Even before billing exists, `team_start` and `pending_run` must call a shared
entitlement/preflight interface so the integration point is impossible to forget
later.

## Implementation Slices

### A-1 - Bootstrap, doctor, help, and recovery

This slice must land before broad MCP expansion.

- Add `mcp_hello`.
- Add `help_get` with `quickstart`, `tool_selection`, `schemas`, `errors`,
  `doctor`, `pending`, `approval`, and `examples` topics.
- Upgrade `DoctorResult` to schema version 2 with `canStartTeamRun`,
  `readyTeams`, `blockedReason`, `nextAction`, `fixes`, `appliedFixes`,
  `humanActions`, `entitlement`, `observedAt`, `staleAfter`, and `traceId`.
- Add remedy tiers: `alln_auto_fixable`, `agent_executable`,
  `user_interactive`, `cannot_fix`.
- Add `doctor_explain` and `error_explain`.
- Add `alln doctor --agent <agent> --json`.
- Add MCP `doctor(agent, full, autoFix, quiet)` parity.
- Add agent-first checks: MCP descriptors/docs, client approval, named agent
  config, coordinator, incremental journal, Pending store, admission parsers,
  default teams, selected team validity, entitlement preflight.
- Implement safe `doctor(autoFix: true)` for Allnighter-owned state only.
- Return structured human actions for provider auth, Keychain, macOS permission,
  and manual-command blockers.
- Generate `agent-error-recovery.md`.

Completion gate:

- A cold setup can be diagnosed.
- All Allnighter-owned safe fixes can be applied once.
- The second doctor call deterministically reports `canStartTeamRun` or a stable
  `blockedReason`.

### A0 - Agent-facing MCP async team loop

- Add `team_preflight`, `team_start`, `team_status`, `team_result`,
  `team_cancel`.
- Project descriptors from the command registry.
- Return run id immediately only after internal preflight passes.
- Support `detail: summary | full | artifactRefsOnly`.
- Include `originAgent`, `originConversationId`, `originMessageId`, and
  `originClientInstallId` when available.
- Require idempotency support for `team_start`.
- Include `nextPollAfterMs` in `team_start` and `team_status`.
- Enforce context/payload caps and artifact refs.
- Ensure async run journal writes before worker execution begins.
- Ensure orphaned async runs resolve to `interrupted`.

Completion gate:

- `team_preflight` catches setup/auth/team/context/entitlement blockers before
  `team_start`.
- `team_start` never says "started" if Core would reject the run.
- `team_status` needs no invented client-side polling policy.

### A1 - Pending over MCP

- Add `pending_add`, `pending_submit`, `pending_edit`, `pending_reorder`,
  `pending_list`, `pending_show`, `pending_cancel`, `pending_run`,
  `pending_stop`.
- Use Pending model from `Pending_Work_And_Drain.md`.
- Expose Draft/Pending/Running; do not expose raw scheduler queue.
- Include blocked/admission reasons, source, `observedAt`, and `retryAfter`.
- Add `limit` and `cursor` to `pending_list`.
- Require idempotency support for `pending_add`.
- Keep edit/reorder semantics identical to the CLI Pending contract.

Completion gate:

- Agents can create, inspect, submit, cancel, stop, and reorder Pending work
  without learning scheduler internals.
- A Pending item blocked by admission can be explained in one chat-safe sentence.

### A2 - Full spec retrieval

- Add `spec_get`.
- Support run id, pending id, thread id, and latest selectors.
- Return summary/full/artifact refs.
- Include warnings and failed workers in full detail.
- Support `limit`/`cursor` for large full packets.
- Return stable artifact refs for large packets.

Completion gate:

- A messaging agent can present a short answer and then retrieve the complete
  packet without opening the GUI.

### A3 - Agent install artifacts

- Generate MCP tool docs.
- Generate `agent-quickstart.md`, `agent-tool-selection.md`,
  `agent-error-recovery.md`.
- Generate OpenClaw/Hermes example configs.
- Add `alln mcp install --target <agent> --print`.
- Add `alln doctor --agent <agent> --json`.
- Do not auto-edit external agent config without consent.

Completion gate:

- A developer can wire OpenClaw/Hermes from generated artifacts without reading
  source code.

### A4 - Messaging UX examples

- Add generated quickstart examples for voice-to-text workflows.
- Include recommended agent prompt.
- Include example Telegram-style start, Pending, completion, auth handoff,
  entitlement block, invalid-args retry, and full-spec reveal messages.
- Include "how long is it taking?" status examples using `nextPollAfterMs`.

Completion gate:

- A messaging agent can produce polished, concise chat messages without inventing
  product language.

### A5 - Provenance and safety gate

- Record origin agent and source message metadata where available.
- Add canonical action digest to risky requests.
- Treat `originAgent` as advisory only.
- Default mutating tools to reveal-only until approved by owning phase docs.
- Add reveal-only handoff object.
- Add high-risk stop errors that agents can present cleanly.

Completion gate:

- A risky action can be prepared and shown without mutating local state.
- Approval is bound to the exact action digest.

### A6 - Entitlement hook, no billing implementation

- Add placeholder entitlement status shape behind a feature flag or interface.
- Ensure MCP and CLI run-start paths call the same entitlement gate when billing
  is implemented.
- Ensure `team_preflight`, `team_start`, and `pending_run` all surface
  entitlement blocks in the same shape.
- Do not choose X or wire payments in this phase.

Completion gate:

- Future billing cannot be bypassed by MCP because the preflight/start hook is
  already shared.

## Works Tests

### Works Test A - cold start self-heals Allnighter-owned state

Setup:

```text
Allnighter config/runs dirs are missing.
MCP server can start.
No external CLI installs or auth changes are required.
```

Gesture:

```text
Client calls mcp_hello, then doctor(agent: "openclaw", autoFix: true), then
doctor(agent: "openclaw").
```

Assertions:

- First result has `canStartTeamRun: false` or `degraded` with
  `alln_auto_fixable` fixes.
- Auto-fix creates only Allnighter-owned dirs/files.
- Second result has `canStartTeamRun: true` or a stable external
  `blockedReason`.
- No external CLI install/auth/Keychain change occurs.

### Works Test B - auth failure becomes a phone-safe human action

Setup:

```text
Claude/Grok/etc. auth probe reports expired auth.
Provider device/browser flow is mocked when available.
```

Gesture:

```text
Client calls team_preflight for Build Bug Hunt.
```

Assertions:

- Preflight does not start a run.
- Response includes `humanActions`.
- If safe device flow exists, action includes `authUrl`, `userCode`,
  expiry, and recheck command.
- If no safe device flow exists, action gives the exact terminal/manual login
  instruction.
- No secret token is logged or returned.

### Works Test C - invalid tool arguments are self-correctable

Gesture:

```text
Client calls team_start with effort "medium".
```

Assertions:

- Error code is structured, e.g. `INVALID_ENUM`.
- Error metadata includes `field: effort` and allowed values
  `["low", "med", "high"]`.
- `error_explain` returns a safe retry action.
- Retrying with `med` can pass preflight.
- No retry is suggested for ambiguous lane/team changes.

### Works Test D - voice dump starts team run

Setup:

```text
MCP server running.
OpenClaw/Hermes-style client can call MCP tools.
Build Bug Hunt team exists.
Doctor reports canStartTeamRun true.
```

Gesture:

```text
Client calls team_preflight, then team_start with a long prompt, lane build,
team build_bug_hunt, effort high, originAgent openclaw, and idempotencyKey.
```

Assertions:

- Preflight passes without spending provider quota.
- `team_start` returns run id immediately.
- Run records origin metadata.
- `team_status` can inspect it and returns `nextPollAfterMs`.
- `team_result(detail: full)` returns TeamRunJSON.

### Works Test E - idempotent retry does not duplicate work

Gesture:

```text
Client calls team_start twice with the same idempotency key and same canonical
payload, then once with the same key and changed prompt.
```

Assertions:

- First two calls return the same `runId`.
- Only one run is created.
- Changed payload returns `IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD`.
- Error does not echo sensitive prompt content.

### Works Test F - status polling is bounded and honest

Gesture:

```text
Client polls team_status through accepted, running, synthesizing, and terminal
states.
```

Assertions:

- Every nonterminal status includes `nextPollAfterMs`.
- No fake progress percentage is returned.
- Failed/timed-out workers remain visible.
- Simulated coordinator interruption resolves the run to `interrupted`.
- `team_result` is available only after terminal/result-available state.

### Works Test G - Pending over MCP

Gesture:

```text
Client calls pending_add with submit true for Build Bug Hunt.
```

Assertions:

- Pending item is created idempotently.
- `pending_list(limit, cursor)` shows it under Pending.
- Blocked/admission reasons are structured and sourced.
- No raw queue terminology is required for user presentation.
- `pending_reorder` is accepted only within the same execution lane.

### Works Test H - full spec retrieval

Gesture:

```text
Client calls spec_get for latest bug packet.
```

Assertions:

- Summary is concise.
- Full detail includes the complete packet, warnings, failed workers, and
  artifact refs.
- Large packets return `nextCursor` or artifact refs.
- Agent can present either short version or full packet.

### Works Test I - no pricing bypass

Setup:

```text
Entitlement gate test double blocks team starts.
```

Assertions:

- `team_preflight`, MCP `team_start`, CLI start, GUI start, and `pending_run`
  surface the same entitlement block shape.
- MCP `team_start` is blocked before returning a run id.
- Error has upgrade/recovery action.
- Prompt content is not included in billing metadata.

### Works Test J - risky execute is reveal-only

Gesture:

```text
Messaging agent attempts mutating dispatch without approval.
```

Assertions:

- Tool refuses or returns reveal-only handoff.
- Response names required approval.
- Approval object has digest, approval id, reveal payload, and expiry.
- No worker is allowed to mutate files.

### Works Test K - generated help prevents schema guessing

Gesture:

```text
Client calls help_get(topic: "tool_selection") and help_get(topic: "schemas").
```

Assertions:

- Tool selection guide names when to use team_start, pending_add, spec_get,
  doctor, and error_explain.
- Schemas include valid lane/team/effort enums or refs.
- Generated docs version matches binary contract.

## Proof Commands

Core/package proof:

```bash
swift test
```

Generated contract drift:

```bash
alln dev export-contracts --check
```

Manual MCP smoke:

```bash
alln mcp serve --stdio
```

Manual agent recovery smoke:

```bash
alln doctor --agent openclaw --json
alln doctor explain mcp.clientApproved.openclaw --json
```

Missing proof until implementation:

- no `mcp_hello` tool;
- no agent-ready doctor schema v2;
- no OpenClaw/Hermes example artifacts;
- no MCP async team tools;
- no MCP Pending tools;
- no `spec_get` tool;
- no entitlement interface;
- no messaging UX examples.

## Done When

- A messaging-first agent can call `mcp_hello` and know whether Allnighter can
  start a team run.
- If setup is broken, the same agent can run safe auto-fixes once or present
  exact human actions.
- A messaging-first agent can preflight and start a team run through MCP and get
  a run id without opening the GUI.
- The same agent can inspect status using server-provided polling cadence and
  fetch full results/specs.
- Pending Draft/Pending/Running is exposed through MCP.
- The agent can add work to Pending and later present Activity/blocked reasons.
- All MCP tools are generated/projected from the same registry as CLI.
- Agent-originated runs record provenance without treating provenance as trust.
- Risky mutating actions are reveal-only or approval-gated.
- MCP/OpenClaw/Hermes paths cannot bypass pricing/entitlement once billing
  exists.
- The Mac GUI is no longer required for the happy path, only for setup,
  settings, floor visibility, and explicit approvals when policy requires them.

## Resolved Decisions

- First demo minimum is bootstrap/doctor/help plus async team lifecycle and
  `spec_get`; Pending ships immediately after in the same phase because it is a
  core agent-first workflow.
- `spec_get` remains a separate tool. `team_result(detail: full)` may return full
  run output, but `spec_get` is the generic long-lived artifact/spec retriever.
- Generated named examples for OpenClaw and Hermes ship alongside generic MCP
  descriptors.
- Agents must call `team_preflight` before `team_start` in recommended flows.
- `originAgent` is provenance, not a security boundary.
- Pricing is not implemented here; no MCP path may bypass the future shared
  entitlement gate.

## Remaining Open Questions

- Billing SSOT must choose X free runs and the exact paid-run meter.
- Provider-by-provider auth probes must confirm whether official device/browser
  flows can be safely captured.
- The safety/approval owner doc must decide whether chat-confirm approvals are
  enabled by default or require opt-in.
- The named agent examples should be refreshed whenever OpenClaw/Hermes config
  conventions change.
