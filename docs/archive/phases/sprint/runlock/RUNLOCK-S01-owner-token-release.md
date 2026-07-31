# RUNLOCK-S01 — Owner-token release guard

Status: **done**
SSOT: CR-01 triage [`../../code_review/triage/CR-01-findings.md`](../../code_review/triage/CR-01-findings.md) (P1 — owner-token `release`)
Promoted from: Phase 1 code review CR-01 (2026-06-27)

## Goal

`release` must require an ownership token so stray/double release cannot free the lock under the real holder.

## Copy-paste prompt

```text
Implement owner-token release for RunWriteLockRegistry.

READ: RunWriteLock.swift, RunService write-lock acquire/release path.

CHANGE: acquire/waitToAcquire return a Token; release(key, token) verifies holder.
Stray or double release is no-op or debug assertion — never hands lock to wrong waiter.

TOUCH ONLY: RunWriteLock.swift, RunService.swift (call sites), tests.

PROOF: swift test --filter RunWriteLock
```

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/RunWriteLock.swift`
- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift` (lock acquire/release)
- `docs/phases/code_review/triage/CR-01-findings.md` (P1 owner-token section)

## Touch only

- `Packages/AllnighterCore/Sources/AllnighterEngine/RunWriteLock.swift`
- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift`
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/RunWriteLockTests.swift` (create if missing)

## Do not

- Change FIFO semantics or waiter queue structure beyond token plumbing
- Broad refactor of pair-programming or SliceGate

## Steps

1. Add `RunWriteLock.Token` (or owner receipt) returned from successful acquire/wait.
2. Record holder token per key in the actor; `release` validates before handoff/clear.
3. Update `RunService` defer release to pass token.
4. Tests: stray release ignored; double release safe; legitimate handoff preserved.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter RunWriteLock
```

## Done when

- [x] `release` without valid token cannot free lock or transfer to waiter
- [x] Existing FIFO / one-writer tests green
- [x] RunService mutating path updated
