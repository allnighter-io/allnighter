# QUEUE-S02 — Honor `options.until` mid-slice

Status: **done**
Source: [`code_review/triage/CR-06-findings.md`](../../code_review/triage/CR-06-findings.md) (P1)

## Goal

Check `options.until` inside long-running slice work (not only at outer `runQueue` loop
start) so deadline-bound pair runs stop promptly.

## Copy-paste prompt

```text
You are implementing sprint work order QUEUE-S02 ONLY.

Read ONLY:
- docs/phases/sprint/queue/QUEUE-S02-mid-slice-deadline.md
- Packages/AllnighterCore/Sources/AllnighterEngine/PairCoordinator.swift

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/PairCoordinator.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/PairCoordinatorTests.swift

Add deadline checks before retry/compaction waits and between executor attempts.
When past `until`, exit runQueue with clear terminal state (do not start new slices).

Proof: swift test --package-path Packages/AllnighterCore --filter PairCoordinator
```

## Read only

- `PairCoordinator.swift` (`runQueue`, `options.until` ~188–191)

## Touch only

- `PairCoordinator.swift`
- `PairCoordinatorTests.swift`

## Steps

1. Extract small `isPastDeadline(options)` helper if needed.
2. Call at inner retry points, not only loop head.
3. Test: deadline during simulated long slice → queue stops without extra attempts.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter PairCoordinator
```

## Done when

- [x] `until` honored between executor attempts
- [x] Test proves mid-slice stop
- [x] No change to default unbounded runs (nil until)
