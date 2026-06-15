# Pending Work and Drain

Status: Draft founder packet; CLI-first Pending approved
Owner: AllnighterCore + AllnighterEngine + Mac app backend
Updated: 2026-06-15

## Founder Intent

Allnighter should let the user create useful work even when the best worker is
busy, cooling down, asleep behind Mac reachability, or otherwise unavailable.

The user should not have to babysit Claude's reset windows. They should be able
to leave work ready, go away, and trust Allnighter to drain it when the selected
worker or allowed fallback can accept work again.

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

Allnighter's core promise is an overnight AI-agent factory. A first-class
Pending surface turns intermittent model availability into continuous useful
work:

```text
capture intent now
-> package it as a safe work item
-> wait honestly when workers are unavailable
-> drain ready work when admission passes
-> show the morning receipt
```

This is especially valuable around short vendor reset windows. Native model UX is
session-attention-bound: if Claude cools down, the user usually has to remember,
return, reconstruct context, and try again. Allnighter can keep the context,
retry at the observed wake time, and preserve the user's priority order.

## Trusted Workflow Slice

```text
user captures several work items
-> Allnighter stores them as Pending items with explicit worker/team policy
-> scheduler admits only safe, available attempts
-> cooled-down workers are retried from observed reset signals or conservative rechecks
-> completed, held, failed, and needs-attention items appear in Morning Pull
```

First lovable slice:

```text
Claude cools down mid-job
-> Allnighter records a held follow-up
-> observed reset time arrives
-> Allnighter asks Claude to continue from the saved context
-> the thread shows the completed follow-up or the new blocking reason
```

## Non-Goals

- No quota dashboard.
- No billing dashboard.
- No estimated remaining quota, runtime, cost, token burn, or task complexity.
- No provider-limit evasion, spam probing, or synthetic keepalive loops.
- No unattended mutating dispatch unless the work item explicitly allows it and
  safety checks pass.
- No silent worker substitution.
- No cloud-owned durable Pending store.
- No provider-native chat-history dependency.
- No automatic creation of unapproved new work from worker suggestions.

Deferred elsewhere:

- Admission states, cooldown parsing, fallback policy, and probes belong to
  `Utilization_Admission_Control.md`.
- Work-thread storage and context packets belong to `Persistent_Work_Threads.md`
  and `threads/01_Work_Threads_MLP.md`.
- iOS reachability, sealed command inbox, and sleep/drain behavior belong to
  `ios/00_iOS_Transport_Decision.md` and the iOS spine.

## User-Visible Claim

```text
Allnighter keeps Pending ready and drains it when your selected workers can work.
```

Sharper product copy:

```text
Keep Claude's next window full.
```

Useful floor copy:

```text
Night shift: 8 items ready
Claude: 3 waiting - cooling down until 2:14 AM, observed from Claude
Codex: running 1 item
Gemini: 2 ready
1 dispatch needs attention - working directory changed
```

Useful item copy:

```text
Waiting for Claude. Will retry after observed reset.
Claude cooled down while reviewing Codex's patch. Follow-up is pending.
Ready for any allowed reviewer: Claude preferred, Codex fallback allowed.
Held for you: this dispatch can write to the working directory.
```

Never:

```text
Claude has enough quota for this
Low-cost Pending item
Estimated reset window
We saved 63% quota
```

## Core Distinction

Pending and queue are related, not identical.

```text
Pending = user-owned intent waiting to become or continue work.
Queue   = scheduler-owned attempts waiting on admission, local slots, or safety.
```

A Pending item can create one or more queued attempts over time. A queue entry is
an execution attempt, not the durable user intent.

## Public CLI Decision

Pending is public CLI vocabulary, not a GUI-only label.

Required public surfaces:

