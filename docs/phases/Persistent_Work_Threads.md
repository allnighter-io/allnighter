# Persistent Work Threads

Status: MLP BUILT (S01–S06) — PAUSED 2026-06-15; S07–S09 + fast-follows remain
Owner: AllnighterCore + AllnighterEngine + Mac app backend
Updated: 2026-06-15

> **Resume pointer:** the MLP (chat → team run → work order → dispatch loop's chat
> primitive) is built and green on branch `feat/design-chain`. Per-slice status,
> file locations, and what remains live in
> [`threads/01_Work_Threads_MLP.md`](threads/01_Work_Threads_MLP.md) §
> "Implementation Status". The fast-follow docs (02/03/04) are not started.

## Product Promise

```text
One thread for one goal: chat, team run, build, review, and keep going without
leaving Allnighter or re-explaining yourself.
```

This phase fixes the missing product unit. Allnighter is not just a team-run
launcher and not a generic chat aggregator. It owns **local work threads** that
can route each turn to one worker, escalate to the team, turn an answer into a
work order, dispatch a builder, and review the return.

## Decision

Build this as **persistent async agent messaging with escalation**, not as a
full realtime ChatGPT/Cursor replacement.

The MLP should feel like SMS/Telegram for the user's agent bench:

```text
send a message
see it saved immediately
see the selected worker running
leave or continue elsewhere
get the reply in the same thread
escalate to team run / work order / dispatch when ready
```

Mac notifications, token streaming, and observed usage metadata are fast
follow docs. They are not in the MLP because they should not block proving the
core thread primitive.

## Implementation Sequence

Build in this order:

1. [`threads/01_Work_Threads_MLP.md`](threads/01_Work_Threads_MLP.md) — **MLP
   BUILT (S01–S06); S07–S09 remain. See that doc's Implementation Status.**
   - [x] Persistent thread + turn models.
   - [x] One-worker async chat.
   - [x] Context packets.
   - [x] Minimal Mac thread surface alongside the existing team-run UI.
   - [ ] Existing team/design/review/dispatch work attaches to threads as
     turns (S07 — backend linkage exists; rich in-timeline cards pending).

2. [`threads/02_Notifications.md`](threads/02_Notifications.md) — **not started**
   - Fast follow for Mac local notifications when work lands or needs attention.
   - OneSignal mobile push lands later, after the remote spine exists.
   - This is the walk-away loop: keep the bench useful without staring at the app.

3. [`threads/03_Mac_Streaming.md`](threads/03_Mac_Streaming.md) — **not started**
   - Fast follow for live output where the driver/CLI can expose it.
   - May ship Mac-only first.
   - This is the stare-at-it loop: make long turns feel alive.

4. [`threads/04_Observed_Usage.md`](threads/04_Observed_Usage.md) — **not started**
   - Fast follow for provider-reported usage only.
   - No estimates, no fake dollar math, no opaque quota percentages.
   - Duration stays first-class and already partially exists.

## Non-Negotiable Product Rules

- **Chat is the default turn.** The user can brainstorm with one worker before
  any team run, work order, or dispatch. That worker is still `model + skill`:
  usually a selected model wearing the default Chat skill.
- **Routing is per turn.** A thread may use Grok, then Claude, then the team,
  then Codex as builder.
- **Enter never builds.** Hitting Enter sends a chat turn to the resolved default
  worker. Dispatch is always a named action from an editable work-order preview.
- **Allnighter transcript is truth.** Vendor-native sessions may be used later
  as an optimization, never as durable product truth.
- **Thread liveness is derived.** Running, failed, waiting, and needs-attention
  states are computed from turns, not stored as drift-prone thread flags.
- **Failures are turns too.** Failed, timed-out, cancelled, cooling-down, and
  manual-paste states remain visible inside the thread.
- **No usage theater.** Show observed duration and source-labeled usage only
  when known. Never estimate token cost, dollar cost, runtime, or quota burn.

## Current State

Existing truth owners:

- Legacy `TeamRun` is the current durable unit for team/design/review/dispatch
  history until the vocabulary cleanup renames it to `TeamRun`.
- `StageOutput` records analysis, plan, review, final spec, dispatch, return
  review, and outcome score stages.
- `RunStore` persists runs as local folder-of-JSON plus derived Markdown.
- `WorkerRunner.invoke` runs one legacy worker/model CLI once and already accepts
  `workingDirectoryOverride`.
- `CommandRunner.run(...) async -> CommandResult` is request/response. There is
  no streaming path today.
- Worker-answer duration is already captured through `durationMs` and displayed
  on answer cards. Scorecards already store `medianLatencyMs`, though the current
  Doctor scorecard UI does not surface it.

Truth added by the MLP (S01–S06, built 2026-06-15):

- ✅ Durable thread object — `WorkThread` (AllnighterCore).
- ✅ Persisted chat turn model — `ThreadTurn` + `ThreadStore` (folder-of-JSON).
- ✅ Backend contract for one-worker chat — legacy `WorkerChatCoordinator`
  (rename/classify during the Model/Worker cleanup).
- ✅ Context packet builder — `ThreadContextBuilder` + persisted
  `ThreadContextPacket`.

Still missing (deferred):

- No streaming command path (fast follow `03_Mac_Streaming.md`).
- No observed usage model (fast follow `04_Observed_Usage.md`).
- No thread/turn notification policy (fast follow `02_Notifications.md`).

## Architecture Rule

Threads reference runs. Runs do not become chats.

```text
WorkThread
  -> ThreadTurn(kind: teamRun, runId: ...)
  -> ThreadTurn(kind: dispatch, runId: ..., stageId: ...)

TeamRun
  -> keeps worker answers + stage outputs as today
```

`TeamRun` stays the run-truth owner after the rename. `ThreadTurn.runId` is the linkage.
Inverse lookup is a store index, not authoritative state.

## Designer Contract

The designer should spec surfaces from these backend truths:

1. Home becomes a thread list, not a run list.
2. Thread detail is a timeline of turns.
3. The composer is always visible.
4. Default action is chat with the resolved worker.
5. Ask team, turn into work order, dispatch, and continue from result are
   escalation actions inside the thread.
6. Team/build turns expand in place.
7. Running/failed/waiting are turn states, not separate inboxes.
8. The thread header exposes title, working directory, and default worker
   (`model + chat skill`), not a bare model.
9. The thread list is a triage surface: needs-attention, running, pinned, then
   recent.

Visual design belongs in the design-system and GUI docs. This doc owns product
semantics and sequencing.

## Resolved Open Questions

1. **Native session continuity:** yes later, never MLP, never truth.
2. **Multiple in-flight team runs per thread:** one active heavy turn per
   thread in v1.
3. **Thread scope:** encourage one thread per feature/goal, not forever threads.
4. **Team snapshot:** use current team at escalation time; record exact workers
   used on the turn/run.
5. **Quick capture default:** new thread by default; append-to-active can be a
   setting or explicit picker.
6. **iOS compose:** iOS should send async chat turns in the first serious remote
   cut. When Dispatch/Execute appears on iOS, it is a named send mode from an
   editable work order, not a second-confirmation flow.
7. **Search:** not MLP; add title + first-message + run-prompt search once Home
   flips to thread list.

## Proof Wall

The MLP must pass:

```text
swift test
scripts/check.sh
```

Each fast follow owns its own deterministic Works Test in the routed doc. Do not
claim chat parity until streaming exists for at least one real driver.
