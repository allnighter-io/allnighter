# 01 - Work Threads MLP

Status: Ready for implementation
Owner: AllnighterCore + AllnighterEngine + Mac app backend
Updated: 2026-06-15

## Goal

Ship the smallest lovable thread experience:

```text
create thread
-> chat with one worker
-> follow up with saved thread context
-> ask the team from the same thread
-> turn an answer into a work order
-> dispatch from the thread
-> return review lands in the thread
```

This is async agent messaging with escalation. It is not token streaming, not a
full IDE chat replacement, and not mobile sync.

## User-Visible Claim

```text
Allnighter keeps one local work thread per goal. You can think with one worker,
ask the team when it matters, and turn the result into work without copy/paste.
```

## Non-Goals

- No token-by-token streaming.
- No mobile push or remote sync.
- No token/cost reporting.
- No vendor chat-history import.
- No provider-native session continuity requirement.
- No rolling summarization or auto-harvested facts.
- No A/B branch or fork-and-merge lanes.
- No managed worktrees or commit ownership.
- No inline git reset / discard-changes action. A cancelled or failed dispatch
  may warn that the working directory could be dirty, but destructive cleanup
  belongs to a later managed-execution phase with explicit safeguards.
- No token-weight meter based on estimates. The MLP may show context size,
  included sources, and truncation in bytes/characters; token counts wait for
  source-labeled observed usage.
- No design-board-first-class timeline polish; attaching design turns may wait
  until after chat + team run + dispatch are proven.

## Core Models

Truth owner: `AllnighterCore`.

```text
WorkThread
- id
- title                  # auto from first user message; editable
- status                 # active | archived
- createdAt
- updatedAt
- pinnedAt?
- workingDir?            # context anchor + default dispatch cwd
- projectLabel?
- defaultWorkerId?
- turns: [ThreadTurn]
```

Derived, never stored:

```text
WorkThread.isRunning       = any turn.status in { queued, running }
WorkThread.hasPending      = linked PendingItem exists with status == pending
WorkThread.needsAttention  = failed/timedOut/manual-paste/sign-in turn exists
WorkThread.lastWorkerId    = most recent user-facing worker turn; for a team
                              result this is the plan writer
WorkThread.preview         = most recent message/reply excerpt
```

Fast follow `05_Unread_Message_Light.md` adds `ThreadReadCursor` and derives
`WorkThread.hasUnread` from the cursor plus unread-eligible turns. Do not infer
unread from `updatedAt`.

```text
ThreadTurn
- id
- threadId
- kind                   # storage enum
- status                 # draft | pending | queued | running | done | failed | timedOut | cancelled
- createdAt
- completedAt?
- author                 # user | worker(workerId) | system
- text?
- workerId?
- runId?                 # references TeamRun after rename; legacy TeamRun today
- stageId?
- artifactRefs: [ArtifactRef]
- contextPacketId?
- supersedesTurnId?
- seedFromTurnId?
```

```text
ThreadContextPacket
- id
- threadId
- turnId
- createdAt
- strategy               # recent_turns | explicit_selection
- includedTurnIds: [ThreadTurn.ID]
- includedRunIds: [TeamRun.ID]
- includedFiles: [String]
- text
- truncated: Bool
- truncationNote?
```

```text
ArtifactRef
- kind                   # plan | finalSpec | designBoard | dispatchResult
                         # returnReview | screenshot | file | diff
- runId?
- stageId?
- path?
- excerpt?
```

Ownership rule:

- `ThreadTurn.runId` references `TeamRun` after the rename; current code still
  references legacy `TeamRun`.
- The run object is not modified for chat.
- A thread-level `teamRun` result is user-facing from the worker that wrote the
  plan/result (`TeamRunJSON.teamRun.planWriterWorkerId` / `plan.writerWorkerId`).
  Fan-out workers are evidence and expandable detail; they are not reply targets.
- A store-level index may map run -> thread, but it is derived.

## Turn Families

Use granular storage kinds but simple UI families:

| Family | Storage kinds | Meaning |
| --- | --- | --- |
| Message | `user_message`, `user_decision` | User text, notes, decisions |
| Reply | `worker_chat` | One-worker response |
| Team | `teamRun`, `designBoard`, `reviewBoard` | Rich expandable run turn |
| Build | `work_order`, `dispatch`, `return_review` | Spec, execution, result |
| System | `system_event` | Migration, Pending reasons, sign-in, manual-paste notes |

## Thread List Contract

Home becomes a floor-manager inbox, not a passive run log.

Default MLP row order:

