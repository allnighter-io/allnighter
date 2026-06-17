# Composer Image Attachments (Paste + CLI + MCP)

**Status:** Draft founder packet — **not implementation-ready until
`threads/05_ThreadStore_Hardening.md` lands**
**Owner:** AllnighterCore · AllnighterEngine · Mac GUI · CLI/MCP
**Created:** 2026-06-16 · **Updated:** 2026-06-17 (implementation law + invoke/reveal hardening + ThreadStore prerequisite)
**Process:** `docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`
**Depends on:** [`Persistent_Work_Threads.md`](Persistent_Work_Threads.md),
[`threads/05_ThreadStore_Hardening.md`](threads/05_ThreadStore_Hardening.md),
[`CLI_Implementation_Contract.md`](CLI_Implementation_Contract.md),
[`Agent_First_MCP_And_Messaging_Workflows.md`](Agent_First_MCP_And_Messaging_Workflows.md)

---

## Current implementation gate

CR4b is built. Do not re-run the CR4 send packet for this feature.

The blocker is storage/send truth: implement
[`threads/05_ThreadStore_Hardening.md`](threads/05_ThreadStore_Hardening.md)
before this doc, then update this packet's status to execution-ready. The rest
of `docs/phases/threads/` is **not** a prerequisite for image attachments.

## First principle

A pasted image is part of the user's turn. If Allnighter shows it in the composer
and the user presses Send, **thread history, context reveal, and worker prompt must
all agree on the same ordered attachment set.** No partial sends. No hidden drops.
No best-effort history.

**The bar:** if the user sees an image in the composer, then after Send there is
exactly one ordered attachment truth, one audit packet showing what the worker
received, and one canonical history source that survives mirror cleanup and app
restarts.

---

## Implementation law (binding)

### 1. One engine-owned send path

`RoutingComposer`, CLI `thread send`, and MCP `thread_send` **must not** append
turns or packets directly. They call the same coordinator/service
(`WorkerChatCoordinator` or thin wrapper). Current `ThreadsViewModel.sendRouting`
append paths for Fan out / Execute are **temporary scaffolding** and must not
survive the attachment send-transaction slice.

### 2. Send transaction owns the full truth write

Under the per-thread `.lock`, **one transaction** must:

1. Promote ready drafts → `attachments/`
2. Update `attachments/attachments.json`
3. Append user turn with ordered `attachmentRefs`
4. Re-hash/stage and compute delivery snapshot (`canonicalPath`, `deliveredPathUsed`, `storedSha256` per attachment)
5. Save `context/<packetId>.json` with `includedAttachments`
6. Create optimistic `running` worker turn

If any required step fails → **send fails** before a user-visible sent turn is
committed. No split-brain thread state. All file writes in this transaction are
atomic (temp + rename; port `RunStore` law).

### 3. Draft readiness enforced twice

UI Send shows **"Preparing…"** while any draft is ingesting. The coordinator
**also** rejects or awaits ingesting drafts. **UI state is not a safety boundary.**

### 4. Attachment order is paste order forever

Assign `sequence` at paste/attach time; persist immediately in `draft_index.json`.
Thumbnails, `ThreadTurn.attachmentRefs`, `ThreadContextPacket.includedAttachments`,
and prompt path blocks **all sort by `sequence`**. Never sort by async completion
order, filename, id, or write time.

### 5. Context packets are the audit record

`IncludedAttachmentDelivery` stores:

- `attachmentId`
- `sequence`
- `canonicalPath`
- `deliveredPathUsed`
- `storedSha256`

UI file open/reveal → `canonicalPath`. Context reveal labels `deliveredPathUsed`
as **"path sent to worker."** Workspace mirrors are not truth.

The worker prompt is rendered from the saved packet + `includedAttachments`, not
from drafts, transient GUI state, or a fresh attachment-store scan. Once the packet
is saved, invoke and later reveal must agree on the same attachment block.

### 6. Workspace mirrors are delivery cache only

