# DRIVER-S01 — DriverConcurrencyGate cancel + acquire timeout

Status: **done**
Source: [`code_review/triage/CR-08-findings.md`](../../code_review/triage/CR-08-findings.md) (P1)

## Goal

Drop cancelled waiters from the driver concurrency gate queue (do not run `body` after
cancel) and add acquire timeout so a hung holder cannot deadlock all driver spawns.

## Copy-paste prompt

```text
You are implementing sprint work order DRIVER-S01 ONLY.

Read ONLY:
- docs/phases/sprint/spawn/DRIVER-S01-gate-cancel-timeout.md
- Packages/AllnighterCore/Sources/AllnighterEngine/DriverConcurrencyGate.swift

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/DriverConcurrencyGate.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/DriverConcurrencyGateTests.swift (new or extend)

Replace `CheckedContinuation<Void, Never>` with cancellation-aware waiting:
on Task cancellation, remove waiter and resume without calling body.
Add optional acquire timeout (configurable constant for tests); on timeout, fail open
or return error per existing gate contract — document choice in test.

Proof: swift test --package-path Packages/AllnighterCore --filter DriverConcurrencyGate
```

## Read only

- `DriverConcurrencyGate.swift` (`withPermit`, wait queue)

## Touch only

- `DriverConcurrencyGate.swift`
- `DriverConcurrencyGateTests.swift`

## Steps

1. Track waiters with cancellation handlers that dequeue on cancel.
2. Add timeout around acquire wait; test hung holder does not block forever.
3. Preserve slot accounting — no double-release.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter DriverConcurrencyGate
```

## Done when

- [ ] Cancelled task never runs `body`
- [ ] Acquire timeout prevents indefinite deadlock in tests
- [ ] Slot count invariant holds under cancel + timeout
