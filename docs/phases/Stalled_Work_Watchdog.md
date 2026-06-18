# Stalled Work Watchdog

Status: Finalized Project-scoped v1 implementation spec
Owner: AllnighterCore + AllnighterEngine + Mac app backend + CLI/MCP contracts
Updated: 2026-06-18

## Authority

This doc owns the stalled-work detection and recovery contract.

Read with:

- `docs/phases/Project_Spine_And_Project_Manager.md`
- `docs/phases/Persistent_Work_Threads.md`
- `docs/phases/threads/02_Notifications.md`
- `docs/phases/Pending_Work_And_Drain.md`
- `docs/phases/Agent_First_MCP_And_Messaging_Workflows.md`
- `docs/operations/Execution-Playbook.md`

Durable semantics live in AllnighterCore and Project Manager turns. SwiftUI,
notifications, prompt copy, CLI output, MCP output, and worker prose render or
project this truth; they do not own it.

## Founder Intent

Allnighter should keep Project work moving after the user walks away.

The important user question is not:

```text
Can Allnighter predict quota, runtime, or cooldowns?
```

It is:

```text
Did the work I asked for get stuck, and what should I do next?
```

The Project Manager should notice old nonterminal work from local truth, create
one durable nudge in the right Project, and offer safe recovery actions without
becoming a quota brain, global queue, or background scheduler.

## Product Claim

```text
The Project Manager notices when Project work stops moving and gives you one
safe next move.
```

It should feel like:

```text
The Project Manager knows this Project has a run that has not moved, checked the
local truth before bothering me, and can help me refresh, wait, open, or cancel.
```

It must not feel like:

```text
A timer that nags, a second job tracker, a quota predictor, or an agent that
silently retries work behind my back.
```

## First-Principles Decision

Stalled work is a recovery loop, not admission control.

Admission asks:

```text
Should a worker start now?
```

The watchdog asks:

```text
Work already started or was queued for start. Has local truth stopped changing
long enough that the Project Manager should ask the user to decide?
```

Therefore v1 uses only observed local truth:

- Project id;
- thread/run/turn status;
- journal or stage events;
- known terminal outcomes;
- known auth/setup/manual blockers;
- notification mute/debounce settings;
- user decisions on the current stall episode.

It does not estimate quota, cost, token burn, reset windows, runtime, task
complexity, or provider capacity.

## Trusted Workflow Slice

```text
worker chat turn or async team run enters queued/running
-> watchdog records the last observable local event
-> deadline passes with no new event
-> watchdog refreshes status from existing local truth
-> if still nonterminal and still no progress, create one Project Manager nudge
-> Mac notification points to that nudge when allowed
-> user checks status, opens the thread, keeps waiting, or cancels
-> stall episode clears when local truth moves terminal or user recovery ends it
```

## V1 Scope

V1 targets only the two cases with the clearest signal and highest user pain:

| Target | Included states | Default threshold | Why v1 |
| --- | --- | --- | --- |
| Worker chat turn | `queued`, `running` | 30 minutes since last observable event | The user asked one worker for an answer and nothing came back. |
| Async team run | `queued`, `running`, nonterminal worker stage | 60 minutes since last observable event | Fanout/team runs are core Allnighter value and already have status/result refresh paths. |

The defaults are intentionally boring. They are product defaults, not
predictions. They can become per-Project/user settings after real dogfood
evidence shows the noise shape.

Deferred from v1:

- idle Pending items that have not been run;
- approved proposals or work orders that have not been dispatched;
- dispatch return review follow-ups;
- native drain/scheduler loops;
- cooldown/admission-driven resume;
- worker substitution;
- prompt rewriting;
- silent retry.

Pending may be "blocked" or "needs attention," but idle Pending is not
stalled. Pending means work is on the Project desk until a user or external loop
owner runs it.

## Project Law

Every stall candidate must resolve to exactly one Project.

Rules:

- A candidate without a reliable `projectId` is a repair/unassigned problem, not
  a stalled-work nudge.
- Stalls in one Project must not block, reorder, or reprioritize another
  Project.
