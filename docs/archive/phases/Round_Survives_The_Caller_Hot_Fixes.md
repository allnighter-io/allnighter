# Round Survives The Caller — Redesign (RSC-HF)

**Status:** Complete — archived 2026-07-28  
**Predecessor:** `Round_Survives_The_Caller.md` (S01–S05 shipped; mid-flight audit: REFACTOR REQUIRED)  
**Constraint:** zero users → hard cut, no migration, zero dead code.

## Goal

`--no-wait` means: ack only after the child durably accepted the work, return the
real id, and never introduce a second dispatch state machine.

## Shipped design

1. **`DetachedHandoff` + `DetachedDispatch.launchAndAwaitAcceptance`** — parent
   creates a handoff directory, sets `ALLNIGHTER_DETACHED_HANDOFF`, spawns the same
   registered verb with `--no-wait` stripped, waits for `runner_ready.json`. Child
   writes accepted/refused after durable claim. Reuses existing
   `RunnerReadyHandshake` I/O — did **not** restore deleted `team __runner`.
2. **Collapsed relay** — deleted `relay-continue`, `relay-start-continue`,
   `dispatchToken`, and parent-mutate-then-continue. Child runs normal
   `pair relay` / `relay-resume` / `relay adopt`.
3. **Run identity** — public `--run-id` removed. Handshake returns the actual id
   (including idempotency replay). `RunStore.validateRunId` rejects path escape.
4. **Hard-fail claim** — first `.running` persist throws via `persistClaim`.
5. **GUI** — `claimStart` then navigate; loop via `complete`.
6. **Proofs** — `RSCHostileDetachedTests` + unit suites; contract 5.0.0 / binary 0.10.6.

## Successor owners

- `DetachedHandoff.swift`, `DetachedDispatch.swift`
- `RelayCoordinator.swift` (`claimStart` / `persistClaim` / `resumeGuard` / `adoptGuard`)
- `RelayDispatchLock.normalizeDocPath`
- `RunCLI.swift`, `RunStore.validateRunId`
- `RelayLaunchViewModel.swift`
- `ContractRegistry+Milestone1` (5.0.0)
