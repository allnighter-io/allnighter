# Pending Work and Drain

Status: Draft founder packet; CLI-first Pending approved
Owner: AllnighterCore + AllnighterEngine + Mac app backend
Updated: 2026-06-15

## Founder Intent

Allnighter should let the user write the work now even when the best worker is
busy, cooling down, asleep behind Mac reachability, or otherwise unavailable.

The user should not have to babysit Claude's reset windows. They should be able
to submit work to Pending, go away, and trust Allnighter to drain it when the
selected worker or allowed fallback can accept work again.

This is not an overnight-only feature. It matters just as much at 2:00 PM when
Claude resets at 3:30 PM as it does while the user sleeps.

The product unlock:

```text
Allnighter separates intent capture from worker availability.
```

The brand-fit claim:

```text
Leave work on Claude's desk. When Claude wakes up, it starts.
```

This is not quota evasion. It is local, honest, user-authorized orchestration of
the subscriptions and CLIs the user already pays for.

## Product Value

Allnighter's core promise is an agent factory that keeps working when the user
steps away. A first-class Pending surface turns intermittent model availability
into continuous useful work:

```text
capture intent now
-> package it as a safe work item
-> keep it Pending when workers are unavailable
-> drain submitted work when admission passes
-> show the activity receipt when the user returns
```

This is especially valuable around short vendor reset windows. Native model UX is
session-attention-bound: if Claude cools down, the user usually has to remember,
return, reconstruct context, and try again. Allnighter can keep the context,
retry at the observed wake time, and preserve the user's priority order.

Default mental model:

```text
Pending is the next turn in a thread, not a project-management backlog.
```

Global Pending views exist so the user can see the floor, but capture starts
where intent is hot: the thread composer, a blocked worker reply, a completed
team run, or a worker return that suggests a follow-up.

## Trusted Workflow Slice

```text
user captures several work items
-> Allnighter stores them as Pending items with explicit worker/team policy
-> scheduler admits only safe, available attempts
-> cooled-down workers are retried from observed reset signals or conservative rechecks
-> completed, blocked, failed, and Draft suggestions appear in Activity Summary
```

First lovable slice:

```text
Claude cools down mid-job
-> Allnighter returns the item to Pending with a resume packet
-> observed reset time arrives
-> Allnighter asks Claude to continue from the saved context
-> the thread shows the completed follow-up or the new blocking reason
```

## Non-Goals

- No quota dashboard.
- No billing dashboard.
- No estimated remaining quota, runtime, cost, token burn, or task complexity.
- No provider-limit evasion, spam probing, or synthetic keepalive loops.
- No unattended mutating dispatch in Pending v1.
- No silent worker substitution.
- No cloud-owned durable Pending store.
- No provider-native chat-history dependency.
- No branch, worktree, commit, merge, or workspace-management ownership.
- No automatic creation of unapproved new work from worker suggestions.

Deferred elsewhere:

- Admission states, cooldown parsing, fallback policy, and probes belong to
  `Utilization_Admission_Control.md`.
- Work-thread storage and context packets belong to `Persistent_Work_Threads.md`
  and `threads/01_Work_Threads_MLP.md`.
- iOS reachability, sealed command inbox, and sleep/drain behavior belong to
  `ios/00_iOS_Transport_Decision.md` and the iOS spine.
- Mutating dispatch and workspace safety belong to the dispatch/work-order
  phases. Pending v1 drains non-mutating turns only.

## User-Visible Claim

```text
Allnighter keeps work Pending and drains it when your selected workers can work.
```

Sharper product copy:

```text
Keep Claude's next window full.
```

Useful floor copy:

```text
6 pending
Claude: 3 pending - cooling down until 2:14 AM, observed from Claude
Codex: running 1 item
Gemini: 2 pending
1 dispatch needs attention - working directory changed
```

Useful item copy:

```text
Pending - Claude cooling until 3:30 PM, observed from Claude.
Claude cooled down while reviewing Codex's patch. Follow-up is pending.
Pending for any allowed reviewer: Claude preferred, Codex fallback allowed.
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
Pending = submitted intent; Allnighter may run it when admission and safety allow.
Running = active attempt.
Queue   = internal scheduler machinery for execution attempts.
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
- Editing a Pending item moves it back to Draft, cancels scheduled wakes/leases,
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
Pending may hold a backlog of Execute orders, but it submits Execute work FIFO
per execution lane.
```

An Execute order is work intended to let a target CLI act, not just answer. The
same user can stack five Execute orders for Claude, leave the app window closed,
and let `alln serve` keep Claude busy. Allnighter still submits only one Execute
order at a time to the same lane.

The lane rule is submission ordering only. It is not branch strategy, worktree
management, isolation, commit policy, or merge policy.

## Public CLI Decision

Pending is public CLI vocabulary, not a GUI-only label.

Required public surfaces:

```text
GUI: Draft/Pending/Running rows, add-to-Draft and submit-to-Pending actions.
CLI: alln pending add/submit/edit/list/show/cancel/run/stop, backed by the same PendingItem model.
Resident: alln serve drains eligible Pending while the app window is closed.
```