- Project root truth comes from `ProjectStore`; raw `workingDir` values are
  historical receipts only.
- The durable nudge is a `ProjectManagerTurn` for that Project with typed
  `nextActions`.
- The target thread receives the existing `thread.needsAttention` signal with a
  `stallReason` facet. Do not create a parallel attention system.
- Global stalled views are aggregate floor views grouped by Project. They are
  not a global durable queue.
- Project Manager triage order comes from the same Home/Project triage contract
  used by threads and notifications, not watchdog scan order.

## Dependency On Project Spine

The watchdog is Project Manager behavior. It should not ship as a global run
scanner ahead of the Project floor.

Minimum Project Spine dependencies:

- durable Projects exist;
- new threads and runs can resolve `projectId`;
- Project context can include active runs and attention records;
- Project Manager turns can carry typed `nextActions`;
- notifications can open the linked Project/thread/turn.

Rules:

- Before a target can resolve `projectId`, the scanner must emit no stalled
  episode for it. It may surface a repair/unassigned warning through the owning
  migration path.
- Active stalls may be summarized in `ProjectContextPacket.work`, but the
  packet is a receipt. `StallEpisode` remains the durable stall truth.
- Non-git folder Projects may still have stalled chat/team-run attention, but
  recovery remains limited to safe actions. They can never gain commit-proof
  semantics from the watchdog.

## State Distinctions

The watchdog must not relabel every old item as stalled.

| State | Truth owner | Watchdog role |
| --- | --- | --- |
| Terminal failure, timeout, cancellation, or completion | Turn/run lifecycle + notification policy | Do not create a stalled nudge. Existing failure/completion attention owns it. |
| Auth/setup/manual-paste blocked | Worker readiness, turn state, or notification events | Surface setup/manual copy through existing attention. Do not call it stalled. |
| Idle Pending | Pending model | Do not call it stalled. It is waiting for a user, CLI, GUI, MCP client, or external loop owner to run it. |
| Blocked Pending | Pending model + admission/safety reason | Keep the Pending label and sourced blocker. It may need attention, but it is not stalled. |
| True stall | Stalled Work Watchdog | Nonterminal queued/running work in one Project with no local progress past threshold after refresh. |

Canonical active stall states:

```text
candidate -> refreshing -> active -> snoozed -> cleared
```

`candidate` and `refreshing` are internal. The user sees only `active`,
`snoozed`, or cleared history.

## Progress Signal

V1 uses cheap progress signals already present in local truth. It does not run a
provider probe to decide whether something is stalled.

`lastObservableEvent` is the newest of:

- turn status change;
- run/team stage status change;
- journal append for that turn/run/stage;
- worker answer/result chunk committed to durable thread/run truth;
- explicit user recovery action;
- terminal result observation.

If process liveness is already recorded by the run subsystem, it may contribute
as a sourced event. The watchdog must not add a separate process monitor in v1.

A stall is eligible only when both are true:

```text
target is still nonterminal
lastObservableEvent.at is older than the target threshold
```

Before promotion to `active`, the scanner must refresh from the existing status
path for that target. For async team runs this means the same source of truth
used by `team_status` / `team_result`. For worker chat turns this means the
thread/run store and any existing journal finalization path.

The watchdog must not create a watchdog-only result schema. Team-run refresh
continues to project the shared async team contracts and `TeamRunJSON` result
shape.

If refresh finds terminal completion, failure, timeout, cancellation, auth
required, or manual action required, the candidate is suppressed and routed to
the existing owner.

## Core Model

Truth owner: `AllnighterCore`.

```text
StallEpisode
  id
  projectId
  targetKind: workerTurn | teamRun
  targetId
  threadId
  runId?
  status: active | snoozed | cleared
  reason: queuedNoStart | runningNoProgress | statusUnknownNoProgress
  firstDetectedAt
  deadlineAnchorAt
  thresholdSeconds
  lastObservableEvent
    at
    kind
    source
    summary
  lastRefreshAt?
  lastNudgeTurnId?
  lastNudgeAt?
  snoozedUntil?
  clearedAt?
  clearedBy?: terminalResult | userCancel | userRetry | userDismiss |
              refreshedOut | targetDeleted
  primaryAction
  secondaryActions[]
```

