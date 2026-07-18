# CR-28 — Review ThreadView scroll and live-follow

## Summary

`ThreadTurnTimeline` (ThreadView.swift:271-342) drives live-follow with two
cooperating mechanisms: a bottom sentinel whose global `maxY` is pushed through
`TimelineBottomSentinelKey` to maintain an `atBottom` flag, and an
`onChange(of: TimelineScrollPolicy.liveContentSignal(for:))` that scrolls to the
bottom when `atBottom` (or a post-send force flag) is set. The design intent is
sound — never fight a manual scroll-up, keep a streaming answer in view. The
weakness is that the `atBottom` gate and the follow-scroll read happen through
two different propagation channels (`onPreferenceChange` vs `onChange`) whose
relative ordering is not guaranteed by SwiftUI, so organic live-follow of a
streaming answer is timing-dependent. The post-send path is rescued by
`forceScrollToBottomAfterSendActive()`, but that flag itself can override
`atBottom` and fight a manual scroll-up if it is sticky. Secondary concerns:
sentinel-inside-padding coupling with `isAtBottom` tolerance, stale `atBottom`
across thread switches, and a double-scroll risk on new-turn.

## Findings

### P1 — Live-follow race: `atBottom` is updated post-layout but read by a pre-layout `onChange`

- **Invariant:** A follow-scroll must fire when the user *was* at the bottom
  before the content grew, not when the sentinel says they *are* at the bottom
  after the content grew.
- **Evidence:** `atBottom` is written by `onPreferenceChange(TimelineBottomSentinelKey)` at ThreadView.swift:303-306, which fires after layout/preference propagation — i.e. after the sentinel has already moved down because the streaming answer grew. The follow-scroll reads `atBottom` in `onChange(of: TimelineScrollPolicy.liveContentSignal(for:))` at ThreadView.swift:318-328. When content grows, the sentinel's `g.frame(in: .global).maxY` (ThreadView.swift:296) increases; `isAtBottom` then compares the new (larger) content bottom against the unchanged viewport bottom and can flip `atBottom` to `false` *before* the follow-scroll reads it. If `onPreferenceChange` wins the race, the `if ... atBottom` guard at ThreadView.swift:322 fails and the follow-scroll is silently skipped for that delta. SwiftUI does not document that `onChange(of:)` fires before `onPreferenceChange` for the same update cycle; even if it does today, `proxy.scrollTo(..., animated: false)` (ThreadView.swift:323-327) does not retarget the viewport synchronously within the same pass, so the *next* delta's `onPreferenceChange` can still observe a not-yet-caught-up viewport and latch `atBottom = false`, dropping follow after the first delta. The `forceScrollToBottomAfterSendActive()` short-circuit (ThreadView.swift:322) masks this for the post-send window, but organic follow of a streaming answer the user is watching — the exact RLS-S04 case the comment at ThreadView.swift:274-275 calls out — is fragile.
- **Suggested fix:** Do not gate organic follow on a preference-derived `atBottom` that reflects the post-growth layout. Snapshot the "was at bottom" decision *before* the content change: e.g. capture `atBottom` into a separate `wasAtBottomBeforeDelta` state inside `onChange(of: thread.turns.count)` (ThreadView.swift:309) using the pre-update value, and read that snapshot in the `liveContentSignal` handler. Alternatively, adopt the iOS 17+/macOS 14+ `scrollPosition` API which reports scroll offset synchronously without a layout round-trip, removing the preference channel from the hot path entirely.
- **Suggested slice:** sprint: stabilize live-follow with pre-delta atBottom snapshot

### P1 — `forceScrollToBottomAfterSendActive()` bypasses `atBottom` and can fight a manual scroll-up after send

