# Message Image Rendering

Status: **Partially built** — engine + capture + CLI/MCP send parity landed (2026-06-17); **timeline and board image rendering are not built**
Owner: AllnighterCore + AllnighterEngine + Mac app + CLI/MCP
Updated: 2026-06-22
Process: `docs/workflows/SSOT_Feature_Workflow.md`

## Requires

```text
Composer_Image_Attachments.md          (canonical attachment store — backend built)
threads/08_Worker_Image_Output_In_Chat.md (worker-produced chat images — backend built; WIO-S04 GUI deferred)
mvp/Design1_Image_Team.md              (design fan-out capture — backend built)
Team_Run_Floor.md                      (Floor reader; design image tiles remain)
CLI_Implementation_Contract.md         (no MCP-only schema forks)
docs/gui/GUI_Workflow.md               (surface briefs before large GUI slices)
```

## Founder Intent

Raw request:

```text
When AI responds with an image — in a single chat lane or when the Design team
fans out mockups — the user must see that image in the message, not a file path
or prose claiming an image exists. This is especially critical when Design comes
back with options to pick from.
```

Product value:

```text
Images are first-class message content. The thread is the continuous record;
visual work (mockups, screenshots, generated art) must survive restart, open on
click, and flow into the next turn's context without forcing another full fan-out.
```

Trusted workflow slices:

```text
Single lane:
  user asks for an image (or tweaks a prior one)
  -> worker captures PNG/JPEG into thread attachments/
  -> timeline shows thumbnail + caption
  -> next send includes the image in includedAttachments

Design team:
  user sends screenshot + brief
  -> Design team fans out N mockups
  -> thread designBoard turn shows horizontal option tiles (pick badge, Open board)
  -> user picks -> chat tweak can reference the picked image inline
```

Non-goals:

- New image providers or hosted generation
- Inline HTML render pipeline
- Fake thumbnails, stock art, or emoji standing in for missing bytes
- Read-time scraping of vendor session dirs (`~/.grok/...`) at render time
- iOS timeline v1 (store + refs are already portable)

---

## Answer: Is This Built?

**No — not end-to-end.** The durable substrate and MCP send surfaces are largely
in place. **Nothing in the Mac thread timeline or design-board row renders image
bytes today.**

| Surface | Image truth (engine) | MCP / CLI | Mac GUI |
| --- | --- | --- | --- |
| **User paste / attach → send** | `ThreadAttachmentStore` + `attachmentRefs` on user turns | `thread_send` `images[]`, `attachmentIds`, `attachments[]` | Composer chips exist; **timeline chips not wired** (CIA-S04) |
| **Single-lane worker reply with image** | `WorkerImageCapture` + `workerGenerated` attachment on worker turn | `thread_send` returns `workerAttachmentIds` / `workerAttachments` (WIO-S05) | **`ThreadView.workerBubble` is markdown text only** (WIO-S04) |
| **Design fan-out → board** | `DesignImageRunner` → run-relative PNG/JPEG; `BoardPayload` on run | `team result --json` exposes `workerAnswers[].output` as run-relative path; **structured `board` stage filtered from `TeamRunJSON`** | **`ThreadBoardRow` shows markdown/path text, not tiles**; `DesignBoardView` removed |
| **Factory Floor (design lane)** | Same run folder bytes | Same as team result | **Text/markdown reader only** — no mockup tile strip |
| **Context reveal** | `includedAttachments` audit on packets | Visible in send JSON | **No thumbnails** |

The screenshot in design handoff (`fan-out · N mockups`, horizontal tiles, pick
badge, "Open board") is **pixel reference, not shipped product truth**.

---

## SSOT

Truth owners:

```text
ThreadAttachmentStore + attachments.json     canonical bytes for thread-scoped images
ThreadTurn.attachmentRefs                      ordered refs on any turn (user or worker)
ThreadTurn.text                                caption / prose (path lines stripped)
TeamRun workerAnswers[].output                 run-relative image path (design seats)
StageOutput.board (BoardPayload)               structured design options + chosen
DriverManifest.imageGen                        per-driver capture contract
```

Lie-prone layers:

```text
SwiftUI markdown-only bubbles
WorkerAnswer.output displayed as markdown when value is a .png path
Vendor CLI session folders
stdout prose without a matching attachmentRef or run file
GUI parsing markdown for ![](...) at render time
```

Binding rules:

1. **Thread chat images** use `attachmentRefs` → canonical store. Never
   `ArtifactRef` for chat/worker images.
2. **Design fan-out images** live in the run folder until materialized into
   thread attachments (WIO-S03 path for chat continuity). Thread UI resolves
   `runId` + `imagePath` for display; it does not invent URLs.
3. **No fake image**: caption without bytes → show text only; failed seat →
   honest gray tile + reason, never stock art.
4. **One shared chip/tile component** for timeline attachments (user + worker)
   and design option tiles where dimensions align (see GUI slices).

---

