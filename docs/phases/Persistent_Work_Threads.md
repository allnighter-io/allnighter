# Persistent Work Threads

Status: Parent/router — core thread MLP + CR4 conversation send paths delivered;
remaining work deferred to routed child docs
Owner: AllnighterCore + AllnighterEngine + Mac app backend
Updated: 2026-06-22

> **Parent doc:** this page is the router for the work-thread product lane. It
> records what shipped and which child doc owns the next work. Do not use this
> page as the detailed implementation spec when a routed child doc exists.
> When this page conflicts with
> [`docs/archive/phases/Compose_Routing_CR4_Send_And_Conversations.md`](../archive/phases/Compose_Routing_CR4_Send_And_Conversations.md)
> or `threads/01_Work_Threads_MLP.md`, this page wins; those docs now contain
> historical implementation context for already-built work.
>
> **Resume pointer:** the MLP thread primitive is built, and later CR4 work added
> the Home conversation rail plus real Chat, Fan out, and Execute send paths.
> ThreadStore hardening and Threads 2.0 rail controls are archived. Mac local
> notifications 1.0 are built (02). Remaining active thread work: rich-turn read
> clear (06 S08), message image rendering/read-path enrichment
> (`Message_Image_Rendering.md`), thread forking (09), core-loop gaps in `01`,
> and fast follows 03–04.
>
> **Project spine dependency:** threads are no longer the top-level floor for
> new forward work. [`Project_Spine_And_Project_Manager.md`](Project_Spine_And_Project_Manager.md)
> owns the durable Project root, `projectId` binding, and Project Manager chat.
> This doc owns thread/turn behavior inside a Project.

## Product Promise

```text
One thread for one goal: chat, team run, build, review, and keep going without
leaving Allnighter or re-explaining yourself.
```

This phase fixed the missing conversation unit. Allnighter is not just a
team-run launcher and not a generic chat aggregator. It owns **local work
threads** that can route each turn to one worker, escalate to the team, turn an
answer into a work order, dispatch a builder, and review the return. New
forward work must attach those threads to a Project.

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

1. [`threads/01_Work_Threads_MLP.md`](threads/01_Work_Threads_MLP.md) — **core
   MLP built; remaining core-loop gaps still owned here**
   - [x] Persistent thread + turn models.
   - [x] One-worker async chat.
   - [x] Context packets.
   - [x] Minimal Mac thread surface.
   - [x] Home conversation rail and Send creates/opens conversations (CR4a).
   - [x] Chat send runs one model and renders the reply in-thread (CR4b).
   - [x] Fan out runs a real team/design board and renders it from durable
     `runId` truth (CR4c).
   - [x] Execute dispatches to the repo and renders a durable dispatch result
     from `runId`/`stageId` truth (CR4d).
   - [x] Rail filters, search, and pinned/recent grouping exist (CR4e).
   - [ ] Not delivered: editable `work_order` turn creation, return-review as a
     thread turn, team-result reply defaulting to the writer with switch-away
     warning, and full thread export with linked run artifacts. Keep these in
     `01_Work_Threads_MLP.md` until resliced. Zero-user rule: do not add
     migration readers or aliases for old local dogfood shapes; wipe/reseed if a
     schema cutover needs it.

2. [`ThreadStore Hardening`](../archive/phases/05_ThreadStore_Hardening.md)
   — **BUILT / archived**
   - Engine prerequisite is complete: serialized writes, explicit mutation APIs,
     atomic `thread.json` persistence, and `updatedAt`/transcript law.
   - Also delivered `WorkThread.formatVersion`, duplicate id/turn-id rejection,
     context-packet reference integrity, and the no-raw-save caller gate.
   - Unread and rail controls can now build on this archived gate.

3. [`threads/06_Unread_Message_Light.md`](threads/06_Unread_Message_Light.md)
   — **UNR-S01–S06 + S07 BUILT** (2026-06-17); S08 remains
   - Durable read cursors, Core derivation, store `markRead*`, presenter unread
     buckets, Mac rail indication light, viewport clear, and GUI matrix proof
     are built.
   - Notification suppression hooks (UNR-S06) shipped with `02_Notifications.md`.
   - Rich-turn read-clear defers to UNR-S08.
   - iOS read-state protocol moved to
     [`ios/03_iOS_Thread_Read_State_And_Push.md`](ios/03_iOS_Thread_Read_State_And_Push.md)
     and is not a Mac blocker.

