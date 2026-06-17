# 05 - Unread Message Light

Status: Draft founder packet - ready for implementation
Owner: AllnighterCore + AllnighterEngine + Mac app backend
Updated: 2026-06-17

## Founder Intent

Raw request:

```text
IMPORTANT: Do we track read vs. unread messages?

We MUST add a note to new / unread messages. Not a note. An indication light.
Check our database.
```

Product value:

```text
The floor manager should instantly know which threads changed while their
attention was elsewhere.
```

Trusted workflow slice:

```text
worker/team/dispatch turn lands -> thread row shows a small unread light ->
open the thread -> first unread turn is visible -> light clears durably
```

Non-goals:

- No visible note, label, unread count, or marketing copy in the row.
- No `Mark all read` command in v1. Bulk dismissal is a future inbox-zero
  product decision, not a read-truth shortcut.
- No notification delivery. That remains `02_Notifications.md`.
- No fake read state inferred from app launch, scroll position guesses, or
  thread `updatedAt`.
- No per-worker or public read receipts.
- No cloud sync, analytics, or multi-user read state.
- No unread prompt/context behavior. Read state is a UI attention contract, not
  a worker context input.
- No auto-unarchive rule in this slice. Archived unread is preserved and shown
  when the archive is viewed; changing archive status needs a separate archive
  semantics decision.

## Current State

The current thread database does not track read/unread.

Persisted today:

```text
~/Library/Application Support/Allnighter/Threads/thread_<id>/thread.json

WorkThread
- id
- title
- status
- createdAt
- updatedAt
- pinnedAt?
- workingDir?
- projectLabel?
- defaultWorkerId?
- turns: [ThreadTurn]

ThreadTurn
- id
- threadId
- kind
- status
- createdAt
- completedAt?
- author
- text?
- workerId?
- runId?
- stageId?
- artifactRefs
- contextPacketId?
- supersedesTurnId?
- seedFromTurnId?
- systemEvent?
```

Derived today:

```text
WorkThread.isRunning       = any queued/running turn
WorkThread.needsAttention  = failed/timedOut/open blocking system turn
WorkThread.lastWorkerId    = latest worker-authored turn
WorkThread.preview         = latest text turn
```

Gaps:

- No `readAt`, `seenAt`, `lastReadTurnId`, or equivalent cursor.
- Thread list status dots currently mean running/result/attention, not unread.
- Selecting a thread is GUI-local and not durable across restart.
- Existing persisted threads cannot truthfully tell whether old worker replies
  were read before this feature existed.

## User-Visible Claim

```text
When new work lands in a thread while you are elsewhere, Allnighter lights that
thread until you read the landed turn.
```

The light is the product signal. The row should not say "unread", show a note,
or expose a count in the normal Mac rail.

## SSOT

Truth owner:

```text
AllnighterCore.WorkThread + ThreadReadCursor + unread derivation helpers
AllnighterEngine.ThreadStore serialized thread mutation operations
~/Library/Application Support/Allnighter/Threads/thread_<id>/thread.json
```

Allnighter has no Rust truth layer and no SQL database today. The durable thread
truth is Swift `Codable` data stored as local JSON:

```text
AllnighterCore      -> schema and pure derived semantics
AllnighterEngine    -> ThreadStore/RunStore persistence and mutation gates
Application Support -> folder-of-JSON storage on disk
SwiftUI             -> renders state and sends intents only
```

Thread storage:

```text
~/Library/Application Support/Allnighter/
  Threads/
    thread_<threadId>/
      thread.json       # authoritative WorkThread + turns + read cursor
      transcript.md     # derived from thread.json; never authoritative
      context/
        <packetId>.json # exact worker context packets
  Runs/
    run_<runId>/
      run.json          # run truth for team/design/review/dispatch
      *.md              # derived run exports/transcripts
```

For v1, keep `ThreadReadCursor` inside `thread.json`. Do not introduce
`cursor.json`, `read_cursors.json`, SwiftUI state, notification receipts, or a
side database as parallel read truth. If cursor writes become a measured
performance problem later, a storage split must preserve a single transactional
thread truth owner first.