Episode rules:

- Idempotency key: `(targetKind, targetId, id)`.
- At most one non-cleared episode exists for a target.
- A new episode starts only after the previous episode cleared and the same
  target later becomes newly eligible, or a retry/new attempt creates a new
  target id.
- `Keep waiting` sets `status = snoozed` and `snoozedUntil`; it does not clear
  the episode.
- Scanner reads `snoozedUntil` from durable state. Snooze is never memory-only.
- `lastNudgeAt` prevents duplicate Project Manager turns and notifications for
  the same episode.
- An ignored nudge does not auto-escalate. Repeat notification requires a user
  snooze that expires or a meaningful target state change.
- The episode clears automatically when refresh/local truth observes a terminal
  result or a non-stall owner state such as auth/manual blocker.
- Clearing an episode does not delete the historical Project Manager turn.

No fields may represent estimated runtime, cost, quota, complexity, or reset
windows.

## Scan Triggers

This is a coarse watchdog, not a precision scheduler.

Run the scanner:

- when a watched target enters `queued` or `running`;
- when a watched target records a new local observable event;
- on a coarse periodic interval while the Mac app backend or resident
  coordinator is running;
- after app launch/resident restart;
- after sleep/wake, but only after refreshing status.

Default periodic interval:

```text
5 to 15 minutes
```

The exact interval is implementation policy. It must be coarse enough to avoid
becoming a provider polling loop.

App-closed behavior:

- If the resident coordinator is not running, v1 makes no app-closed stall
  promise.
- On next launch/resident start, the scanner refreshes before declaring stale
  work stalled.
- Sleep/wake may make timestamps look old. Refresh-before-declare is mandatory
  to avoid a burst of false nudges.

## Project Manager Nudge

A stalled nudge is a durable Project Manager turn. The notification is only a
pointer.

Minimum `ProjectManagerTurn` projection:

```text
ProjectManagerTurn
  mode: wait
  projectId
  threadId: project.managerThreadId
  contextPacketId?
  warnings[]
  nextActions[]
  stallEpisodeId
```

Fixed facts block:

```text
What you asked for: <title>
Current status: <enum from local truth>
Last change: <timestamp + event kind + source>
Waiting since: <deadline anchor>
Suggested next move: <one primary action>
```

Rules:

- The nudge must name the Project.
- The nudge must link to the target thread/run/turn.
- The nudge must be source-labeled. No provider guesses.
- The nudge offers one primary action and demotes the rest.
- The nudge is created only after refresh confirms the item is still eligible.
- If the target thread is already visible/read, local notification delivery may
  be suppressed, but the durable nudge still exists when the episode is active.

Primary action policy:

| Reason | Primary action | Secondary actions |
| --- | --- | --- |
| `queuedNoStart` | `Cancel` when no worker has started, otherwise `Open thread` | `Check status`, `Keep waiting` |
| `runningNoProgress` | `Check status` | `Open thread`, `Keep waiting`, `Cancel` |
| `statusUnknownNoProgress` | `Open thread` | `Check status`, `Keep waiting`, `Cancel` |

`Retry` is not a silent watchdog action in v1. The Project Manager may help the
user create a new proposal/work order or restart path after an explicit cancel
or human approval, but the watchdog itself does not rewrite prompts, choose a
new worker, or start a replacement attempt.

## Recovery Actions

All actions are explicit and Project-scoped.

| Action | Effect |
| --- | --- |
| `Check status` | Refresh the target from existing local truth. If terminal or owner-blocked, clear/suppress the stall. If still stalled, update `lastRefreshAt` without creating a duplicate nudge. |
| `Open thread` | Navigate to the linked Project/thread/turn. Does not change episode state by itself. |
| `Keep waiting` | Set `snoozedUntil` using the same default threshold as the target unless the user picks a specific duration. Keeps attention visible but suppresses repeat nudges until snooze expires or state changes. |
| `Cancel` | Calls the existing safe cancel path for that target. On success, target becomes terminal `cancelled` and the episode clears. On failure, keep the episode active and show the sourced failure. |
| `Dismiss` | Clears only the nudge/episode attention, not the underlying run. Use sparingly in UI; prefer `Keep waiting` when work may still be running. |