4. [`Threads 2.0`](../archive/phases/07_Threads_2_0.md) — **BUILT / archived**
   (2026-06-17)
   - Rename, pin, archive/unarchive, archive view, unified triage on Home +
     legacy Threads rails, context menus, keyboard commands, archived composer
     disabled until explicit unarchive.
   - GUI proof: `docs/qa/gui/home/2026-06-17-th2-rail/`.

5. [`threads/08_Worker_Image_Output_In_Chat.md`](threads/08_Worker_Image_Output_In_Chat.md)
   — **Backend BUILT** (WIO-S00–S03, S05, 2026-06-17); WIO-S04 GUI deferred
   - Chat replies from workers declaring `imageGen` capture the generated
     image via the shared `WorkerImageCapture` contract and commit it as a
     `.workerGenerated` attachment (same store as user paste). Text caption
     lives in turn.text.
   - Design continuity: after a board (or prior chat image), a follow-up chat
     tweak materializes the seed image into `includedAttachments` via
     `ThreadImageSeedResolver` + optional `userDecision` turn.
   - Mac timeline thumbnails for worker bubbles (WIO-S04); CLI/MCP JSON parity
     (`workerAttachmentIds`) shipped in WIO-S05.

6. [`Message_Image_Rendering.md`](Message_Image_Rendering.md) — **Ready for
   implementation packet** (2026-06-22)
   - Umbrella handoff for image rendering across user attachments, worker image
     replies, Design fan-out boards, and Factory Floor design readers.
   - First slice is MCP/CLI read enrichment: wire `thread get/status`, resolve
     `attachmentRefs` to canonical paths, and expose Design board option paths
     in `TeamRunJSON`.
   - GUI slices render shared timeline attachment chips, worker/user bubble
     images, Design board tile strips, and Floor design mockups.

7. [`threads/02_Notifications.md`](threads/02_Notifications.md) — **BUILT**
   (NOTIF-S01–S05 + UNR-S06, 2026-06-17)
   - Mac local notifications when work lands or needs attention; menu-bar
     live/needs-attention indicator; per-thread mute; debounce and quiet hours
     policy in Core/Engine.
   - Owns UNR-S06 suppression when the landed turn is already visible/read.
   - Mobile push is deferred to
     [`ios/03_iOS_Thread_Read_State_And_Push.md`](ios/03_iOS_Thread_Read_State_And_Push.md).

8. [`threads/03_Mac_Streaming.md`](threads/03_Mac_Streaming.md) — **not started**
   **defer here**
   - Fast follow for live output where the driver/CLI can expose it.
   - May ship Mac-only first.
   - This is the stare-at-it loop: make long turns feel alive.

9. [`threads/04_Observed_Usage.md`](threads/04_Observed_Usage.md) — **not started**
   **defer here**
   - Fast follow for provider-reported usage only.
   - No estimates, no fake dollar math, no opaque quota percentages.
   - Duration stays first-class and already partially exists.

10. [`threads/09_Thread_Forking.md`](threads/09_Thread_Forking.md) — **Draft
   feature packet; MCP/CLI-first**
   - Fork a thread or terminal turn prefix into a new active child thread with
     durable provenance.
   - MCP `thread_fork` and CLI `alln thread fork` are the acceptance surface;
     Mac inline/rail affordances present that contract after proof.
   - Must copy referenced thread subresources and harden run inverse lookup
     before copied run turns ship.

## Non-Negotiable Product Rules

- **Chat is the default turn.** The user can brainstorm with one worker before
  any team run, work order, or dispatch. That worker is still `model + skill`:
  usually a selected model wearing the default Chat skill.
- **Project Manager is the default project chat.** Once the Project spine lands,
  ordinary chat starts as a Project Manager turn inside the selected Project.
  It can answer without creating a work order.
- **Routing is per turn.** A thread may use Grok, then Claude, then the team,
  then Codex as builder.
- **Enter never builds.** Hitting Enter sends a chat turn to the resolved default
  worker. Dispatch is always a named action from an editable work-order preview.
- **Allnighter thread record is truth.** `thread.json`/`run.json` own durable
  product truth. Derived Markdown transcripts are exports/views. Vendor-native
  sessions may be used later as an optimization, never as durable product truth.