```text
1. pinned threads needing attention
2. unpinned threads needing attention
3. pinned running threads
4. unpinned running threads
5. pinned recent threads
6. recent threads by updatedAt
7. archived threads, hidden behind Archive
```

After `05_Unread_Message_Light.md`, unread landed work slots between
needs-attention and running.

Row content:

- title, editable from the thread header;
- preview from the most recent meaningful turn;
- last worker glyph/chip when present;
- relative time;
- unread indication light after `05_Unread_Message_Light.md`;
- derived state: draft, pending, running, failed, manual-paste, auth-required;
- optional `workingDir` path chip when set.

Minimum list affordances:

- `New thread` is primary.
- Quick capture creates a new thread by default.
- local text filter over title, preview, first message, and run prompt arrives
  with the Home flip if full search is not ready.
- imported legacy run threads show a collapsed system note: "Imported team run -
  no prior chat."

## Composer Contract

Default worker resolution:

```text
1. result writer, when replying to or continuing from a team/review/result turn
2. latest team result writer, when the composer is sitting after that result
3. thread.defaultWorkerId, if set
4. else thread.lastWorkerId
5. else global daily-driver preference
6. else first ready model with the default Chat skill
```

The resolved worker must be visible as a composer chip:

```text
Replying as Opus / Plan Writer - wrote this team answer
Replying as Opus / Chat - last used in this thread
```

Tapping the chip changes the worker for this turn; the user may optionally save
that choice as the thread default.

If the current reply target came from a team result writer, switching to any
other worker shows a warning modal before the switch is applied. No
warning appears when the user simply replies to the writer.

Modal shape:

```text
Switch reply worker?

Opus wrote this team answer and saw every worker response.
Grok may only see the visible thread context Allnighter includes for this reply.

Reply with Opus
Switch to Grok
```

Vocabulary rule: a chat turn is one model wearing one skill. It is not a full
team run, but product copy should still call the active turn target a worker, not
a bare model.

Composer state:

```text
empty thread + Enter       -> worker_chat to resolved worker
existing thread + Enter    -> worker_chat to resolved worker
Shift+Enter                -> newline
Ask team                   -> teamRun
Turn into work order       -> work_order, editable, nothing runs
Dispatch / Execute         -> dispatch from editable work_order
Continue from result       -> worker_chat seeded from selected turn
```

Guardrails:

- Enter never builds.
- Dispatch/Execute is a named send mode tied to an editable work-order preview;
  choosing it is the explicit user action. Do not add a second confirmation step.
- The boundary label and context reveal are visible before dispatch, but they are
  not approval gates.
- "Continue from this" seeds the next input; it does not auto-send.
- Casual chat does not auto-fan out or auto-reroute.
- After a fan-out, the writer is the default reply worker because that is the
  only worker that spoke to the user with full team context.
- Warn only when the user switches away from that writer. Do not add persistent
  limited-context badges to the happy path.
- If the resolved worker is `authRequired`, `coolingDown`, `degraded`, `busy`, or
  `unknown`, the composer shows the observed reason and offers explicit choices:
  save Draft, submit to Pending, switch worker, manual-paste, or attempt anyway
  where admission policy permits. It never silently sends to a different worker.
- Pending is primarily a thread-composer capture path: it preserves the next turn
  in this thread when the chosen worker cannot accept it yet.
- One active heavy turn (`teamRun`, `dispatch`, `return_review`) is allowed
  per thread in v1. While one is active, new heavy actions are disabled with an
  explanation. Simple chat may continue only if the coordinator can safely attach
  it as an independent `worker_chat` turn without mutating the active run.

## Context Assembly

V1 packet:

```text
Thread: <title> (workingDir: <path>, if set)

Recent turns:
1. User: ...
2. Claude: ...
3. User: ...

Quoted / selected:
- <turn excerpt>

Attached files:
- <path>: <capped contents>

Relevant artifacts:
- Plan from run <id>: <excerpt>

Latest user message:
<message>
```

Rules:

- Strategies: `recent_turns` and `explicit_selection`.
- Preserve author and worker provenance.
- Apply a byte/character cap.
- Show visible truncation metadata: "included last N turns; older omitted."
- Provide a first-class context reveal for manual-paste, team run, and dispatch:
  "What the worker will see", included turn/file/artifact list, size, cap, and
  one-click copy. This is product trust, not a debug drawer or a required
  confirmation step.
- When the user switches a reply away from a team result writer, the warning
  path must be backed by the same context reveal. Do not imply the alternate
  worker saw raw fan-out answers unless those answers are actually included in
  its context packet.
- Do not include artifacts from outside the thread unless explicitly attached.
- Attached files are resolved against `workingDir`, capped, and local.
- Highlight included turns/files in the timeline only as a context-boundary aid.
  Do not display estimated tokens.