Clear rules:

- Terminal refresh clears the episode silently; no "all good" turn is required.
- User cancel clears only after the target reports cancelled.
- Keep waiting does not clear; it snoozes.
- Opening the thread does not clear; viewing is not recovery.
- Target deletion or migration to unassigned clears with `targetDeleted` and
  should leave a repair warning when appropriate.
- A retry/new attempt gets a new target id or new episode; it does not mutate the
  historical episode into success.

## Notification Integration

Mac local notifications are governed by
`docs/phases/threads/02_Notifications.md`.

Rules:

- A stalled episode emits `thread.needsAttention` with a `stallReason` facet.
- Local notification delivery is content-light and points to the Project/thread
  at the nudge turn.
- Respect global notification settings, quiet hours, per-thread mute, and
  debounce.
- Emit at most one notification per stall episode unless the user snoozes and
  the snooze expires while the target is still stalled.
- Do not emit a stalled notification merely because persisted state was reread
  on app restart.
- Do not double-notify terminal failures, auth-required turns, or manual-paste
  blockers; their existing notification events own those cases.

Default copy examples:

```text
Allnighter work may be stalled in "Fix team setup UX"
Team run needs a decision in "Allnighter"
Codex has not moved in "Project Manager spine"
```

No secrets or prompt bodies in notification text by default.

## CLI And MCP Contract

CLI/MCP are proof and integration surfaces. The primary human recovery UX is the
Project Manager nudge.

Project-scoped CLI:

```text
alln project stalled <project-id-or-name> --json
alln project stalled <project-id-or-name> --include-cleared --json
```

Aggregate CLI:

```text
alln stalled list --all --json
```

Rules:

- Project command output is authoritative for one Project.
- Aggregate output groups by Project and must not become a global queue.
- JSON mirrors the same Core `StallEpisode` ids, status, facts block, and
  `nextActions` visible to the Project Manager.
- Read-only CLI ships before mutating CLI recovery commands.
- External loop owners may use the read-only list as a signal to message the
  user or call normal Project Manager tools. This does not make Allnighter own
  their scheduler.
- MCP may expose `project_stalled` only as a projection of the same Core state.
  MCP must not invent MCP-only stall semantics or self-approve recovery.

## Privacy And Permissions

Rules:

- Stall scanning is local-first.
- No new provider credentials, Keychain entries, Full Disk Access, network
  permissions, or cloud storage are justified by this phase.
- The watchdog does not open provider account pages, scrape provider UI, accept
  prompts, or run quota probes.
- Recovery actions use existing run/thread cancel and navigation paths.
- Any future background behavior that changes macOS permission posture routes
  through the high-risk stop policy before implementation.

## Non-Goals

- No quota, billing, reset-window, cost, token, runtime, or complexity
  prediction.
- No provider scraping.
- No native scheduling/drain revival.
- No automatic retry.
- No silent worker substitution.
- No prompt rewriting.
- No cross-Project queue.
- No new terminal viewer.
- No branch/worktree/commit manager.
- No iOS-first implementation.
- No global "all work is stalled" truth owner.

## Implementation Impact

Core:

- Add `StallEpisode` and deterministic candidate derivation.
- Add fake-clock tests for thresholds, snooze, clear rules, and idempotency.
- Derive stall attention from existing Project/thread/run truth.
- Add Project-scoped JSON projection.

Engine/Mac backend:

- Run coarse scanner when coordinator/app is alive.
- Refresh target status before promoting a candidate to active.
- Execute safe recovery actions through existing run/thread APIs.
- Record nudge/action decisions durably.

ThreadStore/Project Manager:

- Create one `ProjectManagerTurn(mode: wait)` for each active episode.
- Link the turn to target Project/thread/run/turn.
- Set existing `thread.needsAttention` with a stall facet.
- Include active stalls in Project context packets under work/attention
  summaries without making the packet authority.

