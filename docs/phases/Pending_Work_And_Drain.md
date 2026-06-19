# Pending Work

Status: **Pending0 + Pending1 BUILT** (2026-06-17); Wake Ticket resume ready spec; broad native drain/scheduling parked
Owner: AllnighterCore + AllnighterEngine + Mac app backend
Updated: 2026-06-19

## Scope Correction

Allnighter is **not** building a native scheduler/run-loop product in v1.

Pending's active job is durable, Project-scoped work intent:

```text
write it down
keep it editable
keep it scoped to the Project
let a human, CLI, GUI, MCP client, or external loop owner run it later
```

OpenClaw, Hermes, cron, or another agent may own schedules and loops, then call
Allnighter through CLI/MCP. Allnighter should be the best place to define, hold,
run, and inspect Project work; it should not compete to own every trigger.

Any sections below that describe broad automatic drain, scheduler leases, or
admission-driven away mode are parked future material unless a slice explicitly
reactivates native scheduling. Sourced one-shot cooldown resume is only allowed
through the Wake Ticket exception below.

Exception: `Stalled_Work_Watchdog.md` owns a narrow Wake Ticket slice. A Wake
Ticket is not general drain. It applies only after already-authorized work made a
real attempt and the CLI returned a sourced capacity/cooldown signal. The
resident coordinator may sleep until that observed/conservative wake and make one
same-work resume attempt. Fairness sweeps, Away Mode, global scheduling, PTY
probes, and admission ledgers remain parked.

## Founder Intent

Allnighter should let the user write the work now even when they do not want to
run it now.

The user should be able to submit work to Pending, keep it attached to the right
Project/thread, and later run it from CLI, GUI, MCP, or an external agent loop.

The product unlock:

```text
Allnighter separates intent capture from worker availability.
```

The brand-fit claim:

```text
Leave work on the Project desk. Run it when you or your agent are ready.
```

This is not quota evasion. It is local, honest, user-authorized orchestration of
the subscriptions and CLIs the user already pays for.

## Product Value

Allnighter's core promise is an agent factory that keeps Project intent orderly
while work moves across agents and time. A first-class Pending surface turns
loose intentions into durable Project work:

```text
capture intent now
-> package it as a safe work item
-> keep it Pending until a human or external agent triggers it
-> run through the same CLI/MCP/Core contract
-> show the activity receipt when it returns
```

This is especially valuable for agent-first users. A Hermes/OpenClaw-style agent
can schedule or watch externally, then call Allnighter when it wants the Project
team to run.

Default mental model:

```text
Pending is the next turn in a Project thread, not a global backlog.
```

Global Pending views exist so the user can see the whole floor, but they are
aggregate views grouped by Project. The durable Pending item belongs to exactly
one Project. Capture starts where intent is hot: the Project thread composer, a
blocked worker reply, a completed team run, or a worker return that suggests a
follow-up.

## Trusted Workflow Slice

```text
user captures several work items
-> Allnighter stores them as Pending items with explicit worker/team policy
-> user or external agent chooses when to run one
-> completed, blocked, failed, and Draft suggestions appear in Activity Summary
```

First lovable slice:

```text
Project Manager proposes a follow-up
-> user saves it as Pending instead of running now
-> Hermes/OpenClaw or the user later calls `pending_run`
-> the thread shows the completed follow-up or the new blocking reason
```

## Non-Goals

- No quota dashboard.
- No billing dashboard.
- No estimated remaining quota, runtime, cost, token burn, or task complexity.
- No provider-limit evasion, spam probing, or synthetic keepalive loops.
- No new unattended mutating dispatch in Pending v1. A Wake Ticket may resume an
  already-approved mutating attempt exactly once at the sourced wake boundary.
- No silent worker substitution.
- No cloud-owned durable Pending store.
- No provider-native chat-history dependency.
- No branch, worktree, commit, merge, or workspace-management ownership.
- No automatic creation of unapproved new work from worker suggestions.
- No broad native schedule/loop ownership in v1; one-shot Wake Tickets are the
  scoped exception.

Deferred elsewhere:

- Broad admission states, fallback policy, automatic drain, and probes are
  parked. Sourced cooldown parsing for Wake Tickets is active implementation
  prep in `Stalled_Work_Watchdog.md`.
- Work-thread storage and context packets belong to `Persistent_Work_Threads.md`
  and `threads/01_Work_Threads_MLP.md`.
- iOS reachability, sealed command inbox, and sleep/remote behavior belong to
  `ios/00_iOS_Transport_Decision.md` and the iOS spine.
- Mutating dispatch and workspace safety belong to the dispatch/work-order
  phases. Pending v1 can run explicitly requested non-mutating turns; native
  drain remains parked.

## User-Visible Claim

```text
Allnighter keeps Project work Pending until you or your agent run it.
```

Sharper product copy:

```text
Keep the Project desk loaded.
```

Useful floor copy:

```text
6 pending
Build: 3 pending
Codex: running 1 item
Copy: 2 pending
1 dispatch needs attention - working directory changed
```

Useful item copy:

```text
Pending - ready when you or your agent run it.
Follow-up is pending on the Project desk.
Pending for Bug Hunt team.
Pending - Claude is finishing the prior execute order.
Pending - sign in needed.
Pending - working directory changed.
```

Never:

```text
Claude has enough quota for this
Low-cost Pending item
Estimated reset window
We saved 63% quota
```

## Core Distinction

Draft, Pending, Running, and queue are related, not identical.

