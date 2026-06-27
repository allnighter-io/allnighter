# CR-02 — SliceTerminalClassifier (compaction ≠ stall)

Status: **ready**
SSOT: [`Pair_Programming_Team.md`](../../Pair_Programming_Team.md) §3 F2, §5

## Goal

Stress-test terminal classification so GLM mid-compaction is never killed as stalled.

## Why this chunk

**F2 is the single most dangerous false-positive in the pair loop.** `SliceTerminalClassifier`
is ~65 lines — ideal for deep reasoning without reads. Wrong classification → killed GLM mid-recovery
or infinite retry on a dead slice.

## Review lenses

1. Is `isCompactionMarker` too brittle? (substring `"compaction"` in output/reasoning)
2. Can a real stall masquerade as compacting?
3. Order of checks: infraBackoff → compacting → stalled — any path that mis-labels?
4. Empty visible output → `.stalled` — false positive for slow-but-alive executors?
5. `isInfraBackoff` heuristics (429, busy, rate limit) — gaps or over-match?

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/SliceTerminalClassifier.swift` (full file)
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/SliceTerminalClassifierTests.swift` (test case names + assertions summary — inline in prompt)

## Touch only

- `docs/phases/code_review/findings/CR-02.md`

## Copy-paste prompt

```text
Review SliceTerminalClassifier — decides passed/failed/stalled/compacting/infraBackoff for pair-programming slices.

CRITICAL INVARIANT (F2): Compaction is RECOVERY, not failure. Never kill a compacting GLM as stalled.

READ ONLY inlined file below. No greps.

Lenses:
1. isCompactionMarker brittleness
2. Stall masquerading as compacting (or reverse)
3. Classification order bugs
4. Empty output → stalled false positives
5. infraBackoff heuristic gaps

Write findings to docs/phases/code_review/findings/CR-02.md per README contract.
For each finding suggest a concrete test case name if missing from tests.
```

## Check

```bash
test -f docs/phases/code_review/findings/CR-02.md && grep -q "compaction" docs/phases/code_review/findings/CR-02.md
```

## MCP packet

[`packets/CR-02.json`](../packets/CR-02.json)
