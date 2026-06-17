# 07 - Threads 2.0

Status: Draft founder packet — rail controls after ThreadStore hardening + unread
Owner: AllnighterMac GUI + AllnighterEngine (store mutations)
Updated: 2026-06-17

## Requires

```text
05_ThreadStore_Hardening.md  — serialized writes, explicit mutation APIs, timestamp law
06_Unread_Message_Light.md     — read cursor, hasUnread derivation, unread light
```

Do not implement Threads 2.0 rail controls until both prerequisites are complete.
GUI must call `ThreadStore` methods from doc 05; unread rendering follows doc 06.

## Founder Intent

```text
The thread rail becomes a real floor-manager inbox: rename, pin, archive, unread
lights, and one triage order on every rail surface — without letting the GUI
become thread truth.
```

Product value:

```text
The user can triage parallel agent work like a messaging app: pin what matters,
archive what is done, see what landed unseen, and keep one consistent rail
whether they are on Home or the legacy Threads sidebar.
```

Trusted workflow slice:

```text
worker reply lands unseen -> unread light on row ->
user pins thread -> pin holds row in triage bucket ->
user archives finished thread -> row leaves active rail, unread preserved in archive view ->
user renames from header or context menu -> title persists in thread.json
```

## Non-Goals (v1)

- Delete thread (out of scope; no soft-delete, no turn purge).
- Bulk mark-read / mark-all-read (owned by 06 — not in v1).
- Auto-unarchive on read, notification, or new work (explicit user unarchive only).
- Search/filter beyond existing local title/preview filter scope (defer unless
  PWT-S08 already landed).
- Cloud sync of pin/archive/read state.
- Multi-select bulk pin/archive.
- iOS rail controls (Mac first; protocol fields may be stubbed).
- New stored booleans (`isUnread`, `isPinned` beyond `pinnedAt`, etc.).

## Current State

Built (MLP S01–S06):

- `WorkThread` has `title`, `status`, `pinnedAt`, `updatedAt`, turns.
- `ThreadStore.archive` exists but bumps `updatedAt` (fixed in 05).
- No `renameThread`, `setPinned`, `unarchiveThread` store methods yet.
- `ThreadsPresenter.triaged` orders: attention → running → recent (no unread yet).
- `ThreadsPresenter.railThreads` (Home/CR4): `updatedAt` newest-first only.
- Legacy `ThreadsView` sidebar + CR4 `HomeView` conversation rail can drift.
- `ThreadsPresenter.railGroups` currently creates broad Pinned/Recent groups,
  which conflicts with unread/attention/running triage buckets.
- Row context menus, archive view, pin/unpin, rename UI are missing or partial.

Gaps this doc closes:

- Explicit rename/pin/archive/unarchive product semantics.
- Home rail and legacy Threads rail share one triage function.
- Archive as a first-class view (not just filtered-out rows).
- Row context menu + keyboard/menu commands.
- Unread light integration on both rails (rendering owned by 06; ordering here).

## SSOT

| Concern | Truth owner | GUI role |
| --- | --- | --- |
| Title | `WorkThread.title` via `renameThread` | edit field → intent |
| Pin | `WorkThread.pinnedAt` via `setPinned` | toggle → intent |
| Archive | `WorkThread.status` via `archiveThread`/`unarchiveThread` | toggle → intent |
| Unread | derived in Core from `readCursor` + turns (06) | render light only |
| Row order | `ThreadsPresenter.triaged` (+ archive partition) | render sorted list |
| Selection | GUI-local `selectedThreadId` | not durable truth |

Duplicate truth to delete:

- GUI-local title aliases not written to store.
- Computed pin state not backed by `pinnedAt`.
- Separate Home vs Threads sort caches.
- Archive as a filtered flag in view model without `status == .archived`.

## Product Rules (Locked)

### Rename