## Latency Policy For MLP

No streaming in this doc.

The MLP must still avoid dead-chat feel:

- Save and render the user turn immediately.
- Create the worker turn immediately with status `running`.
- Show worker, model, running heartbeat, and elapsed time while running.
- Land the full reply when the CLI exits.
- Stop kills the active attempt and returns linked Pending work to Pending.
- Cancel is separate: it cancels Draft/Pending intent so no future attempt runs.
- Timeout leaves a timed-out turn with elapsed time and worker provenance.
- Auto-scroll to new content only when the user is already near the bottom.
- Notification deep-links and future menu-bar jumps focus the relevant turn.

## Backend Impact

AllnighterCore:

- Add models, enums, family mapping, fixtures, and Codable tests.
- Add derived-liveness computed helpers.
- Add illegal-state tests for turn lifecycle.

AllnighterEngine:

- Add `ThreadStore` beside `RunStore`.
- Add `ThreadContextBuilder`.
- Add `WorkerChatCoordinator` (legacy name; classify/rename during the
  Model/Worker cleanup).
- When attaching a team result to a thread, set the result turn's user-facing
  `workerId` from `TeamRunJSON.teamRun.planWriterWorkerId` / `plan.writerWorkerId`.
- Reuse `WorkerRunner.invoke`, passing `workingDirectoryOverride`.
- Add manual-paste fallback that reveals exact context and stores pasted reply.
- Add thin turn-update mechanism for chat turns.

Mac app:

- Add thread list and thread detail timeline alongside current team-run UI.
- Keep existing run history until the later ownership flip.
- Add always-visible composer.
- Add worker picker/default worker chip.
- Add thread header with editable title, `workingDir` pill, and default worker.
- Add "Ask team", "Turn into work order", "Dispatch", and "Continue from this"
  as semantic actions, even if the first UI is plain.
- Default replies after a team result to the result writer. Show the warning
  modal only if the user switches the composer chip away from that writer.
- Add manual-paste turn UI: reveal/copy exact context, open/copy affordance, and
  inline paste box that completes the worker reply turn.
- Reuse existing team-run/worker-answer/plan/dispatch/return-review cards as
  compact expandable rich turns instead of navigating away from the timeline.

GUI prep:

- Before S06 implementation, write Tier C surface briefs per
  `docs/gui/GUI_Workflow.md` for `ThreadList` and `ThreadTimeline`.
- S06 is not complete unless thread list triage, composer worker chip, running
  heartbeat, context reveal, and workingDir pill exist in the Mac surface.

## Migration

- Existing legacy runs become lazy auto-threads on access/list.
- Each auto-thread has one `teamRun` turn and one collapsed `system_event`
  noting imported run with no prior chat.
- Do not synthesize missing user/worker chat turns.
- `Run again` becomes "Continue in thread" or "Fork to new thread."

## Ordered Slices

- [x] PWT-S01 - Core models, enums, fixtures, Codable round-trip tests.
- [x] PWT-S02 - `ThreadTurn.runId` linkage and store-level inverse index.
- [x] PWT-S03 - `ThreadStore` create/list/get/append/update/archive.
- [x] PWT-S04 - `ThreadContextBuilder` with caps and visible truncation.
- [x] PWT-S05 - `WorkerChatCoordinator` with optimistic turns and manual fallback.
- [x] PWT-S06 - Minimal Mac thread list + timeline + composer.
- [ ] PWT-S07 - Attach team/review/dispatch as turns, with team-result replies
  defaulting to the writer and switch-away warning modal.
- [ ] PWT-S08 - Home flips to thread list; legacy runs migrate lazily.
- [ ] PWT-S09 - Export full thread transcript + linked run artifacts.

MLP is S01-S06. S07-S09 complete the loop but must not block proving chat.

## Implementation Status (paused 2026-06-15)

**MLP is DONE and green** on branch `feat/design-chain`. `scripts/check.sh`
passes: 179 Core/Engine `swift test` + 26 Mac tests. Each slice is its own
commit (`git log --grep PWT-S`). The legacy team-run UI is untouched; Threads is
reached by a sidebar toggle (Home does not flip until S08).

### Done — where the code lives

