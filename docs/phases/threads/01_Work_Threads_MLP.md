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
-> ask the panel from the same thread
-> turn an answer into a work order
-> dispatch from the thread
-> return review lands in the thread
```

This is async agent messaging with escalation. It is not token streaming, not a
full IDE chat replacement, and not mobile sync.

## User-Visible Claim

```text
Allnighter keeps one local work thread per goal. You can think with one worker,
ask the panel when it matters, and turn the result into work without copy/paste.
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
  until after chat + council + dispatch are proven.

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
WorkThread.needsAttention  = failed/timedOut/manual-paste/sign-in turn exists
WorkThread.lastWorkerId    = most recent worker-authored turn
WorkThread.preview         = most recent message/reply excerpt
```

```text
ThreadTurn
- id
- threadId
- kind                   # storage enum
- status                 # draft | queued | running | done | failed | timedOut | cancelled
- createdAt
- completedAt?
- author                 # user | worker(workerId) | system
- text?
- workerId?
- runId?                 # references CouncilRun for council/design/review/dispatch
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
- includedRunIds: [CouncilRun.ID]
- includedFiles: [String]
- text
- truncated: Bool
- truncationNote?
```

```text
ArtifactRef
- kind                   # masterPlan | finalSpec | designBoard | dispatchResult
                         # returnReview | screenshot | file | diff
- runId?
- stageId?
- path?
- excerpt?
```

Ownership rule:

- `ThreadTurn.runId` references `CouncilRun`.
- `CouncilRun` is not modified for chat.
- A store-level index may map run -> thread, but it is derived.

## Turn Families

Use granular storage kinds but simple UI families:

| Family | Storage kinds | Meaning |
| --- | --- | --- |
| Message | `user_message`, `user_decision` | User text, notes, decisions |
| Reply | `worker_chat` | One-worker response |
| Council | `council_run`, `design_board`, `review_board` | Rich expandable run turn |
| Build | `work_order`, `dispatch`, `return_review` | Spec, execution, result |
| System | `system_event` | Migration, waiting, sign-in, manual-paste notes |

## Thread List Contract

Home becomes a floor-manager inbox, not a passive run log.

Default row order:

```text
1. pinned threads needing attention
2. unpinned threads needing attention
3. pinned running threads
4. unpinned running threads
5. pinned recent threads
6. recent threads by updatedAt
7. archived threads, hidden behind Archive
```

Row content:

- title, editable from the thread header;
- preview from the most recent meaningful turn;
- last worker glyph/chip when present;
- relative time;
- derived state: running, waiting, failed, manual-paste, auth-required;
- optional `workingDir` path chip when set.

Minimum list affordances:

- `New thread` is primary.
- Quick capture creates a new thread by default.
- local text filter over title, preview, first message, and run prompt arrives
  with the Home flip if full search is not ready.
- imported legacy run threads show a collapsed system note: "Imported council
  run - no prior chat."

## Composer Contract

Default worker resolution:

```text
1. thread.defaultWorkerId, if set
2. else thread.lastWorkerId
3. else global daily-driver preference
4. else first healthy headless-CLI worker
```

The resolved worker must be visible as a composer chip:

```text
Replying as Claude - last used in this thread
```

Tapping the chip changes the worker for this turn; the user may optionally save
that choice as the thread default.

Composer state:

```text
empty thread + Enter       -> worker_chat to resolved worker
existing thread + Enter    -> worker_chat to resolved worker
Shift+Enter                -> newline
Ask panel                  -> council_run
Turn into work order       -> work_order, editable, nothing runs
Dispatch                   -> dispatch from work_order, confirmed
Continue from result       -> worker_chat seeded from selected turn
```

Guardrails:

- Enter never builds.
- Dispatch is named, confirmed, and tied to an editable work-order preview.
- "Continue from this" seeds the next input; it does not auto-send.
- Casual chat does not auto-fan out or auto-reroute.
- If the resolved worker is `authRequired`, `coolingDown`, `degraded`, `busy`, or
  `unknown`, the composer shows the observed reason and offers explicit choices:
  wait/queue when allowed, switch worker, manual-paste, or attempt anyway where
  admission policy permits. It never silently sends to a different worker.
- One active heavy turn (`council_run`, `dispatch`, `return_review`) is allowed
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
- Master plan from run <id>: <excerpt>

Latest user message:
<message>
```

Rules:

