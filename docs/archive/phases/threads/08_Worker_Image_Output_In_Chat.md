# 08 — Worker Image Output in Chat (design continuity)

Status: **Backend BUILT** (WIO-S00–S03, S05, 2026-06-17) — WIO-S04 Mac timeline GUI deferred
Owner: AllnighterCore + AllnighterEngine + Mac app
Updated: 2026-06-17

## Requires

```text
../Persistent_Work_Threads.md          (thread + chat send paths — CR4b built)
../Composer_Image_Attachments.md       (canonical attachments/ store — backend built)
../../mvp/Design0_Design_Team_Overview.md
../../mvp/Design1_Image_Team.md        (DesignImageRunner + imageGen driver contract)
../../archive/phases/05_ThreadStore_Hardening.md
```

Do **not** re-run CR4b send scaffolding or the CIA user-attachment transaction. Extend `completeSend` + `ThreadAttachmentStore` commit for the worker-producer case. GUI timeline for worker images coordinates with CIA-S04 but owns the worker bubble case. This slice owns the *worker-produced* image path.

---

## Founder Intent

Raw request:

```text
If someone uses the design lane for fan-out and then asks for a tweak to a design,
that should be possible. If they can never get a response with a new image unless
they use fan-out, something is wrong.
```

Product value:

```text
A work thread is one continuous conversation. Design fan-out produces options; chat
must be able to iterate on a picked look — "make the header bolder", "try it in
dark mode" — and land a new image in the same thread without forcing another full
bench run every time.
```

Trusted workflow slice:

```text
fan-out design board lands -> user picks an option -> user sends a chat tweak ->
image-capable worker returns a new canonical image attachment -> timeline shows
thumbnail + caption -> next turn can reference that image in context
```

Non-goals:

- No new image provider or model hosting. Reuse the user's existing CLIs.
- No inline HTML render pipeline (Design0 § dead).
- No fake image: if capture fails, show honest text failure — never a placeholder
  thumbnail or stock emoji standing in for a photo.
- No requirement that every chat worker generates images — only workers whose
  driver manifest exposes `imageGen`.
- No iOS surface in v1 (Mac thread timeline first).
- No broad taste-memory or pick-management feature in v1. WIO-S03 only
  materializes a picked design image into a lightweight `user_decision` turn when
  that image is needed as the reference for an image-producing chat tweak.

---

## Current State

### What works today

| Path | Image truth | Timeline UI |
| --- | --- | --- |
| **Fan out → Design team** | `DesignImageRunner` captures PNG/JPEG into run folder; `WorkerAnswer.output` = path | `DesignBoardView` renders tiles; `ThreadBoardRow` is text-only |
| **Chat → one worker** | `WorkerRunner` captures **stdout text only** (`grok --output-format plain`) | `ThreadView.workerBubble` = markdown text only |
| **User → worker attachments** | `ThreadAttachmentStore` + `attachmentRefs` on user turns (CIA backend built) | Composer paste + timeline chips **not wired** (CIA-S03/S04) |

Note: `ThreadTurn.attachmentRefs` has been modeled on *all* turns (including `workerChat`) since the thread MLP with a default of `[]`. The schema was intentionally general; only the write path from a worker reply and the timeline renderer were missing.

### Why worker image output in chat was not shipped earlier

It was a deliberate sequencing decision, not an accidental gap or a hard technical prohibition.

- The canonical attachment store, `ThreadAttachmentStore`, `AttachmentIngestor`, atomic send transaction, `includedAttachments` audit, hash verification, workspace staging, and CLI/MCP parity (CIA-S00–S07) had to exist *first*. Without that substrate there was no single durable home for any image that would survive restarts, participate in context packets, and obey the same laws as user paste.
- Chat send (CR4b) was intentionally text-oriented while that foundation landed.
- The `imageGen` driver contract + `DesignImageRunner` capture/normalization were built for the parallel design-fan-out lane (`DesignCoordinator`, per-seat files in the run dir, board UI). They proved the arrival modes and normalization work.
- Once user images + the send transaction were solid, the symmetric case (a worker *producing* a canonical image on a chat turn) became the next logical slice.