```text
Draft   = editable saved intent; not submitted and not eligible to run.
Pending = submitted intent; runnable by explicit user/CLI/GUI/MCP/external-agent trigger.
Running = active attempt.
Queue   = internal machinery for execution attempts; not product language.
```

A Pending item can create one or more queued attempts over time. A queue entry is
an execution attempt, not the durable user intent.

Public active lifecycle:

```text
Draft -> Pending -> Running
```

Result labels such as `replied`, `spec ready`, `board ready`, `exit 0`, and
`exit 1` are outcomes, not extra active states. The user never needs a public
`waiting` state. A blocked item is still Pending, with a sourced reason.

Edit rules:

- Editing a Draft keeps it Draft.
- Editing a Pending item moves it back to Draft, cancels parked wake/lease
  metadata if present,
  and requires the user to submit it to Pending again.
- Running items are not edited in place.
- Stopping a Running attempt returns the item to Pending with the latest resume
  packet and attempt summary.
- If the user wants it gone, they cancel the Pending item.

Workspace rule:

```text
Pending owns when work is submitted. It does not own where code changes land.
```

If the user wants Claude/Codex/etc. to work in a different directory, session,
branch, or worktree, they set that up in the target worker/process. Pending does
not manage branches, worktrees, commits, merges, or landing.

Execute rule:

```text
Pending may hold Execute orders, but explicit run attempts must respect FIFO per
execution lane.
```

An Execute order is work intended to let a target CLI act, not just answer. The
same user can stack five Execute orders for Claude, but Allnighter still starts
only one explicitly triggered Execute order at a time in the same execution lane.

The execution-lane rule is submission ordering only. It is not branch strategy,
worktree management, isolation, commit policy, or merge policy.

The execution-lane serialization gate is **always active in v1**, independent of
whether native drain is ever revived. It is enforced on every explicit run
trigger — `alln pending run`, the GUI run action, and MCP `pending_run`: a lane
has at most one Running Execute item, and a run request for an Execute item that
is not the head of a busy lane is refused with reason `executionLaneBusy`. It
never starts a second concurrent Execute in the same lane. The full gate is the
"Execution-lane order rules" below; only that subsection is in force in v1.

An execution lane is an internal scheduler grouping. It is distinct from the
product Lane vocabulary in `Work_Order_Team_Model.md` (`Build`, `Design`,
`Copy`) and must always be qualified as "execution lane" in docs, JSON, logs, and
debug UI.

## Public CLI Decision

Pending is public CLI vocabulary, not a GUI-only label.

Required public surfaces:

```text
GUI: Draft/Pending/Running rows, add-to-Draft, submit-to-Pending, and reorder actions.
CLI: alln pending add/submit/edit/reorder/list/show/cancel/run/stop with Project
scope, backed by the same PendingItem model.
Resident: alln serve supports long/remote run coordination; native Pending drain
is parked.
```

Rules:

- GUI and iOS render Pending from Mac/Core truth; they do not own a separate
  Pending store.
- `alln pending` is the first public command family for this feature.
- Do not promise "runs while the app is closed" until native drain is explicitly
  revived.
- Queue remains internal scheduler language except in logs, debug output, and
  schema fields that represent execution attempts.
- Thread composer capture is the primary UX. Global Pending is a floor view, not
  the product's center of gravity.

Examples:

- User says "ask Claude to review this later" -> Pending item.
- Hermes/OpenClaw decides it is time -> external agent calls `pending_run`.
- Claude cools down mid-run and the item needs continuation -> same Pending item
  with a resume packet, waiting for explicit retry.
- Worker suggests "run a proof skeptic pass" -> suggested Draft item, not submitted
  until the user approves or a preset explicitly permits that suggestion class.

## Product Laws

- Pending is not failure. Pending is how Allnighter preserves Project intent
  until a user or agent runs it.
- Pending items are explicit user intent, preset intent, or approved suggestions.
- Pending items are Project-scoped. Global Pending is an aggregate view, not a
  global queue.
- Admission still owns availability. Pending must not guess quota or readiness.
- Draft items are never runnable.
- Pending items may be blocked by admission or safety, but they stay Pending in
  public UI.
- Execute items run FIFO per execution lane. Later same-execution-lane Execute
  items stay Pending until the earlier item is finished, cancelled, or explicitly
  skipped by the user.
- A worker reset time is used only when observed from provider/CLI output or
  user-entered.
- If no reset time is known, rechecks use conservative backoff and local policy;
  the UI says "will check later," not "resetting soon."
- Real work is the best probe. Do not run a separate probe when a normal queued
  attempt is allowed and would teach the same admission fact.
- Away mode follows stored policy only. It never attempts manual paste, silent
  fallback, or "try anyway."
- Mutating dispatch is deferred from Pending v1.
- A failed, skipped, blocked, or substituted worker is recorded honestly.
- Activity Summary reports actual outcomes only.

## Current State

Existing truth owners:

- `Persistent_Work_Threads.md` owns durable threads, turns, context packets, and
  run-to-thread linkage.
- Broad observed availability, fallback policy, and admission attempts are parked
  with the admission scheduler. Sourced cooldown observations for Wake Tickets
  are routed through `Stalled_Work_Watchdog.md`.
- `ios/00_iOS_Transport_Decision.md` owns phone-to-Mac command delivery,
  reachability honesty, sealed payloads, and sleep/drain behavior.
- `Work_Order_Team_Model.md` owns worker/team/lane/type/effort vocabulary.

Existing useful pieces:

- Thread turns already have `queued` and `running` internal status.
- Parked Utilization defines future scheduler behavior for cooldowns, local
  slots, fallbacks, present/away mode, and mutating dispatch safety.