Lie-prone layers:

- SwiftUI selection state.
- Scroll position and auto-scroll heuristics.
- `updatedAt` used as a freshness proxy.
- Notification delivery state.
- Ad hoc row dots that encode multiple meanings.
- Any sidecar cursor file unless it is transactionally bound to thread truth.

New semantic rule:

```text
Unread is derived from turn truth and a durable read cursor. It is never a
stored boolean on a row.
```

Duplicate truth to delete:

- Any future GUI-only `isUnread`, `hasNewMessage`, or row dot state.
- Any status pill color that silently means unread.
- Any notification-delivery receipt used as read truth.
- Any direct file write path that bypasses `ThreadStore` cursor rules.

## Core Model

Add a durable cursor to `WorkThread`:

```text
ThreadReadCursor
- lastReadTurnId: String?
- lastReadTurnCreatedAt: Date?
- readAt: Date
```

Suggested shape:

```swift
public struct ThreadReadCursor: Codable, Sendable, Equatable {
    public var lastReadTurnId: String?
    public var lastReadTurnCreatedAt: Date?
    public var readAt: Date
}

public struct WorkThread {
    ...
    public var readCursor: ThreadReadCursor?
}
```

Rules:

- `lastReadTurnId` is the primary cursor.
- `lastReadTurnCreatedAt` is a fallback for migrations, corrupted fixture data,
  or a future compaction that removes a turn id from the visible timeline.
- `readAt` records when the cursor advanced. It is used only for debugging,
  future iOS reconciliation, and out-of-order completion detection. It is not
  used to sort threads.
- Updating the cursor must not change `thread.updatedAt`.
- Updating the cursor must not regenerate or change user-facing transcript
  content.
- Missing cursor in legacy data means "no known unread yet", not "everything is
  unread."
- New threads should start with an empty cursor at `createdAt`, then advance
  through the first visible user turn after send if there are no earlier unread
  anchors.
- `turns` array order is canonical timeline/send order. Do not sort turns by
  timestamp for unread derivation; timestamps are fallbacks and landing-time
  checks only.

## Unread Eligibility

A turn can create unread only if it is user-visible work the user did not
author.

Unread-eligible:

```text
worker_chat       done | failed | timed_out
team_run          done | failed | timed_out
design_board      done | failed | timed_out
review_board      done | failed | timed_out
dispatch          done | failed | timed_out
return_review     done | failed | timed_out
system_event      running, when systemEvent is sign_in_required or manual_paste
system_event      failed | timed_out
```

Never unread by itself:

```text
user_message
user_decision
work_order, any status
queued/running worker/team/dispatch work before it lands
system_event migration_imported
system_event waiting
cancelled turns caused by explicit user cancellation
```

Clarifications:

- Running remains running. It is not unread until it lands, fails, times out, or
  becomes a blocking system action.
- A failed/timed-out worker turn is both unread and attention-worthy if the user
  has not seen it.
- A manual-paste or sign-in system turn is unread while open because it asks the
  user to act.
- User-authored turns never create unread. They may advance the read cursor only
  when no earlier unread anchor exists or when visibility has already cleared
  every earlier unread anchor.
- Terminal unread-eligible turns should set `completedAt`. If `completedAt` is
  absent, derivation falls back to `createdAt`.

## Derived Freshness

Add derived helpers in `AllnighterCore` beside existing `WorkThread.isRunning`
and `WorkThread.needsAttention`. Presenters may format and sort; they must not
own freshness semantics.

```text
WorkThread.unreadTurnIds
WorkThread.firstUnreadTurnId
WorkThread.latestUnreadTurnId
WorkThread.hasUnread
WorkThread.unreadNeedsAttention
```

Derivation:

```text
1. Keep `turns` in stored array order. This is the timeline order.
2. Find the index of readCursor.lastReadTurnId in turns.
3. If found, a turn is after the cursor when its index is greater than the
   cursor index.
4. If not found but lastReadTurnCreatedAt exists, a turn is after the fallback
   cursor when its createdAt is greater than that timestamp.
5. A turn is landed-after-read when `(completedAt ?? createdAt) > readAt`.
6. An unread candidate is unread-eligible AND (after cursor OR
   landed-after-read).
7. If no cursor exists, legacy baseline is "read through current known turns"
   until a new append/update happens under the feature-aware store.
```