`Persistent_Work_Threads.md` and the thread MLP router listed this explicitly as future work after the attachment backend. No product law forbade it; the work was ordered to de-risk the harder shared store and transaction first.

### Observed failure (2026-06-17 repro)

Thread `Give me a picture of a cute cat`:

- Persisted worker turns contain prose only (`Here's a photorealistic photo…`).
- `attachmentRefs: []` on every turn.
- Grok **did** write `~/.grok/sessions/.../ProbeScratch/.../images/1.jpg` (~293 KB).
- Allnighter never copied or referenced that file.

Root cause is **two gaps**, not a rendering typo:

1. **Backend:** `ThreadSendCoordinator.completeSend` + `WorkerRunner.invoke` always use the worker's regular `invoke` block (text/plain) and `settle` writes only `outcome.output` into the worker turn. The `manifest.imageGen` block and `DesignImageRunner`'s capture logic are never consulted for chat.
2. **Frontend:** even if a path existed, `ThreadView.workerBubble` (and legacy) are markdown-text only. CIA-S04 owns user-attachment chips; worker-authored images were explicitly out of scope for that slice.

### Design handoff mockups (not yet product truth)

`docs/phases/wiring/design_handoff_home_workspace/` shows:

- **fanout** turns with 78×120pt option tiles + pick badge + Open board;
- **chat** turns with markdown body;
- **user** turns with screenshot thumbnails.

Those are pixel reference. Shipped `ThreadView` implements chat as text-only and
fan-out board rows without inline image tiles.

---

## User-Visible Claim

```text
After a design board — or any chat turn to an image-capable worker — a reply that
includes a generated image shows that image inline in the thread, durably, with
caption/prose when available. A follow-up tweak can reference the last image and
return a new one.
```

---

## SSOT

Truth owner:

```text
AllnighterEngine.ThreadSendCoordinator.completeSend     (profile choice + capture + commit)
AllnighterEngine.ThreadAttachmentStore                  (canonical bytes + attachments.json)
ThreadTurn.text                                         (human caption / prose)
ThreadTurn.attachmentRefs                               (ordered worker output images on workerChat turns)
ThreadContextPacket.includedAttachments                 (audit: exactly what the next worker received)
DriverManifest.imageGen                                 (per-driver capture contract + arrival rules)
```

The single write site for worker images on chat turns is inside (or immediately after) `completeSend`, before the worker turn is marked terminal. `settle` is extended to carry attachment refs.

Lie-prone layers:

```text
RoutingComposer local state
SwiftUI markdown-only worker bubbles
Grok / agy / codex session folders under ~/.grok/, ~/.gemini/... (vendor cache — never product truth)
stdout prose claiming "here is the image" without a corresponding attachment ref
read-time scraping of vendor dirs at render time
```

Semantic rules (new):

1. **Worker-generated images are canonical attachments**, same store law as user
   paste (`Composer_Image_Attachments.md` § Truth owner). Do **not** use
   `ArtifactRef` for chat/worker images.
2. Add exactly `AttachmentSourceKind.workerGenerated = "worker_generated"` to
   distinguish worker-producer provenance in `attachments.json`.
3. When a chat send selects the `imageGen` profile, `completeSend` must attempt
   image capture **before** settling the worker turn terminal. Regular text chat
   to an image-capable worker stays text-only unless the profile decision fires.
4. Capture reuses the **DesignImageRunner arrival modes** (`promptDirected`,
   `stdoutPath`) — one shared normalizer, not a second ad-hoc Grok parser in the
   GUI. `sessionIdRegex` is resume metadata only; it is not permission to scrape
   vendor session folders. A future folder-harvest mode would require an explicit
   manifest field naming safe roots and copy rules.
5. `ThreadTurn.text` remains the human-readable caption/prose after emitted path
   lines are stripped. If the image profile replies with a path only, text may be
   `nil` or a neutral status label; attachments carry the image truth.
6. **Design continuity:** when the thread contains a recent design-board turn or
   a prior worker image attachment, `ThreadContextBuilder` must include the
   relevant image in the outbound packet (path + hash via `includedAttachments`).
   Minimum v1: last worker-generated attachment in thread; picked board images
   are materialized into thread attachments before use (see WIO-S03).
