# Team Run Load Performance

Status: **SHIPPED 2026-07-19** — S01–S04b, S05a, and S06 hard gates landed.
S05b sidecars deferred. S00 signpost/monster-fixture polish remains optional.
Owner: AllnighterCore + AllnighterEngine + AllnighterMac
Updated: 2026-07-19 (PERF-S06 hard gates + phase archive)

Currency snapshot (code wins over older prose below):

- Terminal Team-run beachball mitigated: decode cache + collapsed/lazy worker
  markdown + Open Factory Floor.
- S01 shipped for Team/execution streaming (`applyLiveDelta`, 1.5s checkpoint).
- S02/S03 shipped (rail summaries + linearized unread / precomputed row facts).
- RunStore half of S05 shipped (`d13540da`: non-terminal progress skips derived
  artifact regen).
- S04a shipped: default-chat streaming uses `LivePartialObserver` →
  `applyLiveDelta(persistCheckpoint: false)`; 150 ms full-`reload()` poll removed.
- S04b shipped: `reloadAsync()` lists/decodes off MainActor on a serial queue;
  publish is generation-gated so live deltas win over stale snapshots.
- S06 shipped: counter/linearity gates for reload/write/decode, Team-run open
  cache, rail summaries, and unread; wall-clock first-paint/Floor timing waived
  (no SwiftUI host harness).
- Deferred: Floor projection memoization; summary sidecars (S05b).

## Founder Intent

Raw report:

```text
Pressing the first big Team run in the rail locks the app for 5-10 seconds before
the thread loads. This cannot be the product feel. Check the real files, decide
whether JSON-only storage is already hurting us, and explain why a team run opens
as a THREAD instead of the factory floor.
```

Product bar:

```text
Clicking a completed Team run should feel instant. The user should see a compact
receipt or the Floor within one frame, then full worker returns should stream into
view lazily. A long team run must never block the main app thread.
```

Target:

```text
5-10s observed stall -> <50ms first response, <150ms receipt ready, lazy full
Floor content after that. This is the 100x target.
```

## Actual Dogfood Files

Local evidence from the reported run:

```text
Thread:
~/Library/Application Support/Allnighter/Threads/thread_0645CBFD-F666-4B82-93EA-E9EBE27F7D26/thread.json

Run:
~/Library/Application Support/Allnighter/Runs/run_3BF1481D-56CD-4E10-AE52-EAFB00D5174C/run.json
```

Measured shape:

```text
All app data inspected:
  Threads: 33
  Runs: 92
  Total thread.json bytes: ~39 KB
  Total run.json bytes: ~385 KB

Reported thread folder: ~8 KB
Reported run folder: ~452 KB across 33 files

thread.json:
  2 turns
  user message: 253 bytes
  team_run turn -> runId 3BF1481D-56CD-4E10-AE52-EAFB00D5174C

run.json:
  156 KB
  team: Bug Hunt MAX
  presetId: custom_code_bug_hunt_custom
  threadId: null (the thread turn owns the run link)
  workers: 11
  workerAnswers: 10
  stages: 1 plan stage
  terminal status: complete

Visible markdown payload in run.json:
  synthesis / plan: ~7 KB
  worker outputs: ~36 KB total
```

Verdict:

```text
The specific files are not large enough to justify a 5-10 second lock by raw disk
bytes. JSON is not automatically the culprit. The likely problem is synchronous
main-actor work: load full run truth during SwiftUI body evaluation, render every
markdown answer inline, and use the thread timeline as the terminal result reader.
```

## Why It Originally Opened As A Thread

Original shell code path:

```text
HomeView.ProjectThreadRow tap
-> threads.select(thread)
-> HomeView.mainPane sees selectedThread != nil
-> ThreadView()
-> ThreadConversationPane
-> ThreadTurnTimeline
-> ThreadBoardRow for .teamRun
```

At investigation time, the GUI had no branch that said "this selected row's
latest meaningful thing is a terminal team run, so open the Floor." It always
opened the selected `WorkThread`.

`FactoryFloorView` existed, but it was not the production destination for this
rail selection path. The first fix added an "Open Factory Floor" action and made
the terminal board lazy. The outer shell still selects a thread first, so the
long-term product split remains important:

This is the active product decision in `Live_Team_Board.md`:

```text
Thread Live Team Board = compact live progress and terminal receipt.
Factory Floor          = full worker answers, synthesis, artifacts, receipts.
```

