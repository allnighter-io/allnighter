# CR-09 — TimelineVisibility scroll and read-clear

Status: **ready**
SSOT: [`Team_Run_Load_Performance.md`](../../Team_Run_Load_Performance.md), [`threads/06_Unread_Message_Light.md`](../../threads/06_Unread_Message_Light.md)

## Goal

Review timeline viewport intersection and read-clear logic for scroll jank and redundant work.

## Why this chunk

Active perf pain: streaming + scroll. `TimelineVisibility.swift` ~250 lines — preference keys,
`visibleTurnIdsForReadClear`, follow-scroll helpers. Recently touched in dogfood.

## Review lenses

1. `PreferenceKey.reduce` merging turn frames — O(n) per layout pass?
2. `thread.turns.first(where:)` inside filter — quadratic?
3. Intersection threshold 0.25 — edge cases (partial rows, zero height)?
4. `countsTowardReadClear` — team-run cards deferred to UNR-S08 — gaps?
5. Follow-scroll vs user-scroll handoff (if in this file's extension) — fighting?

## Read only

- `Apps/AllnighterMac/Sources/TimelineVisibility.swift` (full file)

## Touch only

- `docs/phases/code_review/findings/CR-09.md`

## Copy-paste prompt

```text
Review TimelineVisibility.swift — SwiftUI preference-based viewport tracking for thread read-clear and scroll.

PERF CONTEXT: Team-run streaming caused main-thread jank; this file participates in per-layout visibility work.

READ ONLY inlined file. No greps.

Lenses:
1. PreferenceKey reduce cost per frame
2. Quadratic turn lookups
3. Intersection math edge cases
4. Read-clear eligibility gaps for team runs
5. Auto-scroll vs user scroll contention

Output: docs/phases/code_review/findings/CR-09.md
Tag perf findings P1 with estimated impact (micro/macro).
```

## Check

```bash
test -f docs/phases/code_review/findings/CR-09.md && grep -q "## Findings" docs/phases/code_review/findings/CR-09.md
```

## MCP packet

[`packets/CR-09.json`](../packets/CR-09.json)