Stage into `<workingDir>/.allnighter/attachments/thread_<id>/<id>.png` only for
invocation (byte copy, not symlink). Delete mirrors after worker turn **terminal +
24h grace**. Canonical Application Support bytes are **never** swept by this cleanup.

### 7. Git hygiene is local and non-invasive

| Condition | Action |
| --- | --- |
| `<workingDir>/.gitignore` exists | Append `.allnighter/` idempotently |
| Git repo, no `.gitignore` | Append `.allnighter/` to `.git/info/exclude` |
| Neither writable | Stage if possible; warn `ATTACHMENT_STAGE_UNIGNORED` |
| Not a git repo | Stage; no ignore action |

**Never** create a visible `.gitignore` in a folder that did not already have one.

### 8. CLI freezes bytes before validation

For every `--image`: copy source → temp ingest file → hash + validate **temp** →
acquire thread lock → commit from temp. Prevents source mutation between
validation and send.

### 9. MCP union is registry work

Add array/union param support to `ContractRegistry` so `images[]` can be:

- absolute path `string`
- `{ "mimeType", "base64" }`

Regenerate descriptors. Runtime parsing without generated schema support **does
not count**. No hand-coded MCP-only descriptors.

### 10. Legacy decode is zero-migration

Existing `ThreadTurn` and `ThreadContextPacket` JSON without attachment fields
decode with empty arrays (`attachmentRefs: []`, `includedAttachments: []`). Explicit
tests against existing fixtures.

### 11. History renders from canonical bytes

Timeline chips and thumbnails for old turns load from **canonical** storage, never
workspace mirrors. Message threads stay reliable after mirror cleanup.

### 12. Failure is visible and namespaced

Registry-owned errors only (add to `ContractRegistry` before emit):

| Code | When |
| --- | --- |
| `ATTACHMENT_HASH_MISMATCH` | `storedSha256` ≠ disk at invoke or load |
| `ATTACHMENT_TOO_MANY` | Over count cap |
| `ATTACHMENT_TOO_LARGE` | Over byte cap |
| `ATTACHMENT_UNSUPPORTED_TYPE` | Not an allowed image type |
| `ATTACHMENT_DECODE_FAILED` | Corrupt / undecodable |
| `ATTACHMENT_BASE64_INVALID` | MCP base64 decode failure |
| `ATTACHMENT_STAGE_FAILED` | Could not copy into workspace mirror |
| `ATTACHMENT_STAGE_UNIGNORED` | Staged but could not update gitignore/exclude |
| `CONTEXT_ATTACHMENT_CAP_EXCEEDED` | Protected attachment block won't fit |
| `THREAD_SEND_IDEMPOTENCY_CONFLICT` | Same idempotency key, different payload |

Each needs `agentAction`, `fixCommand` where applicable, `retryable`.

Protected context rule: never silently trim the **current send's** attachment
block; fail with `CONTEXT_ATTACHMENT_CAP_EXCEEDED`.

---

## Truth owner (one table)

| Layer | Owns |
| --- | --- |
| `threads/.../attachments/` (Application Support) | **Canonical** bytes + `attachments.json` |
| `draft_attachments/` + `draft_index.json` | Pre-send drafts + `sequence` |
| `ThreadTurn.attachmentRefs` | Committed ordered refs (sent turns) |
| `context/<packetId>.json` | Audit: `includedAttachments` |
| `<workingDir>/.allnighter/...` | Invoke delivery cache only |
| `AttachmentIngestor` | Decode, downscale (2048 long edge), normalize, hash — all surfaces |

Do not embed full `TurnAttachment` on each turn in `thread.json`. Do not use
`ArtifactRef` for chat images.

History lookup is a join: `ThreadTurn.attachmentRefs` → `attachments.json` →
canonical bytes. If the index or bytes are missing, render a broken attachment
chip and a visible system note; do not silently hide the ref.

---

## Schema

