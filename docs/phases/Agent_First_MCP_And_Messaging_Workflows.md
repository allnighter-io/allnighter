# Agent-First MCP and Messaging Workflows

Status: Draft feature packet for mentor review
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
-> agent calls Allnighter MCP `team_start`
-> Allnighter starts Build / Bug Hunt / High
-> agent receives run id immediately
-> agent polls or subscribes to status
-> agent fetches final TeamRunJSON + full spec/packet
-> agent presents concise result and exact next actions in chat
```

Second slice:

```text
user says "put this on Claude's desk when it wakes up"
-> agent calls Allnighter MCP `pending_add`
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
- No OpenClaw/Hermes install artifact exists.
- No messaging/voice result contract exists.
- No agent identity/provenance model exists for always-on messaging agents.
- Pricing/entitlement for agent-originated runs is not specified in a billing
  owner doc.

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
doctor
models_list
teams_list
team_show
team_start
team_status
team_result
team_cancel
run_show
run_export
spec_get
pending_add
pending_submit
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

`team_start` input:

```json
{
  "prompt": "string",
  "lane": "build",
  "team": "build_bug_hunt",
  "effort": "high",
  "threadId": "optional",
  "context": "optional bounded context",
  "originAgent": "openclaw",
  "idempotencyKey": "optional client-generated key"
}
```

`team_start` output:

```json
{
  "runId": "run_...",
  "status": "queued|running",
  "lane": "build",
  "teamPresetId": "build_bug_hunt",
  "teamDisplayName": "Bug Hunt",
  "effort": "high",
  "nextActions": [
    {"kind": "poll", "tool": "team_status", "runId": "run_..."},
    {"kind": "result", "tool": "team_result", "runId": "run_..."}
  ]
}
```

`team_result` returns `TeamRunJSON` or a compact projection selected by a
`detail` parameter:

```text
detail: summary | full | artifactRefsOnly
```

Default for messaging agents should be `summary` plus artifact references. Full
spec retrieval is explicit through `spec_get` or `team_result(detail: full)`.

## Pending Over MCP

Expose the simple Pending surface to MCP.

The tool names use Pending, not queue:

```text
pending_add
pending_submit
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
  }
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
  "detail": "summary|full|artifactRefsOnly"
}
```

Rules:

- `summary` is optimized for chat presentation.
- `full` returns complete markdown or structured JSON where available.
- `artifactRefsOnly` returns local paths/ids for agents that will fetch/export.
- Failed workers and warnings are always included in full detail.
- The agent may present a concise answer, but must be able to reveal the full
  packet on request.

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

Rules:

- Acknowledge run id or pending id immediately.
- Name lane/team/effort when a team run starts.
- Keep chat summaries short by default.
- Offer full spec retrieval.
- Do not hide failed workers.
- Do not invent progress percentages.
- Do not imply that Pending has started when it is waiting.

## OpenClaw / Hermes Integration Shape

This phase does not depend on private APIs from any one agent project.

Ship generic artifacts that messaging-first agents can consume:

```text
docs/generated/alln/mcp-tools.json
docs/generated/alln/agent-quickstart.md
docs/generated/alln/openclaw.example.md
docs/generated/alln/hermes.example.md
```

Install helpers:

```bash
alln mcp install --target openclaw --print
alln mcp install --target hermes --print
alln doctor --agent openclaw --json
alln doctor --agent hermes --json
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

## Safety and Provenance

Always-on messaging agents are powerful because they combine memory, tools,
identity, scheduling, and local action. That is also the risk.

Every agent-originated request records:

```text
origin: mcp | localApi
originAgent: openclaw | hermes | codex | claude | other
originConversationId?
originMessageId?
receivedAt
requestedTool
canonicalActionDigest
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

## Implementation Slices

### A0 - Agent-facing MCP async team tools

- Add `team_start`, `team_status`, `team_result`, `team_cancel`.
- Project descriptors from the command registry.
- Return run id immediately.
- Support `detail: summary | full | artifactRefsOnly`.
- Include `originAgent`.

### A1 - Pending over MCP

- Add `pending_add`, `pending_submit`, `pending_list`, `pending_show`,
  `pending_cancel`, `pending_run`, `pending_stop`.
- Use Pending model from `Pending_Work_And_Drain.md`.
- Expose Draft/Pending/Running; do not expose raw scheduler queue.
- Include blocked/admission reasons.