```text
GUI: Pending pill/filter, pending item rows, add-to-pending composer action.
CLI: alln pending add/list/show/cancel/run, backed by the same PendingItem model.
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

Examples:

- User says "ask Claude to review this when it is back" -> Pending item.
- Scheduler holds the Claude attempt until cooldown ends -> queue entry.
- Claude cools down mid-run and the item needs continuation -> same Pending item,
  new queued attempt with a resume packet.
- Worker suggests "run a proof skeptic pass" -> suggested Pending item, not ready
  until the user approves or a preset explicitly permits that suggestion class.

## Product Laws

- Queueing is not failure. Queueing is how Allnighter converts intermittent
  availability into useful work.
- Pending items are explicit user intent, preset intent, or approved suggestions.
- Admission still owns availability. Pending must not guess quota or readiness.
- A worker reset time is used only when observed from provider/CLI output or
  user-entered.
- If no reset time is known, rechecks use conservative backoff and local policy;
  the UI says "will check later," not "resetting soon."
- Real work is the best probe. Do not run a separate probe when a normal queued
  attempt is allowed and would teach the same admission fact.
- Away mode follows stored policy only. It never attempts manual paste, silent
  fallback, or "try anyway."
- Mutating dispatch requires explicit unattended permission and a clean safety
  check at the moment of dispatch.
- A failed, skipped, held, or substituted worker is recorded honestly.
- Morning Pull reports actual outcomes only.

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

- Thread turns already have `queued` and `running` status.
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
- No Night Shift or Morning Pull contract exists for draining user-selected work
  overnight.

## SSOT

Truth owner:

```text
AllnighterCore owns Pending models and semantic rules.
AllnighterEngine owns drain scheduling.
CLI command registry owns the public alln pending grammar and JSON projection.
Mac app backend owns local persistence, safety checks, and floor snapshots.
```

Lie-prone layers:

- SwiftUI Pending views can confuse ready intent with available capacity.
- iOS snapshots can make sleeping Mac commands look like started work.
- Scheduler code can accidentally turn retry policy into quota guessing.
- Worker-generated prose can accidentally become hidden work.
- Dispatch UI can treat "queued" as permission to write later under changed
  workspace conditions.

New/changed semantic rules:

- A Pending item is durable user intent; a queue entry is an execution attempt.
- Ready Pending means "safe to consider for admission," not "worker available."
- Cooldown resume is a continuation of the same Pending item unless the user
  forks it into a new item.
- Morning Pull is a receipt, not a forecast.
- Suggested follow-ups are draft until approved or preset-authorized.

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
- status: draft | ready | held | leased | running | done | failed | cancelled | needsAttention
- priority: pinned | normal | low
- createdAt
- updatedAt
- createdBy: user | preset | failedRun | returnReview | approvedSuggestion | remoteDevice
- prompt
- contextPacketId?
- seedTurnId?
- runId?
- stageId?
- target: PendingTarget
- policy: PendingPolicy
- safety: PendingSafety
- resume: PendingResume?
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
- drainMode: manualStart | drainWhenReady | drainOvernight
- maxAttempts?
- retryFloorSeconds?
- allowDegraded: Bool
- requireKnownAvailable: Bool
- createSuggestedFollowUps: Bool
```

```text
PendingSafety
- mutationMode: nonMutating | mayWriteWorkingDir
- unattendedMayMutate: Bool
- workingDir?
- requiresCleanWorkingDir: Bool
- requiresTrustedDevice: Bool
- privacyLabel?
```

```text
PendingResume
- reason: cooldown | localBusy | timeout | cancelled | appRestart | macSleep | userPaused
- lastAttemptId?
- transcriptRef?
- nextInstruction
- observedResetAt?
- wakeAfter?
```

```text
PendingAttemptSummary
- attemptId
- createdAt
- startedAt?
- completedAt?
- workerIds: [Worker.ID]
- status: queued | running | done | failed | timedOut | cancelled | skipped | held
- admissionEventIds: [CapacityEvent.ID]
- reason
```

Notes:

- `PendingItem` owns user intent. It may reference thread turns and runs, but it
  does not duplicate run truth.
- `PendingPolicy` composes with `AdmissionPolicy`; it does not replace it.
- `PendingResume.nextInstruction` must be visible/editable before a held item is
  resumed in present mode.
- `expiresAt` is optional and user/preset-defined. Do not invent expiry from
  guessed usefulness.

## Scheduler Drain Policy

Inputs:

- ready or held Pending items;
- derived queue entries;
- `ModelAdmission` from utilization;
- local concurrency slots;
- Mac reachability and power posture;
- attention mode;
- mutation safety checks;
- notification and quiet-hours settings.

Default order:

```text
1. pinned needs-attention items that can be resolved by the present user
2. pinned ready items
3. resume attempts after observed resetAt/wakeAfter
4. oldest ready item per active thread
5. oldest remaining ready item
```

Fairness rules:

- At most one new heavy item per thread per scheduler sweep unless pinned.
- A cooling worker does not block unrelated ready work for other workers.
- A preferred worker can hold a specific item without holding all Pending work.
- Fallbacks run only when stored policy allows them.
- If all selected workers are blocked and no fallback is allowed, the item stays
  held with the observed reason.

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

## Night Shift

Night Shift is the product surface for pending work intended to drain while the
user is away.

The composer can stay prompt-first:

```text
Add to Night Shift
Run when ready
Claude preferred
Fallbacks: Codex, Gemini
Mutation: ask before writing
```

Night Shift must show the boundary before the user leaves:

- what can run unattended;
- which workers are selected or allowed as fallbacks;
- whether any item can write to the working directory;
- what will pause for sign-in, manual paste, or dirty working tree;
- what notifications will wake the user.

This is close to the Allnighter brand because it makes the Mac feel like an
overnight floor: not a passive queue, but a shift plan.

## Follow-Up Harvesting

Completed and failed work may propose follow-up Pending items, but suggestions
are not ready work until authorized.

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
What is ready?
What is waiting?
What can run overnight?
What needs me?
What completed since I left?
Can I pause/cancel/reprioritize it?
```

Remote capture:

- a phone-created Pending item is sealed to the Mac before relay;
- if the Mac is asleep, the command waits and drains on next wake according to
  the iOS transport docs;
- phone UI distinguishes `Mac asleep`, `Mac unreachable`, `worker cooling`,
  `auth required`, and `ready on Mac`.

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
- Mutating dispatch keeps the existing working-directory safety boundary.
- The user can pause Night Shift and cancel queued attempts.
- The user can delete Pending items without deleting completed run history they
  already generated, unless they explicitly delete both.

High-risk stops before implementation:

- any new cloud-durable Pending storage;
- any background behavior that changes macOS permission posture;
- any unattended write behavior broader than an explicit work item;
- any automated probing that could look like provider-limit evasion.

## Implementation Impact

Core/package impact:

- Add Pending models, Codable persistence, validation, and fixture builders.
- Add deterministic derivations for item display state and needs-attention state.
- Add tests for ready/held/leased/running/done transitions.

CLI impact:

- Add `alln pending` to the command registry before GUI wiring depends on it.
- Emit `PendingItemJSON` from `add`, `show`, and `run`.
- Make `alln pending list --json` the proof surface for GUI/iOS snapshots.
- Make `alln serve` the only resident drainer for app-closed execution.

Mac app backend impact:

- Persist Pending beside thread/run history.
- Expose a floor snapshot that includes Pending items, queue attempts, and held
  reasons.
- Run safety checks immediately before mutating dispatch.
- Provide pause, cancel, reprioritize, and run-now actions.

Engine impact:

- Bridge Pending items to admission requests.
- Lease items before spawning attempts so app restarts can recover cleanly.
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
- `alln pending cancel <id>`.
- `alln pending run <id>`.
- `PendingItemJSON` fixture and schema.
- Error/recovery metadata for invalid worker, auth-required, admission-blocked,
  unsafe mutation, and serve-unavailable cases.

Works Test:

```text
Run alln pending add --worker claude "Review this patch when Claude is ready."
Run alln pending list --json.
The item appears with status ready or held, selected worker, policy, safety, and
no guessed quota/cost/runtime fields.
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
- Basic Mac Pending list: ready, held, running, done, needs attention.
- Manual `Add to pending` and `Run when ready` for non-mutating worker chat/team
  work.

Works Test:

```text
Create three Pending items from a thread.
Restart the app.
Items remain ordered, linked to the thread, and not duplicated as run truth.
Manual run creates one queued attempt and records the attempt summary.
```

### Pending2 - Serve-Owned Admission-Aware Drain

Goal:
Drain ready Pending items through `alln serve` when utilization allows,
without guessing availability.

Scope:

- Scheduler bridge from Pending items to `AdmissionRequest`.
- `alln serve` owns leases and attempts while running.
- Observed reset wakeups.
- Conservative rechecks when no reset is known.
- Local slot fairness.
- Held reasons and needs-attention transitions.
- No mutating unattended dispatch yet unless safety check is explicitly wired.

