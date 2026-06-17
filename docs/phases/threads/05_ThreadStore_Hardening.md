# 05 - ThreadStore Hardening

Status: Draft founder packet — **implementation prerequisite** for unread and Threads 2.0
Owner: AllnighterEngine (+ AllnighterCore schema helpers)
Updated: 2026-06-17

## Why This Exists

Unread, archive, rename, and pin all mutate or derive from `WorkThread`. The
dangerous part is not the UI. The dangerous part is letting multiple write paths
mutate `thread.json` differently.

Correct foundation order:

```text
ThreadStore hardening
  -> unread/read cursor
  -> Threads 2.0 rail controls
```

Wrong order (how you get month-long SSOT bugs):

```text
add unread light
add pin button
add archive button
hope ThreadStore holds together
```

This doc is an **engine/SSOT spec**, not a UI spec. GUI phases `06` and `07`
must call the APIs defined here; they must not invent parallel mutation paths.

## Founder Intent

```text
One mutation gate for thread truth. Every durable thread change goes through
ThreadStore with explicit semantics, serialized writes, and atomic persistence.
SwiftUI sends intents; it never saves mutated WorkThread structs.
```

## Current State

`ThreadStore` exists and already owns basic CRUD (`create`, `list`, `get`,
`append`, `update`, `archive`). `WorkThread` is a clean Core model. Thread truth
is local, inspectable folder-of-JSON. The derived-state pattern
(`isRunning`, `needsAttention`, `preview`) is already established.

**Good bones. Risky joints.**

| Area | Today | Risk |
| --- | --- | --- |
| `save(_:)` | `public`, writes `thread.json` + regenerates `transcript.md` | Any caller can bypass mutation law, timestamp law, and cursor rules |
| Atomic writes | Direct `Data.write(to:)` without `.atomic` | Concurrent readers can see torn/partial `thread.json` (RunStore already fixed this) |
| Write serialization | None | Concurrent `append` + `markRead` can race; last writer wins loses data |
| `updatedAt` law | `append`/`update`/`archive` all bump; no metadata/cursor split | Archive/rename/pin/read will corrupt recency ordering if left unfixed |
| Metadata APIs | Only `archive`; no `rename`, `setPinned`, `unarchive` | GUI will ad-hoc mutate structs and call `save` |
| Transcript regen | Every `save` regenerates `transcript.md` | Cursor-only and pin/archive writes must not churn transcript bytes |
| Schema evolution | No `formatVersion`; no duplicate-id guard | Decode/migration rules stay implicit; duplicate create can overwrite a thread |

Relevant code today:

- `Packages/AllnighterCore/Sources/AllnighterEngine/ThreadStore.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/WorkThread.swift`
- `Packages/AllnighterCore/Sources/AllnighterEngine/RunStore.swift` (atomic-write reference)

Production callers mostly use store methods, but the CR4 Home/Threads view model
also appends and updates team/design/dispatch turns directly, and fixture seeding
still mutates a loaded `WorkThread` then calls `save`. The hardening pass must
route **all** production content paths through explicit mutation APIs, not only
the chat coordinator. Tests and fixtures may keep full-record writes only behind
an explicit import/fixture gate.

## SSOT

Truth owner:

```text
AllnighterCore.WorkThread + ThreadTurn schema + `formatVersion`
AllnighterEngine.ThreadStore (sole mutation gate)
~/Library/Application Support/Allnighter/Threads/thread_<id>/thread.json
```

Derived, never authoritative:

```text
transcript.md
run→thread inverse index (scan of turns)
GUI selection, scroll, visibility, pin sort cache
```

Layer contract:

```text
AllnighterCore      -> schema + pure derived semantics (no I/O)
AllnighterEngine    -> ThreadStore serialized mutation + atomic persistence
Application Support -> folder-of-JSON on disk
SwiftUI / ViewModel -> render + intent only; never durable thread truth
```

Duplicate truth to delete:

- Public/generic `ThreadStore.save(_:)` for app runtime callers.
- GUI-local title aliases, pin flags, archive flags, or read booleans.
- Sidecar cursor files (`cursor.json`, `read_cursors.json`).
- Any coordinator or view model that reads `thread.json`, mutates a struct, and
  writes back without a store method.

## Schema And Migration Contract

Add a top-level `formatVersion` to `WorkThread` before adding `readCursor`.