- iOS docs already define "commands queue and drain on next wake" when the Mac
  is asleep.
- `Mac_Standalone_App_And_Background_Coordinator.md` now defines `alln serve` as
  the resident coordinator process.

Missing truth:

- Pending0/1 built the user-owned Pending object and public `alln pending`
  contract.
- Pending0/1 predate Project binding and must be migrated before drain claims.
- No distinction exists between durable work intent and scheduler attempts.
- `PendingResume` exists, but no capacity-observation / Wake Ticket wiring exists
  yet for "continue this exact job when Claude is available."
- No Away Mode or Activity Summary contract exists for draining user-selected work
  while the user is not actively watching.

## SSOT

Truth owner:

```text
AllnighterCore owns Pending models and semantic rules.
AllnighterEngine owns the execution-lane serialization gate (always active in v1)
and admission bridging for explicitly triggered runs. Native drain scheduling is
parked; in v1 drain is triggered externally, one item at a time.
CLI command registry owns the public alln pending grammar and JSON projection.
Mac app backend owns local persistence, safety checks, and floor snapshots.
```

Lie-prone layers:

- SwiftUI Pending views can confuse submitted intent with available capacity.
- iOS snapshots can make sleeping Mac commands look like started work.
- Scheduler code can accidentally turn retry policy into quota guessing.
- Worker-generated prose can accidentally become hidden work.
- Dispatch UI can treat "queued" as permission to write later under changed
  workspace conditions.

New/changed semantic rules:

- A Pending item is durable user intent; a queue entry is an execution attempt.
- A Pending item belongs to exactly one Project; queue attempts inherit that
  `projectId`.
- Draft means editable and not submitted; Pending means submitted and eligible
  when admitted.
- Cooldown resume is a continuation of the same Pending item unless the user
  forks it into a new item.
- Activity Summary is a receipt, not a forecast.
- Suggested follow-ups are Draft until approved or preset-authorized.

Duplicate truth to delete or avoid:

- UI-local Pending arrays that do not persist through `AllnighterCore`.
- Separate iOS Pending stores.
- GUI-only Pending commands that cannot run through `alln pending`.
- Driver-specific retry ledgers outside admission events.
- Prompt-only rules that decide unattended mutation.
- Global Pending queues that can reorder or drain across Project boundaries.

## Core Model

Truth owner: `AllnighterCore`.

```text
PendingItem
- id
- projectId
- threadId?
- workOrderId?
- title
- kind: workerChat | teamRun | workOrder | dispatch | returnReview | followUp
- status: draft | pending | running | done | failed | cancelled
- priority: pinned | normal | low
- createdAt
- updatedAt
- submittedAt?
- createdBy: user | preset | failedRun | returnReview | approvedSuggestion | remoteDevice
- prompt
- contextPacketId?
- seedTurnId?
- runId?
- stageId?
- target: PendingTarget
- policy: PendingPolicy
- execution: PendingExecution?
- safety: PendingSafety
- resume: PendingResume?
- lease: PendingLease?
- attempts: [PendingAttemptSummary]
- expiresAt?
```

```text
PendingTarget
- workerIds: [Worker.ID]
- teamPresetId?
- preferredWorkerIds: [Worker.ID]
- fallbackWorkerIds: [Worker.ID]
- requiredWorkerIds: [Worker.ID]
- minWorkers?
```

```text
PendingPolicy
- selectedOnly | allowFallbacks | allowPartialTeam | requireFullTeam
- attentionMode: present | away
- triggerMode: manual | externalAgent
- legacy drainMode?: manualStart | drainWhenReady | drainAway
- maxAttempts?
- retryFloorSeconds?
- allowDegraded: Bool
- requireKnownAvailable: Bool
- createSuggestedFollowUps: Bool
```

```text
PendingExecution
- intent: ask | execute
- executionLaneKey?
- executionLaneKeyVersion?
- executionLanePolicy: fifo | userOrdered
- executionLaneOrder?
```

```text
PendingSafety
- localRootPathSnapshot?
- workingDir?   # legacy import/read-only receipt; new items derive root from Project
- requiresTrustedDevice: Bool
- privacyLabel?
```

```text
PendingResume
- reason: cooldown | providerBusy | localBusy | timeout | stopped | appRestart | macSleep | userPaused
- lastAttemptId?
- transcriptRef?
- nextInstruction
- observedResetAt?
- wakeAfter?
```

```text
PendingLease
- leaseId
- owner: serve | cli | gui | localApi
- leasedAt
- expiresAt
- attemptId?
```

```text
PendingAttemptSummary
- attemptId
- createdAt
- startedAt?
- completedAt?
- workerIds: [Worker.ID]
- status: queued | running | done | failed | timedOut | cancelled | skipped | blocked
- admissionEventIds: [CapacityEvent.ID]
- projectId
- executionLaneKey?
- reason
```

```text
PendingExecutionLaneState
- executionLaneKey
- executionLanePolicy: fifo | userOrdered
- pausedReason?: user | editLock
- orderedItemIds: [PendingItem.ID]
- editLease?: PendingLease
```

Notes:

- `PendingItem` owns user intent. It may reference thread turns and runs, but it
  does not duplicate run truth.
- `PendingItem.projectId` is required for new items. Migrated items without a
  reliable Project are visible for repair and are not drainable.
- `PendingSafety.localRootPathSnapshot` is a receipt from the owning Project at
  submit time. It is not the scope owner.
- `PendingPolicy` composes with `AdmissionPolicy`; it does not replace it.
- `PendingExecution.intent = execute` means "submit this as an order to the
  selected worker when allowed." It does not mean Allnighter owns the workspace.