`unreadNeedsAttention`:

```text
unreadNeedsAttention =
  unreadTurnIds contains at least one turn where turn.requiresUserAttention
```

This lets the row render attention and unread as separate axes without inventing
a new stored state.

The UI may compute a count for accessibility, tests, or a future menu-bar badge,
but the Mac rail renders a light only.

## Store Semantics

`ThreadStore` is the mutation owner. Every thread read-modify-write must flow
through store methods that enforce cursor rules.

Add explicit store operations:

```text
ThreadStore.markRead(threadId:throughTurnId:now:)
ThreadStore.markReadToLatestVisible(threadId:visibleTurnIds:now:)
ThreadStore.ensureLegacyReadBaseline(threadId:beforeAppendingOrUpdating:)
```

Write-gate rules:

- Serialize all thread file writes per store root (actor, file lock, or a
  single internal queue). Last writer wins is not acceptable for cursor state.
- External callers should not call a general `save(_:)` with ad hoc mutated
  threads. Make raw save internal/private, or document it as a fixture/import
  path that still validates cursor invariants.
- Cursor-only writes must use a dedicated non-bumping save path: preserve
  `updatedAt`, write `thread.json` atomically, and leave `transcript.md`
  byte-identical.
- Append/update writes remain the only ordinary paths that bump `updatedAt`.
- Store never reads SwiftUI selection, scroll, focus, or window state.

`markRead` rules:

- Validate that the thread exists.
- Validate that `throughTurnId` exists in the thread.
- Move the cursor forward only. Calling with the current cursor or an older turn
  is an idempotent no-op, not an error.
- If `throughTurnId` is unread-eligible, advance through it only when all earlier
  unread anchors are already cleared or included by the visible-prefix helper.
- If `throughTurnId` is not unread-eligible, advance through it only when there
  are no unread anchors at or before that turn. This supports a new visible user
  send without clearing earlier unseen work.
- Allow archived threads. Archive status does not change read truth.
- Preserve `thread.updatedAt`.
- Save atomically with the thread JSON.
- Return the updated `WorkThread`.

`markReadToLatestVisible` algorithm:

```text
input: visibleTurnIds in timeline order
1. Re-derive unreadTurnIds from current thread truth.
2. Starting at firstUnreadTurnId, walk unreadTurnIds in order.
3. Advance only through the contiguous prefix whose turn ids are visible.
4. Call markRead through the last visible unread id in that prefix.
5. If the first unread id is not visible, no-op.
```

This prevents seeing a later unread turn from clearing earlier unseen unread
turns. Debounce viewport reports; do not write on every scroll tick.

Append/update rules:

- Before appending or settling a turn on a legacy thread with no cursor, seed the
  cursor through the latest already-known read baseline. This avoids an
  upgrade-time unread storm while still making newly landed work unread.
- For append, the baseline is the latest existing turn before the append.
- For update, if the updated turn is transitioning from non-unread-eligible to
  unread-eligible, the baseline is the latest turn before that updated turn, not
  the updated turn itself.
- Appending a user-authored turn does not itself clear unread. After append, the
  coordinator/view model may request `markRead` through that user turn only if
  the timeline is mounted, the window is active/key, and there is no earlier
  unread anchor still unseen.
- Appending an optimistic running worker turn does not create unread.
- Updating that worker turn from `running` to `done`, `failed`, or `timed_out`
  may create unread if the user has not seen the turn.
- Manual-paste/sign-in system turns become unread when created open.

Layer split:

```text
Store        -> cursor math, baseline seeding, serialized persistence
Coordinator  -> tells store when a user/worker/system turn was appended/settled
ViewModel    -> tells store when timeline visibility proves a read event
SwiftUI view -> reports visible turn ids and focus/window facts only
```

Sorting rule:

```text
Read cursor updates do not bump updatedAt and do not by themselves move a thread
to the top of recent history.
```

