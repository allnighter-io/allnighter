# RLC-S02 — Durable same-source continuation

Status: **done**
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

## Done when

- [x] Parkable capacity → `queued/waitingForVendor` + `vendorBackoff` blocker; write lock released
- [x] Coordinator tick wakes overdue parks; direct in-process resume (no child `alln run`)
- [x] Session resume or bounded fresh handoff; repeat limit re-parks with attempt append
- [x] Hard max attempts → escalate (non-silent)
- [x] N runs one source → one readiness attempt
- [x] Works test green; committed `feat(rlc): S02 — park/wake same-source continuation`