- **Invariant:** The RLS-S04 contract (ThreadView.swift:274-275) is that a manual scroll-up is *never* fought.
- **Evidence:** The follow-scroll guard at ThreadView.swift:322 is `if threads.forceScrollToBottomAfterSendActive() || atBottom`. The `||` means the force flag short-circuits `atBottom`: while the flag is active, the follow-scroll fires regardless of whether the user has since scrolled up. The same flag is also passed into `scrollOnTurnCountChange` at ThreadView.swift:314. If `forceScrollToBottomAfterSendActive()` remains true for any window after the user manually scrolls up (e.g. until the next turn completes, or until a consume that the `liveContentSignal` path does not perform), every streaming delta yanks the viewport back to the bottom — the exact anti-pattern `atBottom` exists to prevent. The flag's clear condition lives in `ThreadsViewModel` (not inlined), so this review cannot confirm it is cleared before a manual scroll-up could occur.
- **Suggested fix:** Gate the force flag on `atBottom` too, or clear `forceScrollToBottomAfterSendActive()` as soon as `atBottom` flips to `false` (i.e. on the first manual scroll-up after send). At minimum, the force flag should be consumed by the first follow-scroll that actually fires, not re-asserted on every `liveContentSignal` delta. Confirm the flag's lifecycle in `ThreadsViewModel` and add a test that a manual scroll-up between send and turn-completion is not fought.
- **Suggested slice:** sprint: clear force-scroll-to-bottom on first manual scroll-up

### P2 — Sentinel lives inside `.padding(20)`, coupling `isAtBottom` tolerance to the padding amount

- **Invariant:** `atBottom` must read `true` when the user is parked at the real bottom of the list.
- **Evidence:** The sentinel `Color.clear.frame(height: 1)` (ThreadView.swift:291-297) is the last child of the `VStack` that carries `.padding(20)` (ThreadView.swift:299). When the user is scrolled to the absolute bottom, the sentinel's `maxY` sits ~20pt *above* the viewport bottom (the 20pt bottom padding is below it). `isAtBottom` is called with `contentBottomY: sentinelMaxY` and `viewportBottomY: outer.frame(in: .global).maxY` at ThreadView.swift:304-305. For `atBottom` to read `true` at the real bottom, `TimelineScrollPolicy.isAtBottom`'s tolerance must be >= 20pt (plus any safe-area inset). If the tolerance is tuned tighter than 20pt, `atBottom` never latches true at the bottom and organic live-follow (P1 above) never engages. The 20pt value and the tolerance live in different files with no linking comment.
- **Suggested fix:** Either move the sentinel outside the padded region (e.g. as a sibling below the padded `VStack` inside the `ScrollView`), or add a named constant shared between the padding and `isAtBottom`'s tolerance, or document the coupling at both sites. Verify `TimelineScrollPolicy.isAtBottom`'s tolerance against 20pt + safe area.
- **Suggested slice:** sprint: decouple bottom sentinel from timeline padding

### P2 — `atBottom` is not reset on `thread.id` change, leaving a stale gate from the previous thread

- **Invariant:** Opening a thread should start from a known follow state, not inherit the previous thread's scroll position.
- **Evidence:** `atBottom` is `@State` on `ThreadTurnTimeline` (ThreadView.swift:276) and persists across `thread.id` changes as long as the view identity is stable. `onChange(of: thread.id)` at ThreadView.swift:308 calls `scrollTimelineToOpenPosition` but does not reset `atBottom`. If the user was scrolled up in thread A (`atBottom == false`) and switches to thread B, there is a window before the new sentinel's `onPreferenceChange` fires in which `atBottom` is still `false`; a `liveContentSignal` delta arriving in that window (e.g. thread B is mid-stream) is skipped. The initial `@State` default of `true` (ThreadView.swift:276) only helps on first construction, not on thread switch.
- **Suggested fix:** Reset `atBottom = true` (or to the open-position intent) inside `onChange(of: thread.id)` at ThreadView.swift:308 before scrolling, so the new thread starts from a follow-friendly state until the sentinel reports otherwise.
- **Suggested slice:** sprint: reset atBottom on thread switch

### P2 — `onPreferenceChange` fires on every scroll frame, re-running `isAtBottom` and assigning `@State` each frame