- `PendingExecution.executionLaneKey` is computed and frozen at submit time when
  the Execute item has one concrete worker candidate. For fallback or multi-worker
  targets, the scheduler derives candidate keys deterministically and freezes the
  actual key when an attempt is leased.
- Editing the item returns it to Draft; resubmitting may compute new execution
  lane keys from the edited target/safety context.
- Reordering changes execution-lane order only. It does not edit the prompt,
  target, safety context, or lifecycle status.
- `PendingResume.nextInstruction` must be visible/editable before a Pending item
  is resumed in present mode.
- A lease is process/scheduler bookkeeping. It is not a public status.
- `needsAttention` is derived from admission/safety/manual-action reasons; it is
  not a stored lifecycle status.
- `expiresAt` is optional and user/preset-defined. Do not invent expiry from
  guessed usefulness.

Default `kind` -> `intent` mapping:

| `kind` | Default intent | Notes |
| --- | --- | --- |
| `workerChat` | `ask` | Can become `execute` only when the user marks it as an order. |
| `followUp` | `ask` | Continuations that only request an answer stay ask-intent. |
| `returnReview` | `ask` | Review/critique by default. |
| `teamRun` | `ask` | Team synthesis is read/reply by default; mutating team dispatch is later work. |
| `workOrder` | `execute` | When it asks a live CLI to act in a project/session. |
| `dispatch` | `execute` | Mutating dispatch remains deferred from Pending v1. |

Canonical execution lane key:

```text
executionLaneKey = v2:hash(projectId, workerId, normalizedProjectRoot || "unknown-root", sessionBinding || "unknown-session")
```

Derivation rules:

- `projectId` is always part of the execution-lane key. Same-worker Execute work
  in different Projects must not serialize unless another policy explicitly says
  so.
- `workerId` is the concrete candidate worker for execution-lane head checks and
  the worker actually selected for an Execute attempt.
- `normalizedProjectRoot` is the owning Project's normalized root path when
  known. If unknown or unsafe to resolve, use `unknown-root`.
- `sessionBinding` is the known worker session/thread binding when Allnighter has
  one. If absent, use `unknown-session`.
- Unknown values make the key more conservative, not more permissive. Unknown
  root/session means same-worker Execute orders in the same Project share the
  same conservative execution lane until proven independent.
- The key must not inspect or mutate git state.
- Attempt summaries copy the actual `executionLaneKey` used at lease/spawn time.

## Wake Tickets

Truth owner: `PendingItem.resume` plus the latest attempt summary. The
`CapacityObservation` source contract lives in `Stalled_Work_Watchdog.md`.

A Wake Ticket is the smallest useful resume contract:

```text
already-authorized work attempts
-> CLI returns sourced capacity/cooldown signal
-> Pending item returns to Pending/Sleeping
-> PendingResume records reason + observedResetAt/wakeAfter
-> resident coordinator wakes once at the boundary
-> same item gets one resume attempt
```

Rules:

- Wake Tickets are not broad Pending drain. They do not sweep all runnable
  Pending work and do not own cross-Project fairness.
- The item must already be authorized: submitted Pending, user-sent worker turn
  promoted to Pending, or approved work order. Worker suggestion prose cannot
  create a Wake Ticket by itself.
- During cooldown, Allnighter makes zero provider calls.
- At wake time, the default action is the same real work attempt. Driver-specific
  smoke probes may be added only when proven cheaper/safer by fixtures.
- `observedResetAt` is stored only when sourced from the CLI/provider/user.
  Conservative local retry policy stores `wakeAfter` without pretending the
  provider reported a reset.
- `providerBusy` is server-side overload/capacity saturation; `cooldown` is the
  user's account/plan/item capacity sleep; `localBusy` is the user's machine or
  Allnighter process capacity.
- A new sourced cooldown replaces the Wake Ticket. Success clears it. Auth,
  manual, or repeated unknown failure routes to attention instead of churn.
- `PendingItemDerivation.nextWakeAt` remains the public projection point.

## Scheduler Drain Policy

> **Parked except the execution-lane gate and Wake Tickets.** The Inputs, Default order, Fairness
> rules, Project order rules, and Retry rules in this section describe a future
> native or external coordinator and are **parked** until native scheduling is
> explicitly revived (see Scope Correction). They are not a v1 promise; re-tense
> them as "a coordinator that drains Pending MUST…" when reading. The
> **Execution-lane order rules** below are the exception: the execution-lane
> serialization gate (one Running Execute per lane, FIFO, head-only) is **always
> active in v1** and enforced on every explicit run trigger (`alln pending run`,
> GUI run, MCP `pending_run`), regardless of whether native drain exists. Wake
> Tickets are the other exception: one same-work wake attempt after sourced
> capacity sleep.

Inputs:

- Pending items;
- Project binding and root state;
- derived queue entries;
- `ModelAdmission` from utilization;
- local concurrency slots;
- Mac reachability and power posture;
- attention mode;
- mutation safety checks;
- notification and quiet-hours settings.

Default order:

```text
1. pinned Pending items with needs-attention badges that can be resolved by the present user
2. pinned Pending items
3. resume attempts after observed resetAt/wakeAfter
4. oldest Pending item per active thread
5. oldest remaining Pending item
```

Fairness rules:

- At most one new heavy item per thread per scheduler sweep unless pinned.
- A cooling worker does not block unrelated Pending work for other workers.
- A preferred worker can hold a specific item without holding all Pending work.
- Fallbacks run only when stored policy allows them.
- If all selected workers are blocked and no fallback is allowed, the item stays
  Pending with the observed reason.