## Thread List Triage

Unread landed work is more actionable than merely running work.

Revised default row order:

```text
1. pinned threads needing attention
2. unpinned threads needing attention
3. pinned unread threads
4. unpinned unread threads
5. pinned running threads
6. unpinned running threads
7. pinned recent threads
8. recent threads by updatedAt
9. archived threads, hidden behind Archive
```

Reason:

```text
Running means the factory is busy.
Unread means the factory handed something back.
Attention means the factory needs the floor manager now.
```

If a thread is both unread and running, unread wins for triage once at least one
eligible unread turn exists. The running state can still render inside the row.

Within each bucket, sort by `updatedAt` descending. Cursor-only writes do not
change `updatedAt`; append/update writes do.

## Surface Binding

Unread must land on the surface users actually see.

Mac row surfaces:

```text
HomeView.ConversationRow      # CR4 conversation rail / forward Home surface
ThreadsView.ThreadRow         # legacy Work Threads sidebar while it remains
```

Rules:

- Both surfaces read the same `WorkThread.hasUnread`/`firstUnreadTurnId`
  derivation from Core.
- Both surfaces reserve the same trailing light slot so the row does not reflow.
- Home must adopt the same triage order as ThreadList when unread ships.
  `railThreads` newest-first is not sufficient for unread.
- `ThreadsPresenter.rowState` remains attention/running/idle. Unread is a
  separate axis, not a fourth mutually exclusive row state.
- `ConversationStatus` / status pills may still report stable outcome
  (`replied`, `board ready`, `spec ready`, `exit 0`, `exit 1`). They must not
  encode freshness, suppress the unread light, or become the read truth.
- If a status pill and unread light both appear, the pill says what happened;
  the light says the user has not seen it yet.

## Visual Contract

The unread affordance is an indication light.

Required behavior:

- Small circular light, reserved row slot, no layout shift.
- Far trailing edge of the row, vertically centered against the title/status
  block.
- Amber for ordinary unread landed work.
- Red or failed-status treatment may be used only when the unread anchor also
  requires attention.
- No visible text label, no note, no badge count.
- Accessibility label/value must expose the unread state for assistive tech.
- One-time arrival bloom is allowed; no perpetual blink for unread.
- A running/live indicator may pulse separately, but unread should not borrow
  the running dot.
- Clearing read fades the light out; it should not snap away before the turn is
  visible.

Design-system binding:

- Use named app tokens only (`ALColor.accent`, status tokens, border/glow
  tokens). No hard-coded hex in SwiftUI.
- Amber is the warm signal. Do not introduce a new hue for unread.
- Motion should be restrained: 120-280ms for fade/scale, with reduced-motion
  respected.
- The light should read like amber phosphor on midnight: precise, quiet, and
  unmistakable.

Row state matrix:

```text
state                         leading/live status       trailing unread light
read idle                     none/status pill only     none
unread reply                  normal outcome pill       steady amber
unread completed run          normal outcome pill       steady amber
attention, already read       attention treatment       none
unread + attention            attention treatment       steady amber + a11y value
running, no unread            running/live treatment    none
running + unread              running/live treatment    steady amber
selected unread               current selected style    remains until visible
```

## Read/Clear Interaction

Marking read should mean "the user could actually see the landed turn", not "the
row was clicked."

Mac rules:

- Selecting a thread scrolls to the first unread turn when one exists.
- Mark read only after the unread anchor turn is rendered in the timeline while
  the app window is active.
- If the user is already in the selected thread and near the bottom, a landed
  reply can auto-scroll into view and clear after it is visible.
- If the user is scrolled up, a newly landed turn keeps the light on until the
  user reaches it or uses an explicit mark-read command.
- If the app is inactive or hidden, do not mark read merely because the selected
  thread id matches.
- Clicking a notification deep-link opens the thread but clears only after the
  target turn is visible.

Definition: unread anchor

```text
firstUnreadTurnId = first unread-eligible turn after the cursor, including any
turn that landed after readCursor.readAt.
```

Visibility contract:

