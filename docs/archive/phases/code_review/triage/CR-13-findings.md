# CR-13 — ThreadsViewModel reload coalescing

## Summary

The reload coalescing in `requestReload()` is sound for the MainActor-only case but
has a data race on `reloadScheduled` if called from background threads (which the
`Task { @MainActor in }` hop implies). `applyLiveDelta()` correctly avoids per-token
store writes but leaves `railRows` stale during streaming, advances the checkpoint
throttle timestamp before the durable write (extending the crash window on failure),
and silently swallows checkpoint errors while still bumping the write counter. The
fire-and-forget `processNotificationTransitions` Task can process transitions out of
order across rapid reloads. No P0 invariant violation found; five P1 real wins and
three P2 nits.

## Findings

### P0 — None

No invariant or security violation proven from the inlined sources alone. The data
race on `reloadScheduled` (P1 below) would escalate to P0 if the class is confirmed
non-`@MainActor`-isolated and `requestReload` is confirmed called from background
threads — both outside the inlined window.

### P1 — `railRows` stale during live streaming

- **Invariant:** `railRows` is a published derived view of `threads` and must stay
  consistent with it.
- **Evidence:** `railRows` is derived only in `reload()` at
  `ThreadsViewModel.swift:204`. `applyLiveDelta()` mutates
  `threads[ti].turns[tj].text` at `:237` and `reasoningText` at `:240` but never
  touches `railRows`. The rail rows remain stale for the entire streaming duration
  until the next `reload()`.
- **Suggested fix:** Re-derive the single affected rail row in `applyLiveDelta`:
  `railRows[ti] = ThreadsPresenter.railRow(from: threads[ti])` after the text
  mutation. O(1), no full list decode.
- **Suggested slice:** `rail-rows-live-delta-refresh`

### P1 — `requestReload()` data race on `reloadScheduled`

- **Invariant:** The coalescing flag must be accessed atomically.
- **Evidence:** `requestReload()` at `ThreadsViewModel.swift:216` is not
  `@MainActor`-annotated. The check-then-set at `:218-219`
  (`if reloadScheduled { return }; reloadScheduled = true`) is non-atomic. The
  `Task { @MainActor in ... }` at `:220` implies the method is called from
  non-MainActor contexts (otherwise the hop is redundant). Two background callers
  can both read `false`, both set `true`, and both schedule Tasks — defeating
  coalescing and racing on the flag.
- **Suggested fix:** Annotate `requestReload()` with `@MainActor` so the
  check-and-set is serialized. If the class is already `@MainActor`-isolated, make
  it explicit on the method signature for call-site clarity.
- **Suggested slice:** `request-reload-mainactor-isolation`

### P1 — Checkpoint timestamp advanced before store write

- **Invariant:** The throttle timestamp should only advance after a successful
  durable write.
- **Evidence:** `liveCheckpointAt[turnId] = now` at `ThreadsViewModel.swift:248`
  runs before `_ = try? store.updateTurn(...)` at `:253`. The `try?` silently
  swallows write failures. If the write fails, the next delta won't attempt another
  checkpoint for `liveCheckpointInterval` seconds, extending the crash window to up
  to 2x the interval.
- **Suggested fix:** Move `liveCheckpointAt[turnId] = now` to after the successful
  `store.updateTurn` call (inside the `if var stored` block, after the write). On
  failure, leave the timestamp unchanged so the next delta retries immediately.
- **Suggested slice:** `checkpoint-timestamp-on-success`

### P1 — `processNotificationTransitions` fire-and-forget Task can reorder

- **Invariant:** Notification transitions must be processed in reload order.
- **Evidence:** `reload()` at `ThreadsViewModel.swift:211` dispatches
  `Task { await processNotificationTransitions(before: beforeSnapshots, after: afterSnapshots) }`
  — a detached, non-`@MainActor` Task. Two rapid reloads can have their transitions
  processed concurrently or out of order, potentially posting duplicate or stale
  user notifications.
- **Suggested fix:** Serialize transition processing (chain onto a stored `Task` or
  `AsyncStream`), or mark `processNotificationTransitions` as `@MainActor` and call
  it without the `Task` wrapper if it is non-blocking.
- **Suggested slice:** `notification-transitions-serial`

### P1 — `store.get(threadId)` full-deserialize on streaming path