Project order rules:

- Scheduler sweeps may consider multiple Projects, but they never merge Projects
  into one durable queue.
- Global Pending list order is a display aggregation. It does not authorize
  cross-Project reorder.
- A missing, archived, or permission-denied Project blocks only that Project's
  Pending drain.
- Project-specific ordering and execution-lane ordering are evaluated before
  worker admission.

Execution-lane order rules:

- Execute items are serialized by `executionLaneKey`.
- If the scheduler cannot prove two Execute orders are independent, they share an
  execution lane.
- Each execution lane has at most one Running Execute item.
- Execution-lane order is FIFO by submitted order until the user manually
  reorders Pending items in that execution lane.
- Manual reorder sets `executionLanePolicy = userOrdered` for that execution lane
  and records `userReorderedExecutionLane` in audit.
- Pinning can raise an execution lane in the global sweep, but it must not let a
  later same-execution-lane Execute jump an earlier one unless the user manually
  reorders that execution lane.
- A same-execution-lane Execute item behind the head stays Pending with reason
  `executionLaneBusy`.
- An execution lane advances when the head item reaches `done`, `cancelled`, or
  an explicit user `Skip Head` action.
- `failed`, `timedOut`, `stopped`, `cooldown`, `authRequired`, and safety blocks
  keep the head item Pending/needs-attention and hold later
  same-execution-lane Execute items.
- Stopping a Running Execute returns that item to Pending and keeps it at the
  head of its execution lane.
- Cooldown resume is the same head item, not permission to start the next order.
- A Running Execute item cannot be reordered. It remains the execution-lane head
  until it stops, fails, completes, or is cancelled.
- Pending Execute items behind a Running head can be reordered freely.
- If no item is Running and the head is blocked, failed, stopped, or
  needs-attention, the user may move another same-execution-lane Pending item
  ahead of it. This is explicit user intent, not scheduler autonomy.
- Manual reorder opens a short `editLock` for that execution lane. `alln serve`
  must not start the next item from that execution lane while the lock is open.
  Unrelated execution lanes continue draining.
- Only `intent = execute` participates in execution-lane serialization by
  default. Ask/follow-up items can still drain according to normal admission,
  local concurrency, and driver limits unless their policy explicitly pins them
  to the same execution lane.
- Multi-worker/team Execute items are decomposed into per-worker execution-lane
  checks before spawn. A fallback worker uses its own execution lane; falling back
  must not let a later same-execution-lane item jump the original head for another
  worker.
- `Skip Head` is a present-user recovery action, not an automatic scheduler
  decision. It preserves audit/history, records a skipped attempt/decision, and
  releases the execution lane without pretending the skipped item succeeded.
- FIFO and explicit user order are the only M1 execution-lane policies. LIFO is
  deferred and must not be smuggled in through `priority: pinned`.

Retry rules:

- `coolingDown` with observed `resetAt`: wake at `resetAt` plus jitter.
- `coolingDown` without `resetAt`: recheck later using conservative backoff.
- `exhausted`: hold until a later observed signal, user action, or scheduled
  conservative recheck changes state.
- `authRequired`: hold and ask for sign-in.
- `manualRequired`: hold unless the user is present.
- `unknown`: attempt only when policy permits; otherwise probe according to
  utilization rules.
- repeated `timeout` or `degraded`: follow degraded policy; do not churn.

Backoff policy should be configurable, but the default posture is patient:

```text
No known reset -> recheck no more than hourly while the item is still desired.
Known reset    -> wake after the observed reset, with jitter.
Failure loop   -> widen backoff and mark needs attention after the attempt limit.
```

## Away Mode (Parked Future Work)

Away Mode is parked until native scheduling/drain is explicitly revived. The
shape below is future material, not a v1 promise.

The composer can stay prompt-first:

```text
Submit to Pending
Run later
Claude preferred
Fallbacks: Codex, Gemini
Mutation: ask before writing
```

Away Mode must show the boundary before the user leaves:

- what can run unattended;
- which workers are selected or allowed as fallbacks;
- whether any item can write to the working directory;
- what will pause for sign-in, manual paste, or dirty working tree;
- what notifications will wake the user.

This is close to the Allnighter brand because it makes the Mac feel like an
active floor: not a passive queue, but a simple outbox an agent can call.

Future boundary:

- Away Mode would drain non-mutating Pending only.
- Mutating dispatch stays Draft/Pending with a reason until a present user acts.
- Pending may carry working-directory context for handoff, but it does not own
  isolation, worktrees, branches, commits, merges, or landing.

## Activity Summary

Activity Summary is the time-agnostic receipt for what happened while the user
was away from the thread, app, or Mac.

It reports actual outcomes only:

```text
Since you left:
- Claude: reply completed
- Codex: team run completed - spec ready
- Gemini: still Pending - cooling until 3:30 PM, observed
- 1 Draft suggestion ready to review
```

It is actionable, not predictive:

- open completed replies/results;
- submit or edit Draft suggestions;
- stop Running work;
- cancel Pending;
- resolve sign-in/manual-paste/safety reasons.

It never forecasts quota, cost, runtime, task difficulty, or future capacity.

## Follow-Up Harvesting

Completed and failed work may propose follow-up Pending items, but suggestions
are not submitted work until authorized.

Allowed suggestion sources:

- return review;
- failed run with a clear recovery path;
- worker answer that names a useful next pass;
- user-configured preset that explicitly creates a review/finalization follow-up.