- Edits `WorkThread.title` only through `ThreadStore.renameThread`.
- No GUI-local aliases. What the header shows == `thread.json` title after save.
- Does **not** bump `updatedAt` (05 timestamp law).
- Regenerates transcript title heading only.
- Validation: reject empty/whitespace-only titles at store or GUI (both is fine).
- Auto-title from first user message still applies on create; rename overrides.

### Pin / Unpin

- Pin sets `pinnedAt` (use action timestamp from store `now` injection).
- Unpin clears `pinnedAt`.
- Pin affects **ordering only**, not unread, attention, or running semantics.
- Does **not** bump `updatedAt`.
- Does **not** regenerate transcript.
- **Cannot pin archived threads** (reject at store; hide/disable in GUI).
- Pin is idempotent: pin already-pinned thread is no-op.

### Archive / Unarchive

- Archive sets `status = .archived`.
- Archive **clears `pinnedAt`** (pin is active-rail state; no hidden pinned archive).
- Archive hides thread from **active rail only** — not delete, not cancel work, not
  clear unread, not mutate run truth.
- Archive does **not** bump `updatedAt`.
- Unarchive sets `status = .active`; does **not** restore old pin.
- **No auto-unarchive** in v1 (not on read, not on new turn, not on notification).
- Archived unread **remains unread**; archive view shows the same unread light (06).
- Running work on an archived thread: archive does not cancel in-flight turns.
  (Show running in archive view if status is still running — edge case allowed.)
- Composer is disabled for archived threads. The thread can be read, renamed, or
  unarchived, but replying/dispatching requires an explicit unarchive first.

### Unread integration

- Unread derivation, light rendering, mark-read: fully owned by
  [`06_Unread_Message_Light.md`](06_Unread_Message_Light.md).
- This doc owns **triage placement** of unread rows relative to pin/attention/running.
- Unread is an orthogonal axis to `rowState` (attention/running/idle).
- Attention precedence uses `thread.needsAttention`, not
  `thread.unreadNeedsAttention`. A failed turn that has already been read remains
  in the attention bucket without an unread light.

### Delete

- Out of scope. No UI affordance, no store method, no accidental "remove from list"
  that deletes turns.

## Rail Triage Order

Single function used by **both** `HomeView` conversation rail and legacy
`ThreadsView` sidebar:

```text
1. pinned + needs attention
2. needs attention
3. pinned + unread
4. unread
5. pinned + running
6. running
7. pinned recent
8. recent (by updatedAt desc)
9. archived — hidden behind Archive entry/view
```

Within each bucket: `updatedAt` descending.

Bucket precedence when multiple apply:

```text
needsAttention > unread > running > recent idle
```

Examples:

- Thread is unread + running → unread bucket (not running), once at least one
  unread-eligible landed turn exists (06).
- Thread is attention + unread → attention bucket.
- Pinned only affects sub-bucket (pinned variant sorts before unpinned in same tier).

`ThreadsPresenter` changes:

- Replace the current integer bucket with a named triage key that is easy to
  unit-test:

```text
ThreadTriageKey
- archivePartition: active | archived
- bucket:
  pinnedAttention
  attention
  pinnedUnread
  unread
  pinnedRunning
  running
  pinnedRecent
  recent
- updatedAt desc
```

- Extend bucket calculation to accept derived `hasUnread` (from Core, post-06).
- Deprecate `railThreads` newest-first for production rails; keep only for
  explicit debug/fixtures unless CR4 requires a temporary flag.
- Delete or quarantine `railGroups` broad Pinned/Recent production grouping once
  unread ships. If section headers remain, they must mirror triage families
  (Attention / Unread / Running / Recent), not collapse the whole rail into
  Pinned / Recent.
- Add `triagedActive(_:)` (excludes archived) and `triagedArchived(_:)` for
  archive view.
- Store/list order is never authoritative UI order. Store may return newest
  first for convenience; presenters own rail order.

## Surfaces

### Active rail (Home + legacy Threads)

Shared requirements:

- Same `triagedActive` ordering.
- Same row component contract: title, preview, worker chip, relative time, status
  pill, trailing unread light (06), pin marker.