7. Worker-output attachment order is local to the worker turn. In v1 only the
   first normalized image is committed, with `TurnAttachmentRef.sequence == 0`.
   Do not consume or mutate `draft_index.nextSequence`; that sequence belongs to
   user draft/paste order.
8. If capture finds no valid image bytes, settle the turn as today (text only).
   Optionally append a system-visible note when stdout claims an image but capture
   failed — never silently drop the claim.

Duplicate truth to delete:

```text
Any future plan to render worker images from ~/.grok/sessions at read time
Any GUI-only image path parsed from markdown at render time
```

---

## Inference Bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Worker stdout → UI | `completeSend` | "Model said image → show emoji/stock art" | Caption without attachment ≠ image render | Turn with text claim, empty refs → no thumbnail |
| Vendor session dir → thread | `ThreadAttachmentStore` | "File exists in ~/.grok → display in thread" | Must copy into `attachments/` and record ref | Delete vendor file → thread thumbnail still opens |
| Chat vs design invoke | `DriverManifest` | "Same grok driver → same capture" | Chat must opt into `imageGen` capture explicitly | Plain chat invoke does not write PNG without WIO law |
| Board pick → tweak context | `ThreadContextBuilder` | "User typed tweak → model remembers board" | Next packet must include picked/last image delivery | Context packet test asserts `includedAttachments` |

---

## Architecture

Chat send reuses the existing `ThreadSendCoordinator` transaction. `beginSend`
continues to own the user turn, optimistic worker turn, and context packet; WIO-S03
adds an optional seed-image materialization step before the packet is saved.
`completeSend` invokes and settles.

```text
beginSend
  │
  ├─ optional WIO-S03: materialize seed image (prior worker image / picked board)
  │
  ├─ prepare context (ThreadContextBuilder) + deliveries
  │
completeSend
  ├─ decide invoke profile: regular invoke vs imageGen (see below)
  ├─ regular: WorkerRunner.invoke(...) as today
  ├─ imageGen: WorkerImageInvoker.invokeImageGen(...)
  │      (same command resolution law as WorkerRunner, but uses imageGen args,
  │       promptTemplate, promptVia, arrival, and timeoutSeconds)
  ├─ NEW: WorkerImageCapture (factored from DesignImageRunner)
  │      .capture(imageGen: manifest.imageGen, stdout: ..., runDir: ..., intendedOut: ...)
  │      returns validated local PNG/JPEG URL + path-stripped caption/sessionId or nil
  ├─ if image bytes:
  │   AttachmentIngestor → ThreadAttachmentStore.commitIngested(sourceKind: .workerGenerated)
  │   attach TurnAttachmentRef(sequence: 0) to the worker turn
  └─ settle: text = caption (path lines stripped), attachmentRefs = [...]
```

`ThreadView.workerBubble` then renders caption markdown + ordered attachment chips (46×66 pt target from the design handoff spec; reuse or share with CIA-S04).

**Invoke profile decision (binding):**  
Add a deterministic helper named `ChatImageIntent` with fixture tests. Use
the worker's `imageGen` profile (args + promptTemplate + longer timeout + arrival
rules) instead of its regular `invoke` block exactly when:

- the manifest declares `imageGen`, **and**
- the current user message explicitly asks for image output (`generate image`,
  `return an updated mockup`, `draw`, `render`, `screenshot`, `new visual`,
  `make an image`, etc.), **or**
- the thread has prior image context (worker-generated attachment or picked
  design board image) **and** the current message is a visual edit/tweak
  (`make it bolder`, `dark mode`, `more whitespace`, `try this in ...`,
  `more like this`, etc.).

Prior image context alone is not enough. A pure text question like "what do you
think of it?" stays on the fast regular chat path unless the user asks for a new
image or visual edit. The helper's negative fixtures must cover this.

The capture helper must be **shared code**, not duplicated. Recommended: extract the arrival handling (`promptDirected` / `stdoutPath`), `firstCapture`, `copyImage`, `isValidImage`, and normalization into a small reusable type (`WorkerImageCapture`) and then have `DesignImageRunner` call it. Both design seats and chat worker replies must use identical validation rules.