### A2 - Full spec retrieval

- Add `spec_get`.
- Support run id, pending id, thread id, and latest selectors.
- Return summary/full/artifact refs.
- Include warnings and failed workers in full detail.

### A3 - Agent install artifacts

- Generate MCP tool docs.
- Generate OpenClaw/Hermes example configs.
- Add `alln mcp install --target <agent> --print`.
- Add `alln doctor --agent <agent> --json`.
- Do not auto-edit external agent config without consent.

### A4 - Messaging UX examples

- Add generated quickstart examples for voice-to-text workflows.
- Include recommended agent prompt.
- Include example Telegram-style start, Pending, completion, and full-spec
  reveal messages.

### A5 - Provenance and safety gate

- Record origin agent and source message metadata where available.
- Add canonical action digest to risky requests.
- Default mutating tools to reveal-only until approved by owning phase docs.
- Add high-risk stop errors that agents can present cleanly.

### A6 - Entitlement hook, no billing implementation

- Add placeholder entitlement status shape behind a feature flag or interface.
- Ensure MCP and CLI run-start paths call the same entitlement gate when billing
  is implemented.
- Do not choose X or wire payments in this phase.

## Works Tests

### Works Test A - voice dump starts team run

Setup:

```text
MCP server running.
OpenClaw/Hermes-style client can call MCP tools.
Build Bug Hunt team exists.
```

Gesture:

```text
Client calls team_start with a long prompt, lane build, team build_bug_hunt,
effort high, originAgent openclaw.
```

Assertions:

- Tool returns run id immediately.
- Run records originAgent.
- `team_status` can inspect it.
- `team_result(detail: full)` returns TeamRunJSON.

### Works Test B - Pending over MCP

Gesture:

```text
Client calls pending_add with submit true for Build Bug Hunt.
```

Assertions:

- Pending item is created.
- `pending_list` shows it under Pending.
- Blocked/admission reasons are structured.
- No raw queue terminology is required for user presentation.

### Works Test C - full spec retrieval

Gesture:

```text
Client calls spec_get for latest bug packet.
```

Assertions:

- Summary is concise.
- Full detail includes the complete packet, warnings, failed workers, and
  artifact refs.
- Agent can present either short version or full packet.

### Works Test D - no pricing bypass

Setup:

```text
Entitlement gate test double blocks team starts.
```

Assertions:

- MCP `team_start` is blocked the same way CLI/GUI starts are blocked.
- Error has upgrade/recovery action.
- Prompt content is not included in billing metadata.

### Works Test E - risky execute is reveal-only

Gesture:

```text
Messaging agent attempts mutating dispatch without approval.
```

Assertions:

- Tool refuses or returns reveal-only handoff.
- Response names required approval.
- No worker is allowed to mutate files.

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

Missing proof until implementation:

- no OpenClaw/Hermes example artifacts;
- no MCP Pending tools;
- no `spec_get` tool;
- no entitlement interface;
- no messaging UX examples.

## Done When

- A messaging-first agent can start a team run through MCP and get a run id
  without opening the GUI.
- The same agent can inspect status and fetch full results/specs.
- Pending Draft/Pending/Running is exposed through MCP.
- The agent can add work to Pending and later present Activity/blocked reasons.
- All MCP tools are generated/projected from the same registry as CLI.
- Agent-originated runs record provenance.
- Risky mutating actions are reveal-only or approval-gated.
- MCP/OpenClaw/Hermes paths cannot bypass pricing/entitlement once billing
  exists.
- The Mac GUI is no longer required for the happy path, only for setup,
  settings, and floor visibility.

## Open Questions for Mentor Review

- What is the minimum MCP tool set for a magical first OpenClaw/Hermes demo:
  `team_start/status/result` only, or include Pending in the first slice?
- Should `spec_get` be a separate tool, or should `team_result(detail: full)`
  be enough for v1?
- What is the right default agent prompt so OpenClaw/Hermes chooses Allnighter
  for fanout/review/spec work without overusing it for simple chat?
- Should the first agent install target be generic MCP only, or should we ship
  named OpenClaw/Hermes examples immediately?
- What product action should count as a paid run when billing lands: started
  team run, completed team run, result packet, or Pending-drained attempt?
- What is X free runs?
- How much provenance can messaging agents reliably provide across Telegram,
  WhatsApp, Slack, and local shells?