```swift
public struct TurnAttachmentRef: Codable, Sendable, Equatable {
    public var attachmentId: String
    public var sequence: Int
}

public struct DraftAttachmentRef: Codable, Sendable, Equatable {
    public var draftId: String
    public var sequence: Int
    public var status: DraftAttachmentStatus  // ingesting | ready | failed
}

public struct IncludedAttachmentDelivery: Codable, Sendable, Equatable {
    public var attachmentId: String
    public var sequence: Int
    public var canonicalPath: String
    public var deliveredPathUsed: String
    public var storedSha256: String
}

// ThreadTurn — default [] (law §10)
public var attachmentRefs: [TurnAttachmentRef] = []

// ThreadContextPacket — default [] (law §10)
public var includedAttachments: [IncludedAttachmentDelivery] = []
```

```swift
public struct TurnAttachment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var threadId: String
    public var createdAt: Date
    public var storagePath: String       // attachments/<id>.png
    public var mimeType: String          // image/png
    public var byteSize: Int
    public var storedSha256: String
    public var sourceSha256: String?
    public var originalWidth: Int?
    public var originalHeight: Int?
    public var storedWidth: Int?
    public var storedHeight: Int?
    public var originalName: String?
    public var sourceKind: AttachmentSourceKind
    public var wasDownscaled: Bool
}
```

**`AttachmentPolicy` defaults:** max 4 images; 8 MB each; 20 MB total; 2048px long
edge after downscale; 40 MP decode cap.

**On-disk layout:**

```text
threads/thread_<id>/
  .lock
  thread.json
  draft_attachments/
    draft_index.json
    <draftId>.png
  attachments/
    attachments.json
    <id>.png
  context/                    # ThreadStore.savePacket — do NOT rename

<workingDir>/.allnighter/attachments/thread_<id>/   # delivery cache (law §6)
```

**Delivery/invoke boundary:**

1. During the send transaction, re-hash canonical `storedSha256`
2. Stage workspace mirror if `workingDir` set (law §6–7)
3. Save final `includedAttachments` with final `deliveredPathUsed`
4. Render the protected prompt path block from saved `includedAttachments`, sorted by `sequence`
5. Invoke `WorkerRunner` with the saved packet text; no recomputing from drafts or index

Hash mismatch before invoke → `ATTACHMENT_HASH_MISMATCH`, fatal.

---

## Surface contracts

### GUI (CIA-S03)

- `NSTextView.paste(_:)` override: image URLs → pixel data → text fallback
- Paste precedence: **image wins** (no text from same paste when image present)
- Thumbnail strip sorted by `sequence`; loading skeleton during ingest
- Send → **Preparing…** (law §3); image-only send allowed
- Timeline chips render thumbnails from canonical bytes; context reveal shows
  thumbnails/list plus **"path sent to worker"** from the saved packet
- Non-vision: composer badge; vision: privacy notice (worker CLI may upload)
- **DnD → CIA-S09 only** (last slice)

### CLI

```bash
alln thread send <thread-id|latest> [<message>] \
  [--image <path>]... [--worker <model-id>] [--idempotency-key <key>] [--json]
```

Law §8 temp-freeze per `--image`. Law §1 coordinator only. ≥1 of message or `--image`.

### MCP

`thread_send`: `images[]` union (law §9), `idempotencyKey`, `waitSeconds`,
`thread_status` / `thread_get`. Base64 → ingestor → canonical store.

---

## Implementation appendix

The law above is binding. This appendix preserves the operational detail
implementers need so the shorter spec does not become under-specified.

### Current state audit

| Area | Current gap |
| --- | --- |
| `ThreadTurn` | No `attachmentRefs`; chat images must not be squeezed into `artifactRefs` |
| `ThreadContextPacket` | No `includedAttachments`; context reveal only has packet text |
| `ThreadStore` | `thread.json` and packets are not yet protected by per-thread flock + atomic transaction |
| `WorkerChatCoordinator.send` | Text-only; invokes `runner.invoke(..., prompt: packet.text)` |
| `ThreadsViewModel.sendRouting` | Appends user turns directly; must be removed from real send path |
| `RoutingComposer` | Plain `TextEditor`; photo button stub; no paste intercept or draft strip |
| `ContractRegistry.MCPToolSpec.Param` | Scalar params only; needs array/union schema support before `images[]` |
| `DriverManifest` | Already has `readsImages` / `canReadImages`; use this seam for delivery decisions |