Examples:

```text
Codex finished implementation.
Suggested: Ask Claude to review the diff when available.
```

```text
Claude produced a plan.
Suggested: Dispatch Codex with this work order.
```

Rules:

- Suggestions are visible and dismissible.
- Presets may auto-approve narrow suggestion classes, such as "run return review
  after dispatch completes," only when the preset says so.
- Worker prose alone must not create mutating work.
- The suggestion stores its source turn/run/stage so the user can inspect why it
  exists.

## iOS Project Manager Impact

The Mac remains Pending and run truth. iOS captures commands and renders
Mac-owned snapshots/events.

iOS must be able to answer:

```text
What is Draft?
What is Pending?
What is Running?
What needs me?
What completed since I left?
Can I pause/cancel/reprioritize it?
```

Remote capture:

- a phone-created Pending item is sealed to the Mac before relay;
- if the Mac is asleep, the command waits and drains on next wake according to
  the iOS transport docs;
- phone UI distinguishes `Mac asleep`, `Mac unreachable`, `worker cooling`,
  `auth required`, and `Pending on Mac`.

Push payloads stay content-light. Sensitive prompt and result content is fetched
through the trusted remote spine.

## Privacy and Permissions

Pending can contain the union of the user's future work, so the privacy posture
must be tighter than ordinary run history.

Rules:

- Pending is local Mac truth by default.
- No provider credentials or account pages leave the Mac.
- Remote Pending commands are E2E sealed before relay.
- Cloud relays carry metadata and ciphertext only where the iOS docs allow them.
- Provider CLIs see only the work item they are asked to run.
- Mutating dispatch is deferred from Pending v1; later slices keep the existing
  working-directory safety boundary.
- The user can stop Running attempts and cancel Pending items.
- The user can delete Pending items without deleting completed run history they
  already generated, unless they explicitly delete both.

High-risk stops before implementation:

- any new cloud-durable Pending storage;
- any background behavior that changes macOS permission posture;
- any unattended write behavior broader than an explicit work item;
- any branch/worktree/commit/merge ownership added to Pending;
- any automated probing that could look like provider-limit evasion.

## Implementation Impact

Core/package impact:

- Add Pending models, Codable persistence, validation, and fixture builders.
- Add deterministic derivations for item display state and needs-attention state.
- Add tests for Draft/Pending/Running transitions, plus outcome states.

CLI impact:

- Add `alln pending` to the command registry before GUI wiring depends on it.
- Add Project-required pending grammar or flags before any run attempt depends on Pending:
  `alln pending add --project <project>`, `alln pending list --project <project>`,
  and `alln project pending <project>`.
- Emit `PendingItemJSON` from `add`, `show`, and `run`.
- Make `alln pending list --project <project> --json` the Project proof surface
  and `alln pending list --all --json` the aggregate floor proof surface for
  GUI/iOS snapshots.
- Keep native `alln serve` drain parked; explicit `pending run` is the runnable
  surface.
- First Pending milestone accepts non-mutating kinds only:
  `workerChat` and `followUp`.

Mac app backend impact:

- Persist Pending beside thread/run history.
- Expose a floor snapshot that includes Pending items, queue attempts, and blocked
  reasons.
- Keep mutating dispatch out of Pending v1; later dispatch slices run safety
  checks immediately before any mutating attempt.
- Provide edit, submit, stop, cancel, reprioritize, and run-now actions.

Engine impact:

- Bridge explicitly run Pending items to admission requests.
- Lease items before spawning attempts so app restarts can recover cleanly.
- Enforce FIFO execution lanes before spawning Execute attempts.
- Keep wakeup/recheck automation parked with native scheduling.

iOS impact:

- Render Mac-owned Pending snapshots.
- Submit sealed Pending commands when remote capture is enabled.
- Show reachability and admission states distinctly.

Driver/protocol impact:

- Drivers continue to emit `ProviderObservation` and `CapacityEvent`; they do not
  own Pending truth.
- Protocol snapshots/events need Pending ids and item states once iOS surfaces
  this feature.

Auth/privacy/permissions impact:

- No new provider credentials.
- No new cloud-readable content.
- Any change to background availability, power assertion copy, or unattended
  write policy is a high-risk stop.

## Implementation Slices

Implementation order note:

- `Pending0`/`Pending1` may build local Draft/Pending storage and CLI CRUD before
  drain exists.
- Do not claim app-closed broad execution or Away Mode drain until `Serve0` plus
  `Pending2` are built. A narrower "Claude cooldown resumes once" claim belongs
  to `Pending1a` / Wake Tickets and only applies to already-authorized work with
  sourced cooldown state.
- MCP Pending (`A1`) comes after the CLI/model semantics are real; MCP must not
  invent a separate Pending store or friendlier-but-different lifecycle.

### Pending0 - Public CLI Contract

Status: **BUILT** (2026-06-17)

Goal:
Make Pending a public command contract before building GUI-only behavior.

Scope:

- `alln pending add --project <project> [prompt]`.
- `alln pending list --project <project> --json`.
- `alln pending list --all --json` grouped by Project.
- `alln pending show <id> --json`.
- `alln pending submit <id>`.
- `alln pending edit <id>`.
- `alln pending reorder <id>`.
- `alln pending cancel <id>`.
- `alln pending run <id>`.
- `PendingItemJSON` fixture and schema.
- Error/recovery metadata for invalid worker, auth-required, admission-blocked,
  mutation-deferred, invalid-reorder, and serve-unavailable cases.
- M1 kinds: `workerChat` and `followUp`.

Works Test:

```text
Run alln pending add --project Allnighter --worker claude "Review this patch when Claude is ready."
Run alln pending list --project Allnighter --json.
The item appears as Draft with selected worker, policy, safety, and no guessed
quota/cost/runtime fields.
It includes projectId.
Run alln pending submit <id>.
The item becomes Pending.
Run alln pending add --project Allnighter --submit --worker claude "Continue security review."
The new item is created directly as Pending.
Run alln pending reorder <second-id> --before <first-id>.
The two items keep their lifecycle states, and only their execution-lane order
changes.
Attempt to reorder across Projects.
The command is rejected.
Run alln pending cancel <id>.
The item becomes cancelled and is not drained by alln serve.
```

### Pending1 - Local Pending Model

Status: **BUILT** (2026-06-17)

Goal:
Store user-owned work intent separately from scheduler attempts.

Scope:

- `PendingItem`, target, policy, safety, resume, and attempt summary types.
- Project binding for every new Pending item plus migration for existing items.
- Local persistence beside thread/run history.
- Link from thread turns to Pending items.
- Basic Mac Pending list: Draft, Pending, Running, outcomes, needs attention.
- Manual `Save draft`, `Submit to Pending`, and `Run when allowed` for non-mutating worker chat/team
  work.

Works Test:

```text
Create three Pending items from a thread.
Restart the app.
Items remain ordered, linked to the thread, and not duplicated as run truth.
Manual run creates one queued attempt and records the attempt summary.
Editing a Pending item moves it back to Draft and cancels scheduled wake/lease
state.
```

### Pending1a - Wake Tickets / One-Shot Cooldown Resume

Goal:
Make capacity cooldown feel like sleep, not failure, without building broad
native drain.

Scope:

- `CapacityObservation` parser/adapter fixtures live with
  `Stalled_Work_Watchdog.md`.
- Worker/Pending/team attempt settlement can write `PendingResume` with
  `cooldown` or `providerBusy`.
- Pending JSON projects `nextWakeAt`, `blockedReason`, attempt reason, and no
  quota/cost/runtime estimates.
- `alln serve` may wake exactly one due item and retry the same authorized work.
- No fairness sweep, fallback routing, Away Mode, PTY probes, or admission ledger.

Works Test:

```text
Create a submitted Pending item targeting Claude.
Fake worker returns a sourced rate-limit reset at 02:14.
Allnighter records PendingResume and returns the item to Pending.
Fake clock reaches 02:14 plus jitter while alln serve is running.
The same item receives exactly one resume attempt.
If the attempt succeeds, resume clears.
If the attempt returns a new reset, wakeAfter updates and no stall nudge appears.
```

### Pending2 - Serve-Owned Admission-Aware Drain

Goal:
Drain submitted Pending items through `alln serve` when utilization allows,
without guessing availability.

Scope:

- Refuse to drain Pending items without `projectId`.
- Scheduler bridge from Pending items to `AdmissionRequest`.
- `alln serve` owns leases and attempts while running.
- Observed reset wakeups.
- Conservative rechecks when no reset is known.
- Local slot fairness.
- Blocked reasons and needs-attention transitions.
- No mutating unattended dispatch in this slice.

Works Test:

```text
Three Pending items target Claude, Codex, and Gemini.
Claude is cooling down with observed resetAt.
Codex is available.
Gemini requires auth.
Scheduler runs Codex, keeps Claude Pending until resetAt, and marks Gemini needs
sign-in.
Activity Summary reports only actual completed/blocked/auth-required outcomes.
```

### Pending3 - Cooldown Resume

Goal:
Make mid-job cooldown feel like a pause, not a lost session.

Scope:

- Worker failure parser creates `PendingResume` for eligible failed/blocked work.
- Resume packet includes transcript/ref, prior attempt status, and next
  instruction.
- At observed reset, scheduler starts a continuation attempt if policy allows.
- Present user can edit the continuation instruction before resume.

Works Test:

```text
Fake Claude worker rate-limits mid-review and reports reset time.
Allnighter returns the item to Pending with resume context.
Fake clock reaches resetAt.
Worker receives a continuation prompt referencing the prior transcript.
The thread shows the completed follow-up or the new observed block.
```

### Pending4 - Away Mode and Activity Summary

Goal:
Make away-mode draining a visible, lovable product surface.

Scope:

- Away Mode composer affordance.
- Away-mode drain settings.
- Pause/resume/cancel/reprioritize controls.
- Stop Running returns the item to Pending; cancel is a separate explicit action.
- Activity Summary.
- iOS-readable Pending snapshot/events.
- Mutating dispatch remains deferred.

Works Test:

```text
Submit five Pending items for away-mode drain, including one mutating dispatch.
Set the user away.
Available non-mutating items run.
The mutating dispatch remains Draft/Pending with a mutation-deferred reason.
Activity Summary reports completed, blocked, failed, and needs-attention badges without
quota, cost, runtime, or token estimates.
```

### Pending5 - Approved Follow-Up Harvesting

Goal:
Let completed work propose useful next steps without inventing hidden work.

Scope:

- Suggested Draft item model or `PendingItem.status = draft`.
- Suggestion cards from return review and failed runs.
- Preset-approved suggestion classes.
- Audit trail from suggestion to source turn/run/stage.

Works Test:

```text
Codex dispatch completes.
Return review suggests "Ask Claude to review diff when available."
The suggestion appears as a Draft item.
Approving it submits a Pending item targeting Claude.
If Claude is cooling down, it remains Pending with the observed reason.
```

### Pending6 - Ordered Execute Lanes