- Same context menu actions (where applicable).
- `ThreadsPresenter.rowState` unchanged; unread is separate trailing light.

Home-specific:

- CR4 conversation rail adopts triage order (CR4e polish aligns here).
- `ConversationStatus` pills remain outcome facts; they do not suppress unread.

Legacy Threads:

- Sidebar uses identical ordering and light slot as Home.
- Toggle between team-run workspace and Threads remains until PWT-S08 retires it.

### Archive view

- Entry: "Archive" at bottom of active rail or navigation affordance (design TBD
  in GUI brief).
- Lists `status == .archived` threads only.
- Sort: `updatedAt` desc within archive. This means "last work activity," not
  "when archived." Do not add `archivedAt` in v1 unless product explicitly wants
  archive-time ordering.
- Rows show unread light per 06.
- Rows show running/live treatment if the archived thread still has running work.
- Actions: unarchive, open thread, rename (optional in archive — allowed).
- No pin in archive view (pin disabled; unarchive then pin).
- No bulk operations v1.

### Thread header

- Inline editable title → `renameThread` on commit (Return/blur).
- Pin toggle → `setPinned`.
- Archive action → `archiveThread` (confirm if thread is running? **default: allow
  without modal** — archive is hide, not kill; user can still open from archive).
- Archived header shows an Unarchive action and disables composer/send actions.

### Archived composer state

Archived threads remain readable timelines, not writable workspaces.

```text
Archived thread selected -> composer disabled ->
inline action: "Unarchive to reply" -> unarchiveThread -> composer enabled
```

Do not auto-unarchive because the user typed into the composer, clicked a
notification, or new work landed. Archive state is explicit.

### Row context menu

Minimum commands:

```text
Open
Pin / Unpin          (hidden when archived)
Rename…              (opens inline or sheet)
Archive              (active rail only)
Unarchive            (archive view only)
```

Not in v1:

```text
Delete
Mark read
Mark all read
```

### Keyboard / menu commands

Mac app menu or command palette (minimum):

```text
Pin Thread      ⌘⇧P   (toggle)
Archive Thread  ⌘⇧E   (archive when active; unarchive when in archive view)
Rename Thread   F2    (focus header title field)
```

Commands target `selectedThreadId`; disabled when no selection or when action
illegal (pin archived).

## Store ↔ GUI Intent Map

| User action | ViewModel intent | Store method |
| --- | --- | --- |
| Create thread | `createThread` | `create(...)` |
| Rename | `renameThread(id, title)` | `renameThread` |
| Pin | `setPinned(id, true)` | `setPinned` |
| Unpin | `setPinned(id, false)` | `setPinned` |
| Archive | `archiveThread(id)` | `archiveThread` |
| Unarchive | `unarchiveThread(id)` | `unarchiveThread` |
| Mark read | visibility-driven | `markRead*` (06) |

After every mutation: reload thread from store (or use returned `WorkThread`) and
refresh presenter list. Do not mutate local thread arrays without store ack.

## Visual Contract (Rail Controls)

Design-system binding per `docs/design-system/production.md` and
`docs/gui/surfaces/threads/brief.md`.

Pin marker:

- Subtle pin glyph or leading indicator; must not be confused with unread light.
- Pinned rows do not change typography weight unless design tokens say so.

Archive:

- No destructive red styling; archive is "put away", not delete.

Rename:

- Header field uses standard editable title style; no separate "display name."

Unread light:

- Fully specified in 06; this doc only requires reserved trailing slot on all
  rail row variants.

## iOS / Protocol (Forward Stub)

When remote thread list ships, expose:

```text
title, status, pinnedAt, updatedAt, readCursor?, hasUnread? (derived)
Intents: thread.rename, thread.pin, thread.archive, thread.unarchive
```

Mac remains mutation truth owner in v1.

## Inference Bans