### Prompt shaping and reference images for chat image turns

When the chat path selects the `imageGen` profile:

- The `imageGen.promptTemplate` is used (same contract as design).
- The "designPrompt" portion substituted into the template is the user's latest message (the tweak instruction).
- Any reference image (last worker-generated attachment from this thread, or the chosen board option) is delivered to the worker using the existing mechanism: it appears in `includedAttachments` for the turn and is rendered by `AttachmentDeliveryRenderer.pathBlock` (or a small extension for "Reference images").
- `DriverManifest.canReadImages` is build-side capability and must not suppress reference paths for an `imageGen` invocation. For imageGen turns, the imageGen profile itself is the authority that the worker can use local reference-image paths. If a future provider can generate images but cannot consume references, add an explicit `imageGen` capability flag rather than reusing `canReadImages`.
- After the CLI exits we still run the capture/normalize step using `imageGen.arrival`, `stdoutPathRegex`, etc. The worker's prose reply (after stripping any emitted path) becomes the turn `text`; the normalized image becomes `attachmentRefs[0]` (or more if a future worker emits multiple).

This keeps prompt delivery, hashing, staging, and audit records using the same paths that user paste already exercises. "More like this" on a design board may still prefer the engine's resume/`image_edit` flow when the manifest exposes a `sessionId`; a generic chat tweak after a board pick falls back to the re-prompt + reference path.

### Design board pick → chat image continuity

A `designBoard` turn records its truth under a `runId` (with `BoardPayload.chosen`). The chosen option image lives in the run folder today.

For a subsequent chat tweak to "see" the picked image, WIO-S03 uses this binding path:

1. Prefer an existing `.workerGenerated` attachment on the most recent
   `workerChat`/`userDecision` turn in the thread.
2. If none exists, resolve the latest `designBoard` turn's `runId`, load the
   run's board payload, and require `board.chosen`.
3. Copy the chosen option image from the run folder into this thread's
   `attachments/` as `sourceKind: .workerGenerated`.
4. Append a lightweight `userDecision` turn with that `TurnAttachmentRef` and
   text such as `Picked design option <workerId> as the reference image.` before
   the chat `userMessage` that asks for the tweak.
5. Include the materialized attachment in the new worker context packet via
   `includedAttachments`.

Do not leave a seed image as an index-only attachment with no turn reference. Do
not rely on run-folder paths in the prompt after materialization; the prompt must
use the canonical/staged attachment delivery path.

---

## Implementation Slices

### WIO-S00 — Contract + capture helper

**Status:** ✅ Built (2026-06-17)

**Goal:** One engine helper owns "CLI finished with imageGen manifest → optional validated local image file". Zero duplication with design capture.

- Add `AttachmentSourceKind.workerGenerated = "worker_generated"` with Codable
  round-trip coverage. Existing attachment fixtures must still decode.
- Extract the pure capture/normalize logic (`firstCapture`, `copyImage`,
  `isValidImage`, arrival switch, magic-byte validation) into
  `WorkerImageCapture`. Refactor `DesignImageRunner` to call it; do not leave a
  parallel copy behind.
- Capture result shape:
  - `normalizedImageURL`
  - `captionText` (stdout with exact path / JSON path lines stripped)
  - `sessionId`
  - `failureReason`
- Add `WorkerImageInvoker` as the command wrapper for the `imageGen`
  profile. It must reuse WorkerRunner's command-resolution laws: neutral scratch
  CWD when no working dir, `ToolInvocation` support, `promptVia`, env, and
  `timeoutSeconds`.
- Update `DriverManifest.ImageGen` comments to say chat image turns also use this
  block; no JSON change is required for v1.
- Unit tests: promptDirected success, stdoutPath success, path-only caption
  stripping, invalid bytes fail, and no session-folder scraping from
  `sessionIdRegex`.

**Proof:** `swift test --package-path Packages/AllnighterCore --filter 'WorkerImageCapture|DesignImageRunner|AttachmentLegacyDecode'`

