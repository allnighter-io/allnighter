# CR-07 — StalledWorkDetector worker-turn scan

Status: **ready**
SSOT: [`Stalled_Work_Watchdog.md`](../../Stalled_Work_Watchdog.md), [`Pair_Programming_Team.md`](../../Pair_Programming_Team.md) §3 F2

## Goal

Review worker-chat stall detection for false positives that could overlap with pair-loop compaction/slow GLM runs.

## Why this chunk

Two stall systems coexist: **slice-level** (`SliceTerminalClassifier`) and **app-level** (`StalledWorkDetector`).
Slow GLM (10+ min reasoning) might trip watchdog thresholds. Chunk: `scanWorkerTurns` only (~lines 43–77).

## Review lenses

1. `workerChatSeconds` default (30 min) vs GLM slice duration — false stall?
2. `observableEvent` — does streaming partial output reset the clock?
3. Wake ticket suppression — gaps for pair child runs?
4. `requiresUserAttention` skip — correct for pair escalations?
5. Should pair-programming child runs be excluded or use different thresholds?

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/StalledWorkDetector.swift` **lines 1–77** (through `scanWorkerTurns`)
- `StallReason` enum cases (inline in prompt)

## Touch only

- `docs/phases/code_review/findings/CR-07.md`

## Copy-paste prompt

```text
Review StalledWorkDetector.scanWorkerTurns — app-level stall detection for workerChat turns.

CONTEXT: Pair-programming GLM can run 10+ minutes per slice with free reasoning. Slice-level stall uses SliceTerminalClassifier (separate). Risk: double-stall or watchdog killing slow-but-healthy GLM.

READ ONLY lines 1–77 of StalledWorkDetector.swift. No greps.

Lenses:
1. 30min threshold vs slow GLM
2. observableEvent / streaming resets
3. Wake ticket suppression gaps
4. requiresUserAttention interaction
5. Pair child run exclusion policy

Output: docs/phases/code_review/findings/CR-07.md
```

## Check

```bash
test -f docs/phases/code_review/findings/CR-07.md && grep -q "## Findings" docs/phases/code_review/findings/CR-07.md
```

## MCP packet

[`packets/CR-07.json`](../packets/CR-07.json)
