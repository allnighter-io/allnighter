# CR-08 — DriverConcurrencyGate spawn limits

Status: **ready**
SSOT: [`Pair_Programming_Team.md`](../../Pair_Programming_Team.md) §4.1 (opencode `maxConcurrentSpawns:1`)

## Goal

Review per-driver spawn gating — especially OpenCode's `maxConcurrentSpawns: 1` contract.

## Why this chunk

OpenCode driver pins `maxConcurrentSpawns:1`. Violating that → overlapping GLM processes,
context corruption, serve races. ~76 lines, fits one window.

## Review lenses

1. Gate keyed correctly per driver id?
2. Release on crash/cancel — slot leak?
3. Interaction with `WarmWorkerPool` / parallel team runs?
4. Fairness when multiple projects share one OpenCode driver?
5. Timeout waiting for slot — surfaced how?

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/DriverConcurrencyGate.swift` (full file)

## Touch only

- `docs/phases/code_review/findings/CR-08.md`

## Copy-paste prompt

```text
Review DriverConcurrencyGate — limits concurrent CLI spawns per driver (OpenCode maxConcurrentSpawns:1).

READ ONLY inlined file. No greps.

Lenses:
1. Per-driver keying
2. Slot leak on crash/cancel
3. WarmWorkerPool / team-run interaction
4. Multi-project fairness
5. Wait timeout surfacing

Output: docs/phases/code_review/findings/CR-08.md
```

## Check

```bash
test -f docs/phases/code_review/findings/CR-08.md && grep -q "## Findings" docs/phases/code_review/findings/CR-08.md
```

## MCP packet

[`packets/CR-08.json`](../packets/CR-08.json)