---

### WIO-S01 — Chat send capture in `completeSend`

**Status:** ✅ Built (2026-06-17)

**Goal:** Headless chat replies persist worker images into canonical storage.

- Extend `ThreadSendCoordinator.PendingSend` with the profile decision and any
  materialized seed-image deliveries needed by WIO-S03.
- When the profile is regular text, keep today's `runner.invoke` + `settle` path.
- When the profile is `imageGen`, invoke via the imageGen wrapper, then capture
  and ingest the normalized image through `ThreadAttachmentStore.ingestor` +
  `commitIngested(sourceKind: .workerGenerated, sequence: 0)`.
- Commit worker attachment record and worker-turn `attachmentRefs` in one
  per-thread lock window before the turn becomes terminal. If `ThreadStore` and
  `ThreadAttachmentStore` still use separate helpers, add a narrow coordinator
  method rather than writing raw `thread.json`.
- Extend settlement to accept `workerAttachmentRefs` and `captionText`; no GUI
  changes yet.
- `ThreadSendCoordinator.Result.attachmentIds` keeps its existing meaning:
  user/current-send attachment ids. Add explicit `workerAttachmentIds` and
  `workerDeliveries` so CLI/MCP do not overload the existing field.

**Proof:** Extend `WorkerChatCoordinatorTests` — beginSend/completeSend leaves
`attachmentRefs.count == 1` and file exists under `threads/.../attachments/`.
Headless fake vision worker or Grok mock with path in JSON stdout.

---

### WIO-S02 — Image-producing chat invoke profile

**Status:** ✅ Built (2026-06-17)

**Goal:** Grok/Gemini/Codex *chat* turns that target image output use the same
`imageGen` invocation contract (args, template, arrival, timeout) that design
fan-out already proved.

- Add `ChatImageIntent` fixtures for positive and negative routing:
  - positive: "generate an image", "return an updated mockup", "make it bolder"
    with prior image context, "more like this" with prior image context;
  - negative: "what do you think of it?" with prior image context, and text-only
    chat to an image-capable worker.
- When the decision rule fires, invoke using `imageGen.args` +
  `imageGen.promptTemplate` instead of the regular `invoke` block. Use
  `imageGen.timeoutSeconds`, not `invoke.timeoutSeconds`.
- Substitute `{{designPrompt}}` with the latest user message plus a short
  "use the attached reference image when present" instruction. Substitute
  `{{imageOut}}` with a temp file inside the neutral run/scratch dir.
- Do not add session-folder harvest in v1. `stdoutPathRegex` and prompt-directed
  save are the only capture paths.
- On capture failure after an imageGen run: settle the worker turn as text-only
  with the path-stripped prose and a visible failure note/reason. Never synthesize
  a thumbnail.

**Proof:** `ThreadSendCoordinatorAttachmentTests` extension + integration with fake image worker; optional real-Grok founder smoke on a design thread + "make the header bolder, return updated image".

---

### WIO-S03 — Design continuity context

**Status:** ✅ Built (2026-06-17)

**Goal:** A tweak after a board (or prior chat image) references the picked / latest image as a deliverable reference for the worker.

- Add a narrow `ThreadImageSeedResolver` (or coordinator-private helper) that
  returns at most one seed image for v1:
  1. most recent `.workerGenerated` attachment ref on a prior `workerChat` or
     `userDecision` turn;
  2. otherwise latest `designBoard` turn with `runId` whose run board has
     `chosen`.
- If the seed is already a thread attachment, create an
  `IncludedAttachmentDelivery` from `attachments.json`, verifying the stored hash.
- If the seed is a chosen board image, materialize it into `attachments/` as
  `.workerGenerated`, append the `userDecision` turn, then create the delivery.
- Merge current user image deliveries + seed delivery deterministically:
  current user images first, seed image last unless the user explicitly attached
  an image in the current send and the decision helper says no seed is needed.
- Save the prepared packet with final `includedAttachments`; invoke and context
  reveal must read the same saved packet.

