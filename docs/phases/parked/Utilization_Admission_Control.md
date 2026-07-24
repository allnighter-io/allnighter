# Utilization Admission Control

Status: PARKED / deferred — shelved as feature creep until real Mac usage proves
the need for admission scheduling
Owner: AllnighterCore + AllnighterEngine + Mac app backend
Updated: 2026-06-17

Parked note:
This packet is intentionally out of the active phase board. Do not implement
`Utilization0`, `Pending2` drain, Away Mode, PTY probes, or admission-ledger work
until this doc is explicitly moved back into `docs/phases/` and re-approved.
`Pending0`/`Pending1` can stand as durable "save this for later" functionality
without promising automated cooldown scheduling.

## Founder Intent

Allnighter should help the user get real value from the AI subscriptions they
already pay for without turning them into a quota accountant or copy-paste
operator.

This is not an overnight-only feature. It matters all day: during a focused work
session, while the app is in the background, while the user is on their phone,
and across short vendor reset windows such as the common 5-hour limits.

The right abstraction is:

```text
admission control, not accounting
```

Admission control asks:

```text
Can this worker accept this specific attempt now?
If not, should Allnighter wait, use an explicit fallback, run a partial team, or ask the user?
```

It does not ask:

```text
How many credits remain?
How expensive is this task?
How long will this run take?
How much quota will this prompt burn?
```

## Product Value

Allnighter's second killer value proposition is **paid-bench utilization**:

```text
The user's existing workers stay useful across the day.
When one worker cools down, Allnighter keeps the floor moving with workers the
user selected, configured, or explicitly allowed.
When work waits, the user sees why.
```

This pairs with persistent work threads:

```text
thread -> worker chat -> team run -> work order -> dispatch -> return review
```

Admission control is what lets that loop keep moving without lying about quota
or silently rerouting work.

## Execution Sequence Decision

Pending must be public CLI-first because it has to execute when the GUI is
closed. Utilization therefore ships against the resident command path, not a
SwiftUI-only queue.

Execute in this order:

```text
1. CLI/resident prerequisite:
   incremental run journal + alln serve + alln doctor coordinator checks
2. Pending CLI contract:
   alln pending add/submit/edit/list/show/cancel/run/stop + PendingItemJSON
3. Utilization0:
   observed admission ledger + parser fixtures + single/team admission checks
4. Utilization1:
   serve-owned pending drain + fairness + away-mode safety + snapshots
5. Utilization2:
   optional PTY usage probes with timeouts, caching, fixtures, and opt-in
```

This does not require the polished Mac Pending UI first. The GUI should render
the same Core/CLI truth after the command contract exists.

## Non-Goals

- No quota dashboard.
- No billing dashboard.
- No estimated cost, runtime, token burn, or task complexity.
- No fake percentages for opaque vendor limits.
- No silent worker substitution.
- No generic "optimize spend" router.
- No browser scraping by default.
- No mutating unattended dispatch in Pending v1. Later dispatch phases may add it
  only with explicit work-order intent and safety checks.

Deferred elsewhere:

- Subprocess loop-breaker / pause-and-inject-hint belongs to streaming/execution
  safety, not this admission-control slice.
- Context handoff / workspace bridge belongs to work threads and dispatch.
- Agent-initiated design boards and deeper delegation fan-out deserve their own
  phase doc; this doc defines the availability policy they will consume.
- Pending item semantics, Away Mode, cooldown resume packets, and Activity Summary
  live in `Pending_Work_And_Drain.md`.
- Process lifetime for app-closed execution lives in
  `Mac_Standalone_App_And_Background_Coordinator.md` and is implemented through
  `alln serve`.

## Product Law

- Do not estimate unused quota.
- Do not estimate future runtime.
- Do not estimate task cost or complexity.
- Do not normalize opaque provider limits into percentages.
- Do not say "remaining" unless the provider explicitly reports that exact
  value.
- Do not route from guessed token burn, guessed runtime, or guessed task
  difficulty.

Allowed:

- Observed worker state.
- Observed provider messages.
- Observed reset/cooldown times when the provider or CLI reports them.
- Observed local recovery intervals: wall event -> later successful attempt for
  the same source/model.
- Exact selected work shape: model, worker lineup, stage, effort setting,
  fallback policy.
- Actual outcomes after work runs.
- Recommendations from explicit capabilities and observed local outcomes.

