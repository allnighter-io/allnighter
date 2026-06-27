# CR-06 — PairCoordinator queue loop

Status: **ready**
SSOT: [`Pair_Programming_Team.md`](../../Pair_Programming_Team.md) §4, §5

## Goal

Review `runQueue` retry, compaction grace, planner takeover, and escalation — the unattended overnight loop.

## Why this chunk

The queue loop is where F2/F5 meet: compaction grace, executor attempt budget, planner escalation.
Full `PairCoordinator.swift` is ~540 lines — **this task reviews only `runQueue` (~lines 169–400)**.

## Review lenses

1. `executorAttempt -= 1` on `.compacting` / `.infraBackoff` — infinite loop risk?
2. `compactionGraceSeconds` sleep — sufficient? blocks entire queue?
3. Planner takeover after `executorAttemptsBeforePlanner` — correct state on partial success?
4. `reconcileStaleRunning` — crash mid-slice recovery?
5. `until` deadline — in-flight slice behavior?
6. Gate-blocked slice → escalated — retry ever appropriate?

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/PairCoordinator.swift` **lines 169–400 only**
- Signatures: `runSlice`, `runPlannerTakeover`, `applyPlannerTakeover` (names + params inline)

## Touch only

- `docs/phases/code_review/findings/CR-06.md`

## Copy-paste prompt

```text
Review PairCoordinator.runQueue (lines 169–400 only) — unattended pair-programming queue loop.

INVARIANTS:
- ONE mutating executor under RunWriteLock for entire queue run
- Compaction: executorAttempt decremented, grace sleep, retry — NEVER escalate while compacting
- After N executor failures → planner takeover → pass or escalate

READ ONLY the inlined line range. No greps.

Lenses:
1. Infinite retry on compacting/backoff
2. Grace sleep blocking queue throughput
3. Planner takeover state machine holes
4. Stale running reconciliation
5. Deadline mid-slice
6. Gate-blocked escalation

Output: docs/phases/code_review/findings/CR-06.md
```

## Check

```bash
test -f docs/phases/code_review/findings/CR-06.md && grep -q "runQueue" docs/phases/code_review/findings/CR-06.md
```

## MCP packet

[`packets/CR-06.json`](../packets/CR-06.json)