Rules:

- Current writer emits `formatVersion == 1`.
- Legacy decoded threads with no field are treated as version 0 and upgraded in
  memory before any feature-aware write.
- Version handling lives in Core schema helpers; GUI code never branches on raw
  JSON shape.
- Fixtures declare the expected version they exercise: legacy v0, current v1, or
  an explicit migration case.
- Adding optional fields such as `readCursor` must not make old `thread.json`
  files fail to decode.
- Future iOS/remote thread payloads include the version or enough source fields
  for the Mac to remain the read-state truth owner.

No one should infer schema version from the presence or absence of a specific UI
field.

## Storage Layout

Unchanged from MLP:

```text
~/Library/Application Support/Allnighter/
  Threads/
    thread_<threadId>/
      thread.json       # authoritative WorkThread + turns + read cursor
      transcript.md     # derived from thread.json; never authoritative
      context/
        <packetId>.json # exact worker context packets
```

`thread.json` remains the single transactional unit for thread metadata, turns,
and read cursor.

Context packets are separate files but have one ordering invariant: when a turn
references `contextPacketId`, the packet file must already exist on disk before
the turn is committed to `thread.json`. A missing packet is a broken audit trail,
not an acceptable eventual-consistency state.

## Timestamp Law

`updatedAt` means **last work/content activity**, not "anything changed on the
thread record."

| Operation class | Bumps `updatedAt`? | Regenerates `transcript.md`? |
| --- | --- | --- |
| `create` | yes (initial) | yes |
| `appendTurn` | yes | yes |
| `updateTurn` | yes | yes |
| `renameThread` | **no** | yes (title line only changes) |
| `setPinned` / `clearPinned` | **no** | **no** |
| `archiveThread` / `unarchiveThread` | **no** | **no** |
| `markRead` / `markReadToLatestVisible` | **no** | **no** |
| `savePacket` | **no** (packet is separate file) | **no** |
| Fixture/import `saveForImport` | caller supplies `updatedAt` | yes |

Rules:

- Append/update landed turns bump `updatedAt` using the injected `now` from the
  coordinator (deterministic in tests).
- Rename updates `thread.title` only. It does not mean new work landed.
- Pin/unpin edits `pinnedAt` only. Pin affects ordering, not recency.
- Archive/unarchive edits `status` only. Archive hides from active rail; it does
  not delete turns or cancel work.
- Mark-read edits `readCursor` only.
- If we later need metadata audit, add `metadataUpdatedAt`; do **not** overload
  `updatedAt`.

**Breaking fix:** current `archive(_:now:)` bumps `updatedAt`. Hardening removes
that bump. Archive must not reorder a thread in the recent bucket.

## Write Serialization

All thread read-modify-write operations for a given `rootDirectory` must be
**serialized**.

Requirement:

```text
At most one in-flight mutation per store root at a time.
```

Implementation choice for this slice:

```text
private per-root synchronous serial writer
```

Use a private serial dispatch queue or equivalent lock-backed writer, keyed by
canonical `rootDirectory`, so separate `ThreadStore` values pointed at the same
root share the same mutation lane. Keep the public API synchronous for this
slice; moving the store to an async actor is a separate architecture change.

Reads (`get`, `list`, derived index scans) may proceed concurrently **only** if
they tolerate eventually-consistent reads during a write, **or** share the same
serialization domain. Prefer: mutations serialized; reads use atomic file reads
so they never decode torn JSON.

**Proof target:** concurrent `appendTurn` + `markRead` cannot lose either write.

Multi-process posture for v1:

- The Mac app/background coordinator is the only writer process for a thread
  root.
- Future CLI/MCP/iOS writers send intents to that writer or use the same store
  mutation APIs inside the process that owns the root.
- If a resident coordinator and GUI become separate processes, add file-level
  advisory locking before allowing both to write `thread.json`.

## Atomic Persistence

Match `RunStore` discipline:

```text
thread.json writes use Data.write(to:options:.atomic) (temp + replace)
```

On every path that writes `thread.json`:

1. Encode full `WorkThread` in memory.
2. Atomic write to `thread.json`.
3. Regenerate derived artifacts only when the write class requires it (see
   Timestamp Law table).

Use one internal persist function with an explicit write class:

```text
persistContent      # append/update turns, create/import
persistMetadata     # rename/pin/archive/unarchive
persistCursor       # markRead and legacy baseline
```