- **Invariant:** The streaming path should avoid O(thread) deserialization spikes.
- **Evidence:** `applyLiveDelta()` at `ThreadsViewModel.swift:249` calls
  `store.get(threadId)?.turn(id: turnId)` which deserializes the entire thread (all
  turns) to extract one turn. This is throttled by `liveCheckpointInterval` at
  `:247` but still spikes on the streaming path for long threads with many turns.
- **Suggested fix:** Add a `store.getTurn(threadId:, turnId:)` accessor that reads
  only the target turn, or cache the last-read store thread if it hasn't been
  invalidated by a write.
- **Suggested slice:** `store-get-turn-accessor`

### P2 — `.threadJSONWrite` counter increments on attempt, not success

- **Invariant:** Perf counters should reflect actual writes.
- **Evidence:** `PerfCounters.bump(.threadJSONWrite)` at
  `ThreadsViewModel.swift:254` runs after `_ = try? store.updateTurn(...)` at
  `:253`. The `try?` swallows errors, so the counter increments regardless of write
  success, overcounting durable writes.
- **Suggested fix:** Capture the result:
  `do { try store.updateTurn(...); PerfCounters.bump(.threadJSONWrite) } catch { PerfCounters.bump(.threadJSONWriteFailed) }`.
- **Suggested slice:** `thread-json-write-counter-accuracy`

### P2 — `liveCheckpointAt` dictionary unbounded growth

- **Invariant:** Throttle state should not grow without bound.
- **Evidence:** `liveCheckpointAt[turnId] = now` at `ThreadsViewModel.swift:248`
  adds entries keyed by `turnId`. The dictionary is never pruned. Over a long
  session with many turns, it grows without bound.
- **Suggested fix:** Prune entries for completed turns in `reload()`, or cap the
  dictionary size with an LRU eviction.
- **Suggested slice:** `live-checkpoint-dict-prune`

### P2 — `applyLiveDelta` not `@MainActor`-isolated, mutates published `threads`

- **Invariant:** Published UI state must be mutated on the MainActor.
- **Evidence:** `applyLiveDelta()` at `ThreadsViewModel.swift:232` has no
  `@MainActor` annotation. It mutates `threads[ti].turns[tj].text` at `:237` via
  index-based access. If called from a background thread while `reload()` replaces
  `threads` at `:202`, the indices `ti`/`tj` could be invalidated.
- **Suggested fix:** Annotate `applyLiveDelta` with `@MainActor`, or ensure all
  call sites hop to MainActor before invoking.
- **Suggested slice:** `apply-live-delta-mainactor`

## False alarms ruled out

- **markRead bypass via checkpoint:** `applyLiveDelta`'s checkpoint at `:249` reads
  from `store.get(threadId)` (authoritative) and overwrites only `text`,
  `reasoningText`, `partialOutputTruncated` at `:250-252`. It does not touch
  read/unread state, so markRead state in the store is preserved. No bypass.
- **`reloadScheduled = false` before `reload()` creates a coalescing gap:** On
  MainActor, `reloadScheduled = false` at `:221` and `reload()` at `:222` are
  synchronous with no suspension point between them, so no `requestReload()` can
  interleave. The gap only exists if `reload()` itself calls `requestReload()`
  (re-entrancy), which is not evident in the inlined source.
- **`applyLiveDelta` bypasses notification detection:** `applyLiveDelta` only
  updates text/reasoningText (not status), and notification candidates are derived
  from structural state at `:208`. Text streaming should not trigger new
  notification candidates, so skipping `NotificationCandidateDetection.snapshots`
  is correct by design.
- **`floorStatus` stale during streaming:** `floorStatus?.update(from: threads)` at
  `:210` is called in `reload()` but not `applyLiveDelta()`. Floor status reflects
  structural state (running counts), not text content, so staleness during
  streaming is acceptable.
- **`beforeSnapshots` captured before `store.list()`:** `beforeSnapshots` at `:201`
  is captured from the previous `notificationSnapshots` at `:209`, not from the
  pre-reload `threads`. This is correct — it compares the last-detected state to
  the new state, not the pre-list to post-list thread arrays.

## Greps avoided

Confirmed: no repo exploration. All evidence is from the inlined sources (lines
199-257). No `grep`, `glob`, `read`, or `task` tool calls were made against the
repository source. Findings reference only `ThreadsViewModel.swift:199-257` as
provided in the review request.