Notifications:

- Treat active stall as a `thread.needsAttention` source.
- Reuse existing mute, debounce, quiet-hours, visibility/read suppression, and
  click-through behavior.

CLI/MCP:

- Add read-only Project and aggregate stalled-work projections.
- Keep action commands out of the first CLI slice unless Core recovery action
  APIs already exist and are tested.

iOS:

- No blocking work. Future iOS renders Mac-owned Project/thread attention after
  Mac Project truth works.

## Inference Bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Old timestamp -> stall | Watchdog detector | Any old item is stalled. | Only nonterminal v1 targets with no observable progress after refresh can become active stalls. | Idle Pending older than a day is not stalled. |
| Failure -> stall | Turn/run lifecycle | A failed turn should also get a stalled nudge. | Terminal states are not stalled. | Failed turn emits failure attention only. |
| Auth/setup -> stall | Worker readiness / turn state | Sign-in blocker is a stall. | Auth/setup/manual blockers route to setup/manual copy. | Auth-required turn never creates a StallEpisode. |
| Stalled -> retry | Project Manager / user approval | The watchdog may silently retry or pick another worker. | Watchdog actions are explicit; retry/replacement requires human approval through normal Project Manager flow. | Active episode creates no worker attempt until user approves a new run. |
| Project A stall -> global blocker | ProjectStore + triage | One Project's stalled run blocks another Project. | Stalls are Project-scoped; aggregate views group only. | Project B can dispatch while Project A has an active stall. |
| Nudge -> duplicate truth | ThreadStore / Project Manager | A separate stalled inbox owns attention state. | Reuse `thread.needsAttention` with a stall facet. | Menu badge count comes from existing attention derivation. |
| Refresh -> probe | Engine | Refresh may run provider quota probes. | Refresh reads existing target status/result/journal paths only. | No provider-only probe command runs during stall scan. |

## Ordered Slices

- [ ] SWW-S00 - Contract packet: add `StallEpisode`, state distinctions,
  reason enums, JSON fixtures, idempotency rules, no-estimate field tests, and
  Project-required candidate validation. No GUI.
- [ ] SWW-S01 - Detector: fake-clock scanner for worker chat turns and async
  team runs, using `lastObservableEvent`, project scoping, thresholds, snooze,
  and negative cases for failed/auth/manual/Pending/fresh-running targets.
- [ ] SWW-S02 - Refresh-before-declare: wire candidate promotion through
  existing thread/run/journal and async `team_status` / `team_result` truth.
  Terminal or owner-blocked refresh suppresses the stall.
- [ ] SWW-S03 - Project Manager nudge and actions: create one durable
  `ProjectManagerTurn(mode: wait)`, set `thread.needsAttention` with a stall
  facet, and implement `Check status`, `Open thread`, `Keep waiting`, `Cancel`,
  and clear rules.
- [ ] SWW-S04 - Notifications/menu integration: local notification pointer,
  quiet-hours/mute/debounce/read suppression, one notification per episode, and
  no double-notify for failure/auth/manual blockers.
- [ ] SWW-S05 - CLI/MCP read-only projection: `alln project stalled <project>
  --json`, `alln stalled list --all --json`, and optional `project_stalled`
  MCP projection with identical Core ids and facts.

Backend/Core slices come before GUI polish. The user-visible win is the Project
Manager nudge; CLI projection is proof and external-agent affordance.

## Works Tests

Detector:

```text
Create Project A and Project B.
Create a running worker chat turn in Project A with lastObservableEvent 31
minutes ago.
Create a running worker chat turn in Project B with lastObservableEvent 5
minutes ago.
Run the scanner with a fake clock.
Expected:
- Project A emits one active StallEpisode;
- Project B emits none;
- both candidates include projectId;
- no aggregate/global queue item is created.
```

Negative cases:

```text
Create old turns/runs with states failed, timedOut, cancelled, completed,
authRequired, awaitingManualPaste, idle Pending, and blocked Pending.
Run the scanner.
Expected:
- none create StallEpisode;
- existing owner attention remains intact;
- failed/auth/manual cases do not receive duplicate stalled notifications.
```