`persistContent` writes `thread.json` first, then regenerates `transcript.md`.
`persistMetadata` rewrites `transcript.md` only for rename. `persistCursor` never
touches `transcript.md`. If transcript regeneration fails after a successful
content JSON write, `thread.json` remains committed truth; surface/report the
derived-artifact failure without rolling back the thread.

Readers must treat decode failure as "missing thread" (same as today), never as
partial truth.

## Public API Surface

Replace the broad `save(_:)` with explicit mutation methods. Suggested public
runtime API:

```text
ThreadStore.create(...)
ThreadStore.appendTurn(...)          # wraps today's append
ThreadStore.updateTurn(...)          # wraps today's update
ThreadStore.renameThread(threadId:title:)
ThreadStore.setPinned(threadId:pinned:now:)
ThreadStore.archiveThread(threadId:)
ThreadStore.unarchiveThread(threadId:)
ThreadStore.markRead(threadId:throughTurnId:now:)           # cursor; see 06
ThreadStore.markReadToLatestVisible(threadId:visibleTurnIds:now:)  # see 06
```

`ensureLegacyReadBaseline` is an internal/test-visible helper used inside
`appendTurn` and `updateTurn`; GUI/CLI/MCP callers must not call it as a separate
read-then-write step.

Keep reads and side paths:

```text
ThreadStore.get(_:)
ThreadStore.list()
ThreadStore.threadDirectory(forThreadId:)
ThreadStore.savePacket(_:)
ThreadStore.packet(threadId:packetId:)
ThreadStore.threadId(forRunId:)
ThreadStore.runToThreadIndex()
```

Fixture/import-only (not for app runtime):

```text
ThreadStore.saveForImport(_:)   # tests, migrations, hand-built fixtures
```

Deprecate/remove from public app surface:

```text
ThreadStore.save(_:)   # becomes internal or test-only
```

External callers (GUI, coordinators, CLI, MCP) must not construct a mutated
`WorkThread` and persist it generically.

## Per-Operation Semantics

### `create(id:title:now:workingDir:projectLabel:defaultWorkerId:)`

- Creates `WorkThread` with `status: .active`, `createdAt == updatedAt == now`.
- Sets current `formatVersion`.
- `pinnedAt == nil`.
- If 06 is not landed: no `readCursor` field exists yet.
- If 06 is landed: initialize an explicit empty-timeline read cursor at `now`
  (see 06). Legacy nil cursor remains a migration state, not the normal new
  thread state.
- Writes `thread.json` atomically + `transcript.md`.
- Rejects duplicate ids with a typed `ThreadStoreError.threadAlreadyExists(id)`.
  Do not silently overwrite an existing thread folder.

### `appendTurn(_:toThreadId:now:)`

- Loads thread under write lock.
- If 06 is landed: call `ensureLegacyReadBaseline` before first unread-aware
  append on legacy threads **inside the same serialized read-modify-write**.
- Normalizes `turn.threadId` to target.
- Rejects duplicate turn ids within the thread.
- If the turn references `contextPacketId`, validate that the packet exists
  before committing the turn.
- Appends to `turns`, sets `updatedAt = now`.
- Validates turn lifecycle on append only where applicable (queued/running entry).
- Atomic save + transcript regen.

### `updateTurn(_:inThreadId:now:)`

- Loads thread under write lock.
- If 06 is landed: baseline legacy cursor when a turn transitions into
  unread-eligible landed state **inside the same serialized read-modify-write**.
- Replaces turn by id; enforces `allowedTransitions()` unless status unchanged.
- Preserves turn id uniqueness.
- If the updated turn references `contextPacketId`, validate that the packet
  exists before committing the update.
- Sets `updatedAt = now`.
- Atomic save + transcript regen.

### `renameThread(threadId:title:)`

- Trims whitespace and rejects empty/whitespace-only titles with a typed error.
- Sets `thread.title` only.
- Preserves `updatedAt`.
- Atomic save + transcript regen (title heading changes).
- Does not change pin, archive, cursor, or turns.

### `setPinned(threadId:pinned:now:)`

- `pinned == true` → `pinnedAt = now`.
- Setting pinned when already pinned is an idempotent no-op that preserves the
  original `pinnedAt`.