- **Invariant:** Scroll tracking should not re-evaluate the timeline body on every scroll frame.
- **Evidence:** The sentinel's `g.frame(in: .global).maxY` (ThreadView.swift:296) changes as the user scrolls (content moves in global space), so `onPreferenceChange(TimelineBottomSentinelKey.self)` at ThreadView.swift:303 fires on every scroll frame. The closure runs `TimelineScrollPolicy.isAtBottom(...)` and assigns `atBottom` (ThreadView.swift:304-305) every frame. SwiftUI typically coalesces `@State` writes that don't change the value, but the closure and `isAtBottom` call still run per frame; for a long thread this is avoidable work on the scroll hot path.
- **Suggested fix:** Guard the assignment: only write `atBottom` when the boolean actually flips (`if newAtBottom != atBottom { atBottom = newAtBottom }`). This keeps the closure cheap on frames where the user is clearly mid-scroll away from the boundary.
- **Suggested slice:** sprint: coalesce atBottom writes in sentinel preference handler

### P2 — New-turn fires both `scrollOnTurnCountChange` and the `liveContentSignal` handler; potential double-scroll

- **Invariant:** A single content change should produce at most one authoritative scroll decision.
- **Evidence:** When a new turn is appended, `thread.turns.count` changes (firing `scrollOnTurnCountChange` at ThreadView.swift:309-317) and `TimelineScrollPolicy.liveContentSignal(for: thread)` (ThreadView.swift:318) very likely changes in the same update. Both handlers can call into `TimelineScrollPolicy` to scroll — `scrollOnTurnCountChange` at ThreadView.swift:310 and `scrollToBottom` at ThreadView.swift:323. Whether these conflict depends on `TimelineScrollPolicy` internals (not inlined), but two independent scroll decisions for one content change is a smell: if `scrollOnTurnCountChange` scrolls to the new turn (not the bottom) while the `liveContentSignal` handler force-scrolls to the bottom, the second wins and clobbers the first.
- **Suggested fix:** Confirm in `TimelineScrollPolicy` that `scrollOnTurnCountChange` and the `liveContentSignal` handler are mutually exclusive for the same update (e.g. the count-change handler defers to the live-signal handler, or vice versa). If not, route both through a single decision point.
- **Suggested slice:** sprint: dedupe scroll decisions on new-turn

## False alarms ruled out

- **`thread.turns.last?.id` in the `ForEach` (ThreadView.swift:285) is not O(n²).**
  `ForEach(thread.turns)` requires `thread.turns` to be a `RandomAccessCollection`, so `.last` is O(1). No per-row cost concern.
- **`animated: false` on the follow-scroll (ThreadView.swift:326) is intentional, not a bug.**
  The comment at ThreadView.swift:319-320 explicitly calls for no animation so the follow stays tight on streaming deltas. Correct call.
- **`ReasoningRenderPolicy.expanded` (ThreadView.swift, post-344) is clean.**
  User toggle wins; auto-expand is gated on `isLatestTurn && isRunning`. Once a turn settles it collapses to the compact summary. No invariant issue.
- **Capturing `outer` (the `GeometryProxy`) in the `onPreferenceChange` closure (ThreadView.swift:305) is a standard SwiftUI pattern.**
  The proxy reads current geometry at call time; it is not a stale capture.
- **`bottomAnchorId` as a `static let` string (ThreadView.swift:277) is fine.**
  It is a stable scroll anchor id used consistently at ThreadView.swift:292, 315, 325, 339.
- **`scrollTimelineToOpenPosition` on both `onAppear` and `onChange(of: thread.id)` (ThreadView.swift:307-308) is not a double-scroll in practice.**
  `onAppear` fires once on construction; `onChange(of: thread.id)` fires on subsequent thread switches. They do not both fire for the same thread open unless the view identity is recreated, which is a parent-view concern outside this slice.

## Greps avoided

No repo exploration performed. This review used only the inlined
`Apps/AllnighterMac/Sources/ThreadView.swift` lines 265-360 and the resolved
symbol list provided in the CR. `TimelineScrollPolicy`, `ThreadsViewModel`,
`GUIFixture`, and `TimelineBottomSentinelKey` implementations were not read;
findings that depend on their behavior are flagged as such with the dependency
named explicitly.