The original "why is this a thread?" was a product bug, not just a performance
bug. The initial fix should not be regressed: the thread is the cockpit/receipt;
the Floor is the room.

## Original Stall Mechanism

Evidence at investigation time:

```text
ThreadsViewModel.reload()
  store.list() decodes every full thread.json synchronously.

ThreadsViewModel.select(thread)
  marks read on open, then may reload.

ThreadBoardRow.run
  private var run: TeamRun? { turn.runId.flatMap { threads.teamRun(forRunId: $0) } }

ThreadsViewModel.teamRun(forRunId:)
  runStore.load(runId:) synchronously decodes run.json.

ThreadBoardRow.board
  renders synthesis plus every worker answer as MarkdownText inside the thread.
```

The first fix addressed the Team-run specific part:

- terminal `TeamRun` decode is cached by `RunDecodeCache`;
- worker answers are collapsed/lazy instead of all markdown-rendered at first
  paint;
- the Floor is reachable for full reading.

The remaining expensive parts are still not bounded well enough:

- `reload()` still decodes every full `thread.json`;
- streaming deltas still do `get -> updateTurn -> reload`;
- read-clear and notification paths can trigger reloads while a surface is
  mounting;
- rail, search, unread, and Floor-derived state can still be recomputed after
  broad `threads` publishes.

The lesson remains: the first frame should not try to become the whole store,
and a token should not make the whole app pay a history tax.

## JSON Verdict

Keep JSON as durable truth for now, but stop treating full JSON files as view
models.

JSON is acceptable for current local truth if:

- Rail/list views read summary records, not full `WorkThread.turns`.
- Terminal team cards read summary records, not full `TeamRun.workerAnswers`.
- Full `run.json` loads off the main actor and is cached by `runId`.
- Heavy markdown is loaded/rendered only for the selected worker or selected
  Floor panel.
- Derived sidecars are regenerated by the store, never hand-edited or treated as
  stronger truth than `thread.json` / `run.json`.

JSON will become the wrong primary query layer if we keep adding:

- full-history search,
- cross-project filtering,
- many hundreds/thousands of runs,
- ad hoc scans from SwiftUI surfaces,
- live updates that rewrite and re-render whole run records.

GRDB/SQLite is the documented growth path, but a database migration alone would
not fix this bug if the GUI still reloads and recomputes whole app state for
every small event. The next fix should be reload/live-state/read-model work, not
a storage rewrite.

## Current Status After First Fix

The narrow "click a terminal Team run and beachball while SwiftUI repeatedly
decodes/rendered the same run" problem has a real fix in code:

- `RunDecodeCache` caches terminal `TeamRun`s so body evaluation does not decode
  the same immutable `run.json` repeatedly.
- `ThreadBoardRow` now renders worker answers lazily instead of laying out every
  full markdown answer at first paint.
- Terminal boards expose "Open Factory Floor" so the Floor can be the full reader
  and the thread can stop being the result room.

That is good, but it is not enough to call Allnighter performance solved. The
next hot path is broader and nastier (historical 2026-06 framing — see
Implementation Slices for current S04a/S04b/S06 ordering):

```text
live answer/reasoning delta
-> ThreadStore.get(threadId)             # full decode of thread.json
-> ThreadStore.updateTurn(...)           # full read + atomic rewrite of thread.json
-> ThreadsViewModel.reload()
-> ThreadStore.list()                    # scan + decode every thread_*/thread.json
-> notification snapshot + FloorManagerStatus + presenter derivations
-> publish the whole threads array
-> every rail/sidebar/thread observer recomputes
```

The chat path historically ran a 150ms poll loop that called `reload()` while a
worker was streaming (removed in S04a — live partials now overlay in memory).
The remaining risk is high-frequency work where each small event still pays an
app-wide tax on other paths (full-store MainActor scans, Floor projection).

## First-Principles Review

The pasted ideas are directionally right, but the ordering matters. From first
principles:

- First paint must be bounded by visible UI, not by total threads, total turns, or
  total historical worker output.
- A streaming delta is not the same durability tier as a settled turn. Treating
  every token as canonical thread history creates write amplification.
- Durable truth and UI invalidation are separate boundaries. A file write should
  not imply "reload the entire app model."
- Derived state is state. Rail order, unread flags, search hits, and Floor
  projections need ownership, caching, invalidation, and proof instead of being
  recomputed casually from `body` and computed properties.