- `pinned == false` → `pinnedAt = nil`.
- Preserves `updatedAt`.
- Atomic save; **no** transcript regen.
- Reject pin on archived threads in v1. Pin is active-rail state.

### `archiveThread(threadId:)`

- Sets `status = .archived`.
- **Clears `pinnedAt`** explicitly. Pin is active-rail state; no hidden pinned
  archive rows.
- Preserves `updatedAt`.
- Does **not** clear read cursor, cancel running work, delete turns, or mutate
  run truth.
- Atomic save; no transcript regen.

### `unarchiveThread(threadId:)`

- Sets `status = .active`.
- Does not restore prior `pinnedAt` (user must re-pin).
- Preserves `updatedAt`.
- Atomic save; no transcript regen.
- No auto-unarchive side effects elsewhere.

### `markRead` / `markReadToLatestVisible` / `ensureLegacyReadBaseline`

Owned by [`06_Unread_Message_Light.md`](06_Unread_Message_Light.md) for cursor
math and eligibility. This doc owns the **write gate** they must use:

- Cursor-only save path: preserve `updatedAt`, atomic `thread.json`, leave
  `transcript.md` byte-identical.
- Serialized with all other mutations.
- Legacy baseline seeding must be part of the append/update transaction that
  creates the new unread-aware state. It must not be a separate caller-side
  read/write that can interleave with another mutation.

### `savePacket(_:)`

- Writes packet JSON atomically.
- Does not bump `updatedAt`.
- Does not regenerate `transcript.md`.
- Must happen before any turn that references the packet is appended/updated.
- Missing packet references fail the content mutation rather than creating a
  broken transcript/audit chain.

## Transcript Regeneration Law

`ThreadMarkdown.transcript(_:)` regenerates from full thread truth.

| Write class | Regenerate transcript? | Expected diff |
| --- | --- | --- |
| Content (append/update) | yes | new/changed turn sections |
| Rename | yes | `# title` line only |
| Pin/archive/unarchive | no | none |
| Mark read | no | none |

**Proof:** cursor-only write leaves `transcript.md` byte-identical.

## Caller Contract

| Caller | Allowed mutations |
| --- | --- |
| `WorkerChatCoordinator` | `appendTurn`, `updateTurn`, `savePacket` |
| `ThreadsViewModel` / GUI intents | `create`, metadata methods, `markRead*`; temporarily `appendTurn`/`updateTurn` for CR4 team/design/dispatch paths until moved engine-side |
| Future `ThreadTurnCoordinator` / run-attachment coordinator | all non-chat content turn append/update paths |
| Tests / fixtures | `saveForImport` + explicit methods |
| CLI / MCP (future) | same explicit methods; no raw save |
| SwiftUI views | **none** (intents → view model → store) |

Ban: `var t = store.get(...)!; t.title = "x"; try store.save(t)` in app code.

## Relationship To Sister Docs

```text
05 ThreadStore Hardening   <- you are here (engine gate)
06 Unread Message Light    <- requires 05; adds readCursor + derivation + light
07 Threads 2.0             <- requires 05 + 06; rail rename/pin/archive UI
```

Do not implement 06 or 07 until 05 proof wall is green.

## Inference Bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Generic save | `ThreadStore` | "I'll just save the struct" | No public raw save in app runtime | App target cannot call `saveForImport` |
| Concurrent writes | write serializer | last writer wins | Serialize per root | concurrent append + markRead retain both fields |
| Duplicate create | `ThreadStore.create` | create overwrites existing folder | Reject duplicate thread ids | duplicate id throws typed error |
| Duplicate turn id | `appendTurn`/`updateTurn` | cursor targets ambiguous | Reject duplicate turn ids | append duplicate turn id fails |
| Archive recency | `updatedAt` law | archive bumps recent sort | archive preserves `updatedAt` | archive does not move thread in recent bucket |
| Rename recency | `updatedAt` law | rename means new activity | rename preserves `updatedAt` | rename alone does not change list recency order |
| Pin transcript | transcript law | pin rewrites export | pin does not regen transcript | pin write leaves transcript bytes identical |
| Archive pin | `pinnedAt` + `status` | archived thread stays pinned hidden | archive clears `pinnedAt` | archived row has `pinnedAt == nil` |
| Torn read | atomic write | partial JSON is truth | atomic `thread.json` writes | concurrent reader never decodes torn file |
| GUI truth | `WorkThread` | view model caches title | GUI reads store snapshot after mutation | rename in GUI matches `get` after relaunch |
| Read cursor | 06 doc | mark read bumps `updatedAt` | cursor-only path | markRead preserves `updatedAt` and transcript |
| Packet reference | content mutation | context can appear later | packet exists before turn references it | append with missing packet fails |