All admission state is local, sourced, timestamped, and honest.

## Current State

Existing truth owners:

- `Pending_Work_And_Drain.md` owns user-visible Pending intent and drain surface.
- `Mac_Standalone_App_And_Background_Coordinator.md` owns `alln serve` lifecycle
  and single-writer resident behavior.
- `CLI_Implementation_Contract.md` owns public command grammar, JSON/NDJSON,
  generated docs, doctor checks, and proof gates.
- `threads/01_Work_Threads_MLP.md` owns thread turns and context packets.
- `threads/04_Observed_Usage.md` owns observed usage metadata; this doc consumes
  only admission signals from the shared provider observation layer.

Existing useful pieces:

- Worker drivers already observe real run success/failure.
- Thread turns and runs already have status vocabulary that can render Pending,
  Running, failed, and completed work.
- The pending phase now requires `alln pending` and `alln serve` before GUI-only
  execution promises.

Missing implementation:

- No persisted `ModelAdmission` ledger.
- No shared provider observation parser seam for admission + usage.
- No deterministic admission fixtures for provider cooldown/auth/exhaustion text.
- No serve-owned scheduler bridge from Pending items to `AdmissionRequest`.
- No PTY probe runner or manifest grammar.

## SSOT

Truth owner:

```text
AllnighterCore owns admission models, aggregation, and semantic rules.
AllnighterEngine owns admission checks, scheduler decisions, and worker attempts.
alln serve owns resident process lifetime and leases while draining Pending.
Mac/iOS/GUI render snapshots; they do not invent admission truth.
```

Lie-prone layers:

- GUI pills can imply capacity exists because an item is Pending.
- Scheduler code can convert unknown reset windows into fake estimates.
- Driver parsers can overfit one provider string and mark stale capacity high
  confidence.
- iOS can confuse Mac reachability with worker availability.
- PTY probes can become unsafe keepalive loops if not cached and opt-in.

New/changed semantic rules:

- Draft means editable saved intent that is not submitted.
- Pending means submitted intent; admission decides whether an attempt can run.
- Running means an active attempt.
- Blocked admission or safety appears as a sourced reason under Pending, not as a
  separate public Waiting state.
- Queue remains internal scheduler language.
- `alln serve` is the drainer for app-closed Pending work.
- PTY probes are optional admission signals, never the baseline truth source.

Duplicate truth to delete or avoid:

- Per-driver cooldown ledgers outside `ModelAdmission`.
- GUI-local availability state.
- Separate iOS admission stores.
- Prompt-only retry/backoff rules.
- Probe parsers that do not emit `ProviderObservation`.

## User-Visible Claim

```text
Allnighter keeps your AI bench moving and tells you when something needs you.
```

Example floor copy:

```text
4 pending
Codex available
Claude pending - cooling down until 2:14 AM, observed from Claude
Gemini unknown - will check before dispatch
Grok needs sign-in
```

Useful substitution copy:

```text
Claude is cooling down. Codex and Gemini are available. Continue with one of them?
```

Never:

```text
Claude 0% remaining
Codex has 47 minutes left
This task is low cost
Estimated unused quota: 63%
High quota risk
```

## Core Model

Truth owner: `AllnighterCore`.

```text
ModelAdmission
- modelId
- sourceId?
- observedAt
- state: available | coolingDown | exhausted | authRequired | degraded | unknown | busy | manualRequired
- resetAt?
- source: teamRun | workerChat | dispatch | doctor | usageStdout | usagePTY | smokeProbe | browserText | manual
- confidence: high | medium | low
- reason
- windows: [CapacityWindow]
```

```text
CapacityWindow
- scope: provider | modelGroup | model | session | weekly | unknown
- modelLabel?
- state: available | coolingDown | exhausted | authRequired | degraded | unknown
- resetAt?
- label
- source
- confidence: high | medium | low
```

```text
CapacityEvent
- modelId
- sourceId?
- observedAt
- source
- outcome: success | rateLimited | exhausted | authRequired | timeout | cancelled | degraded | parseFailed
- modelLabel?
- resetAt?
- rawSnippet: truncated local text
```

```text
RecoveryObservation
- modelId
- sourceId?
- wallEventId: CapacityEvent.ID       # rateLimited/exhausted/cooling event
- recoveredEventId: CapacityEvent.ID  # later success
- wallObservedAt
- recoveredAt
- intervalSeconds
- source
- confidence: medium | low
```