Rules:

- GUI and iOS render Pending from Mac/Core truth; they do not own a separate
  Pending store.
- `alln pending` is the first public command family for this feature.
- `alln serve` is required before Pending can promise "runs while the app is
  closed."
- Queue remains internal scheduler language except in logs, debug output, and
  schema fields that represent execution attempts.
- Thread composer capture is the primary UX. Global Pending is a floor view, not
  the product's center of gravity.

Examples:

- User says "ask Claude to review this when it is back" -> Pending item.
- Scheduler holds the Claude attempt until cooldown ends -> queue entry.
- Claude cools down mid-run and the item needs continuation -> same Pending item,
  new queued attempt with a resume packet.
- Worker suggests "run a proof skeptic pass" -> suggested Draft item, not submitted
  until the user approves or a preset explicitly permits that suggestion class.

## Product Laws

- Queueing is not failure. Queueing is how Allnighter converts intermittent
  availability into useful work.
- Pending items are explicit user intent, preset intent, or approved suggestions.
- Admission still owns availability. Pending must not guess quota or readiness.
- Draft items are never drained.
- Pending items may be blocked by admission or safety, but they stay Pending in
  public UI.
- Execute items drain FIFO per execution lane. Later same-lane Execute items stay
  Pending until the earlier item is finished, cancelled, or explicitly skipped by
  the user.
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
- `Utilization_Admission_Control.md` owns observed availability, cooldowns,
  fallback policy, and admission attempts.
- `ios/00_iOS_Transport_Decision.md` owns phone-to-Mac command delivery,
  reachability honesty, sealed payloads, and sleep/drain behavior.
- `Work_Order_Team_Model.md` owns worker/team/lane/type/effort vocabulary.

Existing useful pieces:

- Thread turns already have `queued` and `running` internal status.
- Utilization already defines scheduler behavior for cooldowns, local slots,
  fallbacks, present/away mode, and mutating dispatch safety.
- iOS docs already define "commands queue and drain on next wake" when the Mac
  is asleep.
- `Mac_Standalone_App_And_Background_Coordinator.md` now defines `alln serve` as
  the resident coordinator process.

Missing truth:

- No user-owned Pending object exists.
- No public `alln pending` contract exists.
- No distinction exists between durable work intent and scheduler attempts.
- No cooldown-resume packet exists for "continue this exact job when Claude is
  available."
- No Away Mode or Activity Summary contract exists for draining user-selected work
  while the user is not actively watching.

## SSOT

Truth owner:

```text
AllnighterCore owns Pending models and semantic rules.
AllnighterEngine owns drain scheduling.
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

## Core Model

Truth owner: `AllnighterCore`.

```text
PendingItem
- id
- threadId?
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
- drainMode: manualStart | drainWhenReady | drainAway
- maxAttempts?
- retryFloorSeconds?
- allowDegraded: Bool
- requireKnownAvailable: Bool
- createSuggestedFollowUps: Bool
```

```text
PendingExecution
- intent: ask | execute
- laneKey?
- lanePolicy: fifo
```

```text
PendingSafety
- workingDir?
- requiresTrustedDevice: Bool
- privacyLabel?
```

```text
PendingResume
- reason: cooldown | localBusy | timeout | stopped | appRestart | macSleep | userPaused
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
- executionLaneKey?
- reason
```

Notes:

- `PendingItem` owns user intent. It may reference thread turns and runs, but it
  does not duplicate run truth.
- `PendingPolicy` composes with `AdmissionPolicy`; it does not replace it.
- `PendingExecution.intent = execute` means "submit this as an order to the
  selected worker when allowed." It does not mean Allnighter owns the workspace.
- `PendingExecution.laneKey` can be derived and stored for recovery/audit. The
  default lane is target worker plus known working directory/session binding.
- `PendingResume.nextInstruction` must be visible/editable before a Pending item
  is resumed in present mode.
- A lease is process/scheduler bookkeeping. It is not a public status.
- `needsAttention` is derived from admission/safety/manual-action reasons; it is
  not a stored lifecycle status.
- `expiresAt` is optional and user/preset-defined. Do not invent expiry from
  guessed usefulness.

## Scheduler Drain Policy

Inputs:

- Pending items;
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

FIFO execution lane rules:

- Execute items are serialized by `executionLaneKey`.
- The default lane key is conservative: worker id plus known working directory
  plus known session/thread binding. If the scheduler cannot prove two Execute
  orders are independent, they share a lane.
- Each lane has at most one Running Execute item.
- Lane order is FIFO by submitted order. Pinning can raise a lane in the global
  sweep, but it must not let a later same-lane Execute jump an earlier one.
- A same-lane Execute item behind the head stays Pending with reason
  `executionLaneBusy`.
- A lane advances when the head item reaches `done`, `cancelled`, or an explicit
  user skip.
- `failed`, `timedOut`, `stopped`, `cooldown`, `authRequired`, and safety blocks
  keep the head item Pending/needs-attention and hold later same-lane Execute
  items.
- Stopping a Running Execute returns that item to Pending and keeps it at the
  head of its lane.
- Cooldown resume is the same head item, not permission to start the next order.
- Non-mutating Ask/follow-up items can still drain according to normal admission
  unless their policy explicitly pins them to the same execution lane.

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

## Away Mode

Away Mode is the product surface for Pending intended to drain while the user is
not actively watching. It applies at 2:00 PM, during a meeting, from iPhone, or
overnight; time of day is not the semantic owner.

The composer can stay prompt-first:

```text
Submit to Pending
Run when ready
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
active floor: not a passive queue, but a simple outbox that drains when it can.

