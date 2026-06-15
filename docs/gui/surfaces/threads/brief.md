# Work Threads — Brief (ThreadList + ThreadTimeline)

**Build status (2026-06-15, PAUSED):** functionally BUILT in PWT-S06 and green
(`Apps/AllnighterMac/Sources/{ThreadsView,ThreadsViewModel,ThreadsPresenter}.swift`,
reached via the legacy team-run ↔ Threads sidebar toggle in `RootView.swift`). It is
**not yet re-skinned** to a final mockup — visuals are token-correct but
provisional. Remaining: design re-skin once mockups land, plus S07 rich
team/build turn cards (the `richRow` here is a placeholder). See
`docs/phases/threads/01_Work_Threads_MLP.md` § Implementation Status.

**Tier:** D (renders run/dispatch state, worker liveness, manual-paste)
**Visual kit:** docs/design-system/ (tokens: `AllnighterTokens.swift`)
**Behavioral owner:** docs/phases/Persistent_Work_Threads.md +
docs/phases/threads/01_Work_Threads_MLP.md
**Core contracts:** `WorkThread`, `ThreadTurn`, `ThreadContextPacket`,
`ArtifactRef` (AllnighterCore); `ThreadStore`, `WorkerChatCoordinator`,
`ThreadContextBuilder` (AllnighterEngine).

This brief covers two surfaces that ship together in PWT-S06: the **ThreadList**
(triage inbox) and the **ThreadTimeline** (turns + always-visible composer).
They live alongside the existing team-run UI; Home does not flip to threads until
PWT-S08.

---

## ThreadList

### States
loading · empty ("No threads yet — start one") · populated · archived (behind a
toggle). Per-row derived state: running · needs-attention · waiting ·
manual-paste · failed.

### Intents
- New thread → `ThreadStore.create(...)` then select it.
- Select thread → open ThreadTimeline.
- (S08) local text filter over title/preview/first message/run prompt.

### Row order (triage — `WorkThread` derived liveness, never stored)
1. pinned + needs-attention → 2. needs-attention → 3. pinned + running →
4. running → 5. pinned recent → 6. recent by `updatedAt` → 7. archived (hidden).

### Field Ownership Ledger
| GUI field | Core model field | Source | States | Test owner |
| --- | --- | --- | --- | --- |
| Title | `thread.title` | WorkThread | all | ThreadsPresenterTests |
| Preview line | `thread.preview` | derived (latest text turn) | populated | ThreadsPresenterTests |
| Last-worker chip | `thread.lastWorkerId` | derived | populated | ThreadsPresenterTests |
| Relative time | `thread.updatedAt` | WorkThread | populated | — (Foundation format) |
| Running dot | `thread.isRunning` | derived | running | ThreadsPresenterTests |
| Attention flag | `thread.needsAttention` | derived | needs-attention | ThreadsPresenterTests |
| workingDir pill | `thread.workingDir` | WorkThread | when set | ThreadsPresenterTests |
| Pinned marker | `thread.isPinned` / `pinnedAt` | WorkThread | pinned | ThreadsPresenterTests |

---

## ThreadTimeline

### States
empty (new thread, composer only) · populated · running (heartbeat on the live
worker turn) · done · failed · timed_out · manual-paste (awaiting paste).

### Intents (composer + turn actions)
- Enter / Send → `WorkerChatCoordinator.send(message:toThreadId:requestedWorkerId:)`
  — **Enter never builds.**
- Shift+Enter → newline (no send).
- Tap worker chip → choose worker for this turn; optionally save as default.
- Reveal context → `WorkerChatCoordinator.revealContext(threadId:packetId:)`.
- Paste reply (manual) → `completeManualPaste(threadId:workerTurnId:manualNoteTurnId:reply:)`.
- Ask team / Turn into work order / Dispatch / Continue from this → escalation
  actions (semantic now; richer UI may follow). Heavy actions disabled while
  `thread.hasActiveHeavyTurn`.

### Turn rendering by family (`ThreadTurnKind.family`)
- message → user bubble (`text`).
- reply → worker bubble with worker glyph + status; running shows heartbeat +
  elapsed; failed/timedOut show `text` (errorReason) + retry/switch.
- team/build → compact expandable rich turn reusing existing team-run/
  plan/dispatch/return-review cards, referenced by `runId`/`stageId`.
- system → muted note; migration ("Imported team run — no prior chat")
  collapses; open sign-in/manual-paste notes are the attention surface.

### Field Ownership Ledger
| GUI field | Core model field | Source | States | Test owner |
| --- | --- | --- | --- | --- |
| Header title | `thread.title` | WorkThread (editable) | all | ThreadsPresenterTests |
| workingDir pill | `thread.workingDir` | WorkThread | when set | ThreadsPresenterTests |
| Default-worker chip | `thread.defaultWorkerId` | WorkThread | all | ThreadsPresenterTests |
| Composer "Replying as X" | resolved worker | `WorkerChatCoordinator.resolveWorkerId` | all | WorkerChatCoordinatorTests |
| Turn author/glyph | `turn.author` + `turn.workerId` | ThreadTurn | all | ThreadsPresenterTests |
| Turn status pill | `turn.status` | ThreadTurn | all | ThreadsPresenterTests |
| Running heartbeat + elapsed | `turn.status==running` + `turn.createdAt` | ThreadTurn | running | ThreadsPresenterTests |
| Reply text | `turn.text` | ThreadTurn | done | — |
| Failure reason | `turn.text` (errorReason) | ThreadTurn | failed/timedOut | ThreadsPresenterTests |
| Team/build card | `turn.runId` → `TeamRun` after rename; legacy `TeamRun` today | RunStore | populated | (existing run cards) |
| Artifact chip | `turn.artifactRefs[].{kind,excerpt}` | ArtifactRef | populated | ThreadsPresenterTests |
| Context reveal body | `packet.text` | ThreadContextPacket | reveal | (ThreadContextBuilderTests) |
| Context size | `packet.byteCount` | derived (bytes) | reveal | ThreadContextBuilderTests |
| Context truncation note | `packet.truncationNote` | ThreadContextPacket | reveal | ThreadContextBuilderTests |

### Non-negotiables honored here
- No usage theater: context size shown in **bytes/characters only**; never an
  estimated token/dollar/quota number.
- Never fake state: failed shows failed, timeout shows timed out, manual-paste
  shows awaiting paste — all from `turn.status` / `systemEvent`.
- Hide the plumbing: copy says model / skill / worker / team / plan, never
  subprocess / worktree / branch or legacy panel/council/master-plan words.
- One active heavy turn per thread (v1): heavy actions disabled when
  `thread.hasActiveHeavyTurn`.

### Rules check
No GUI field above lacks a core field. Size/truncation are derived and sourced.
No quota/secret/billing fields are rendered.