```text
AdmissionRequest
- turnId?
- runId?
- stageId?
- workerId?                 # runtime worker = model + skill, when applicable
- modelId
- sourceId?
- purpose: workerChat | teamWorker | reduceStage | dispatch | returnReview | probe
- attentionMode: present | away
- mutationMode: nonMutating | mayWriteWorkingDir
- policy: AdmissionPolicy
```

```text
AdmissionPolicy
- selectedOnly | allowFallbacks | allowPartialTeam | requireFullTeam
- fallbackWorkerIds: [Worker.ID]
- allowDegraded: Bool
- requireKnownAvailable: Bool
- unattendedMayMutate: Bool
```

Notes:

- `busy` is local process capacity, not provider quota.
- `manualRequired` is a worker capability/admission state for paste-only flows.
  It is eligible only when the user is present.
- `resetAt` is present only when directly observed or user-entered.
- `RecoveryObservation` is historical local evidence, not a reset promise. It
  may tune recheck timing, but UI must not render it as provider-reported reset.
- `degraded` means "works, but route cautiously": repeated timeouts, partial
  responses, parse instability, or flaky CLI behavior.
- `rawSnippet` stays local and truncated for parser proof/debug.

## Window Aggregation

`ModelAdmission.state` is derived from relevant windows plus local process
state. Implementers must not guess.

Relevant window selection:

- Provider-scope windows apply to every request for that provider.
- Model-group windows apply when the request's model belongs to that group.
- Model windows apply only to the matching model label.
- Session/weekly windows apply when the provider message identifies that scope.
- Unknown-scope windows apply to the model/source until a narrower parser rule
  exists.

Precedence:

```text
authRequired beats everything
busy blocks local spawn but does not change provider state
manualRequired blocks unattended automation
high/medium confidence coolingDown or exhausted blocks matching requests
degraded blocks only when policy disallows degraded workers
unknown does not block unless policy requires known availability
available only means no relevant blocking window is active
```

Confidence rules:

- `high`: parsed from stable driver output, provider/CLI usage output, or a
  rate-limit/auth message fixture.
- `medium`: observed from real failure text but parser confidence is partial.
- `low`: stale, manual, or weakly parsed signal.

Low-confidence blocking states should be shown as stale/uncertain and may expose
manual retry when the user is present. Away-mode scheduling should treat low
confidence conservatively only when the work order requires known availability.

## Signal Ladder

Use signals in this order:

1. Real run outcome.
2. Driver/parser observation from that same output.
3. Headless usage command when a provider exposes one.
4. PTY usage screen for CLIs whose slash commands need a terminal.
5. Smoke probe when stale/unknown and the user has allowed probing.
6. Browser text scrape only as explicit opt-in.

Real runs are the best probe because they answer the actual dispatch question.
If a worker succeeds, it was available. If it rate-limits, the refusal often
contains the next useful admission signal. Do not run a separate probe when
normal work already taught the scheduler enough.

## Shared Provider Observation Layer

Admission and observed usage must not grow duplicate parsers.

Driver-specific parsers should emit a shared local observation:

```text
ProviderObservation
- modelId
- sourceId?
- modelLabel?
- observedAt
- admissionEvent?
- observedUsage?
- rawSnippet?
- source
```

`Utilization_Admission_Control.md` consumes `admissionEvent`.
`threads/04_Observed_Usage.md` consumes `observedUsage`.

One fixture should prove both views when a CLI output contains both a usage
footer and an admission signal. Parser failure fails closed: admission becomes
`unknown` and usage becomes unavailable.

## PTY Probes

PTY probes are optional, per-worker, and never required for the first useful
implementation. They are screen-scraping with a cache, not truth.

Shape:

```text
capacityProbe:
  mode: stdout | pty
  command: ...
  sendSequence: ...
  timeoutSeconds: ...
  parseRules: ...
```

Rules:

- Hard timeout and kill the process tree.
- Cache results with a short TTL.
- Record raw terminal buffers as fixtures.
- Parser rules should live in driver data where possible.
- Parser failures produce `unknown`, not fake availability.
- PTY probes are disabled for workers whose CLI cannot be safely automated.

Candidate probes:

```text
claude /usage       -> stdout/browser behavior where available
codex TUI /usage    -> PTY slash-command automation
agy TUI /usage      -> PTY slash-command automation
```