## Ordered Slices

- [x] TSH-S00 - Add `WorkThread.formatVersion`, legacy decode fixtures, typed
  duplicate-id and duplicate-turn-id errors.
- [x] TSH-S01 - Add per-root synchronous serial writer around all mutation entry
  points. Prove concurrent `appendTurn` + `markRead` do not lose either field
  (stub `markRead` if 06 not landed yet).
- [x] TSH-S02 - Atomic `thread.json` writes (`.atomic`), matching RunStore
  comments. Add concurrency read test mirroring `RunStoreConcurrencyTests`.
- [x] TSH-S03 - Split save paths: `persistContent(_:)` vs `persistMetadata(_:)`
  vs `persistCursor(_:)` with timestamp + transcript law enforced internally.
- [x] TSH-S04 - Replace public `save(_:)` with explicit APIs:
  `renameThread`, `setPinned`, `archiveThread` (fix `updatedAt`), `unarchiveThread`.
  Add `saveForImport` for tests only.
- [x] TSH-S05 - Rename `append`/`update` to `appendTurn`/`updateTurn` (keep
  deprecated aliases one slice if needed) and route all production callers,
  including CR4 team/design/dispatch append/update paths.
- [ ] TSH-S06 - Document + enforce caller allowlist; grep gate in
  `scripts/check.sh` or audit test that app sources do not call `saveForImport`.
- [ ] TSH-S07 - Unit proof wall: timestamp law table, transcript byte identity,
  archive-clears-pin, packet-reference invariant, duplicate-id/turn-id rejection,
  atomic read under concurrent writes.

## Works Test

Unit:

```text
swift test --package-path Packages/AllnighterCore --filter ThreadStoreTests
swift test --package-path Packages/AllnighterCore --filter ThreadStoreConcurrencyTests
```

Scenarios:

```text
1. appendTurn bumps updatedAt; renameThread does not.
2. archiveThread does not bump updatedAt and clears pinnedAt.
3. setPinned does not change transcript.md bytes.
4. persistCursor (markRead stub) does not change updatedAt or transcript.md.
5. Concurrent append + cursor write: final thread contains both new turn and
   advanced cursor.
6. Reader during write: get() never returns torn partial decode (or returns nil,
   never corrupt model).
7. saveForImport works in tests; app target grep shows no raw save usage.
8. create with an existing id throws and preserves the original thread.
9. append/update with a missing `contextPacketId` fails before writing
   `thread.json`.
```

Green wall:

```text
bash scripts/check.sh
```

## Done When

- `thread.json` is the sole authoritative thread truth; `transcript.md` stays
  derived.
- All runtime mutations flow through explicit `ThreadStore` methods.
- Writes are serialized per store root.
- `thread.json` writes are atomic.
- `updatedAt` law matches the table; archive/rename/pin/read do not bump it.
- Cursor/metadata writes leave `transcript.md` byte-identical.
- Archive clears `pinnedAt`.
- Duplicate thread ids and duplicate turn ids are rejected.
- A turn cannot reference a missing context packet.
- `WorkThread.formatVersion` exists and legacy fixtures decode.
- Public raw `save(_:)` is removed or test/fixture-only.
- Concurrency + timestamp negative tests are green.
- 06 and 07 docs can cite this gate as complete.

## Deferred Enhancements

- A formal `ThreadStoreEvent` publisher is useful later, but 05 only requires
  returned `WorkThread` snapshots plus explicit view-model reload/refresh after
  mutations.
- Background transcript generation may be useful if transcript writes become
  slow. It is not part of the truth gate; first enforce the write classes and
  byte-identity proofs.
- A full multi-process file-locking design is deferred until GUI/resident/CLI can
  actually write the same root from separate processes.

## Resolved Choices

- Serialization: per-root synchronous serial writer, not an async actor migration
  in this slice.
- Empty rename: reject whitespace-only titles at the store; GUI should validate
  before calling.
- Pin archived thread: reject; pin is active-rail state.