- The main actor paints. It should receive small view snapshots, not synchronously
  scan, decode, sort, search, and rewrite file stores.
- External writers (CLI/MCP/iOS) are real, so "just keep everything in memory" is
  not sufficient. We need a change/invalidation story, not constant polling.

Verdict on the pasted ideas:

- **Correct / high priority:** coalesced reloads, in-memory or throttled live
  partials, lightweight rail/read models, unread index maps, moving derivations
  out of computed properties, off-main store reads, and a RunStore progress fast
  path.
- **Correct / lower priority:** summary sidecars, search debounce, lighter
  pending reads, and Factory Floor projection memoization. These matter, but they
  do not remove the per-delta app-wide tax by themselves.
- **Not the first move:** SQLite/GRDB. A database can help later with query shape
  and large history, but it will not fix a UI that reloads/recomputes everything
  on every stream event.
- **Rejected as stated:** "stop persisting partial text" with no replacement.
  We should stop full `thread.json` rewrites per delta, but if crash/reopen
  continuity matters, use a throttled live sidecar or timer-based checkpoint.

## Updated Recommendations

### P0 - Add Perf Instrumentation And A Monster Fixture

Do this before or alongside the first code slice. We need numbers because the app
now has two different performance stories: terminal Team-run open and live
thread streaming.

Add `os_signpost` / counters for:

```text
rail.click
thread.select.start/end
threads.reload.start/end
threadStore.list.start/end
threadStore.get.start/end
threadStore.updateTurn.start/end
runStore.load.start/end
pending.queueJSON.start/end
unread.derive.start/end
presenter.projectSections.start/end
markdown.render.start/end
floor.firstPaint
```

Counters to assert in tests:

```text
reloads per streaming second
thread.json writes per streaming second
full thread-list decodes per streaming second
run.json decodes per terminal Team-run click
main-actor blocked time per rail click
```

Seed:

```text
33 current-style threads
1 long selected thread
1 terminal 11-worker Team run from this dogfood shape
1 synthetic 100-worker / 2 MB output run
1 streaming worker emitting deltas every 50-100ms
```

### P1 - Coalesce Reloads

Replace direct `reload()` calls in mutation, streaming, polling, read-clear, and
notification paths with a coalesced scheduler:

```text
requestReload(reason)
  if reload already scheduled: mark reason and return
  schedule one MainActor publish at next frame / short debounce
```

Rules:

- One frame gets at most one thread-list refresh.
- A burst of deltas should not produce a burst of full `ThreadStore.list()`.
- Selection should update selected id immediately, then refresh in the coalesced
  lane only if a file-backed mutation actually changed list-level truth.

### P2 - Split Live Partials From Durable Thread History

Streaming text should update the visible running turn without rewriting the full
thread file on every delta.

Recommended tiers:

```text
In-memory live overlay:
  threadId + turnId -> answerText/reasoningText/truncated/updatedAt
  published directly to selected-thread UI

Durable checkpoint:
  optional throttled live sidecar every 1-2s or on meaningful boundary
  never full thread-list reload per checkpoint

Settled truth:
  final ThreadStore.updateTurn on done/failed/cancelled
  final reload or targeted in-memory update
```

For Team runs, remember that `RunService` / `RunStore` already owns durable run
truth. The thread turn can carry a compact live receipt; it does not need to
become the full streaming transcript store.

### P3 - Introduce A Thread Read Model

The GUI needs two products, not one `threads: [WorkThread]` blob:

```text
ThreadRailRowState
  id, projectId, title, updatedAt, pinned, displayState, unread, running,
  latestRunId?, latestRunSummary?, shortPreview

SelectedThreadDetail
  id, title, projectId, turns, liveOverlay, archive/pin state
```

Rules:

- Rail/sidebar views render `ThreadRailRowState`, not full `WorkThread`.
- `selectedThread` detail loads only when the pane needs the turns.
- Publishing a live delta for the selected turn must not invalidate every rail
  row unless it changes row-level facts.
- `ThreadStore.list()` becomes a refresh operation, not the normal way to keep
  live UI current.

This can be implemented with JSON sidecars later, but start with an in-memory
derived read model so we remove the hot-path tax first.

### P4 - Make Derived State Versioned And Linear

Fix the known repeated scans:

- Build an id -> turn index map once per unread derivation instead of calling
  `firstIndex` inside each candidate check.