- The timeline must be mounted for the selected thread.
- The app window must be key/active.
- `selectedThreadId` alone never proves visibility.
- A `scrollTo` call alone never proves visibility.
- A turn id is visible only when its root timeline row intersects the viewport
  by the configured threshold and the scroll animation/layout pass has settled.
- Use a short debounce (about 150-250ms) to avoid clearing during fast
  scroll-past. Do not use a 1-2 second dwell timer as read truth.
- Reduced Motion disables bloom/extra motion, not visibility requirements.

Minimum visible by family:

| Family | Minimum visible for read-clear |
| --- | --- |
| `workerChat` | Turn header plus the first body line/content region is visible; very long replies do not need to be fully visible. |
| `systemEvent` sign-in/manual-paste | The inline action surface or blocking note is visible. |
| `teamRun`/`designBoard`/`reviewBoard` | S07 must define a compact card header with landed status + preview; that header visible is sufficient. If no preview exists, require expansion before clearing. |
| `dispatch`/`returnReview` | S07 must define a compact card header with landed status + result preview; that header visible is sufficient. If no preview exists, require expansion before clearing. |

UNR v1 proof scope is `workerChat` plus blocking `systemEvent`. Team/build
derivation can be fixture-tested in Core, but user-facing clear-on-visible for
rich turns is not complete until PWT-S07 gives those turns real cards with the
minimum-visible contract above.

Scroll policy priority:

```text
1. On thread open with unread -> scroll to firstUnreadTurnId.
2. On notification deep-link -> scroll to the target turn, then apply visibility.
3. On new turn while selected -> auto-scroll only if the user is near bottom, or
   if the new turn is the first unread anchor and the thread was already at the
   read edge.
4. On read-cursor-only updates -> never auto-scroll.
5. On ordinary turn count changes -> never override a first-unread target.
```

Implementation path:

```text
ThreadTimeline reports visible turn ids -> ThreadsViewModel asks ThreadStore to
mark read through the contiguous visible unread prefix.
```

Avoid a "clear on select" shortcut. It makes demos pass and real floor-manager
work fail.

## Notification Relationship

This slice does not deliver notifications.

It does create the read-state foundation that notifications should respect:

- If the user is actively viewing the landed turn, no unread light remains and a
  local notification can be suppressed.
- If a notification is delivered, it is not a read receipt.
- Clicking a notification is not read by itself; visibility clears read.
- Mobile push payloads remain content-light and do not carry read truth.
- Menu-bar numeric count, when notifications land, is for needs-attention
  threads only. Ordinary unread may get a quiet amber dot only after a designed
  menu-bar contract exists; do not double-count unread + attention.

## iOS Relationship

iOS is not required for the first Mac slice, but the model must not block it.

Future iOS rules:

- Mac remains the read-state truth owner.
- iOS renders the same unread light from the Mac thread payload.
- iOS sends `markRead(threadId, throughTurnId)` after the target turn is visible.
- If iOS is offline, it may clear locally for feel, but must reconcile with Mac
  truth on reconnect.
- Reconciliation is monotonic: Mac accepts an iOS cursor only if it advances the
  Mac cursor under the same store rules; otherwise Mac sends its newer truth
  back to iOS.
- Push notification delivery state is separate from read state.

## Protocol Impact

When the remote spine exposes threads, add:

```text
Thread payload
- readCursor?
- hasUnread              # derived convenience allowed only if source fields are
                         # also present or versioned by the Mac
- firstUnreadTurnId?
- latestUnreadTurnId?

Intent
- thread.mark_read(threadId, throughTurnId)  # monotonic/forward-only

Event
- thread.read_state_changed(threadId, readCursor, firstUnreadTurnId?)
```

Do not let iOS invent unread from local timestamps.

## Privacy And Permissions

- Read state is local attention metadata.
- It contains no prompt, reply, code, artifact text, secret, or credential.
- It should not require a new macOS permission.
- It should not leave the user's machines except through the explicit local/iOS
  remote thread protocol.
- Do not use read state for analytics or worker prompting.

## Migration

Existing persisted threads have no read cursor. We cannot truthfully reconstruct
what the user already read.

