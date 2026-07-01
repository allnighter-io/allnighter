# CR-26 — Review Timeline read-clear and ThreadTurn kinds

## Summary

Read-clear visibility logic in `TimelineVisibility.swift` is structurally sound:
the O(n²) `Dictionary`-rebuild pattern was correctly replaced by
`TurnFrameAccumulator.absorb` (O(1) per emitter, O(n) total per preference
cycle), coordinate spaces are consistent (`.global` for both turn frames and
viewport), division-by-zero is guarded, and the report gate coalesces same-tick
preference co-updates to a single main-actor Task. One P1 remains from the
CR-09 follow-up: `countsTowardReadClear` uses a `default: return false` arm
that silently swallows every `ThreadTurnKind` not explicitly listed, making the
intentional team-run deferral (to UNR-S08) implicit and fragile against new
kinds. Two P2 nits: a doc-comment case-name mismatch and `&+` on a signal
documented as monotonic.

## Findings

### P1 — `countsTowardReadClear` uses `default`, hiding the team-run kind gap

- **Invariant:** Every `ThreadTurnKind` case must get a conscious read-clear
  decision when added; the team-run deferral to UNR-S08 must be explicit, not
  implicit.
- **Evidence:** TimelineVisibility.swift:7-19 — the switch handles only
  `.workerChat` (line 8) and `.systemEvent` (line 10); all other kinds (user
  messages, team/run turns, and any future kind) fall into `default: return
  false` (lines 17-18). The header comment (lines 3-4) says "Rich team/build
  cards defer to UNR-S08," but the code encodes this deferral via `default`
  rather than named cases. A new chat-like kind added to `ThreadTurnKind`
  would silently be excluded from read-clear with no compile error, leaving
  unread badges stuck. The `ThreadTurn` doc comment (ThreadTurn.swift:3-4)
  names four kind families (user message, one-worker reply, team/mutating-run,
  system note), so at least two kind families are currently caught by
  `default` without being named.
- **Suggested fix:** Replace `default: return false` with explicit cases for
  every remaining `ThreadTurnKind` (e.g., `.userMessage`, team/run kinds),
  each returning `false` with a one-line comment pointing at UNR-S08 for
  team-run kinds. This makes the switch exhaustive and forces a compile-time
  decision when new kinds are added.
- **Suggested slice:** "Exhaustive read-clear kind switch"

### P2 — Doc comment says `.system_event`, code uses `.systemEvent`

- **Invariant:** Doc comments should match the symbol names they reference.
- **Evidence:** ThreadTurn.swift:36 — `/// Only meaningful for `.system_event`
  turns`; TimelineVisibility.swift:10 — `case .systemEvent:`. The enum case is
  camelCase (per usage in `countsTowardReadClear`), but the doc comment uses
  snake_case.
- **Suggested fix:** Update the doc comment to `.systemEvent`.

### P2 — `liveContentSignal` uses `&+` for a signal documented as monotonic

- **Invariant:** `liveContentSignal` is documented as "a monotonic signal that
  grows" (TimelineVisibility.swift:272) — `onChange` relies on it not
  decreasing during a stream.
- **Evidence:** TimelineVisibility.swift:276 — `(last.text?.count ?? 0) &+
  (last.reasoningText?.count ?? 0)`. `&+` can wrap to a smaller value on
  overflow, which would break the monotonic assumption and cause `onChange` to
  miss a follow-scroll frame. Astronomically unlikely with real text, but `+`
  would trap on overflow (surfacing a real bug) and matches the documented
  "monotonic" contract.
- **Suggested fix:** Use `+` instead of `&+`, or document why overflow-wrap is
  acceptable for this signal.

## False alarms ruled out

- **O(n²) not present.** `TurnFrameAccumulator.absorb` (lines 59-63) is O(k)
  per reduce call where k = entries in `nextValue`; each emitter reports
  exactly one frame (lines 88-93), so k=1 and total accumulation is O(n) per
  preference cycle. The previous `merging`-based reduce (which copied the
  growing dictionary each call, O(n²)) is correctly replaced.
  `visibleTurnIdsForReadClear` builds a Set (O(m)) then iterates turns with
  O(1) lookups (O(n)). `geometricallyVisibleTurnIds` is O(m). No quadratic
  paths remain.
- **Division-by-zero guarded.** `geometricallyVisibleTurnIds` (line 48)
  guards `frame.height > 0` before dividing by it (line 50).
- **Coordinate spaces consistent.** Both `timelineTurnFrame` (line 91) and
  the viewport `GeometryReader` (line 134) use `.global`. No mixed spaces.
- **Report gate coalescing is correct.** `TimelineReadClearReportGate.schedule`
  (lines 109-117) sets `pending = true`, enqueues one `@MainActor` Task, and
  clears `pending` before running — so co-updates on the same tick collapse to
  one `report()`. `[weak self]` drops the report if the view is gone (safe).
- **`@State` holding a class reference is acceptable.** `reportGate` (line
  126) is never reassigned; only its methods are called. `@State` preserves
  the reference across view rebuilds, and property changes don't drive
  rendering (intended — it's a side channel).
- **Stale frames don't accumulate.** `onPreferenceChange(TurnFramePreference.self)`
  (line 138) receives the fully reduced dictionary (all current emitters), not
  a delta. Removed turns' emitters are gone, so their frames drop out of the
  next reduced value. `turnFrames` is always current.
- **Threading is main-actor.** `TimelineReadClearReportGate` is `@MainActor`;
  the modifier's `onPreferenceChange`/`onChange` closures run on the main
  actor; `report()` calls `threads.reportTimelineVisibility` on the main
  actor. Pure scroll-policy functions (`threadOpenScrollAction`,
  `turnCountScrollAction`, `isAtBottom`, `liveContentSignal`) are correctly
  non-isolated.
- **Null viewport guarded.** `report()` (line 148) guards `viewport != .null`
  before computing visibility, and `ScrollViewportPreference.defaultValue` is
  `.null` (line 79), so no read-clear fires before layout reports a real
  viewport.

## Greps avoided
No repo exploration. Review used only the two inlined sources and the
resolved symbol list. `ThreadTurnKind` enum definition was not inlined;
findings about kind coverage are based on the `ThreadTurn` doc comment
(ThreadTurn.swift:3-4, which names user message, one-worker reply,
team/mutating-run, and system note families) and the `.systemEvent` usage in
`countsTowardReadClear`.