- Compute `hasUnread`, `firstUnreadTurnId`, `needsAttention`, `isRunning`,
  `lane`, `preview`, and row state once per thread version.
- Compute `projectSections` / search results in the view model or a derived-state
  object, not repeatedly from `HomeSidebar` computed properties.
- Search should scan row summaries first. Full turn-text search can be explicit,
  debounced, and off-main.

Target complexity:

```text
Per changed thread: O(turns in that thread)
Per rail publish: O(visible rows log visible rows), no turn-text walk
Never: O(all threads * all turns) per stream delta
Never: O(turns^2) unread derivation
```

### P5 - Move Store Reads Off The Main Actor

Add a serial store-reader actor or detached refresh task:

```text
ThreadStoreReader actor
  loadRailSnapshot() async -> [ThreadRailRowState]
  loadThreadDetail(id) async -> SelectedThreadDetail
  loadChangedThreads(since generation) async -> ...
```

Publish back with a generation counter so stale async loads cannot overwrite a
newer in-memory state.

External writers still matter. The reader should pair with one of:

- explicit write notifications from in-process stores,
- lightweight polling with coalescing,
- file-system events for `Threads/`, `Runs/`, and `Pending/`,
- or an eventual resident coordinator event stream.

### P6 - Keep The Floor Lazy, Then Memoize It

The first fix made terminal Team-run reading much better. Keep those rules:

- Thread terminal card is a receipt + short synthesis + "Open Factory Floor".
- Full worker markdown renders only when the worker is expanded/selected.
- The Floor renders synthesis and cast rail first; non-selected worker answers
  load lazily from artifacts or cached `TeamRun` output.

Then harden:

- Memoize `FloorProjector.project(run)` by `run.id` + run version.
- Do not rebuild cast/floor on every `@State` toggle.
- Keep `RunDecodeCache`, but evolve it into a `RunRepository` only after the
  thread hot path is under control.

### P7 - Add Store Fast Paths And Sidecars

After P1-P5, add store-level optimizations where they now have a clear purpose:

```text
Threads/index.json or thread_<id>/summary.json
Runs/run_<id>/summary.json
Runs/run_<id>/floor_summary.json
```

Rules:

- `thread.json` and `run.json` remain truth.
- Sidecars are derived by stores on save.
- Missing/stale sidecars rebuild in the background.
- Views never choose sidecar truth over canonical truth when the two conflict.

RunStore should also get a progress-save fast path:

- During running/progress updates, avoid rewriting every derived artifact if only
  answer text grew.
- Regenerate `bundle.md`, worker artifacts, stage files, reviews, and return
  artifacts on terminal/stage boundaries or throttled checkpoints.

### P8 - Clean Up Smaller Amplifiers

Useful once the main reload/delta tax is gone:

- Debounce search-driven filtering.
- Make `refreshArmedPending()` event-driven or backed by a pending summary
  instead of rebuilding `PendingService` and walking the queue from the rail.
- Avoid `store.get` just to compare before/after when the in-memory selected
  thread already has the old cursor.
- Audit every GUI call to `ThreadStore.list`, `RunStore.list`, `RunStore.load`,
  and `PendingService.queueJSON` from `body`, computed properties, `onAppear`,
  layout callbacks, and high-frequency `onChange`.

## Storage Decision

Do not lead with SQLite.

Keep JSON as durable truth for the next performance slice because the current
failure is mostly algorithmic and architectural:

```text
per-delta full decode/write/reload
whole-array observation invalidation
unmemoized derived state
main-actor disk work
```

SQLite/GRDB becomes the right answer when the dominant problem is:

```text
large cross-thread search
large history filtering
many thousands of rows
multi-process query coordination
needing indexed predicates that sidecars cannot cover cleanly
```

If we migrate before fixing the hot path, we will simply run expensive queries
and publish too much state on every delta instead of decoding too much JSON.

## Implementation Slices