Migration rule:

```text
Legacy threads start read-through-current. Only turns appended or settled after
the feature-aware store touches the thread can become unread.
```

Implementation options:

1. Lazy baseline: when a legacy thread is about to receive a new append/update,
   set `readCursor` through the latest already-known read baseline before
   writing the new state. If an existing running turn is settling into a landed
   unread-eligible turn, baseline through the previous turn so the landed result
   still lights the row.
2. Eager baseline: on first app launch after the feature, walk all threads and
   set `readCursor` through the current last turn.

Prefer lazy baseline unless eager migration is needed for UI simplicity. Either
way, do not show every old thread as unread after upgrade.

Archived threads:

- Archive status does not clear read state.
- New unread-eligible turns on archived threads keep unread truth, but this
  slice does not auto-unarchive them.
- If the archive view is opened, archived unread rows may show the same light.
- A future auto-unarchive rule must be owned by an archive/lifecycle phase, not
  smuggled into read-state derivation.

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Thread row light | `ThreadReadCursor` + turns | `updatedAt > selectedAt` means unread | Do not derive unread from timestamps alone | Updating `updatedAt` for a title edit does not show the light |
| Thread selection | Timeline visibility | selected row means read | Do not clear on select before the unread turn renders | Select unread thread with timeline not visible; light remains |
| Notification | Notification policy | delivered/clicked means read | Do not use notification delivery as read truth | Click notification with app hidden; cursor unchanged until turn visible |
| Running turn | `ThreadTurn.status` | running worker means unread | Do not mark queued/running as unread | Running turn shows live state but no unread light |
| Legacy migration | `ThreadStore` | missing cursor means all old turns unread | Do not create upgrade-time unread storm | Old fixture with worker reply and no cursor has no unread |
| User message | `TurnAuthor.user` | latest message in row means unread | User-authored turns never create unread | Appending a user message leaves unread false |
| User send while scrolled up | Composer/view model | sending a reply means earlier unseen turns were read | Do not advance through a user turn when an earlier unread anchor is unseen | User sends while scrolled above an unread reply; light remains |
| Out-of-order completion | index-only cursor | a completed older running turn before cursor is read | Include landed-after-read using `completedAt/readAt` | Running turn created before cursor completes after cursor; light appears |
| Direct save | ad hoc `ThreadStore.save` caller | partial write can bypass cursor/baseline rules | All RMW writes go through serialized store operations | Direct save path is unavailable or validates cursor invariants |
| Partial viewport | SwiftUI visibility callback | any visible later unread clears all earlier unread | Mark through contiguous visible unread prefix only | Turn 5 visible while turn 3 unread unseen; cursor does not jump to 5 |
| Rich collapsed turn | timeline row header | any collapsed header is read | Apply family visibility contract; require preview or expansion | Rich turn with no preview header visible; cursor unchanged |
| Home rail | `HomeView.railThreads` | newest-first is enough for unread | Primary rails must use triage order and Core `hasUnread` | Home unread thread sorts above running/recent |
| Archived thread | archive status | archive clears or suppresses read truth | Archive hides rows only; cursor semantics continue | Archived unread thread shows light when archive is viewed |

## Ordered Slices

- [ ] UNR-S01 - Add `ThreadReadCursor` to Core, Codable migration fixtures, and
  pure unread derivation helpers, including landed-after-read logic.
- [ ] UNR-S02 - Add serialized `ThreadStore` write gate, `markRead`, cursor-only
  save, and append/update legacy-baseline semantics. Prove `updatedAt` is
  preserved and `transcript.md` is byte-identical on cursor-only writes.
- [ ] UNR-S03 - Add presenter freshness state and revised triage ordering:
  attention -> unread -> running -> recent. Apply to Home and legacy Threads
  rails.
- [ ] UNR-S04 - Add Mac thread-row unread light component on both rail rows using
  design tokens, no visible label/count, with accessibility value and reserved
  trailing slot.
- [ ] UNR-S05 - Add timeline visibility reporting, contiguous visible-prefix
  mark-read helper, and clear-on-visible behavior for `workerChat` + blocking
  `systemEvent`.
