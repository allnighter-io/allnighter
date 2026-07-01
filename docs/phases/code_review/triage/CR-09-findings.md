# CR-09 — TimelineVisibility scroll and read-clear perf review

## Summary

`TimelineVisibility.swift` wires viewport-intersection preferences into a read-clear
cursor and owns the timeline auto-scroll policy. The read-clear path is quadratic in
turn count on every scroll frame (linear `turns.first(where:)` inside a `map.filter`,
plus an O(n²) `Dictionary.merge` in `TurnFramePreference.reduce`), and `report()`
fires twice per scroll frame because `turnFrames` and `viewport` both change together.
There is also a likely team-run read-clear gap: any unread-eligible turn whose `kind`
is not `workerChat`/`signInRequired`/`manualPaste` can never clear. Auto-scroll
contention is minor (a always-queued async second pass and an overflow-tolerant live
signal). No P0 invariants are violated by this file alone.

## Findings

### P1 — Quadratic turn lookup in `visibleTurnIdsForReadClear`
- **Invariant:** Read-clear must run on every scroll frame; cost must scale with visible turns, not all turns.
- **Evidence:** `visibleTurnIdsForReadClear` at TimelineVisibility.swift:24 — the `map(\.id).filter` at :33 calls `thread.turns.first(where: { $0.id == id })` at :35 inside the filter. For a thread with `n` turns this is O(n) per turn → O(n²) per call, and `report()` (TimelineVisibility.swift:118) invokes it on every scroll event.
- **Impact:** For a 500-turn thread, ~250k comparisons per scroll frame; on a 60fps scroll that is ~15M comparisons/sec, all on the main thread. Jank on long threads.
- **Suggested fix:** Iterate `thread.turns` directly and test `geometricallyVisible.contains(turn.id)`, eliminating the inner `first(where:)` entirely:
  ```swift
  return thread.turns.filter { turn in
      guard geometricallyVisible.contains(turn.id) else { return false }
      return UnreadDerivation.isUnreadEligible(turn) ? countsTowardReadClear(turn) : true
  }.map(\.id)
  ```
  This makes the pass O(n) with no extra allocation.
- **Suggested slice:** read-clear: drop quadratic turn lookup in visibleTurnIdsForReadClear

### P1 — `TurnFramePreference.reduce` is O(n²) per scroll event
- **Invariant:** Preference reduction runs once per emitting row; per-row cost must be O(1) amortized.
- **Evidence:** `TurnFramePreference.reduce` at TimelineVisibility.swift:61 uses `value.merge(nextValue(), uniquingKeysWith: { _, rhs in rhs })`. Each row emits a single-entry dict via `timelineTurnFrame` (TimelineVisibility.swift:79); `reduce` is invoked once per emitter, and each `merge` is O(current size). With `n` rows the total reduce cost is O(n²) per preference propagation, and propagation re-runs on every scroll frame because every row's global frame changes.
- **Impact:** Same 500-turn thread → ~125k dict insertions/copies per scroll frame, plus intermediate dictionary allocations. Compounds with the P1 above.
- **Suggested fix:** Either (a) accept the merge but cap the tracked frame set to turns near the viewport (window the reporters), or (b) replace the `[String: CGRect]` preference with a per-row `onGeometryChange`-style callback that writes directly into an `@State` index, avoiding the merge ladder. At minimum, document that this is O(n²) and set a soft cap on tracked turns.
- **Suggested slice:** timeline: window TurnFramePreference reporters to viewport

### P1 — `report()` fires twice per scroll frame
- **Invariant:** One scroll frame should produce one read-clear report.
- **Evidence:** `body` at TimelineVisibility.swift:101 wires `.onChange(of: turnFrames)` and `.onChange(of: viewport)` separately (:113–114). During a drag, both change on the same runloop pass: every row's global frame changes (turnFrames) and the viewport origin changes (viewport). `report()` (TimelineVisibility.swift:118) therefore runs twice, each invocation paying the full O(n²) cost from the two P1s above.
- **Impact:** Doubles the per-frame cost; on top of the quadratic base this is the difference between "sluggish" and "janky" on long threads.
- **Suggested fix:** Coalesce: set a dirty flag in both `onChange` handlers and dispatch a single `report()` on the next runloop tick (or use `.onReceive` of a combined signal). Alternatively gate one on the other — viewport change implies turnFrames change, so a single `onChange(of: viewport)` plus `onChange(of: thread.turns.count)` may suffice.
- **Suggested slice:** timeline: coalesce read-clear report on scroll

