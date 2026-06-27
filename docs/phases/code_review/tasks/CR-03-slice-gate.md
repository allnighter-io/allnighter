# CR-03 — SliceGate scope and danger enforcement

Status: **ready**
SSOT: [`Pair_Programming_Team.md`](../../Pair_Programming_Team.md) §5

## Goal

Verify the gate blocks unsafe slices without blocking legitimate narrow work — and that `touchAllowlist` is enforced downstream.

## Why this chunk

`SliceGate` is small (~60 lines) but load-bearing: danger flags, empty allowlist, executor facts.
Note: **allowlist path enforcement may live in the executor prompt, not here** — GLM should flag if gate-only checks are insufficient.

## Review lenses

1. Can a packet with `dangerFlags` slip through if flags are malformed/unknown?
2. Empty `touchAllowlist` blocks — correct for mutating; how do review-only packets work?
3. Executor validation: mutating, runnable, exactly one worker — edge cases?
4. Check method validation — command/guiFixture empty strings?
5. **Gap analysis:** gate checks packet shape; who verifies executor actually stayed in allowlist?

## Read only

- `Packages/AllnighterCore/Sources/AllnighterCore/SliceGate.swift` (full file)
- Signatures only: `TryFixGate.evaluate` in `Packages/AllnighterCore/Sources/AllnighterCore/TryFixGate.swift` (mirror pattern)

## Touch only

- `docs/phases/code_review/findings/CR-03.md`

## Copy-paste prompt

```text
Review SliceGate — pre-dispatch gate for pair-programming WorkSlicePacket.

READ ONLY inlined SliceGate.swift. TryFixGate signature provided for pattern comparison only.

Lenses:
1. dangerFlags bypass?
2. touchAllowlist empty blocking — review-only workflow gap?
3. Executor facts edge cases (non-mutating, multi-worker, unrunnable)
4. Check command/fixture validation holes
5. Gate vs runtime allowlist enforcement gap

Output: docs/phases/code_review/findings/CR-03.md
```

## Check

```bash
test -f docs/phases/code_review/findings/CR-03.md && grep -q "## Findings" docs/phases/code_review/findings/CR-03.md
```

## MCP packet

[`packets/CR-03.json`](../packets/CR-03.json)