## Scheduler Behavior

The scheduler routes from observed admission state and explicit user intent.

Inputs:

- Pending item, queued attempt, work order, or thread turn;
- effort setting;
- selected workers and their models;
- fallback policy;
- worker admission state;
- local concurrency slots;
- attention mode: present or away;
- mutation mode: non-mutating or may write to the working directory;
- quiet-hours / notification settings;
- user permissions.

Rules:

- `available`: eligible for matching requests.
- `busy`: wait for local slot.
- `coolingDown` with observed `resetAt`: wake at `resetAt` plus jitter.
- `coolingDown` without `resetAt`: back off and recheck later. If local
  recovery observations exist for that source/model, the scheduler may choose a
  next check from that observed cadence, labeled as a local retry policy rather
  than a provider reset.
- `exhausted`: hold until a later observed signal or user action changes state.
- `authRequired`: hold and ask user to sign in.
- `manualRequired`: hold unless the user is present and chooses the paste flow.
- `degraded`: route only if allowed by the work order or user setting.
- `unknown`: attempt or probe according to policy; learn from the result.

No rule may depend on guessed task cost, guessed task duration, or guessed token
burn.

No-reset honesty:

- Provider-observed reset: "Pending - Claude cooling until 3:30 PM, observed from
  Claude."
- Local retry policy from recovery observations: "Pending - Claude cooling; next
  check at 3:30 PM based on local recovery history."
- No useful signal yet: "Pending - Claude cooling; will check later."

Quiet hours:

- Quiet hours suppress or defer notifications according to notification policy.
- Quiet hours do not silently change admission state.
- If a setting pauses dispatch during quiet hours, that is a user boundary, not
  an availability inference.

Local slots:

- Use a global concurrency governor and per-worker slots.
- A worker with no free local slot is `busy` even if provider capacity is
  available.
- Fairness default: priority/pinned turns first, then oldest submitted Pending turn, with at
  most one new heavy turn per thread per scheduler sweep to avoid starvation.

## Present vs Away

Attention mode changes defaults.

`present` means the user initiated or is actively viewing the choice:

- show choices;
- allow explicit switch worker;
- allow explicit fallback use;
- allow `Attempt anyway` for stale/cooling/degraded/unknown when permitted;
- show source text for observed cooldown/auth/degraded state.

`away` means the work is queued, the app is backgrounded, the phone sent a
command for later, `alln serve` is draining Pending, or the user is not expected
to answer immediately:

- never use `Attempt anyway`;
- never enter manual-paste flow;
- never silently switch workers;
- follow the stored fallback/partial-team policy;
- if policy is ambiguous, hold and mark the thread/turn needs attention.

Mutating dispatch boundary:

- Non-mutating turns (worker chat, team run, review, planning, return review)
  may run away if admission passes.
- Pending v1 does not run unattended mutating dispatch.
- Later dispatch phases may add unattended mutation only when the user explicitly
  added that work order to Pending/Away Mode for unattended dispatch and current
  safety checks pass.
- Without a managed-isolation phase, a dirty or changed working directory blocks
  unattended mutating dispatch and creates a needs-attention badge.

## Effort and Admission

Effort is a user instruction, not an estimate.

Effort may influence selected work shape:

- number of team workers;
- whether analysis and plan are separate;
- whether review/final-spec stages are included;
- requested reasoning level where the worker supports it;
- default patience policy for the selected preset.

Effort must not imply:

- predicted cost;
- predicted runtime;
- predicted quota burn;
- predicted task difficulty.

Recommended defaults:

```text
Fast / low effort       -> partial team allowed when enough selected workers are available
Standard / medium       -> ask when present; away follows preset policy
Quality / high effort   -> require selected team unless the user configured fallback/partial policy
Custom                  -> exact user policy
```

These are defaults for work shape and patience only. They are not forecasts.

## Team and Stage Admission

Admission is checked per dispatch attempt:

```text
one worker chat turn
one team worker
one reduce stage
one dispatch
one return review
```

The run coordinator aggregates those checks before spawning work.

Team policies:

```text
requireFullTeam      -> hold until every selected required worker is admissible
allowPartialTeam     -> run admissible workers when minWorkers is met
allowFallbacks       -> use configured fallback workers in order
selectedOnly         -> no substitute workers
```

Default behavior:

- Named quality/high-effort presets should require the selected team unless
  their preset explicitly allows partials or fallbacks.
- Fast/good-enough presets may allow partial teams when the minimum worker count
  is met.
- A present user may choose "run available team now."
- Away mode follows the stored preset/work-order policy. If no policy is stored,
  hold instead of guessing.

Missing workers:

- A skipped/unavailable worker becomes an explicit worker answer with
  status/reason.
- The plan writer receives unavailable workers as first-class absences.
- The plan or stage summary must surface that the team was incomplete.
- A failed worker is never hidden by synthesis.

Mid-run changes:

- If a worker rate-limits mid-run, record the event and let policy decide
  whether the team can continue.
- If a required reduce-stage worker cools down after the team run, pause that stage
  and resume when admission passes, or ask the present user to switch.
- If the same model appears in multiple workers and one observes a rate limit,
  remaining not-yet-started workers for that model inherit the updated admission
  state.

## Fallback Bench

Fallbacks are useful, but only when explicit.

Allowed:

```text
If Claude is cooling, try Codex, then Gemini.
If Opus plan writer is unavailable, use Sonnet as plan writer.
If image reader is unavailable, hold and ask.
```

Banned:

```text
Silently send Claude's turn to Codex.
Silently replace the user's selected plan writer.
Silently change a quality preset into a fast preset.
```

Fallback workers come from user settings, preset policy, or the specific work
order. Every fallback choice is recorded on the turn/run.

Recommendations may use:

- explicit worker capabilities;
- headless vs manual-paste capability;
- image/file/context capability;
- observed local outcomes and scorecards;
- current admission state.

Recommendations may not use guessed prompt complexity, guessed burn, or fake
remaining quota.

## Pending UX

Capacity should appear where it changes behavior: on Pending, the thread
composer, worker picker, active Project, and iOS Project Manager. It should not
become a quota dashboard.

Public words:

```text
Draft   = editable saved intent; not submitted and not eligible to drain.
Pending = submitted intent; may run when admission and safety allow.
Running = active attempt.
Queue   = internal scheduler machinery; avoid in core GUI copy.
```

Blocked admission, local slots, safety, auth, or manual action render as reasons
under Pending. The user does not need a public Waiting state.

Useful copy:

```text
3 pending
Pending - Claude cooling until 2:14 AM, observed from Claude
Pending - local slot busy; Codex is already running
Pending - Grok sign-in required
Gemini unknown - will check before dispatch
Claude has been flaky - last 2 runs timed out
Team ran with 4 of 6 selected workers; 2 were cooling down
```

Avoid:

```text
Predicted-burn warning
Estimated reset in 3h
Cheap task
Low-cost worker
Quota saved
```

If the reset time is observed from a provider message, label it as observed. If
it is not observed, do not invent it.

## Activity Summary

The summary is the receipt for paid-bench utilization. It must report actual
outcomes only.

Example:

```text
Since you last checked:
- 4 turns completed
- 1 team ran with 4 of 6 selected workers
- 1 dispatch pending - working directory changed
- 1 worker needs sign-in

Workers used:
- Codex: 3 turns
- Gemini: 1 team worker
- Claude: pending until 2:14 AM, observed from Claude
```

This may appear as Activity Summary, a thread/Project recap, or an iOS summary.
The name of the surface may vary; the contract is the same: actual completed,
failed, blocked, skipped, and needs-attention work. No estimates.

## Thread / Composer Interaction

Persistent work threads use admission state at the point of action:

- The worker picker shows `available`, `coolingDown`, `exhausted`,
  `authRequired`, `degraded`, `manualRequired`, `unknown`, and `busy` badges only
  where they affect the next turn.
- `degraded` is a warning on the worker picker/composer, not a noisy timeline
  event unless it blocks a turn.
- `authRequired` blocks and asks the user to sign in. Do not offer "attempt
  anyway" because the missing action is user authentication.
- `busy` means local capacity is occupied; offer add to Pending, wait, or cancel
  active local work, not provider bypass.
- `manualRequired` means the worker can still participate when the user is
  present, but it is not useful for automatic Pending drain.
- `unknown` should normally attempt the requested present work once rather than
  run a separate probe first; the real outcome becomes the admission signal.
- `coolingDown`, `exhausted`, `degraded`, and `unknown` may expose explicit
  present-mode actions when policy permits.