- **Thread liveness is derived.** Running, failed, waiting, and needs-attention
  states are computed from turns, not stored as drift-prone thread flags.
- **Thread mutations are store-gated.** All durable thread writes go through
  explicit `ThreadStore` methods; see archived proof in
  `docs/archive/phases/05_ThreadStore_Hardening.md`.
- **Thread schema evolves deliberately.** `WorkThread.formatVersion` and typed
  store errors own migration and duplicate-id safety; UI code must not infer
  durable meaning from missing fields.
- **Thread freshness is derived.** Read/unread state is computed from
  `ThreadReadCursor` plus turns after `threads/06_Unread_Message_Light.md`; the
  GUI never owns unread truth.
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

Truth/UI paths delivered:

- ✅ Durable thread object — `WorkThread` (AllnighterCore).
- ✅ Persisted chat turn model — `ThreadTurn` + `ThreadStore` (folder-of-JSON).
- ✅ Backend contract for one-worker chat — legacy `WorkerChatCoordinator`
  (rename/classify during the Model/Worker cleanup).
- ✅ Context packet builder — `ThreadContextBuilder` + persisted
  `ThreadContextPacket`.
- ✅ Home conversation rail and thread pane render the active conversation.
- ✅ Chat send persists user + worker turns and lands model replies in-thread.
- ✅ Fan out persists a team/design board turn referencing durable `TeamRun`
  truth by `runId`.
- ✅ Execute persists a dispatch turn referencing durable run/stage truth by
  `runId`/`stageId`.

Storage SSOT:

```text
AllnighterCore      -> Swift Codable schema + pure derived semantics
AllnighterEngine    -> ThreadStore/RunStore mutation and persistence gates
Application Support -> local folder-of-JSON storage
SwiftUI             -> render + intent only; no durable truth
```

There is no Rust truth layer and no SQL database today. Thread truth lives at:

```text
~/Library/Application Support/Allnighter/Threads/thread_<id>/thread.json
```

`transcript.md` and Markdown exports are derived from JSON truth. Worker context
packets live under each thread's `context/` folder. Team/design/review/dispatch
run truth remains under `Runs/run_<id>/run.json`; threads reference those runs by
id instead of copying run data.

Still missing / deferred:

- Core-loop gaps still owned by `01_Work_Threads_MLP.md`: editable work-order
  turns, return-review turns, team-result writer default + switch-away warning,
  and full thread export with linked run artifacts. Do not implement migration
  readers for old dogfood data; there are zero users.
- ThreadStore hardening and explicit mutation APIs are built and archived at
  `docs/archive/phases/05_ThreadStore_Hardening.md`.
- Read cursor, unread derivation, Mac rail light, viewport clear, notification
  suppression hooks, and GUI proof are built in `06_Unread_Message_Light.md`;
  S08 remains for rich-turn read-clear.
- Mac local notifications 1.0 are built in `02_Notifications.md`.
- Message image rendering is routed through `Message_Image_Rendering.md`;
  engine capture/storage is built, but `thread_get` path resolution,
  Design-board run JSON enrichment, timeline thumbnails, and Floor design image
  rendering remain.
- No streaming command path (fast follow `03_Mac_Streaming.md`).
- No observed usage model (fast follow `04_Observed_Usage.md`).

## Foundation Gates

These gates are here so future roadmap work does not accidentally skip the hard
part and wire a pretty rail to weak storage:

```text
05 before 06/07:
  one per-root writer, atomic thread.json, no runtime raw save,
  explicit mutation methods, versioned schema, duplicate-id/turn-id rejection

06 before visible unread:
  pure Core derivation, monotonic read cursor, legacy nil cursor baseline,
  viewport-based clear, worker-chat/system-event visual proof

07 before production rail controls:
  one presenter triage key for Home + legacy rails, archive view,
  archived composer disabled until explicit unarchive
```

Do not mark read/unread, rename/pin/archive, or rail convergence complete from
UI behavior alone. The proof must include store law tests and presenter tests.

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
7. Running/failed/waiting/unread are derived from turn state plus read cursor,
   not separate inboxes.
8. The thread header exposes title, working directory, and default worker
   (`model + chat skill`), not a bare model.
9. The thread list is a triage surface: needs-attention, unread landed work,
   running, pinned, then recent.

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
6. **iOS compose:** moved to `ios/README.md`; iOS is deferred until the macOS app
   is done and must not block Mac thread delivery.
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