## Current Backend (Do Not Rebuild)

These slices are **done**. Extend, do not fork.

| Slice | Doc | Proof |
| --- | --- | --- |
| Canonical attachment store, ingest, send transaction | CIA-S00–S02 | `swift test --filter Attachment` |
| CLI/MCP user image send | CIA-S05–S06 | `thread_send` tests |
| Design fan-out first-image → `screenshotPath` | CIA-S07 | `FanoutAttachmentMapperTests` |
| Worker image capture + chat `imageGen` profile | WIO-S00–S02 | `WorkerImageCaptureTests`, `ThreadSendCoordinatorAttachmentTests` |
| Prior / picked image seed for chat tweaks | WIO-S03 | `testDesignBoardPickMaterializedIntoContextPacket` |
| MCP `workerAttachmentIds` on send | WIO-S05 | `ThreadSendCLI` response tests |

---

## Remaining Work (MCP First, Then GUI)

### Phase A — MCP / CLI contract gaps

Agents and headless workflows must resolve image bytes **before** the Mac app
ships thumbnails. GUI presents the same contract.

#### MIR-MCP-S01 — Resolve thread attachments on read

**Status:** Not built

**Goal:** `thread_get` and `thread_status` return enough data to open every image
on a turn without the GUI guessing paths.

Today `WorkThread` turns carry `attachmentRefs: [{ attachmentId, sequence }]`
only. Agents must not read `attachments.json` by convention.

**Deliver:**

- Add `resolvedAttachments: [AttachmentRow]` per turn (or a top-level
  `attachments: [AttachmentRecord]` map keyed by id) in:
  - `alln thread get --json`
  - MCP `thread_get`
  - MCP `thread_status` when turns are included
- `AttachmentRow` shape matches `thread_send` (id, `canonicalPath`,
  `deliveredPathUsed`, `storedSha256`, optional `sourceKind`).
- Document in `ContractRegistry` + generated help; drift gate updated.

**Proof:** Fixture thread with user + worker attachments → `thread_get --json`
lists resolvable `canonicalPath` for each ref; delete vendor path → canonical
still opens.

#### MIR-MCP-S02 — Design run image paths for agents

**Status:** Partial

**Goal:** External agents can fetch design mockup bytes without parsing markdown.

Today `workerAnswers[].output` may be `option_model_grok#0.png` (run-relative).
`TeamRunJSON` **drops** the structured `board` stage.

**Deliver (pick one binding approach — prefer both):**

1. **Run result enrichment:** `team result --json` / MCP run fetch adds
   `designBoard: { options: [{ workerId, persona, imagePath, absolutePath, status }], chosen?, screenshotPath? }`
   when `run.lane == .design`.
2. **Absolute paths:** For each design `workerAnswer` with image output, include
   `outputAbsolutePath` resolved from `RunStore` run directory (never vendor dirs).

**Proof:** Completed design run → JSON lists ≥1 option with openable absolute path;
chosen option surfaced when `chosen_option.json` exists.

#### MIR-MCP-S03 — Attachment reveal helper (optional but recommended)

**Status:** Not built

**Goal:** One tool for "show me this attachment" without loading the whole thread.

**Deliver:**

- `alln thread attachment <thread-id> <attachment-id> --json`
- MCP `thread_attachment_get` → `{ canonicalPath, storedSha256, mime, width?, height? }`

**Proof:** CLI returns path that exists on disk; hash matches store.

---

### Phase B — Mac GUI rendering

Follow `docs/gui/GUI_Workflow.md`: add or extend surface briefs under
`docs/gui/surfaces/threads/` before large view changes. Coordinate sizing with
`docs/phases/wiring/design_handoff_home_workspace/` (78×120pt fan-out tiles,
46×66pt chat thumbs) when that pack is available.

#### MIR-GUI-S01 — Shared `TimelineAttachmentChip`

**Status:** Not built (blocks CIA-S04 + WIO-S04)

**Goal:** One component: thumbnail, click-to-reveal canonical file, optional
remove (composer only).

**Deliver:**

- `TimelineAttachmentChip` (or shared with `ComposerAttachmentTile` extraction)
- Loads thumb from `ThreadAttachmentStore` via view-model cache
- Sizes: chat bubble thumbs **46×66pt**; composer remains **56×56pt**

**Proof:** Unit snapshot or fixture render; reuse in composer + timeline.

#### MIR-GUI-S02 — Worker chat bubble images (WIO-S04)

**Status:** Not built

**Goal:** `ThreadView.workerBubble` renders `turn.attachmentRefs` under caption
markdown.

**Deliver:**

- Ordered chip row below `AnswerBody` for `.done` worker turns
- Running/failed: no fake thumb; honest error text only
- Context reveal panel: same chips for worker attachments in audit list

**Proof:** `bash scripts/gui_proof.sh thread-worker-image-reply` + layout-watcher PASS.

#### MIR-GUI-S03 — User bubble images (CIA-S04)