### Ingest pipeline

All surfaces use `AttachmentIngestor`; no GUI, CLI, or MCP-specific image
pipelines.

```text
source bytes
-> MIME / UTType sniff
-> policy preflight where possible
-> dimension / megapixel guard before full decode when metadata allows
-> background decode
-> downscale to 2048px long edge when needed
-> normalize to deterministic PNG
-> compute sourceSha256 when source bytes are available
-> compute storedSha256 over stored PNG bytes
-> write draft or committed metadata
```

Draft states are `ingesting`, `ready`, and `failed`. A failed draft remains
visible with its error until the user removes it; it never becomes a partial
send.

### Paste mechanics

The composer must use an `NSTextView.paste(_:)` override. A parent
`.onPasteCommand` is not sufficient because the focused `TextEditor` swallows
paste.

Paste precedence:

1. Image file URLs from the pasteboard, filtered by image UTType
2. Pixel data / `NSImage` from the pasteboard
3. Text fallback only when no image was attached

Image wins when the pasteboard contains both image and text. The same paste
gesture must not both attach an image and insert companion HTML/RTF/plain text.

### Draft lifetime

Drafts are durable before send:

```text
threads/thread_<id>/draft_attachments/
  draft_index.json
  <draftId>.png
```

Home composer attachment requires a durable folder. **Create the thread
immediately on first attachment** and store drafts under that thread; do not add a
separate pending scratch folder. If the user removes every draft before any turn
is sent, the empty draft-only thread may be deleted by the same stale-draft
sweeper. Do not leave image bytes only in SwiftUI state.

If the app quits during ingest, reload the draft index on next open. Ready drafts
return as thumbnails; ingesting drafts restart or settle to failed with an exact
error. Send still obeys law §3 after restart.

### Transaction shape

The send transaction is a single critical section. Build the complete ordered
attachment snapshot before writing user-visible turn truth. A useful implementation
shape:

```text
lock thread
  load thread + draft index
  assert every selected draft is ready
  copy/rename draft PNGs into attachments/
  write attachments index atomically
  append user turn with ordered refs
  compute delivery records
  render context body + protected attachment block
  write context/<packetId>.json atomically
  append optimistic worker turn
unlock thread
invoke worker from the saved packet/delivery record
settle worker turn under lock
```

If context assembly cannot include the current send's attachment block, fail
with `CONTEXT_ATTACHMENT_CAP_EXCEEDED` before committing a sent user turn.

### Worker delivery

`readsImages` is capability, not transport. Use manifest-owned
`ImageDeliveryStrategy` so the coordinator does not branch on driver IDs.

V1 strategy is `promptPathBlock`: prepend or include a fixed image block using
`deliveredPathUsed`, sorted by `sequence`. Future strategies may add argv flags or
stdin JSON, but they must be declared by the manifest.

Non-vision workers still receive the user text and the fixed system notice:

```text
[System Notice: The user attached an image to this turn, but your model configuration does not support image viewing. Rely on the user's text below. Do not claim to see the image.]
```

### CLI contract detail

```bash
alln thread send <thread-id|latest> [<message>] \
  [--image <path>]... \
  [--worker <model-id>] \
  [--idempotency-key <key>] \
  [--json]
```

Requires at least one of message or `--image`. JSON output includes `threadId`,
`userTurnId`, `workerTurnId`, `attachmentIds`, `canonicalPath`,
`deliveredPathUsed`, and `storedSha256` for each committed attachment.

Idempotency keys are scoped to the canonical payload: thread target, message,
worker, and frozen image hashes. Reusing a key with a different payload fails
with `THREAD_SEND_IDEMPOTENCY_CONFLICT`.

### MCP contract detail

`thread_send.images[]` accepts either:

```json
"/absolute/local/path.png"
```

or:

```json
{ "mimeType": "image/png", "base64": "iVBORw0KGgo..." }
```

