# CR-01 — RunWriteLock concurrency invariant

Status: **ready**
SSOT: [`Pair_Programming_Team.md`](../../Pair_Programming_Team.md) §5 (pillar 3)

## Goal

Review the one-writer-per-repo gate for races, FIFO fairness leaks, and path-normalization edge cases.

## Why this chunk

`RunWriteLockRegistry` is the **inviolable** safety primitive for mutating runs and the pair queue.
A bug here means two GLMs editing one branch — catastrophe. The whole file is ~120 lines and fits one window.

## Review lenses

1. Can two holders exist for the same normalized root (symlinks, trailing slashes, case)?
2. Is FIFO preserved under concurrent `waitToAcquire` + `release`?
3. What happens if a holder crashes without `release`? Is `owner.pid` liveness sufficient?
4. Are read/answer runs truly parallel (never take the lock)?
5. Any `actor` reentrancy or `Task` cancellation holes?

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/RunWriteLock.swift` (full file)
- Tests: `Packages/AllnighterCore/Tests/AllnighterEngineTests/RunWriteLockTests.swift` (if present — inline signatures only)

## Touch only

- `docs/phases/code_review/findings/CR-01.md`

## Do not

- Grep or read other files
- Propose code edits in this session
- Read `AGENTS.md` or phase boards

## Copy-paste prompt

```text
You are reviewing RunWriteLock for Allnighter — the one-mutating-worker-per-repo-root invariant.

READ ONLY the file content inlined below (and test signatures if provided). Do not grep.

Review lenses:
1. Two holders same root? (path normalization, symlinks, trailing slash)
2. FIFO under concurrent wait/release?
3. Crashed holder without release — liveness via owner.pid?
4. Read runs parallel without lock?
5. Actor/cancellation holes?

OUTPUT: Write docs/phases/code_review/findings/CR-01.md using the contract in docs/phases/code_review/README.md.
Rank findings P0/P1/P2. Include file:line evidence. End with "False alarms ruled out" and "Greps avoided".
```

## Check

```bash
test -f docs/phases/code_review/findings/CR-01.md && \
  grep -q "## Findings" docs/phases/code_review/findings/CR-01.md && \
  grep -q "P0" docs/phases/code_review/findings/CR-01.md || grep -q "no P0" docs/phases/code_review/findings/CR-01.md
```

## MCP packet

[`packets/CR-01.json`](../packets/CR-01.json)

## Done when

- [ ] Findings file exists with required sections
- [ ] Planner triaged P0/P1 (or confirmed clean)