- Strategies: `recent_turns` and `explicit_selection`.
- Preserve author and worker provenance.
- Apply a byte/character cap.
- Show visible truncation metadata: "included last N turns; older omitted."
- Provide a first-class context reveal before manual-paste, panel, and dispatch:
  "What the worker will see", included turn/file/artifact list, size, cap, and
  one-click copy. This is product trust, not a debug drawer.
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
- Cancel kills the subprocess and leaves a cancelled turn.
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
- Add `WorkerChatCoordinator`.
- Reuse `WorkerRunner.invoke`, passing `workingDirectoryOverride`.
- Add manual-paste fallback that reveals exact context and stores pasted reply.
- Add thin turn-update mechanism for chat turns.

Mac app:

- Add thread list and thread detail timeline alongside current council UI.
- Keep existing run history until the later ownership flip.
- Add always-visible composer.
- Add worker picker/default worker chip.
- Add thread header with editable title, `workingDir` pill, and default worker.
- Add "Ask panel", "Turn into work order", "Dispatch", and "Continue from this"
  as semantic actions, even if the first UI is plain.
- Add manual-paste turn UI: reveal/copy exact context, open/copy affordance, and
  inline paste box that completes the worker reply turn.
- Reuse existing council/member/master-plan/dispatch/return-review cards as
  compact expandable rich turns instead of navigating away from the timeline.

GUI prep:

- Before S06 implementation, write Tier C surface briefs per
  `docs/gui/GUI_Workflow.md` for `ThreadList` and `ThreadTimeline`.
- S06 is not complete unless thread list triage, composer worker chip, running
  heartbeat, context reveal, and workingDir pill exist in the Mac surface.

## Migration

- Existing `CouncilRun`s become lazy auto-threads on access/list.
- Each auto-thread has one `council_run` turn and one collapsed `system_event`
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
- [ ] PWT-S07 - Attach council/review/dispatch as turns.
- [ ] PWT-S08 - Home flips to thread list; legacy runs migrate lazily.
- [ ] PWT-S09 - Export full thread transcript + linked run artifacts.

MLP is S01-S06. S07-S09 complete the loop but must not block proving chat.

## Implementation Status (paused 2026-06-15)

**MLP is DONE and green** on branch `feat/design-chain`. `scripts/check.sh`
passes: 179 Core/Engine `swift test` + 26 Mac tests. Each slice is its own
commit (`git log --grep PWT-S`). The Council UI is untouched; Threads is reached
by a new Council↔Threads sidebar toggle (Home does not flip until S08).

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
- `SystemEventKind` (`migration_imported`/`waiting`/`sign_in_required`/
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
- **PWT-S07 — Attach council/review/dispatch as rich turns.** Backend linkage
  exists (`ThreadTurn.runId`/`stageId`, `ArtifactRef`); `richRow` in
  `ThreadsView.swift` is a placeholder card. Reuse the existing council/
  master-plan/dispatch/return-review cards as compact expandable in-timeline
  turns, and route "Ask panel / Turn into work order / Dispatch / Continue from
  this" into thread turns. Recommended to land with the S06 re-skin so run-card
  reuse is design-correct in one pass.
- **PWT-S08 — Home flips to thread list; lazy run migration.** Make threads the
  default (retire the Council↔Threads toggle or invert it); lazily wrap existing
  `CouncilRun`s as auto-threads on list/access with one `council_run` turn + a
  collapsed `migration_imported` system note (see Migration section). Add the
  local title/preview/first-message/run-prompt filter.
- **PWT-S09 — Export full thread transcript + linked run artifacts.** Extend
  `ThreadMarkdown` (currently a viewing transcript) into a full export bundle
  that pulls linked run artifacts by `runId`.
- **Fast-follow docs (separate phases, not started):** `02_Notifications.md`,
  `03_Mac_Streaming.md`, `04_Observed_Usage.md`.

## Works Test

```text
New thread. Send "before we build, brainstorm the simplest approach" to one
healthy worker. The user turn renders immediately. The worker turn shows running
immediately with heartbeat and elapsed time. The reply is saved. Send a follow-up
to a different worker; reveal context shows the earlier user turn and worker
reply plus any truncation note. Ask the panel from the same thread; the council
run is saved as an expandable turn referencing the run. Turn the master plan into
an editable work order. Dispatch it in the thread workingDir. Return review lands
as the next turn. Quit and reopen; the thread is intact and appears in the Home
triage order.
```

## Proof Command

```text
swift test
scripts/check.sh
```

Engine Works Test for S01-S05 must use `MockCommandRunner` and be deterministic.
Mac UI proof can lag behind only if the closeout names the missing UI proof.