### P1 — Team-run read-clear gap for non-`workerChat` turns
- **Invariant:** Any turn the user has actually seen should be eligible to clear; the read cursor must not stall on a whole turn family.
- **Evidence:** `countsTowardReadClear` at TimelineVisibility.swift:7 returns `true` only for `.workerChat` and the `.signInRequired`/`.manualPaste` system events (:9–17); every other `kind` falls to `default: return false` (:18–19). In `visibleTurnIdsForReadClear` (TimelineVisibility.swift:24), a turn is only returned when `UnreadDerivation.isUnreadEligible(turn)` is false **or** `countsTowardReadClear(turn)` is true (:37–40). So an unread-eligible team-run turn (e.g. a delegate/execute result whose `kind` is not `workerChat`) is filtered out — it can be fully visible and never advances the read cursor.
- **Impact:** Team-run answer turns stay pinned unread forever; the unread badge never clears for those threads, and `firstUnreadTurnId` keeps pointing at them. This is a correctness gap, not just perf, but it surfaces as wasted re-evaluation of a never-clearing cursor.
- **Suggested fix:** Confirm the `ThreadTurn.Kind` cases used by team-run turns (answer teams, delegate, execute) and either add them to `countsTowardReadClear` or route them through `UnreadDerivation.isUnreadEligible` so visible ones clear. Cannot verify the enum from this file alone — needs a cross-check against `WorkThread`/`ThreadTurn`.
- **Suggested slice:** read-clear: cover team-run turn kinds in countsTowardReadClear

### P2 — `scrollToBottom` async second pass always queues
- **Invariant:** Auto-scroll should not fight live-follow after the user's message is pinned.
- **Evidence:** `scrollToBottom` at TimelineVisibility.swift:211 unconditionally `DispatchQueue.main.async { scroll() }` (:222) regardless of whether the first pass already landed. If streaming begins immediately after send, `liveContentSignal` (TimelineVisibility.swift:238) fires live-follow; the queued second pass can land after live-follow and cause a visible re-anchor.
- **Suggested fix:** Gate the second pass on a layout-pending signal, or cancel it if `liveContentSignal` becomes non-zero before it runs. Low impact; mostly visible on fast-streaming models.
- **Suggested slice:** (optional) timeline: cancel scrollToBottom second pass when live-follow starts

### P2 — `liveContentSignal` uses `&+` and can stall `onChange`
- **Invariant:** The live-follow signal must be monotonic while a turn is streaming.
- **Evidence:** `liveContentSignal` at TimelineVisibility.swift:238 returns `(last.text?.count ?? 0) &+ (last.reasoningText?.count ?? 0)` using overflow addition. If the combined length wraps `Int.max`, the signal can jump to a small/negative value; a subsequent increment may equal a previously-seen value and `onChange` will not fire, stalling auto-follow for the rest of the stream.
- **Suggested fix:** Use saturating addition (`min(a &+ b, Int.max)`) or a hash of the text rather than a wrapped count. Practically unreachable today but cheap to harden.
- **Suggested slice:** (optional) timeline: make liveContentSignal monotonic

### P2 — Tall-turn intersection ratio can mis-classify
- **Invariant:** A turn that fills the viewport should always count as visible.
- **Evidence:** `geometricallyVisibleTurnIds` at TimelineVisibility.swift:43 computes `ratio = viewport.intersection(frame).height / frame.height` (:51) and requires `ratio >= 0.25`. For a turn much taller than the viewport (long streaming answer, `frame.height >> viewport.height`), the ratio is small even when the turn fills the screen; if the visible slice is < 25% of the turn's full height it is dropped from `geometricallyVisible`.
- **Suggested fix:** Also accept when `intersection.height / viewport.height >= threshold` (viewport-occupancy), so a tall turn that fills the viewport qualifies regardless of its total height.
- **Suggested slice:** (optional) read-clear: accept viewport-occupancy as visibility

## False alarms ruled out

- **`ScrollViewportPreference.reduce` / `TimelineBottomSentinelKey.reduce` cost:** both are `value = nextValue()` (O(1), single emitter). Not a concern, unlike `TurnFramePreference`.
- **`frame.height > 0` guard:** correctly prevents divide-by-zero in the ratio at :51; negative-height frames are also filtered. Not a bug.
- **`viewport != .null` guard in `report()`:** correctly avoids computing visibility before the first viewport preference lands. Fine.
- **`onChange(of: thread.turns.count)`:** count comparison is O(1); this is the right cheap trigger for new-turn scroll. Fine.
- **`isAtBottom` slack default:** 120pt slack is a product tuning constant, not a perf issue. Fine.
- **`scrollOnThreadOpen` vs `scrollOnTurnCountChange` overlap:** they fire on different lifecycle events (open vs turn-count change); no double-fire path identified from this file.

## Greps avoided

Confirmed: no repo exploration performed. Analysis uses only the inlined
`TimelineVisibility.swift` source and the resolved-symbol list provided in the review
request. No `Grep`, `Glob`, or `Read` of other source files was issued. The team-run
read-clear gap (P1) is flagged as needing a cross-check precisely because the
`ThreadTurn.Kind` enum was not read.