Project binding gate:

```text
Create a stale queued/running target that has no reliable projectId.
Run the scanner.
Expected:
- no StallEpisode is created;
- no global stalled item is created;
- the target remains in the owning migration/repair path.
```

Refresh-before-declare:

```text
Create an async team run whose local journal looks stale.
Make team_status/team_result refresh return terminal completed.
Run the scanner.
Expected:
- no active StallEpisode is created;
- any prior candidate clears as refreshedOut;
- no Project Manager nudge or notification is emitted.
```

Snooze/idempotency:

```text
Create one active StallEpisode.
Run the scanner twice.
Expected:
- one Project Manager nudge turn exists;
- one notification candidate exists before delivery policy;
- idempotency key is stable.
Choose Keep waiting.
Run the scanner before snoozedUntil.
Expected:
- no new nudge or notification.
Advance fake clock beyond snoozedUntil while target is still stalled.
Expected:
- the same episode becomes active again and may notify once.
```

Recovery actions:

```text
Create an active stalled team run.
Choose Check status and return still running.
Expected:
- lastRefreshAt updates;
- no duplicate nudge.
Choose Cancel and make cancel succeed.
Expected:
- target is terminal cancelled;
- episode clears;
- thread attention no longer includes the stall facet.
```

Project Manager nudge:

```text
Create a stalled worker turn in the Allnighter Project.
Run promotion.
Expected:
- Project Manager thread receives one mode=wait turn;
- facts block includes title, current status, last change, waiting since, and one
  primary action;
- turn links to the target thread/run/turn;
- target thread has needsAttention with stallReason.
```

Notification:

```text
Create an active stall in an unmuted thread that is not visible/read.
Expected:
- one local notification candidate is produced;
- clicking opens the Project/thread at the nudge turn.
Mute the thread and repeat.
Expected:
- no local notification delivery;
- durable Project Manager nudge still exists.
```

CLI proof:

```text
alln project stalled Allnighter --json
alln stalled list --all --json
```

Expected:

```text
- project command returns only Allnighter episodes;
- aggregate command groups by Project;
- JSON ids/facts/actions match the Project Manager-visible state;
- no estimated quota/cost/runtime fields exist.
```

Green wall:

```text
swift test --package-path Packages/AllnighterCore
bash scripts/check.sh
```

## Done When

- Worker chat turns and async team runs can produce Project-scoped stall
  episodes.
- Every active episode belongs to exactly one Project.
- Detection uses local progress signals and refreshes before declaring.
- Terminal failure/completion, auth/setup/manual blockers, and idle Pending do
  not become stalls.
- The Project Manager creates one durable nudge per episode with a fixed facts
  block and typed next actions.
- `thread.needsAttention` is reused with a stall facet; no parallel attention
  tracker ships.
- Mac local notifications point to the nudge and respect existing mute/debounce/
  quiet-hours rules.
- Stall state clears automatically when local truth shows terminal completion,
  owner-blocked state, or successful user recovery.
- Snooze and duplicate-nudge prevention survive app restart.
- Read-only CLI/MCP projections mirror Core state and remain Project-scoped.
- No quota/admission/scheduler/retry/substitution machinery is introduced.

## Closed Decisions

- V1 targets worker chat turns and async team runs only.
- Refresh-before-declare is mandatory.
- Progress means local truth changed; provider guesses are not progress signals.
- PM turn owns durable recovery history; notification is only a pointer.
- One primary action is shown per stall reason.
- Retry/replacement is outside the watchdog action set unless routed through
  explicit Project Manager approval.
- Pending idle time is not stalled work.
- Global stalled views are aggregate-only.

## Open Questions

- Should default thresholds become per-Project settings after dogfood, or only
  global user settings?
- Should `Dismiss` be exposed in the main UI, or kept as a secondary/overflow
  action to avoid losing still-running work?
- Should future iOS show active stall episodes in the Project snapshot before
  Mac GUI action cards are polished?