```text
PERF-S00 - Instrument + monster fixture  ◐ PARTIAL (2026-06-20)
  PerfCounters (threadsReload / threadJSONWrite / liveDeltaApplied / reloadRequested /
  reloadCoalesced) exist and are test-assertable; OSLog handle exists. Still missing:
  actual signpost call sites, monster fixture, first-paint timings, main-actor
  blocked-time proof. Finish under S06.

PERF-S01 - Coalesced reload + live overlay  ✅ DONE (2026-06-20)
  Team-run/execution streaming deltas update published `threads` in memory via
  ThreadsViewModel.applyLiveDelta (no per-delta ThreadStore.list, no per-delta
  thread.json rewrite); durable thread.json is a throttled 1.5s checkpoint; settlement
  persists the final in-memory text. requestReload() coalesces a burst into one flush.
  Gate: ThreadStreamingPerformanceTests (60 deltas → 0 reloads, ≤1 write).
  Default-chat overlay: see S04a (landed).

PERF-S02 - Thread read model  ✅ DONE (2026-06-20)
  ThreadsViewModel publishes `railRows: [ThreadRailRowState]` (lightweight summaries)
  recomputed ONLY in reload(); the sidebar renders railRows, not full WorkThreads, so a
  live streaming delta (which mutates `threads`) no longer invalidates the rail.
  ProjectThreadRow / context menu / projectSections are row-summary based.
  Gate: ThreadStreamingPerformanceTests.testLiveDeltaDoesNotInvalidateRailRows.
  Broader "selected detail vs full rail storage" split remains optional after S04.

PERF-S03 - Derived-state cache  ✅ DONE (2026-06-20)
  UnreadDerivation resolves the cursor index ONCE (was O(turns) firstIndex per candidate
  → O(turns^2); now linear). ThreadRailRowState precomputes searchText + isRunning/
  hasUnread/hasNeverRun/lane once per reload. Gate: testRailRowSearchUsesPrecomputedText
  + Unread tests. Archive rail still reads full threads only when shown (not hot).

PERF-S04a - Default-chat live overlay  ✅ DONE (2026-07-19)
  Eliminated the default-chat 150 ms @MainActor full-reload poll. Chat streaming
  flushes notify `ThreadSendCoordinator.LivePartialObserver` → ThreadsViewModel
  `applyLiveDelta(persistCheckpoint: false)` (coordinator already persists). Final
  `reload()` only on settlement/error. Works Test:
  testDefaultChatStreamingDoesNotPollReload (60 deltas → 0 threadsReload, 0
  VM threadJSONWrite, final text visible).

PERF-S04b - Background store reader + generation-safe publish  ✅ DONE (2026-07-19)
  `ThreadsViewModel.reloadAsync()` runs `ThreadStore.list()` off MainActor (serial
  queue); publish is generation-gated. `applyLiveDelta` bumps generation so stale
  background snapshots cannot clobber live text. Selection prefetches terminal
  `run.json` into `RunDecodeCache` off-main. Works Tests:
  `testStaleReloadPublishDoesNotClobberLiveDelta`, `testReloadListsOffMainActor`.

PERF-S05a - RunStore progress fast path  ✅ DONE (d13540da)
  Non-terminal progress saves skip derived artifact regeneration.

PERF-S05b - Summary sidecars  ⏸ DEFERRED pending measurement
  Add only if S04 profiling still shows store scans dominant.

PERF-S06 - Hard performance gates  ✅ DONE (2026-07-19)
  Landed durable counter/linearity gates:
  - `TeamRunOpenPerformanceTests` (decode-once + fat receipt fixture)
  - `ThreadStreamingPerformanceTests` named aliases for list/write-per-delta
  - `ThreadRailPerformanceTests` (precomputed searchText)
  - `UnreadDerivationPerformanceTests` (200→800 turn linearity ratio)
  Waived (honest — no SwiftUI host timing harness in tree):
  - wall-clock `<50ms` first visual / `<150ms` receipt / `<300ms` Floor-open
  - `FactoryFloorPerformanceTests.testFloorRendersOnlySelectedWorkerMarkdownInitially`
    (covered in spirit by collapsed `ThreadBoardRow` + `FloorProjector` scan
    excerpts in `FloorProjectorTests.testReturnIsTypedInsightWithSummary`)
  Floor projection memoization still deferred pending measurement.
```

## Performance Gates

Works Tests (landed):

```text
TeamRunOpenPerformanceTests.testTerminalTeamRunClickDoesNotDecodeRunMoreThanOnce
TeamRunOpenPerformanceTests.testTerminalTeamRunFirstPaintUsesReceiptNotAllWorkerMarkdown
ThreadStreamingPerformanceTests.testStreamingDeltasDoNotCallThreadStoreListPerDelta
ThreadStreamingPerformanceTests.testStreamingDeltasDoNotRewriteThreadJSONPerDelta
ThreadStreamingPerformanceTests.testStaleReloadPublishDoesNotClobberLiveDelta
ThreadStreamingPerformanceTests.testReloadListsOffMainActor
ThreadRailPerformanceTests.testRailRowsUseSummariesWithoutTurnTextScans
UnreadDerivationPerformanceTests.testUnreadDerivationIsLinearInTurnCount
```