Manual override rules:

- Label the override as a retry of stale/uncertain observed state, not as a
  promise that quota exists.
- Record `source: manual` and the resulting `CapacityEvent`.
- If it succeeds, update the worker to `available`.
- If it rate-limits, refresh `coolingDown`/`resetAt` from the observed message.
- If it fails for auth, move to `authRequired`.
- Never run manual override in away mode.

Settings must include **Reset Admission Ledger**. It clears observed cooldown and
degraded memory locally; it does not alter worker auth, provider limits, or run
history.

## iOS Project Manager Visibility

The Mac remains admission truth. iOS renders admission state from Mac-owned
events/snapshots.

iOS must be able to answer:

```text
What is running?
What is Draft?
What is Pending, and why?
What is Running?
Which worker needs me?
Can I stop it?
Can I approve a pending action?
```

Push payloads stay content-light. Sensitive content is fetched through the
remote spine according to the iOS trust docs.

## Privacy and Permissions

This feature can touch sensitive surfaces: terminal output, browser pages,
subscription/account UI, and provider error text.

Rules:

- Local only by default.
- No credentials or account pages leave the Mac.
- Browser scraping is opt-in and off by default.
- Store only truncated snippets needed for parser proof.
- Let the user clear the admission ledger.
- Do not collect provider billing/account identifiers unless explicitly needed
  and separately approved.
- Do not expose provider snippets to iOS push payloads.

## Implementation Slices

Global prerequisites:

- `alln serve` exists and can own resident leases for app-closed Pending drain.
- Run journal writes are incremental before resident/away work can be claimed
  durable.
- `alln doctor --json` can report coordinator, source auth, and parser-fixture
  health.
- `alln pending` can create/submit/edit/list/show/cancel/run/stop
  `PendingItemJSON`.

### Utilization0 - Observed Admission Ledger

Goal:
Learn worker availability from real runs and source-labeled driver output. No
PTY required.

Depends on:

- Existing worker driver execution path.
- `CapacityEvent` fixtures checked into the Core test bundle.
- Shared clock abstraction for fake reset-time tests.

Scope:

- `ModelAdmission`, `CapacityWindow`, `CapacityEvent`,
  `AdmissionRequest`, and `AdmissionPolicy`.
- `ProviderObservation` parser seam shared with observed usage.
- Rate-limit/auth/exhausted/timeout/degraded parser for `WorkerRunner` failures.
- `RecoveryObservation` creation when a later success follows a cooldown/rate
  limit without provider reset time.
- Local ledger persisted beside run/thread history.
- Window aggregation and confidence precedence.
- Thread/composer badges and present-mode decisions.
- Single-worker and team-level admission checks.
- `alln doctor --json` admission summary: source, state, observedAt,
  confidence, resetAt when observed, and parser health.

Out of scope:

- PTY probes.
- Resident drain fairness.
- GUI-only Pending controls.

Works Test:

```text
Fake worker returns rate-limit text with reset time.
Allnighter records coolingDown/resetAt with source.
Pending work does not dispatch to that worker.
Fake clock reaches resetAt.
Worker is tried once and dispatches if available.
```

Team Works Test:

```text
Create a 4-worker team: 2 available, 2 coolingDown.
With requireFullTeam, the run holds and explains which workers block it.
With allowPartialTeam(minWorkers: 2), the run starts 2 workers.
The plan writer receives explicit unavailable-worker records for the skipped workers.
The final plan says the team was incomplete.
```

Proof commands:

```text
swift test --filter Admission
swift test --filter ProviderObservation
swift test --filter RecoveryObservation
alln doctor --json
```

### Utilization1 - Pending Drain and Floor Policy

Goal:
Make Pending items move when selected or fallback workers become available,
across normal workday, `alln serve`, mobile, and away modes.

Depends on:

- Utilization0.
- `alln pending` public command contract.
- `alln serve` background scheduler with single-writer journal behavior.
- Pending item leases that recover after coordinator restart.

Scope:

- Queue wakeups from observed reset times.
- Jittered retries and backoff.
- Recheck timing can use observed local recovery cadence when no provider
  `resetAt` exists, without presenting it as a provider reset.
- Local concurrency slots and fairness.
- Auth-required holds.
- Degraded-worker policy.
- Fallback bench policy.
- Present vs away behavior.
- Activity summary of actual outcomes.
- iOS-readable admission state snapshots/events.
- Pending list rows that can show `Draft`, `Pending`, `Running`, `done`,
  `failed`, `cancelled`, and `needs attention`.
