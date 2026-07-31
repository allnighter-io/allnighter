# TIMELINE-S01 — Timeline read-clear scroll performance

Status: **done**
Source: [`code_review/triage/CR-09-findings.md`](../../code_review/triage/CR-09-findings.md) (P1)

## Goal

Fix O(n²) hot paths and duplicate `report()` work in timeline follow-scroll / read-clear
logic — one bounded pass per scroll frame.

## Copy-paste prompt

```text
You are implementing sprint work order TIMELINE-S01 ONLY.

Read ONLY:
- docs/phases/sprint/timeline/TIMELINE-S01-readclear-perf.md
- Apps/AllnighterMac/Sources/TimelineVisibility.swift
- Apps/AllnighterMac/Sources/ThreadView.swift (scroll/report call sites only)

Touch ONLY:
- Apps/AllnighterMac/Sources/TimelineVisibility.swift
- Apps/AllnighterMac/Tests/TimelineFollowScrollTests.swift

Optimize visibleTurnIdsForReadClear and TurnFramePreference.reduce to O(n) or amortized
O(n). Ensure report() runs once per frame path covered by tests. Do NOT change
ThreadTurn.Kind semantics (TIMELINE-S04 is separate).

Proof: swift test --package-path Apps/AllnighterMac --filter TimelineFollowScroll
```

## Read only

- `TimelineVisibility.swift`
- `TimelineFollowScrollTests.swift`

## Touch only

- `TimelineVisibility.swift`
- `ThreadView.swift` (only if needed to dedupe report calls)
- `TimelineFollowScrollTests.swift`

## Steps

1. Replace nested scans with single-pass or cached structures.
2. Deduplicate per-frame `report()` where tests show double invocation.
3. Extend tests for large turn count behavior (synthetic fixtures).

## Works Test

```bash
swift test --package-path Apps/AllnighterMac --filter TimelineFollowScroll
```

## Done when

- [x] Read-clear path is linear or documented amortized linear
- [x] No duplicate report per tested scroll frame
- [x] Existing timeline follow tests pass