M1 boundary:

- Away Mode drains non-mutating Pending only.
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

## iOS Floor Manager Impact

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
- Emit `PendingItemJSON` from `add`, `show`, and `run`.
- Make `alln pending list --json` the proof surface for GUI/iOS snapshots.
- Make `alln serve` the only resident drainer for app-closed execution.
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

- Bridge Pending items to admission requests.
- Lease items before spawning attempts so app restarts can recover cleanly.
- Enforce FIFO execution lanes before spawning Execute attempts.
- Use fake-clock-testable wakeups for observed reset times and conservative
  rechecks.

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

### Pending0 - Public CLI Contract

Goal:
Make Pending a public command contract before building GUI-only behavior.

Scope:

- `alln pending add [prompt]`.
- `alln pending list --json`.
- `alln pending show <id> --json`.
- `alln pending submit <id>`.
- `alln pending edit <id>`.
- `alln pending cancel <id>`.
- `alln pending run <id>`.
- `PendingItemJSON` fixture and schema.
- Error/recovery metadata for invalid worker, auth-required, admission-blocked,
  mutation-deferred, and serve-unavailable cases.
- M1 kinds: `workerChat` and `followUp`.

Works Test:

```text
Run alln pending add --worker claude "Review this patch when Claude is ready."
Run alln pending list --json.
The item appears as Draft with selected worker, policy, safety, and no guessed
quota/cost/runtime fields.
Run alln pending submit <id>.
The item becomes Pending.
Run alln pending add --submit --worker claude "Continue security review."
The new item is created directly as Pending.
Run alln pending cancel <id>.
The item becomes cancelled and is not drained by alln serve.
```

### Pending1 - Local Pending Model

Goal:
Store user-owned work intent separately from scheduler attempts.

Scope:

- `PendingItem`, target, policy, safety, resume, and attempt summary types.
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

### Pending2 - Serve-Owned Admission-Aware Drain

Goal:
Drain submitted Pending items through `alln serve` when utilization allows,
without guessing availability.

Scope:

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

### Pending6 - FIFO Execute Lanes

Goal:
Let users build a real Execute backlog without parallel writes colliding in the
same worker/session/project.

Scope:

- `PendingExecution.intent = execute`.
- Deterministic `executionLaneKey` derivation.
- FIFO lane scheduler gate before admission spawn.
- `executionLaneBusy` blocked reason.
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
Cancelling Task 1 releases the lane and allows Task 2 to be considered.
```

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Pending -> admission | AllnighterCore | Pending item means worker quota exists | Pending means submitted intent, not that capacity exists | A Pending Claude item with coolingDown admission remains Pending with a reason |
| Admission -> retry | AllnighterEngine | No reset time means estimate one | Unknown reset must be labeled unknown and use conservative recheck policy | UI never renders an invented reset time |
| Worker prose -> Pending | AllnighterCore | Model suggestion creates hidden work | Suggestions are Draft until approved or preset-authorized | Worker says "run tests"; no new Pending item appears |
| iOS command -> Mac execution | iOS remote spine | Phone sent command means Mac ran it | Sleeping/unreachable Mac queues command and reports reachability honestly | Phone shows Mac asleep; no run status is faked |
| Dispatch safety -> away drain | Mac backend | Pending dispatch permission covers any workspace state | Safety is checked at dispatch time; dirty working dir keeps item Pending | Dirty cwd blocks unattended mutating item |
| Execute lane -> workspace ownership | AllnighterEngine | FIFO means Allnighter owns branches/worktrees/landing | FIFO controls submission order only; target worker/process owns workspace setup | Two same-lane Execute items serialize, but no branch/worktree is created |
| Activity Summary -> utilization | Mac backend | Report should estimate what could have happened | Activity Summary reports actual outcomes only | Summary contains no future quota/cost/runtime claims |

## Done When

- The user can add work to Pending without requiring the target worker to
  be available at that moment.
- `alln pending` can create, list, show, cancel, and run Pending items before any
  GUI-only Pending surface ships.
- `alln serve` can drain eligible Pending while the app window is closed.
- Pending items preserve target worker/team, context, fallback, priority, and
  mutation policy.
- Draft is editable and never drained; editing Pending returns it to Draft.
- Stopping Running returns it to Pending; cancellation is explicit.
- Scheduler drains admissible Pending and keeps blocked work Pending with sourced
  reasons.
- Execute work is FIFO per execution lane; later same-lane work does not start
  while an earlier item is running, cooling down, stopped, failed-needs-attention,
  or safety-blocked.
- Cooldown resume can continue an interrupted worker from saved context after an
  observed reset.
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