- [ ] UNR-S06 - Add notification handoff hooks so `02_Notifications.md` can
  suppress notifications when the landed turn is already visible.
- [ ] UNR-S07 - Add GUI fixture/proof scenario for unread, selected unread,
  running without unread, unread attention, and running+unread.
- [ ] UNR-S08 - Add rich-turn visibility contract for team/build/dispatch cards
  when PWT-S07 lands.
- [ ] UNR-S09 - Add remote protocol fields/intents when the iOS thread spine
  exposes thread lists.

## Works Test

Mac:

```text
Start with two existing legacy threads. Launch the feature-aware app. Neither
thread shows an unread light.

Create a new thread and send a chat turn. The user turn renders immediately and
does not show unread. The worker turn starts running and shows running, not
unread. Leave the thread selected but scroll away or switch to another thread.
When the worker reply settles, the row shows a small amber unread light and moves
above merely running/recent rows. The light survives app relaunch.

Open the unread thread. The timeline scrolls to the first unread turn. The light
stays until that turn is visible in the active window, then fades out. The read
cursor is persisted, `updatedAt` is unchanged, and relaunch does not bring the
light back.

Repeat with a failed worker. The row shows attention plus unread semantics until
the failed turn is visible.

While an unread reply is below the visible viewport, send a new user message
from the same selected thread. The user message does not clear the earlier
unseen reply. Scroll to the reply; only then does the light clear.

Create two unread landed turns. Make only the second visible. The cursor does
not jump past the first. Make the first visible, then the contiguous visible
prefix clears.

Start with a legacy thread containing a running worker turn and no cursor. After
upgrade, settle that worker turn to done. The store baselines through the prior
turn, the settled worker turn becomes unread, and no older terminal turns light
up.
```

Focused unit proof:

```text
swift test --package-path Packages/AllnighterCore --filter WorkThreadTests
swift test --package-path Packages/AllnighterCore --filter ThreadStoreTests
xcodebuild test -scheme AllnighterMac -destination 'platform=macOS' \
  -only-testing:AllnighterMacTests/ThreadsPresenterTests
```

Green wall:

```text
bash scripts/check.sh
```

Visual proof:

```text
Render the Home thread rail fixture with:
- read idle
- unread reply
- unread failed/attention
- running without unread
- running with unread
- selected unread during fade

Repeat on the legacy Threads rail while it remains in the app.

Pass the GUI visual proof gate for reserved trailing slot, no layout shift,
row spacing, light placement, contrast, and no text overlap.
```

## Done When

- The database has a durable read cursor for threads.
- Unread is derived from cursor plus turn truth, not stored as a boolean.
- All derivation lives in Core; all persistence/mutation lives behind
  serialized `ThreadStore` operations.
- Existing legacy threads do not all light up on upgrade.
- Running turns that complete after the cursor still light via landed-after-read.
- Worker/team/dispatch results that land away from view light the row.
- User-authored turns and running turns do not light the row or clear earlier
  unseen unread anchors.
- Opening the thread clears only after the unread turn is visible.
- Clearing read survives relaunch and does not bump `updatedAt`.
- Thread triage prioritizes attention, then unread landed work, then running on
  both Home and legacy Threads rails.
- The row renders a light, not a note, label, or count.
- Unit tests cover cursor migration, derivation, store updates, and presenter
  ordering.
- GUI proof verifies the light in the actual Mac rail.

## Resolved Product Decisions

- No visible or hidden `Mark all read` in v1.
- Menu-bar count belongs to needs-attention only. Ordinary unread may later get
  a quiet amber dot if `02_Notifications.md` designs it.
- Read clearing waits for viewport visibility in an active/key window. Short
  debounce is allowed; long dwell is not read truth.
- Archived threads are not auto-unarchived by read-state code.

## Open Questions

- Should a future archive/lifecycle slice auto-unarchive background completions,
  or should archive always mean "hide until I inspect archive"?
- After PWT-S07 rich cards land, are compact preview headers enough for every
  team/build read-clear, or should certain artifact-heavy cards require expand?