**Proof:** `ThreadSendCoordinatorAttachmentTests` + `ThreadContextBuilderTests` — thread containing a designBoard (with chosen) or prior worker image attachment, followed by a chat send → the prepared packet's `includedAttachments` contains the prior image's delivery record with matching sha256. Context reveal shows it.

---

### WIO-S04 — Timeline render (Mac GUI)

**Status:** **GUI deferred** — hand off to GUI implementer after backend lands

**Goal:** Worker chat bubbles show thumbnails for `attachmentRefs`.

- Extend `ThreadView.workerBubble` (and legacy `ThreadsView` if still routed):
  caption markdown + attachment chip row (46×66pt thumb per home-workspace spec).
- Reuse CIA-S04 `AttachmentChip` when that slice lands; if WIO ships first, implement
  minimal chip inline and refactor to shared component when CIA-S04 merges.
- Context reveal shows worker attachments in audit panel.
- GUI fixture: `thread-worker-image-reply` + layout-watcher PASS.

**Proof:** `bash scripts/gui_proof.sh thread-worker-image-reply` + watcher PASS.

---

### WIO-S05 — CLI/MCP parity

**Status:** ✅ Built (2026-06-17)

**Goal:** `alln thread send` and MCP `thread_send` return attachment ids when
capture lands.

- Preserve current `attachmentIds` / `attachments` as user-send attachments for
  compatibility.
- Add `workerAttachmentIds` and `workerAttachments` / `workerDeliveries` to CLI
  JSON and MCP response payloads.
- Update `ContractRegistry` / generated artifacts if the response schema is
  represented there; no hand-coded MCP-only schema fork.
- Idempotency replay must return the same split fields when possible. If legacy
  idempotency records cannot reconstruct worker attachments, document the
  compatibility fallback and add a regression test for new records.

**Proof:** CLI/MCP test — send to fake image worker → JSON lists
`workerAttachmentIds`, while `attachmentIds` remains the user-send array.

---

## Works Test (founder)

**Setup:** A thread that already has either (a) a completed design board with at least one picked option, or (b) a prior chat turn that produced a worker image. Grok (or another imageGen worker) is active.

**Gesture:**

1. Open the thread.
2. Ensure chat routing to an image-capable worker (Grok Build).
3. Send: "Make the header bolder and return an updated mockup."
4. Wait for the reply to land.

**Assert:**

- User message appears immediately (optimistic send law).
- The worker turn renders a thumbnail plus caption/prose when available (never
  caption-only when a valid image was captured).
- The thumbnail opens the canonical PNG from `threads/.../attachments/`.
- Quit + relaunch: the image is still present and openable.
- Open context reveal for the *next* chat send in the same thread: the prior
  worker image appears in `includedAttachments` (path + sha256).
- After a design board pick, the first image-producing chat tweak receives the
  chosen image in its packet; if the chosen image was still only in the run
  folder, the thread now contains a `userDecision` turn with the materialized
  attachment ref.

**Engine proof command:**

```text
swift test --package-path Packages/AllnighterCore --filter 'WorkerImageCapture|DesignImageRunner|ThreadSendCoordinatorAttachment|WorkerChatCoordinator|ThreadContextBuilder'
```

---

## Done When

- [x] WIO-S00 shared capture helper + `workerGenerated` source kind; all prior design tests still green.
- [x] WIO-S01–S02: `completeSend` (and deterministic profile selection)
      commits worker images for image-capable chat; tests assert
      worker-turn `attachmentRefs` + canonical file.
- [x] WIO-S03: prior worker / picked image is delivered in context for
      follow-up turns; board picks are materialized into a `userDecision` turn
      before use; context reveal + packet tests pass.
- [ ] WIO-S04: Mac `ThreadView` worker bubbles render thumbnails (layout-watcher PASS on named fixture).
- [x] WIO-S05: `alln thread send --json` and MCP surface
      `workerAttachmentIds` / worker deliveries when capture succeeds, without
      changing the meaning of existing `attachmentIds`.
- [x] No duplicate capture code; vendor session folders remain explicitly non-truth.
- [x] Router in `Persistent_Work_Threads.md` reflects landed status.

## Risks & open details (call out before implementation)