Goal:
Let users build a real Execute backlog without parallel writes colliding in the
same worker/session/project, while still letting them change the order when
parallel work is not safe.

Scope:

- `PendingExecution.intent = execute`.
- Deterministic `executionLaneKey` derivation and versioning.
- Project id and normalized Project root are part of the key.
- FIFO execution-lane scheduler gate before admission spawn.
- Manual reorder of Pending, not Running, Execute items inside one execution
  lane.
- Short execution-lane edit lock while order is being changed.
- `executionLaneBusy` blocked reason.
- Ask-vs-Execute default mapping.
- Stop/resume/fail behavior that keeps the head item in place.
- No branch, worktree, commit, merge, or workspace ownership.

Works Test:

```text
Submit Execute Task 1 and Execute Task 2 to Claude with the same working
directory/session binding.
Scheduler starts Task 1.
Task 2 remains Pending with reason executionLaneBusy.
Task 1 cools down mid-run and returns to Pending with a resume packet.
Task 2 still remains Pending behind Task 1.
Fake clock reaches resetAt and Task 1 resumes.
Only after Task 1 reaches done does Task 2 start.
Stopping Task 1 returns it to Pending and still holds Task 2.
Cancelling Task 1 releases the execution lane and allows Task 2 to be considered.
Submit Ask Task 3 to Claude while Task 2 is Pending behind the execution-lane head.
Task 3 may run under normal admission because ask-intent does not join the
execution lane unless explicitly pinned to it.
Submit Execute Task 4 behind Task 2 in the same execution lane.
Manually reorder Task 4 before Task 2 while Task 1 is Running.
Task 1 keeps running and cannot be moved.
Task 4 starts before Task 2 only after Task 1 reaches done/cancelled/skipped.
Audit records userReorderedExecutionLane.
```

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Pending -> admission | AllnighterCore | Pending item means worker quota exists | Pending means submitted intent, not that capacity exists | A Pending Claude item with coolingDown admission remains Pending with a reason |
| Pending -> Project | AllnighterCore | Pending can float globally until drain | Pending requires `projectId`; unassigned migrated items are repair-only and not drainable | Create Pending without Project; submit/drain is rejected |
| Admission -> retry | AllnighterEngine | No reset time means estimate one | Unknown reset must be labeled unknown and use conservative recheck policy | UI never renders an invented reset time |
| Worker prose -> Pending | AllnighterCore | Model suggestion creates hidden work | Suggestions are Draft until approved or preset-authorized | Worker says "run tests"; no new Pending item appears |
| iOS command -> Mac execution | iOS remote spine | Phone sent command means Mac ran it | Sleeping/unreachable Mac queues command and reports reachability honestly | Phone shows Mac asleep; no run status is faked |
| Dispatch safety -> away drain | Mac backend | Pending dispatch permission covers any workspace state | Safety is checked at dispatch time; dirty working dir keeps item Pending | Dirty cwd blocks unattended mutating item |
| Execution lane -> workspace ownership | AllnighterEngine | FIFO means Allnighter owns branches/worktrees/landing | FIFO controls submission order only; target worker/process owns workspace setup | Two same-execution-lane Execute items serialize, but no branch/worktree is created |
| Manual reorder -> scheduler autonomy | AllnighterEngine | Reorder permission lets scheduler choose a better order | Only explicit user reorder can change same-execution-lane order | Scheduler cannot start Task 4 before Task 2 unless user reordered them |
| Product Lane -> execution lane | AllnighterCore | Code/Design/Copy lane means execution serialization group | Product Lane and execution lane are separate concepts; execution lane is always qualified | A Code work order and Copy work order can still share one Claude execution lane |
| Activity Summary -> utilization | Mac backend | Report should estimate what could have happened | Activity Summary reports actual outcomes only | Summary contains no future quota/cost/runtime claims |

## Done When

- The user can add work to Pending without requiring the target worker to
  be available at that moment.
- Every runnable Pending item is bound to exactly one Project.
- `alln pending` can create, submit, edit, reorder, list, show, cancel, run, and
  stop Pending items before any GUI-only Pending surface ships.
- Native `alln serve` Pending drain remains parked except one-shot Wake Tickets.
- Pending items preserve target worker/team, context, fallback, priority, and
  mutation policy.
- Draft is editable and never runnable; editing Pending returns it to Draft.
- Stopping Running returns it to Pending; cancellation is explicit.
- Explicit run attempts keep blocked work Pending with sourced reasons.
- Execute work is FIFO per execution lane; later same-execution-lane work does
  not start while an earlier item is running, cooling down, stopped,
  failed-needs-attention, or safety-blocked unless the user manually reorders
  Pending items in that execution lane.
- Manual reorder pauses only the edited execution lane for the edit transaction;
  unrelated execution lanes continue draining.
- Wake Tickets can continue the same interrupted worker item once after an
  observed/conservative wake boundary.
- Away Mode makes unattended non-mutating work understandable before the user
  leaves.
- Activity Summary reports actual outcomes across completed, blocked, failed,
  skipped, cancelled, Draft, Pending, Running, and needs-attention badges.
- iOS can submit and inspect Pending state through Mac-owned truth when the iOS
  remote spine is active.
- No Pending, queue, UI, CLI, MCP, or iOS path estimates future cost, runtime,
  quota, token burn, or task complexity.

## Proof Command

```text
swift test
scripts/check.sh
```

Pending scheduler tests must use fake workers, fake clocks, and fixture-backed
admission events. iOS claims require the remote-spine Works Test before public
copy says the phone can submit or monitor Away Mode items.
