# Worker Turn Termination and Lane Release

Status: **READY FOR IMPLEMENTATION — founder approved 2026-08-04**
Owner: AllnighterEngine (`RunService`, `WorkerInvoking`,
`WarmSessionDriver`, `ExecutionLane`)
Created: 2026-08-04
Finalized: 2026-08-04

Related:
[`Run_Lifecycle_Reliability.md`](../archive/phases/Run_Lifecycle_Reliability.md) ·
[`Process_Ownership.md`](../archive/phases/Process_Ownership.md) ·
[`Idle_Stall_False_Kill_Hotfix.md`](../archive/phases/Idle_Stall_False_Kill_Hotfix.md) ·
[`One_Run_Surface.md`](One_Run_Surface.md)

## Founder ruling

Fix the lock at its owner. Do not add PM supervision to compensate for a
worker turn that cannot terminate.

```text
Every worker turn terminates exactly once.
Every terminal path ends mutation authority.
The lane owner releases its depth immediately when mutation authority ends.
Coordinator settlement, receipts, and reporting do not extend worker authority.
```

Keep `LoopCoordinator` and the existing nested single-lane model. It owns
PM/dev rounds, retry sequencing, write-scope admission, and harness proof.
Do not require Git commits, infer completion from Git, add a watcher, add a
daemon, or force-delete flock metadata.

Supervision may be considered later as product visibility. Lock correctness
must not depend on an AI PM noticing and repairing the run.

## User-visible defect

Two consecutive dogfood turns landed commits and rendered useful work while
their run remained `running` and retained the repo lane for approximately 40
and 19 minutes. A queued turn then failed before spawning.

For run `641A3C68`:

- commits `d93bdeca` and `cf9126f5` landed;
- journal remained `working`;
- no terminal worker event or `repoDelta` was persisted;
- manual cancellation eventually let the next turn acquire.

Full incident record:
[`docs/debuglog/WL_PWR_S00_Locus.md`](../debuglog/WL_PWR_S00_Locus.md).

## Root cause

`RunService.run` acquires the lane before `runExecution` and releases it only
after `runExecution` returns.

`runExecution` cannot return until its worker stream ends:

- ACP finishes a turn on the matching prompt result;
- Codex finishes on `turn/completed`;
- cold CLI streams finish when the invocation emits a terminal event/process
  exit.

If the vendor turn, stream, or process never reaches that terminal boundary,
`WorkerRunOutcome` is never built. The lane cannot unwind even if output or
commits already exist.

The clock/kill path compounds this: journal terminality or removed holder
metadata does not close the live flock. The actual owner must stop the mutator
and release its token, or the owner process must die.

### S00 findings retained

| Mechanism | Current behavior |
| --- | --- |
| M1 — post-worker settlement | Worker outcome exists, but lane remains held through proof/stage/persist |
| M2 — missing worker terminal | Warm/cold stream never ends, so no outcome exists |
| M3 — external terminal | Journal can become terminal while the owner still holds the flock |

Existing `WriteLockPostWorkerTests` reproduce M1–M3. They are implementation
acceptance tests, not a reason to add another lifecycle.

## Existing design that stays

### `LoopCoordinator` stays

Its outer lane depth is intentional:

- reserves the logical dev turn across retries;
- admits declared write scopes before worker launch;
- surfaces loop-level FIFO blockage;
- prevents another mutator from interleaving between attempts;
- releases the dev-turn depth and re-acquires as `harnessProof`.

### `RunService` stays the run owner

Its nested lane depth protects every mutating run, including standalone
Chat/Execute runs outside a loop. Relay/pilot nesting reuses the same token and
OS flock through the existing depth count; it is not a second lock system.

The fix is normal unwind:

```text
worker turn terminal
  → RunService releases its depth
  → standalone run: flock becomes free
  → relay/pilot: LoopCoordinator retains only its intentional outer depth
  → retry/review/proof transition releases or re-acquires as already designed
```

Do not remove either owner or special-case loop runs around `RunService`.

## Binding implementation design

### WT-L1 — one terminal worker-turn contract

Every worker invocation resolves exactly once to a terminal
`WorkerRunOutcome`:

```text
done | failed | cancelled | timedOut
```

Terminal means:

1. no active worker turn can mutate the repository;
2. the active stream is finished;
3. the process group is empty, or a warm session has no active turn;
4. the outcome is returned to `RunService`.

Apply this at the existing seams:

- warm: `WarmSessionDriver.prompt` / `WarmWorker`;
- cold: `WorkerInvoking.invoke`;
- owner: `RunService.runExecution`.

Do not create a second worker runner or lifecycle enum.

### WT-L2 — owner-side forced terminal

Normal completion is the vendor terminal event/process exit.

Cancellation or an existing clock fire must force the same terminal boundary:

1. stop the active turn through the existing owner:
   - warm: shut down the keyed `WarmWorker` transport/session;
   - cold: identity-check and terminate the recorded worker process group;
2. wait for the stream/process to close within the existing bounded grace;
3. synthesize `.cancelled` or `.timedOut` if the transport did not emit a
   terminal outcome;
4. return that outcome exactly once.

The active run must observe an external terminal journal revision even when no
more worker events arrive. Race the worker stream with an owner-local
`RunStore` terminal check (bounded to observe within one second); this is a
cancellation signal to the owner, not a new durable control plane.

Never:

- call raw `kill(-pgid, SIGKILL)` without identity checks;
- treat output silence alone as proof of a stall;
- watch shared repo filesystem activity as worker liveness;
- delete `holder.json` and claim the flock was released;
- release while the worker can still mutate.

`Idle_Stall_False_Kill_Hotfix.md` remains binding: healthy silent work must not
be killed by an invented progress signal. Use existing sourced clocks and
explicit cancel/kill only.

### WT-L3 — immediate lane release after final worker terminal

For the final worker attempt:

1. receive terminal `WorkerRunOutcome`;
2. capture `repoDelta`, dirty-file count, and required Git observations while
   this run still owns its lane depth;
3. release the `RunService` lane depth immediately;
4. continue journal settlement, stages, receipt rendering, and PM projection
   without worker mutation authority;
5. harness proof acquires its existing `harnessProof` claim.

Vendor substitution is still one mutating run: do not release between a failed
attempt and an immediately selected replacement unless the replacement
re-acquires through the same FIFO. Vendor park continues to release before
return as it does today.

The outer return path may attempt release again; release is token-checked and
must remain an idempotent no-op. Prefer one explicit owner-local release helper
over more scattered release branches.

### WT-L4 — external terminal unwinds the real owner

`alln kill`, `team cancel`, and clock expiry must make the active
`RunService` turn reach WT-L2. Success is not the journal stamp.

Success is:

```text
former worker cannot mutate
AND RunService released its lane depth
AND LoopCoordinator unwound or retained only its intentional outer depth
AND the next eligible FIFO waiter can acquire
```

Cross-process cancellation remains identity checked. An unresponsive
coordinator may require process death; the kernel then closes its flock.
If the external actor already persisted a terminal run, that durable revision
wins: the returning owner must not overwrite it with stale in-memory
`running`, `complete`, or a second terminal reason.

## Simplification constraints

This phase adds one concept: **a guaranteed terminal worker turn**.

It must not add:

- PM supervision or polling;
- a daemon, service, socket, store, lock, or status envelope;
- a Git completion heuristic or commit requirement;
- a parallel worker invocation path;
- a second timeout policy;
- a metadata-only force-release API.

Reuse:

- `RunClockBudgets` / `RunClockEnforcer`;
- `WarmWorker.shutdown` / `WarmWorkerPool.shutdown(key:)`;
- `ProcessOwnership` identity-checked group termination;
- `WorkerRunOutcome`;
- `ExecutionLane.release`;
- the existing run journal as the cancellation signal.

Delete or consolidate scattered release/cancel branches when the owner-local
terminal path replaces them. A green suite with more lifecycle owners is not
closeout.

## Implementation slices

### WL-PWR-S00 — locus tests (**COMPLETE**)

Retain `WriteLockPostWorkerTests` and the S00 debug record.

### WL-PWR-S01 — terminal outcome releases owner depth

Change `RunService` so the final worker terminal:

- captures repo truth;
- releases the `RunService` token before settlement/proof;
- leaves vendor park and substitution behavior correct;
- does not alter the `LoopCoordinator` outer hold.

Acceptance:

- T-M1 green;
- T-PROOF green;
- T-PARK green;
- nested relay test shows one depth released while the outer turn remains
  valid.

### WL-PWR-S02 — guaranteed warm/cold termination

Make existing clock/cancellation paths terminate the active worker seam and
return one outcome:

- ACP result completes normally;
- Codex `turn/completed` completes normally;
- warm timeout/cancel shuts down the keyed worker and returns terminal;
- cold process exit/timeout/cancel returns terminal;
- end-of-stream without terminal remains an honest failure;
- active streamed progress is not falsely killed.

Acceptance:

- T-M2 timeout variant green;
- warm and cold cancellation tests green;
- `Idle_Stall_False_Kill` regressions green.

### WL-PWR-S03 — external cancel reaches owner

Make active `RunService` observe external terminal/cancel while its stream is
silent, invoke S02 termination, and unwind. Route kill/cancel/clock through
that owner path where the owner is alive.

Acceptance:

- T-M2 kill green;
- T-M3 green;
- next waiter acquires in under 5 seconds;
- former worker cannot write afterward;
- repeated cancel is idempotent;
- docs-only/disjoint holders remain untouched.

### WL-PWR-S04 — deslop and closeout

- remove superseded supervision language and unused recovery branches;
- run Deslop and Code Audit;
- dogfood three consecutive mutating turns;
- archive this packet and promote the worker-turn law to routed SSOT.

## Works Tests

| # | Scenario | Required result |
| --- | --- | --- |
| 1 | Standalone worker completes; settlement is artificially blocked | Next mutator acquires in under 5 seconds |
| 2 | Warm prompt never emits completion; existing clock fires | Warm session stops, outcome terminal, lane free |
| 3 | Cold worker never exits; existing clock fires | Process group stops, outcome terminal, lane free |
| 4 | External cancel during silent warm/cold turn | Owner observes cancel and next waiter acquires |
| 5 | Relay/pilot nested hold | Inner depth releases; outer turn retains retry/proof integrity |
| 6 | Harness proof | Acquires `harnessProof`; no unclaimed concurrent build |
| 7 | Vendor park/substitution | Park releases; substitution does not open an unsafe mutation gap |
| 8 | Legitimate silent work | No false kill from output silence alone |
| 9 | No-commit work order | Same terminal/release behavior; Git is not required |
| 10 | Dogfood | Three sequential mutating turns require no manual lock recovery |

## Inference bans

| Bad inference | Binding correction |
| --- | --- |
| Commit landed → worker finished | Only the worker terminal contract ends the turn |
| Report text rendered → stream terminal | Output is not terminal authority |
| Silence → worker dead | Use sourced clocks/cancel; preserve false-kill protections |
| Journal terminal → flock free | Owner release or process death frees the flock |
| Missing holder metadata → flock free | Probe/acquire the actual lane |
| PM supervision fixes lock correctness | Worker owner must terminate and release without PM judgment |

## Operator recovery until shipped

1. `alln ps --json` — identify holder, lane duration, and identity.
2. `alln kill <holder-run-id> --json`.
3. If the lane remains held after the bounded grace, terminate the recorded
   coordinator identity so the kernel releases the flock.
4. Re-dispatch and read the `alln show --stream` payload, not exit code alone.

## Closeout checklist

- [x] S00 incident locus and failing tests recorded
- [x] Founder approved root-fix direction
- [ ] Every warm/cold worker turn resolves exactly once
- [ ] Final worker terminal releases `RunService` depth before settlement
- [ ] External cancel/clock reaches the active owner
- [ ] No raw PGID kill or metadata-only force release
- [ ] No commit requirement, Git heuristic, watcher, or PM dependency
- [ ] Existing `LoopCoordinator` retry/scope/proof behavior preserved
- [ ] Works Tests 1–10 green
- [ ] Deslop + Code Audit clean
- [ ] Dogfood requires no manual lock recovery
- [ ] Durable law promoted; packet archived