Works Test:

```text
Three Pending items target Claude, Codex, and Gemini.
Claude is cooling down with observed resetAt.
Codex is available.
Gemini requires auth.
Scheduler runs Codex, holds Claude until resetAt, and marks Gemini needs sign-in.
Morning summary reports only actual completed/held/auth-required outcomes.
```

### Pending3 - Cooldown Resume

Goal:
Make mid-job cooldown feel like a pause, not a lost session.

Scope:

- Worker failure parser creates `PendingResume` for eligible failed/held work.
- Resume packet includes transcript/ref, prior attempt status, and next
  instruction.
- At observed reset, scheduler starts a continuation attempt if policy allows.
- Present user can edit the continuation instruction before resume.

Works Test:

```text
Fake Claude worker rate-limits mid-review and reports reset time.
Allnighter creates a held follow-up with resume context.
Fake clock reaches resetAt.
Worker receives a continuation prompt referencing the prior transcript.
The thread shows the completed follow-up or the new observed block.
```

### Pending4 - Night Shift and Morning Pull

Goal:
Make overnight draining a visible, lovable product surface.

Scope:

- Night Shift composer affordance.
- Away-mode drain settings.
- Pause/resume/cancel/reprioritize controls.
- Morning Pull summary.
- iOS-readable Pending snapshot/events.
- Mutating-dispatch safety gate if dispatch is included.

Works Test:

```text
Queue five Night Shift items, including one mutating dispatch.
Set the user away.
Available non-mutating items run.
The mutating dispatch holds when the working directory changes.
Morning Pull reports completed, held, failed, and needs-attention items without
quota, cost, runtime, or token estimates.
```

### Pending5 - Approved Follow-Up Harvesting

Goal:
Let completed work propose useful next steps without inventing hidden work.

Scope:

- Suggested Pending item model or `PendingItem.status = draft`.
- Suggestion cards from return review and failed runs.
- Preset-approved suggestion classes.
- Audit trail from suggestion to source turn/run/stage.

Works Test:

```text
Codex dispatch completes.
Return review suggests "Ask Claude to review diff when available."
The suggestion appears as a draft Pending item.
Approving it creates a ready item targeting Claude.
If Claude is cooling down, it holds with the observed reason.
```

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Pending -> admission | AllnighterCore | Ready item means worker quota exists | Ready means user intent is runnable when admitted, not that capacity exists | A ready Claude item with coolingDown admission remains held |
| Admission -> retry | AllnighterEngine | No reset time means estimate one | Unknown reset must be labeled unknown and use conservative recheck policy | UI never renders an invented reset time |
| Worker prose -> Pending | AllnighterCore | Model suggestion creates hidden work | Suggestions are draft until approved or preset-authorized | Worker says "run tests"; no new ready item appears |
| iOS command -> Mac execution | iOS remote spine | Phone sent command means Mac ran it | Sleeping/unreachable Mac queues command and reports reachability honestly | Phone shows Mac asleep; no run status is faked |
| Dispatch safety -> away drain | Mac backend | Queued dispatch permission covers any workspace state | Safety is checked at dispatch time; dirty working dir holds | Dirty cwd blocks unattended mutating item |
| Morning Pull -> utilization | Mac backend | Report should estimate what could have happened | Morning Pull reports actual outcomes only | Summary contains no future quota/cost/runtime claims |

## Done When

- The user can add work to Pending without requiring the target worker to
  be available at that moment.
- `alln pending` can create, list, show, cancel, and run Pending items before any
  GUI-only Pending surface ships.
- `alln serve` can drain eligible Pending while the app window is closed.
- Pending items preserve target worker/team, context, fallback, priority, and
  mutation policy.
- Scheduler drains admissible ready work and holds blocked work with sourced
  reasons.
- Cooldown resume can continue an interrupted worker from saved context after an
  observed reset.
- Night Shift makes unattended non-mutating work understandable before the user
  leaves.
- Morning Pull reports actual outcomes across completed, held, failed, skipped,
  cancelled, and needs-attention items.
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
copy says the phone can submit or monitor Night Shift items.
