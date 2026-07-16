# Work Threads — Brief (ThreadList + ThreadTimeline)

**Build status (2026-06-15, PAUSED):** functionally BUILT in PWT-S06 and green
(`Apps/AllnighterMac/Sources/{ThreadsView,ThreadsViewModel,ThreadsPresenter}.swift`,
reached via the legacy team-run ↔ Threads sidebar toggle in `RootView.swift`). It is
**not yet re-skinned** to a final mockup — visuals are token-correct but
provisional. Remaining: design re-skin once mockups land, plus S07 rich
team/build turn cards (the `richRow` here is a placeholder). See
`docs/phases/threads/01_Work_Threads_MLP.md` § Implementation Status.

**Image status (2026-06-22):** backend image capture and storage are built, but
timeline/board rendering is not. Implementation routes through
`docs/phases/Message_Image_Rendering.md`: first enrich CLI read paths, then
render user/worker attachment chips and Design board tiles here.

**Tier:** D (renders run/dispatch state, worker liveness, manual-paste)
**Visual kit:** docs/design-system/ (tokens: `AllnighterTokens.swift`)
**Behavioral owner:** docs/phases/Persistent_Work_Threads.md +
docs/phases/threads/01_Work_Threads_MLP.md +
docs/archive/phases/05_ThreadStore_Hardening.md +
docs/phases/threads/06_Unread_Message_Light.md +
docs/phases/Message_Image_Rendering.md +
docs/archive/phases/07_Threads_2_0.md
**Core contracts:** `WorkThread`, `ThreadTurn`, `ThreadContextPacket`,
`ArtifactRef`, `TurnAttachmentRef`, `TurnAttachment`, `BoardPayload`
(AllnighterCore); `ThreadStore`, `ThreadAttachmentStore`,
`WorkerChatCoordinator`, `ThreadContextBuilder`, `RunStore`
(AllnighterEngine).

This brief covers the **ThreadList** (triage inbox) and the **ThreadTimeline**
(turns + always-visible composer). While both the legacy `ThreadsView` sidebar
and CR4 `HomeView` conversation rail exist, any WorkThread rail must render the
same derived unread truth and triage order from `06_Unread_Message_Light.md` and
archived `07_Threads_2_0.md`. Store mutations go through the archived hardening contract
in `docs/archive/phases/05_ThreadStore_Hardening.md`.

---

## ThreadList

### States
loading · empty ("No threads yet — start one") · populated · archived (behind a
toggle). Per-row derived state: unread · running · needs-attention · waiting ·
manual-paste · failed.

### Intents
- New thread → `ThreadStore.create(...)` then select it.
- Select thread → open ThreadTimeline.
- Rename / pin / archive → explicit `ThreadStore` methods (see archived `07_Threads_2_0.md`).
- Read clearing → timeline visibility reports visible turn ids; view model sends
  `ThreadStore.markReadToLatestVisible(...)`.
- (S08) local text filter over title/preview/first message/run prompt.

### Row order (triage — derived, never stored)
1. pinned + needs-attention → 2. needs-attention → 3. pinned + unread →
4. unread → 5. pinned + running → 6. running → 7. pinned recent →
8. recent by `updatedAt` → 9. archived (hidden).

### Field Ownership Ledger
| GUI field | Core model field | Source | States | Test owner |
| --- | --- | --- | --- | --- |
| Title | `thread.title` | WorkThread | all | ThreadsPresenterTests |
| Preview line | `thread.preview` | derived (latest text turn) | populated | ThreadsPresenterTests |
| Last-worker chip | `thread.lastWorkerId` | derived | populated | ThreadsPresenterTests |
| Relative time | `thread.updatedAt` | WorkThread | populated | — (Foundation format) |
| Unread light | `thread.readCursor` + unread-eligible `turns` | derived (see `06_Unread_Message_Light.md`) | unread | ThreadsPresenterTests |
| Running dot | `thread.isRunning` | derived | running | ThreadsPresenterTests |
| Attention flag | `thread.needsAttention` | derived | needs-attention | ThreadsPresenterTests |
| workingDir pill | `thread.workingDir` | WorkThread | when set | ThreadsPresenterTests |
| Pinned marker | `thread.isPinned` / `pinnedAt` | WorkThread | pinned | ThreadsPresenterTests |

