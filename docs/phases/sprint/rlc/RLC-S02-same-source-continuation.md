# RLC-S02 — Durable same-source continuation

Status: **ready** (starts after RLC-S01 commit)
SSOT: `docs/phases/Rate_Limit_Continuity.md` §Park / Wake / Resume + S02 row
Depends on: RLC-S01 (`vendorBackoff`, `waitingForVendor`, `attempts[]`, `VendorBackoffPolicy`)

## Goal

When a single-worker accepted run settles a parkable `CapacityObservation`: close
transport, release write lock, persist `vendorBackoff` blocker + `wakeAfter`,
reconcile from the ResidentCoordinator tick, reacquire lock, resume the vendor
session (or fresh-session handoff), re-park on repeat — with probe timeout,
runtimeOwnership, and source-scoped single-flight cooldown.

## Slice packet

```text
Slice: RLC-S02
Goal: Park → wake → same-source resume for one run id
Out of scope: Mac notifications/receipt (S03); substitution hops (S04)
Truth owner: TeamRun journal blocker + SourceCapacityLedger cooldown
Lie-prone layer: spawning a second alln run; holding write lock across park
Works Test: fake CLI limit @ +2min → park, lock free, wake, resume, settle
Proof command: focused Engine tests + optional two-process ps
Done when: checkboxes below
```

## Read only

- `docs/phases/Rate_Limit_Continuity.md`
- `docs/phases/rlc/S01_Notes.md`
- `docs/archive/phases/Worker_Session_Continuity.md` (session resume)
- RLR kill/settlement / runtimeOwnership (quiescence for close-transport)

## Touch only (expected — refine after S01)

- Settlement path that observes capacity on worker failure (RunService / CatalogRunCoordinator / similar)
- New `VendorBackoffReconciler` (or extend PendingWakeScheduler pattern) hooked from `ResidentCoordinator`
- Write-lock release on park; reacquire via existing FIFO (`waitingForWriteLock`)
- Session resume via existing WorkerSessionStore / CONT path
- Probe timeout (~30s) + runtimeOwnership for resume attempt
- SourceCapacityLedger single-flight nomination (oldest parked run)
- Tests: park, lock release, coordinator wake, re-park bound, crash/lease
- Fake CLI fixture for limit-with-reset

## Do not touch

- Mac GUI / notifications (S03)
- Cross-vendor SeatReseat policy changes beyond "don't reseat when parking" precedence if required for correctness
- Answer-team parallel park

## Done when

- [ ] Parkable capacity → `queued/waitingForVendor` + `vendorBackoff` blocker; write lock released
- [ ] Coordinator tick wakes overdue parks; direct in-process resume (no child `alln run`)
- [ ] Session resume or bounded fresh handoff; repeat limit re-parks with attempt append
- [ ] Hard max attempts → escalate (non-silent)
- [ ] N runs one source → one readiness attempt
- [ ] Works test green; committed `feat(rlc): S02 — park/wake same-source continuation`
