# QUEUE-S01 — runQueue compaction / infraBackoff retry caps

Status: **done**
Source: [`code_review/triage/CR-06-findings.md`](../../code_review/triage/CR-06-findings.md) (P1)

## Goal

Cap unbounded `.compacting` / `.infraBackoff` retries that decrement `executorAttempt`
without progress — prevent pair queue hang when infra never recovers.

## Copy-paste prompt

```text
You are implementing sprint work order QUEUE-S01 ONLY.

Read ONLY:
- docs/phases/sprint/queue/QUEUE-S01-compaction-backoff-caps.md
- Packages/AllnighterCore/Sources/AllnighterEngine/PairCoordinator.swift (runQueue loop)

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/PairCoordinator.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/PairCoordinatorTests.swift

Add per-slice counters or max retries for compacting/infraBackoff paths before
escalating to failed/stalled. Do NOT change write-lock or spawn logic.

Proof: swift test --package-path Packages/AllnighterCore --filter PairCoordinator
```

## Read only

- `PairCoordinator.swift` (`runQueue`, compacting/infraBackoff branches ~285–290)

## Touch only

- `PairCoordinator.swift`
- `PairCoordinatorTests.swift`

## Steps

1. Track consecutive compacting/infraBackoff without executor progress.
2. After N attempts, escalate (fail slice or surface reason) instead of infinite loop.
3. Unit test simulates repeated infraBackoff → bounded exit.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter PairCoordinator
```

## Done when

- [x] Compacting/infraBackoff cannot loop forever on one queue item
- [x] Escalation reason is observable in tests
- [x] No unrelated PairCoordinator refactors
