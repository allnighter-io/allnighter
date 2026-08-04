# Worker Turn Termination and Lane Release

Status: **S02 COMPLETE — dogfood next (founder ceiling 2026-08-04)**
Owner: AllnighterEngine (`RunService`, `ExecutionLane`, kill path)
Created: 2026-08-04
Finalized: 2026-08-04 (scope narrowed by founder)

Related:
[`Run_Lifecycle_Reliability.md`](../archive/phases/Run_Lifecycle_Reliability.md) ·
[`Process_Ownership.md`](../archive/phases/Process_Ownership.md) ·
[`Idle_Stall_False_Kill_Hotfix.md`](../archive/phases/Idle_Stall_False_Kill_Hotfix.md) ·
[`One_Run_Surface.md`](One_Run_Surface.md)

## Founder ruling (binding scope)

```text
When the worker is done, free the repo for the next turn (S01 — shipped).
When the worker hangs or the operator cancels: stop the worker, free the repo.
If that does not free the repo quickly, stop the Allnighter process holding it.
Then dogfood. No further lifecycle work in this packet without a new ruling.
```

Do **not** add: a watcher, daemon, PM supervision, Git completion heuristic,
metadata-only force unlock, or a second timeout policy.

A flock frees only when the owner releases it, or the owner process dies.

## User-visible defect

PM (Opus) delegates to an execution worker (e.g. Grok). The worker goes quiet
or never cleanly ends. Opus sits. The human has to chase the PM. The repo lane
stays held even when useful work already landed.

Incident locus (M2 primary; M1 secondary):
[`docs/debuglog/WL_PWR_S00_Locus.md`](../debuglog/WL_PWR_S00_Locus.md).

## What already shipped

### WL-PWR-S00 — locus (**COMPLETE**)

Failing hermetic tests + Studio record. Kept as acceptance.

### WL-PWR-S01 — release after worker terminal (**COMPLETE**)

When a terminal `WorkerRunOutcome` exists, capture repo truth, then release
`RunService` depth before settlement/proof (`MutationAuthorityHold`). Nested
relay/pilot depth stays. Vendor park still releases before return.

Proof: T-M1, T-PROOF, T-PARK, nested relay — green.

## Remaining slice (founder ceiling)

### WL-PWR-S02 — hang / cancel frees the repo (**COMPLETE**)

One product rule:

```text
alln kill (or cancel) on a live mutating run
  → stop the active worker (identity-checked)
  → release this process's lane hold (mutation + any in-flight proof)
  → next waiter can acquire within seconds
  → if the holder process will not unwind, stop that process (kernel frees flock)
```

Shipped: `RunExecutionRegistry` + `LiveRunStop` — same-process kill releases
mutation/proof holds immediately and cancels in-flight proof; durable kill
journal wins on return. Cross-process holders still rely on identity-checked
worker stop (`KillSettlement`) plus owner unwind.

Acceptance:

- [x] T-M2 kill green
- [x] T-M3 green
- [x] T-M1 / T-PROOF / T-PARK / nested relay stay green

**Stop here and dogfood.** No further lifecycle work in this packet without a
new founder ruling.

## Inference bans (still binding)

| Bad inference | Binding correction |
| --- | --- |
| Commit landed → worker finished | Only a terminal worker outcome ends the turn |
| Journal terminal → flock free | Owner release or process death frees the flock |
| Metadata delete → flock free | Forbidden |
| PM notices hang → lock fixed | Owner must stop and release without PM judgment |

## Operator recovery (until / unless S02 is enough in dogfood)

1. `alln ps --json` — holder, duration, identity.
2. `alln kill <holder-run-id> --json`.
3. If still held after a short wait, terminate the recorded coordinator process.
4. Re-dispatch; trust `alln show --stream`, not exit code alone.

## Closeout checklist

- [x] S00 incident locus and failing tests recorded
- [x] Founder approved root-fix direction
- [x] Final worker terminal releases `RunService` depth before settlement (S01)
- [x] Founder ceiling: hang/cancel frees repo; then dogfood (2026-08-04)
- [x] S02: kill/cancel stops worker and frees lane (T-M2 kill, T-M3)
- [ ] Dogfood: consecutive mutating turns without manual lock recovery
- [ ] Later (new ruling): archive / promote durable law