**Status:** Not built

**Goal:** User / `userDecision` turns show pasted or picked reference images.

**Deliver:**

- Extend `userBubble` with chip row from `attachmentRefs`
- `userDecision` pick materialization (WIO-S03) shows the seed image visibly

**Proof:** `compose-paste-image` fixture + thread timeline fixture with user attach.

#### MIR-GUI-S04 — Design board row in thread (the bench strip)

**Status:** Not built

**Goal:** `ThreadBoardRow` for `.designBoard` turns shows the **horizontal mockup
tile strip** from the handoff mockup — not collapsed markdown paths.

**Deliver:**

- Resolve `runId` → `BoardPayload` from latest `board` stage
- Horizontal `ScrollView` of option tiles:
  - image from `runDir + imagePath` when `hasImage`
  - gray failure tile + `failureReason` when not
  - pick badge on `board.chosen`
- Footer: "You picked **{persona}**" + **Open board** → Factory Floor or
  dedicated design board surface
- Code / Copy team boards **unchanged** (markdown cards)

**Depends:** `ThreadsViewModel.teamRun(forRunId:)` (exists); image cache per run.

**Proof:** GUI fixture `thread-design-board-fanout` + layout-watcher PASS on tile
strip + pick state.

#### MIR-GUI-S05 — Factory Floor design lane tiles

**Status:** Not built

**Goal:** When `run.lane == .design`, the Floor reader shows mockup images for
each worker answer — not a markdown string of `option_*.png`.

**Deliver:**

- Design cast cards: thumb + persona label
- Reader column: full mockup image above any caption
- Reuse tile loader from MIR-GUI-S04

**Proof:** Floor fixture with design run; layout-watcher on reader column.

#### MIR-GUI-S06 — Composer ↔ timeline parity

**Status:** Partial (composer chips exist; send staging wired)

**Goal:** Close CIA-S03/S08 gaps so paste → send → timeline shows the same attachments.

**Deliver:** See `Composer_Image_Attachments.md` CIA-S03, S08, S09.

---

## Inference Bans

| Junction | Bad inference | Ban |
| --- | --- | --- |
| `WorkerAnswer.output` | "It's markdown" | If value ends in `.png`/`.jpg` or board option, render as image |
| Worker prose | "Says here's the image" | No thumb without `attachmentRef` or run file |
| `TeamRunJSON` | "No board stage → no design UI" | Load `TeamRun` natively in GUI for board payload |
| Vendor dirs | "File exists in ~/.grok" | Display only canonical or run-folder copies |

---

## Works Test (founder)

### Single lane

1. Open a thread; send to Grok (or any `imageGen` worker): "Draw a cute cat."
2. Wait for terminal worker turn.
3. **Assert:** Timeline shows image thumbnail + caption; click opens
   `threads/.../attachments/<id>.png`.
4. Quit + relaunch: image still present.
5. `alln thread get --json`: turn includes resolvable attachment paths (after MIR-MCP-S01).

### Design team

1. Send screenshot + brief to Design team.
2. **Assert:** Thread `designBoard` turn shows N mockup tiles (not path strings).
3. Pick an option; footer shows pick + Open board.
4. Send chat tweak: "Make the header bolder."
5. **Assert:** New worker image appears in chat bubble (MIR-GUI-S02).

---

## Done When

- [ ] MIR-MCP-S01: `thread_get` / `thread_status` resolve attachment paths
- [ ] MIR-MCP-S02: Design run JSON exposes board/options with openable paths
- [ ] MIR-GUI-S01: Shared timeline attachment chip
- [ ] MIR-GUI-S02: Worker chat bubbles render worker attachments (WIO-S04)
- [ ] MIR-GUI-S03: User bubbles render attachments (CIA-S04)
- [ ] MIR-GUI-S04: Design board row renders fan-out tile strip
- [ ] MIR-GUI-S05: Factory Floor renders design mockups
- [ ] GUI proof fixtures sealed per `GUI_Visual_Proof_Gate.md`
- [ ] Routers in `docs/phases/README.md` and `Persistent_Work_Threads.md` updated

---

## Related Docs

| Doc | Relationship |
| --- | --- |
| [`Composer_Image_Attachments.md`](Composer_Image_Attachments.md) | User inbound; store law; CIA-S04 timeline |
| [`threads/08_Worker_Image_Output_In_Chat.md`](threads/08_Worker_Image_Output_In_Chat.md) | Worker outbound chat capture (backend done) |
| [`mvp/Design1_Image_Team.md`](../mvp/Design1_Image_Team.md) | Design fan-out capture contract |
| [`Live_Team_Board.md`](Live_Team_Board.md) | Live running board (text); terminal images defer here |
| [`Team_Run_Floor.md`](Team_Run_Floor.md) | Floor reader; MIR-GUI-S05 |
| [`GUI_Visual_Proof_Gate.md`](GUI_Visual_Proof_Gate.md) | Proof + layout-watcher policy |