- Heuristic for "use imageGen profile on chat" can surprise users ("why did this send take 10 min and return an image?"). The deterministic helper above is binding: prior image context alone is not enough.
- Timeout difference: imageGen manifests commonly declare 600s; regular chat invoke is ~300s. The coordinator must use the profile's declared timeout.
- Board pick provenance: do not leave this as a run-folder reference after WIO-S03. Copy into thread attachments and record the `userDecision` turn before delivering it to a chat worker.
- Capability vocabulary: `canReadImages` is build-side. ImageGen reference-image support is governed by the `imageGen` profile in v1; if that stops being true for a provider, add an explicit imageGen capability flag.
- Multiple images per worker reply: start with "at most one" (first normalized image wins) to match current design option model; extend only if a driver manifest signals multi-image.
- iOS: explicitly deferred; the store + refs are already cross-surface.

---

## Related Docs

| Doc | Relationship |
| --- | --- |
| [`Composer_Image_Attachments.md`](../Composer_Image_Attachments.md) | User inbound attachments; shared canonical store |
| [`Design1_Image_Team.md`](../../mvp/Design1_Image_Team.md) | Fan-out image gen — reuse capture, not duplicate |
| [`Design2_Build_This.md`](../../mvp/Design2_Build_This.md) | Downstream: picked image → execute (already built) |
| [`01_Work_Threads_MLP.md`](01_Work_Threads_MLP.md) | Turn families; `attachmentRefs` on turns |
| [`design_handoff_home_workspace`](../wiring/design_handoff_home_workspace/README.md) | Visual target for thumbs + fan-out tiles |

---

## Feature Packet (SSOT Feature Workflow)

```text
Allnighter Feature Packet

Status: Ready for Implementation

Founder Intent
- Raw request: design fan-out then chat tweak must return a new image
- Product value: continuous design iteration inside one thread
- Trusted workflow slice: board → pick → chat tweak → inline image reply
- Non-goals: new providers, HTML render, fake thumbnails, iOS v1

Current State
- Existing truth owners: ThreadStore, ThreadSendCoordinator, DesignImageRunner,
  ThreadAttachmentStore, DriverManifest.imageGen
- Existing UI: ThreadView text bubbles; DesignBoardView full gallery; attachment chips only for user turns
- Existing tests: DesignImageRunnerTests, ThreadSendCoordinatorAttachmentTests,
  WorkerChatCoordinatorTests, Attachment*Tests
- Gap: chat path (invoke + settle) never calls imageGen capture; worker turns never receive attachmentRefs from the engine; timeline has no worker image renderer

SSOT
- Truth owner: ThreadSendCoordinator.completeSend (profile + capture + commit) + ThreadAttachmentStore
- Lie-prone layers: stdout prose, vendor session dirs, SwiftUI text-only bubbles, any future read-time scraping
- New rules: workerGenerated attachments; shared (non-duplicated) capture with design; deterministic image-intent routing; automatic prior-image delivery for continuity
- Duplicate truth to delete: read-time session dir scraping; any GUI-only path parsing for worker images

Implementation
- Core/Engine impact: AttachmentSourceKind.workerGenerated, shared WorkerImageCapture, imageGen invoker/profile selection in coordinator, context seed for prior images
- Mac app impact: ThreadView.workerBubble now renders attachment chips for worker turns (WIO-S04); coordinate sizing with CIA-S04
- iOS: deferred (store + refs are already portable)
- Driver impact: chat path must honor imageGen when the decision rule fires; manifests already declare it correctly

Proof
- Works Test: design thread → chat tweak → thumbnail persists across relaunch
- Exact command: swift test --package-path Packages/AllnighterCore --filter 'WorkerImageCapture|DesignImageRunner|ThreadSendCoordinatorAttachment|WorkerChatCoordinator|ThreadContextBuilder'; bash scripts/gui_proof.sh thread-worker-image-reply
- Missing proof / waiver: none for engine slices; GUI requires layout-watcher

Done When
- User-visible claim: chat returns durably embedded worker images
- Proof: tests + GUI fixture named above
- Docs: this slice + router link in Persistent_Work_Threads.md
```