| Slice | Status | Source | Tests |
| --- | --- | --- | --- |
| S01 | ✅ | `AllnighterCore/{WorkThread,ThreadTurn,ThreadContextPacket}.swift`, fixtures `Resources/Fixtures/thread_*.json`, `Fixtures.swift` | `AllnighterCoreTests/WorkThreadTests.swift` |
| S02 | ✅ | run→thread index in `AllnighterEngine/ThreadStore.swift` (`threadId(forRunId:)`, `runToThreadIndex()`); `runId` on `ThreadTurn` | `AllnighterEngineTests/ThreadStoreTests.swift` |
| S03 | ✅ | `AllnighterEngine/ThreadStore.swift` (create/list/get/append/update/archive + `savePacket`/`packet`), `ThreadMarkdown.swift`, `AllnighterPaths.threads` | `ThreadStoreTests.swift` |
| S04 | ✅ | `AllnighterEngine/ThreadContextBuilder.swift` | `AllnighterEngineTests/ThreadContextBuilderTests.swift` |
| S05 | ✅ | `AllnighterEngine/WorkerChatCoordinator.swift` | `AllnighterEngineTests/WorkerChatCoordinatorTests.swift` (incl. engine Works Test) |
| S06 | ✅ | Mac `Sources/{ThreadsPresenter,ThreadsViewModel,ThreadsView}.swift`, `RootView.swift` (WorkspaceSwitcher); brief `docs/gui/surfaces/threads/brief.md` | `AllnighterMacTests/ThreadsPresenterTests.swift` |

Notable model decisions made during build (not in the original spec, keep on
resume):
- Liveness is fully derived (`WorkThread.isRunning/needsAttention/lastWorkerId/
  preview/hasActiveHeavyTurn`); nothing stored.
- `SystemEventKind` (`migration_imported`/`pending_reason`/`sign_in_required`/
  `manual_paste`) discriminates `system_event` turns. A blocking note
  (sign-in / manual-paste) is created `running` and raises `needsAttention`
  only while non-terminal, then transitioned to `done` to clear attention.
- `author` is a flat `.user/.worker/.system` enum; worker identity is the
  separate `workerId` field (no associated-value Codable).
- Context packets are persisted under `thread_<id>/context/<packetId>.json`;
  `WorkerChatCoordinator.revealContext` reads them for the trust reveal.

### Remaining — to resume

- **S06 design re-skin (fast follow):** the Mac surface is functional but not
  final-design. Re-skin `ThreadsView.swift` against mockups + the design system
  once the founder supplies them; no backend change needed. The S06 completion
  bar (triage, composer worker chip, running heartbeat, context reveal,
  workingDir pill) is already met functionally.
- **PWT-S07 — Attach team/review/dispatch as rich turns.** Backend linkage
  exists (`ThreadTurn.runId`/`stageId`, `ArtifactRef`); `richRow` in
  `ThreadsView.swift` is a placeholder card. Reuse the existing team-run/
  plan/dispatch/return-review cards as compact expandable in-timeline
  turns, and route "Ask team / Turn into work order / Dispatch / Continue from
  this" into thread turns. Recommended to land with the S06 re-skin so run-card
  reuse is design-correct in one pass.
- **PWT-S08 — Home flips to thread list; lazy run migration.** Make threads the
  default (retire the old toggle or invert it); lazily wrap existing
  legacy runs as auto-threads on list/access with one `teamRun` turn + a
  collapsed `migration_imported` system note (see Migration section). Add the
  local title/preview/first-message/run-prompt filter.
- **PWT-S09 — Export full thread transcript + linked run artifacts.** Extend
  `ThreadMarkdown` (currently a viewing transcript) into a full export bundle
  that pulls linked run artifacts by `runId`.
- **Fast-follow docs (separate phases, not started):**
  `05_Unread_Message_Light.md`, `02_Notifications.md`,
  `03_Mac_Streaming.md`, `04_Observed_Usage.md`.

## Works Test

```text
New thread. Send "before we build, brainstorm the simplest approach" to one
healthy worker. The user turn renders immediately. The worker turn shows running
immediately with heartbeat and elapsed time. The reply is saved. Send a follow-up
to a different worker; reveal context shows the earlier user turn and worker
reply plus any truncation note. Ask the team from the same thread; the team
run is saved as an expandable turn referencing the run, and the composer defaults
to the writer that produced the team result. Press Reply without changing the
chip; the follow-up goes to that writer with no warning. Try switching the chip
to another worker; a modal warns that the alternate worker may not have the full
fan-out context and cancel keeps the writer selected. Turn the plan into an
editable work order. Dispatch it in the thread workingDir. Return review lands as
the next turn. Quit and reopen; the thread is intact and appears in the Home
triage order.
```

## Proof Command

```text
swift test
scripts/check.sh
```

Engine Works Test for S01-S05 must use `MockCommandRunner` and be deterministic.
Mac UI proof can lag behind only if the closeout names the missing UI proof.
