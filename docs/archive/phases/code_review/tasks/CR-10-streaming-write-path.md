# CR-10 — Streaming write path coalescing

Status: **ready**
SSOT: [`Team_Run_Load_Performance.md`](../../Team_Run_Load_Performance.md) PERF-S01

## Goal

Review streaming partial buffer + thread store write serialization for redundant I/O and main-actor contention.

## Why this chunk

PERF-S01 shipped coalesced reloads; these two files (~95 lines combined) are the hot-path
primitives. Small, high leverage for "why is streaming still heavy?"

## Review lenses

1. `StreamingPartialBuffer` — flush boundaries, memory growth, duplicate deltas?
2. `ThreadStoreWriteSerializer` — serializes all writes — bottleneck under parallel runs?
3. Throttle interval interaction (1.5s checkpoint — referenced in perf doc, not necessarily in these files)?
4. Lost final partial on cancel?
5. Cross-thread safety without deadlocks?

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/StreamingPartialBuffer.swift` (full file)
- `Packages/AllnighterCore/Sources/AllnighterEngine/ThreadStoreWriteSerializer.swift` (full file)

## Touch only

- `docs/phases/code_review/findings/CR-10.md`

## Copy-paste prompt

```text
Review StreamingPartialBuffer + ThreadStoreWriteSerializer — streaming delta accumulation and serialized thread persistence.

CONTEXT: PERF-S01 moved team-run streaming to in-memory overlay with throttled durable checkpoint.

READ ONLY the two inlined files (~95 lines total). No greps.

Lenses:
1. Buffer flush + memory bounds
2. Write serializer as global bottleneck
3. Throttle/checkpoint interaction (infer from code)
4. Cancelled run final partial loss
5. Deadlock / actor ordering

Output: docs/phases/code_review/findings/CR-10.md
```

## Check

```bash
test -f docs/phases/code_review/findings/CR-10.md && grep -q "## Findings" docs/phases/code_review/findings/CR-10.md
```

## MCP packet

[`packets/CR-10.json`](../packets/CR-10.json)