Unread is an orthogonal axis. `rowState` remains attention/running/idle; the
trailing unread light is derived separately and must not be encoded in status
pill copy.

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
- message → user bubble (`text`) + ordered attachment chips when
  `attachmentRefs` exist.
- reply → worker bubble with worker glyph + status; running shows heartbeat +
  elapsed; failed/timedOut show `text` (errorReason) + retry/switch. Done
  worker turns render ordered attachment chips below the caption.
- team/build → compact expandable rich turn reusing existing team-run/
  plan/dispatch/return-review cards, referenced by `runId`/`stageId`.
  `.designBoard` terminal turns render the Design option tile strip from
  `BoardPayload` once MIR-GUI-S04 lands.
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
| Attachment chip order | `turn.attachmentRefs[].sequence` | ThreadTurn | user/worker done | Attachment + GUI fixture tests |
| Attachment chip image | `turn.attachmentRefs[].attachmentId` → `TurnAttachment.storagePath` → canonical bytes | ThreadAttachmentStore | user/worker done | ThreadAttachmentStoreTests + GUI fixture |
| Attachment metadata | `TurnAttachment.{mimeType,byteSize,storedWidth,storedHeight,sourceKind}` | attachments index | user/worker done, broken | ThreadAttachmentStoreTests |
| Broken attachment state | ref exists but canonical bytes/index/hash missing | ThreadAttachmentStore resolver | user/worker done | MIR-MCP-S01 tests |
| Design board option image | `turn.runId` → `TeamRun.latestStage(.board).payload.board.options[].imagePath` + `RunStore` run dir | TeamRun / BoardPayload | designBoard done | TeamRunJSONMapperTests + GUI fixture |
| Design board pick badge | `BoardPayload.chosen.workerId` | BoardPayload | designBoard done after pick | DesignModelsTests + GUI fixture |
| Design failed option tile | `DesignOption.status` + `failureReason` | BoardPayload | designBoard partial/failed seat | DesignCoordinatorTests + GUI fixture |
| Context reveal body | `packet.text` | ThreadContextPacket | reveal | (ThreadContextBuilderTests) |
| Context reveal attachment rows | `packet.includedAttachments[]` | ThreadContextPacket | reveal | ThreadContextBuilderTests |
| Context size | `packet.byteCount` | derived (bytes) | reveal | ThreadContextBuilderTests |
| Context truncation note | `packet.truncationNote` | ThreadContextPacket | reveal | ThreadContextBuilderTests |

### Message image rendering addendum (MIR)

States:

- loading thumbnail — file row exists, thumbnail decode is in flight.
- ready thumbnail — canonical file exists and hash matches.
- broken attachment — `attachmentRefs` points to missing bytes or hash mismatch.
- design partial — at least one Design option rendered and at least one failed.
- design board missing — `.designBoard` turn has `runId` but no board payload.

Intents:

- Click attachment chip → reveal/open the canonical file path. Never open a
  workspace mirror.
- Click Design option tile → select/focus that option inside the board/Floor
  surface once pick actions exist.
- Open board → open Factory Floor (or a dedicated Design board surface) for the
  referenced `TeamRun`.
- Context reveal → show the exact `includedAttachments` paths sent to the worker
  with hashes; these are audit rows, not alternate thumbnail truth.

Rules:

- Do not render stock placeholders or generated stand-ins. Missing bytes render
  a broken chip/tile tied to the real ref.
- Do not parse Markdown image syntax in `turn.text` or `WorkerAnswer.output` as
  product truth. Thread attachments come from `attachmentRefs`; Design tiles
  come from `BoardPayload`.
- Do not show raw `.png` path strings as the final Design board UI. A path may
  appear only in raw/debug/audit surfaces.
- Local `canonicalPath` / `absolutePath` values are for Mac + local CLI
  clients. Remote/iOS surfaces need a separate portable media contract.

### Non-negotiables honored here
- No usage theater: context size shown in **bytes/characters only**; never an
  estimated token/dollar/quota number.
- Never fake state: failed shows failed, timeout shows timed out, manual-paste
  shows awaiting paste — all from `turn.status` / `systemEvent`.
- Hide the plumbing: copy says model / skill / worker / team / plan, never
  subprocess / worktree / branch or legacy team lineup/team/master-plan words.
- One active heavy turn per thread (v1): heavy actions disabled when
  `thread.hasActiveHeavyTurn`.

### Rules check
No GUI field above lacks a core field. Size/truncation are derived and sourced.
No quota/secret/billing fields are rendered.