| Junction | Owner | Bad inference | Ban |
| --- | --- | --- | --- |
| Archive | `status` | archive deletes turns | Archive hides only |
| Archive unread | 06 cursor | archive clears unread | Unread persists in archive view |
| Archive pin | `pinnedAt` | pinned archive rows | Archive clears `pinnedAt` |
| Auto-unarchive | `status` | new message unarchives | No auto-unarchive v1 |
| Home sort | `triaged` | newest-first is enough | Use full triage buckets |
| Rail groups | `ThreadsPresenter` | Pinned/Recent grouping preserves triage | Production groups mirror triage families or no groups |
| Rename | `title` | GUI-local alias | Store title is sole name |
| Pin recency | `updatedAt` | pin bumps recent | Pin does not bump `updatedAt` |
| Read on archive | 06 | opening archive marks read | Same visibility rules as active |
| Archived composer | `status` | reply auto-unarchives | Disable composer until explicit unarchive |
| Delete | — | archive is delete | No delete in v1 |

## Ordered Slices

- [ ] TH2-S01 - Store methods from 05: `renameThread`, `setPinned`, `unarchiveThread`;
  fix `archiveThread` timestamp/pin law. (May land entirely in TSH-S04.)
- [ ] TH2-S02 - `ThreadsPresenter.triagedActive` with unread buckets (post-06);
  remove production use of `railThreads` newest-first and `railGroups`
  Pinned/Recent grouping.
- [ ] TH2-S03 - Wire Home conversation rail to `triagedActive`.
- [ ] TH2-S04 - Wire legacy `ThreadsView` sidebar to same triage.
- [ ] TH2-S05 - Archive view + navigation entry; `triagedArchived`.
- [ ] TH2-S06 - Row context menu actions → view model → store.
- [ ] TH2-S07 - Thread header rename + pin + archive affordances.
- [ ] TH2-S08 - Keyboard/menu commands.
- [ ] TH2-S09 - Presenter tests: full pin × attention × unread × running matrix,
  archive exclusion, archived unread row, archived running row, and no
  Pinned/Recent grouping in production unread rails.
- [ ] TH2-S10 - GUI visual proof fixture: pinned, unread, archive, rename states.

## Works Test

```text
Create three threads. Pin thread A. Land an unseen worker reply on thread B
(unread light on). Archive thread C.

Active rail order: B (unread) above merely recent; A (pinned recent) in pinned
bucket; C absent.

Open archive view: C visible. Land unseen work on C in background (simulated
append): C shows unread light in archive.

Unarchive C: appears in active unread bucket; pin not restored.

Select archived C before unarchiving: timeline is readable, composer is disabled,
and Unarchive is the only way to reply.

Rename B from header: title persists after relaunch; updatedAt unchanged if only
rename.

Archive pinned A: pin cleared; A in archive unpinned.

Home rail and legacy Threads sidebar show identical order and lights for the same
fixture set.
```

Proof:

```text
swift test --package-path Packages/AllnighterCore --filter ThreadStoreTests
xcodebuild test -scheme AllnighterMac -destination 'platform=macOS' \
  -only-testing:AllnighterMacTests/ThreadsPresenterTests
bash scripts/check.sh
```

## Done When

- Rename, pin, archive, unarchive mutate only via explicit `ThreadStore` APIs.
- Archive clears pin; archive does not bump `updatedAt` or clear unread.
- Home and legacy rails share one triage ordering including unread buckets.
- Production rails no longer use newest-first or broad Pinned/Recent grouping
  once unread ships.
- Archive view lists archived threads with unread lights intact.
- Archived thread composer/send actions are disabled until explicit unarchive.
- Context menu + header + keyboard commands call view model intents, not store
  directly from views.
- No delete, no bulk mark-read, no auto-unarchive in v1.
- Presenter + GUI proof cover pin/unread/archive/rename matrix.

## Open Questions

- Archive confirmation when thread `isRunning`? Default: no modal.
- F2 rename when focus in composer? Default: F2 targets header title only.
- Persist `lastSelectedThreadId` in UserDefaults? Useful app polish, but view
  state only and not part of thread truth for this slice.