Waived (S06 closeout):

```text
Wall-clock first paint <50ms / receipt <150ms / Floor-open <300ms
  — no SwiftUI host timing harness; dogfood remains manual.
FactoryFloorPerformanceTests.testFloorRendersOnlySelectedWorkerMarkdownInitially
  — GUI collapse + FloorProjector excerpt proof stand in; dedicated Floor UI
    host test not built.
```

Manual dogfood proof:

```text
Seed the reported run fixture plus a larger synthetic 100-worker / 2 MB run.
Click the rail row.
First visual response <50ms.
Receipt visible <150ms.
Open Floor <300ms to synthesis + cast rail.
Start a streaming worker.
Reload count <= 10/sec, preferably <= display frames actually needed.
Full thread-list decode count is not tied to token count.
Thread file writes are throttled/checkpointed, not per token.
```

Done means counter/linearity gates are green; wall-clock paint targets remain
manual dogfood until a host harness exists.

## Debug Packet

```text
Tier: T2 SSOT/performance
Symptom / repro: Original: click large Bug Hunt MAX Team run row and app blocks 5-10s. Remaining: MainActor store scans; hard first-paint/Floor timing gates unproved.
Bug fingerprint: ThreadsViewModel reload model + whole-array observation + synchronous file stores on MainActor.
Truth owner: WorkThread owns settled conversation truth; TeamRun/FloorRun own Team-run result truth; live deltas are transient selected-turn UI state until checkpoint/settlement.
Lie-prone layer: SwiftUI and view models historically treated every small write as "reload all thread truth" (Team/execution and default-chat streaming now use applyLiveDelta).
Regression considered: Initial RunDecodeCache/lazy Floor fix addressed terminal run open; S01–S03 + S04a fixed streaming + rail/unread + default-chat poll; off-main reads remain.
Missing kill test / proof: Wall-clock paint/Floor harness waived in S06; counter gates landed.
Fix boundary: Performance architecture only. Do not change user-visible run truth, hide failed workers, drop settled output, or replace canonical JSON with unsourced GUI state.
Proof command / founder test: ThreadStreamingPerformanceTests + TeamRunOpenPerformanceTests + ThreadRailPerformanceTests + UnreadDerivationPerformanceTests.
```

## Done When

- Phase archived after S04b + S06 (must-before-launch). S05b remains deferred.
- Terminal Team-run click remains fast and opens a receipt/Floor path.
- Team/execution streaming deltas update visible UI without `ThreadStore.list()`
  per delta and without rewriting full `thread.json` per delta.
- Default chat performs zero full-list reloads per delta/poll while streaming
  (S04a Works Test — landed).
- Rail rendering is driven by row summaries / derived state, not repeated full
  turn-text scans.
- Unread derivation is linear in turn count.
- Heavy store reads run off MainActor and publish generation-safe snapshots
  (S04b).
- Counter gates prove reload/write/decode/unread invariants (S06). Wall-clock
  first-paint / Floor-open timings remain manual dogfood (waived in S06).

## Should-build (2026-07-19 Sol → closeout)

- **Shipped before launch:** S04a, S04b, S06 (S01–S03 and S05a already landed).
- **Defer:** S05b sidecars, Floor memoization, search debounce, deeper
  selected-detail restructuring until measured; SwiftUI host wall-clock harness.
- **Cut for this phase:** SQLite/GRDB migration and speculative filesystem-event /
  coordinator infrastructure before the measured hot path demands it.

## Open Questions

- Do we need crash-resumable partial text? Recommendation: yes, but via throttled
  live checkpoint/sidecar, not full `thread.json` rewrite per delta.
- Should summary sidecars be JSON or SQLite first? Recommendation: JSON sidecars
  after P1-P5. Revisit GRDB when query breadth, history search, or row counts
  become the measured bottleneck.
- Should `FloorRun` be persisted as a sidecar? Recommendation: persist only a
  small `floor_summary.json`; project full `FloorRun` from `run.json` and
  artifact refs on demand until profiling says otherwise.