- `alln pending run <id>` behavior for present/manual attempts; if the item is
  Draft, run submits it first.
- `alln serve` drain behavior for away/unattended attempts.

Out of scope:

- PTY probes.
- Follow-up suggestion creation; that belongs to Pending.
- Mutating dispatch beyond the explicit safety gate.

Works Test:

```text
Three Pending items, two workers cooling down, one available.
Scheduler dispatches only admissible work.
At observed reset time, one blocked Pending item is retried once.
Summary reports actual completed/failed/blocked work, not estimates.
```

Mutation-Deferred Works Test:

```text
Create a Pending item that would require unattended mutation.
Set the user away.
Allnighter keeps it Pending with mutation-deferred reason and does not run the
worker.
```

App-closed Works Test:

```text
Start alln serve.
Create a Pending item with alln pending add --worker model_opus --when ready.
Close the GUI.
Fake clock reaches observed resetAt.
alln serve leases and runs the item.
Reopen the GUI.
The same pending/run/thread journal renders without field translation.
```

No-Reset Works Test:

```text
Fake Claude rate-limits without resetAt.
Scheduler keeps the item Pending and schedules a conservative retry.
Later fake Claude succeeds.
Allnighter records wall -> recovery interval.
Future no-reset cooldown uses that observed cadence for next check copy labeled
as local recovery history, not provider reset.
```

Proof commands:

```text
swift test --filter PendingDrain
swift test --filter AdmissionScheduler
alln pending list --json
alln doctor --json
```

### Utilization2 - Optional PTY Usage Probes

Goal:
Use terminal-only slash commands as optional admission signals.

Depends on:

- Utilization0 parser seam and admission ledger.
- Utilization1 cache/backoff policy, so probes do not become churn.
- Per-source manifest entries that explicitly opt in to PTY probing.

Scope:

- `forkpty` runner.
- Manifest-driven send sequence and parse rules.
- Fixtures for raw terminal buffers.
- Timeout/kill/caching.
- Per-worker setting to enable/disable PTY probing.
- Probe audit event linked to `CapacityEvent`.
- `alln doctor --json --full` probe status with last observed source, cache age,
  timeout/error, and whether PTY probing is disabled.

Out of scope:

- Browser scraping.
- Provider account-page automation.
- Any probe loop that runs more often than cache/backoff policy allows.
- Making PTY probes required for Pending drain.

Works Test:

```text
Fixture terminal buffer for codex /usage parses to coolingDown.
Malformed buffer parses to unknown.
Probe timeout leaves no child process.
```

Safety Works Test:

```text
Disable PTY probing for Claude.
Run alln doctor --json --full.
No PTY process starts for Claude.
Enable a fake PTY probe with a 1s timeout.
The child process tree is killed after timeout and admission remains unknown.
```

Proof commands:

```text
swift test --filter PTYProbe
swift test --filter AdmissionProbeCache
alln doctor --json --full
```

## Done When

- Allnighter can hold Pending work because a selected worker is cooling down,
  exhausted, auth-required, manual-required, degraded, busy, or unknown under a
  policy that requires known availability.
- It can resume when an observed reset or later signal says the worker may run.
- `alln serve` can drain admissible Pending while the app window is closed.
- The user can see why work is Pending in thread, Pending, Mac floor, and iOS
  floor views where implemented.
- Present users can explicitly switch, fallback, run partial teams, or retry
  stale states where policy permits.
- Away-mode scheduling never silently switches workers or uses manual override.
- Team runs have deterministic full/partial/fallback behavior.
- A skipped or unavailable worker is visible to the plan writer and the user.
- Mutating away dispatch remains deferred from Pending v1 and cannot run through
  the baseline Pending drain.
- The local admission ledger can be reset.
- PTY probes, when enabled, are opt-in, cached, timeout-bound, fixture-tested,
  and never required for the baseline Pending drain.
- No UI, scheduler, CLI, or MCP path estimates future cost, runtime, quota burn,
  token burn, or task complexity.

## Proof Command

```text
swift test
scripts/check.sh
```

Parser tests must be deterministic and fixture-backed. UI claims about iOS
visibility require the remote-spine Works Test before public copy says the phone
can monitor admission state.