Path inputs must be readable by the `alln` process. Base64 inputs are decoded to
temporary frozen bytes, then use the same ingestor as CLI and GUI. `waitSeconds`
may return an in-flight worker turn; `thread_status` / `thread_get` retrieve
settled state.

### Fan-out and Design lane

Chat sends every current-turn attachment through the one-worker path. Fan-out
compiles per-seat prompts:

- vision seats get the path block in sequence order;
- non-vision seats get the fixed system notice;
- `TeamToolResult.warnings[]` names seats that could not receive images.

Design fan-out maps the first image to the Design request screenshot path when
that lane needs a single primary screenshot; additional images remain in the
prompt context as ordered attachment paths.

### History and cleanup

Timeline chips, thumbnails, and open/reveal actions resolve from canonical
Application Support bytes. Workspace mirrors are delivery cache only and may be
deleted after terminal + 24h grace. Mirror cleanup must be opportunistic as well
as background-safe: running on thread-store access is acceptable; relying only on
a future resident coordinator is not.

Cleanup logs what mirror files were removed. It never touches
`threads/.../attachments/` canonical files or `attachments.json`.

---

## Required proof (slice not done until all pass)

| # | Proof |
| --- | --- |
| 1 | GUI paste → fake vision worker receives path; hash matches `storedSha256`; reveal shows thumbnail + "path sent to worker" |
| 2 | Image-only send works |
| 3 | Send during ingest waits (**Preparing…**), then sends complete ordered refs |
| 4 | Multi-image paste completing out of order → prompt still in paste `sequence` |
| 5 | CLI: mutate source after temp freeze → sent bytes unchanged |
| 6 | MCP base64 and CLI file ingest → same canonical `storedSha256` |
| 7 | `workingDir` set → workspace staging; prompt uses staged relative path |
| 8 | Mirror cleanup removes workspace files; history thumbnails still open canonical |
| 9 | Legacy thread fixtures decode with `attachmentRefs == []` |
| 10 | Concurrent GUI + CLI sends → no lost turns, no packet mismatch |
| 11 | Hash mismatch at invoke → fatal, visible `ATTACHMENT_HASH_MISMATCH` |

CI gate: **fake vision worker** (not real model color guessing). Real Claude/Codex =
smoke only. GUI proof fixture `compose-paste-image` (CIA-S08). DnD manual (CIA-S09).

---

## Slices

| Slice | Delivers |
| --- | --- |
| **CIA-S00** | Schema, `AttachmentIngestor`, canonical store, flock, atomic writes, law §10 defaults |
| **CIA-S00b** | `ThreadStoreConcurrencyTests`, validate, orphan recovery |
| **CIA-S01** | `includedAttachments`, sequence, delivery renderer, protected context, fake worker fixture |
| **CIA-S01b** | Workspace staging, git hygiene (law §7), mirror cleanup (law §6) |
| **CIA-S02** | **Send transaction** (law §2) in coordinator |
| **CR4b** | Remove `sendRouting` bypass (law §1) |
| **CIA-S03** | Paste + attach; law §3–4; Preparing send |
| **CIA-S04** | Timeline from canonical (law §11) |
| **CIA-S05** | CLI law §8 + idempotency |
| **CIA-S06** | MCP law §9 + idempotency + poll tools |
| **CIA-S07** | Design fan-out attachment mapping |
| **CIA-S08** | GUI proof seal |
| **CIA-S09** | Drag-and-drop (last; not blocking v1 done) |

---

## Non-goals

- Workspace mirror as durable truth
- Symlinks for staging
- Renaming `context/` → `packets/`
- iOS v1

---

## Related docs

- `docs/archive/phases/Compose_Routing_CR4_Send_And_Conversations.md` (historical CR4 packet; CR4b is built)
- `docs/phases/threads/01_Work_Threads_MLP.md`
- `docs/mvp/Design2_Build_This.md`
- `ThreadStore.savePacket` → `context/`
- `RunStore` / `RunStoreConcurrencyTests`
