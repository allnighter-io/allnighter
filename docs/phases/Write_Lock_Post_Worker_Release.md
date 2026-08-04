# Delegated Run Supervision and Lock Recovery

Status: **OPEN — FOUNDER PIVOT after S00. Simplify; do not implement old L1/L2/L3 plan.**
Owner: AllnighterEngine (`LoopCoordinator`, `RunService`,
`ProcessOwnershipSurface`, `ExecutionLane`)
Created: 2026-08-04
Updated: 2026-08-04 (supervised-delegation simplification pivot)

Related: archived
[`Run_Lifecycle_Reliability.md`](../archive/phases/Run_Lifecycle_Reliability.md)
(RLR-L3 phases, RLR-L5 kill settlement) ·
[`One_Run_Surface.md`](One_Run_Surface.md) (attention-required stream exit;
known follow-up on killed-run lane deadlock) · code SSOT `RunService.swift`,
`ExecutionLane.swift`, `ExecutionLaneFlock.swift`,
`ProcessOwnershipSurface.swift`, `RunClockEnforcer.swift`,
`KillSettlement.swift`

## Founder intent

Delegation is not fire-and-forget. The PM that delegates a run owns two jobs:

1. delegate;
2. supervise that child until it settles or needs a PM decision.

The PM must be woken automatically from durable facts. The founder must not
have to press the PM to notice that commits landed, progress stopped, a lane is
still held, or another AI is blocked.

This packet must **simplify** the control plane. Useful existing instruments
stay. Machinery that duplicates truth, cannot recover the floor, or only asks
the caller to check again must be removed or routed to one owner. A watcher
that becomes another service, store, lifecycle, or status contract is a
rejection, not an implementation.

## Product value

Allnighter is an AI control loop. An AI PM that delegates and then receives no
automatic reason to think again is not controlling the loop. Multi-slice work
becomes an outage when the next AI sits in `waitingForWriteLock` for tens of
minutes while the parent PM is dormant and the child is observably stale.

## Binding product laws (target)

```text
Delegate implies supervise: the parent coordinator owns the child until
terminal settlement or an explicit PM decision.

Observation is deterministic and token-free. AI reasoning wakes only on a
material state transition or sourced anomaly.

One observation, one supervisor loop, one authoritative revoke.

Revoke means the former mutator cannot edit and the OS flock is free. Journal
or holder metadata alone is not revocation.

Git is supplementary work evidence. A commit is neither required nor treated
as terminal.

Failure, timeout, or PM intervention must not retain the lane indefinitely.
```

### Binding simplification rule

This phase is **replacement work, not additive work**:

- no new daemon, resident service, socket, lock, store, durable lifecycle, or
  parallel JSON contract;
- no second Git/process/token observer;
- no periodic PM model calls;
- no prompt-only supervision or release semantics;
- the existing `LoopCoordinator` remains the parent owner;
- the existing run journal / `alln show` observation and process/lane facts
  remain truth;
- kill, cancel, timeout, and PM intervention converge on one revoke operation;
- each new branch must delete or route away an independent old decision path;
- closeout includes a before/after concept inventory. If the number of truth
  owners or recovery paths grows, the phase fails even if tests are green.

## Incident classification

| Field | Value |
| --- | --- |
| Severity (outage) | **T3** if multi-slice mutating FIFO is blocked ≥ ~15m with no active mutation — dogfood 2026-08-04 supports this |
| Diagnosis confidence | **Medium (post-S00)** — locus proven; Studio = M2 primary, M1+M3 compounding |

### S00 locus decision (2026-08-04)

Full record: [`docs/debuglog/WL_PWR_S00_Locus.md`](../debuglog/WL_PWR_S00_Locus.md)

```text
Studio primary: M2 (cursor_agent stream never terminal — run 641A3C68, commits landed, no repoDelta)
Hermetic proof: T-M1 FAIL (M1), T-M2 kill FAIL (M3), T-M3 FAIL (M3), T-M2 hang PASS, T-PARK/T-PROOF PASS
Founder pivot: preserve this evidence; replace the mechanism-first L1/L2/L3
plan with parent supervision + one authoritative revoke.
```
| Work posture | **Simplification design first; no old L1/L2/L3 implementation** |

### Evidence — 2026-08-04 (`Ikiro.Studio`)

| Slice | Run id | Symptom | Git / work truth | Journal truth |
| --- | --- | --- | --- | --- |
| B | (prior) | ~40m silence after commit `e2476cc1` | Installer landed | Coordinator `running`, lock held |
| C | `641A3C68` | ~19m silence after connect work | `d93bdeca`, `cf9126f5` ~10:39 PT | `cancelled`, `phase: working`, no `repoDelta`; last activity `17:41:18Z`; cleared `18:00:52Z` |
| E | `7B7BDEA9` | After manual clear | — | Acquired lane ~8s after C cleared |

**What this proves:** live coordinator + held lane after visible worker commits;
FIFO queue semantics work (`attentionRequired` / `sourcedBlocker`); manual kill
eventually unblocks.

**What this does not prove:** that a Git commit is completion, that a commit
should be required, or that a new watcher subsystem is justified.

### What is NOT broken (do not re-litigate)

- FIFO queue + `attentionRequired` stream boundary (ORS) — designed behavior;
  exit-code education stays in ORS / agent rules.
- `RunWriteLock.waitToAcquire` 30m timeout — last-resort safety valve.
- `alln team reconcile` — reaps **identity-dead** owners only; live wedged
  coordinator is correctly skipped.

## Code truth (read before changing)

| Path | Fact |
| --- | --- |
| `RunService.run` | Acquires lock before `runExecution`; releases **after** `runExecution` returns (or on park-before-return). |
| `RunService.runExecution` | Warm path: `for try await event in warm.prompt(...)` then builds `WorkerRunOutcome`. Proof optionally re-acquires under `ExecutionLaneSite.harnessProof`. Terminal persist after proof/stages. |
| `ProcessOwnershipSurface.killRun` | On verified stop: stamps terminal; `withdrawWaiter` only if `blocker != nil`. **Does not** unlock active holder flock. |
| `ExecutionLane.release` | Drops registry token, `removeHolder`, **unlocks flock**, grants waiters. |
| `ExecutionLaneFlock.removeHolder` | Metadata only. Identity-alive / foreign-flock holders are preserved (PO-F9). Empty `holder.json` + foreign flock still blocks (PO-F9 #6). |
| `KillSettlement` | Does not SIGTERM responsive `inProcess` coordinator (RLR-L5). |
| RLR-L3 | Phases exist; terminal clears phase; **no lock-lifetime rule**. |
| `LoopCoordinator` | Already owns the PM/dev round and persists `devRunId`; it already sleeps/adopts vendor-parked children. This is the supervision owner — do not add another. |
| `PilotStatusJSON` / status projection | Already exposes owner liveness, `lastProgressAt`, `silenceAgeSeconds`, stream warning, `commitsSinceBaseline`, observed usage, and `devLeg`. Reuse/consolidate; do not create another status envelope. |
| `LoopDispatch` | Already renders relay progress and status hints. Replace manual “check again” posture where supervision can own the wait. |

### Fingerprint (candidate mechanisms — pick via S00)

```text
M1 — post-worker: outcome known; hang in proof / stage / persistTerminal;
     lock still held until runExecution returns.

M2 — in-prompt: warm.prompt (or cold stream) never ends after agent commits;
     WorkerRunOutcome never exists → early release never runs.

M3 — kill/clock: journal terminal or operator kill while coordinator alive;
     OS flock remains until process death; removeHolder alone does not free lane.
```

Primary product bug may be M1, M2, M3, or a combination. Packet must not
pretend they share one lever.

## Active design — supervised delegation

### One observation

Do not invent a new snapshot. Consolidate the facts already exposed by
`alln show`, `ProcessOwnershipSurface`, `StreamLiveness`, `GitObserver`, and the
pilot status projection into one engine-owned observation consumed by the
parent coordinator:

```text
child run id and lifecycle
worker/coordinator identity alive | dead | unknown
lane state, held duration, and blocked queue
last semantic activity and silence age
baseline HEAD, current HEAD, commits since baseline
dirty/untracked file count and last observed repo change
observed usage delta when sourced; unknown when unavailable
```

Language must remain observational:

- “HEAD advanced 18 minutes ago,” not “work completed”;
- “no observed repository change for 18 minutes,” not “worker did nothing”;
- “token telemetry unavailable,” not “zero tokens”;
- “journal says running while progress is stale,” not an invented failure.

Git commits are useful evidence presented to the PM. They are not required and
do not release the lane by themselves.

### One supervisor loop

`LoopCoordinator` already owns the parent/child relationship through
`devRunId`. Extend that existing wait boundary; do not create a watcher type
with its own persistence.

Conceptual API:

```text
supervise(childRunId, now) ->
  wait(checkAgainAfter)
  wakePM(reason, observation)
  finished(run)
```

The deterministic loop samples locally without model tokens. It wakes the PM
only when:

1. the child becomes terminal;
2. stream progress is stale while the lane is held and another mutator waits;
3. commits or repo changes exist but no later progress is observed for the
   existing silence-warning bound;
4. journal, owner, and lane facts contradict one another;
5. the loop deadline or existing clock fires.

No fixed “commit means done” rule. No mandatory commit. No AI polling on a
timer. The PM receives a compact evidence packet and chooses among existing
product actions: continue waiting, revoke and advance, retry/redelegate, or
escalate a real ambiguity.

### One authoritative revoke

Supervision is useless if the PM can diagnose a zombie but cannot recover the
floor. Kill, cancel, timeout, and PM “revoke and advance” must converge on one
operation with one success criterion:

```text
former mutator cannot edit
AND lane.lock flock is free
AND next FIFO waiter can acquire
```

Journal terminality and `holder.json` cleanup are consequences, not proof.
Cross-process limits remain honest: cooperative cancel first, bounded
identity-checked process termination when necessary. Do not add a second lock
or metadata-only escape hatch.

### PM wake example

```text
Child 641A3C68 requires review.

Git: HEAD advanced 18m ago (d93bdeca, cf9126f5)
Tree: 0 dirty files; no observed repo change for 18m
Run: running / working; no semantic activity for 18m
Owner: alive
Lane: held for 19m; 1 mutating run blocked
Usage: telemetry unavailable

Recommended next action: revoke child and advance the queue.
```

The recommendation is derived from sourced facts. The PM remains the judgment
owner; supervision is deterministic plumbing.

## Rejected directions

- **Commit-required write lane:** rejected by founder 2026-08-04. Work orders
  may legitimately finish without a commit; Git remains evidence.
- **Commit → terminal/release:** rejected. A commit does not prove the worker
  cannot mutate again.
- **New watcher daemon/service:** rejected. Parent supervision belongs in
  `LoopCoordinator`.
- **Status-only watcher:** rejected. Better display without automatic PM wake
  preserves the “founder must press” defect.
- **Old L1/L2/L3 mechanism plan as active sequence:** superseded. Its S00
  evidence and tests remain useful; implementation now converges through the
  supervisor and authoritative revoke.

## Non-goals

- `attentionRequired` exit codes (ORS).
- Background `alln serve` sweeper or any new resident watcher.
- Auto-reconcile on every `ps` (RLR: `ps` never kills).
- Requiring commits or treating Git activity as terminal truth.
- Solving every vendor-specific stream hang.
- Museum / `alln gc` hygiene for ancient terminal rows.

## Slices

| Slice | Goal | Gate |
| --- | --- | --- |
| **WL-PWR-S00** | Locus proof + failing hermetic tests | **COMPLETE** — evidence retained |
| **WL-PWR-S01** | Simplification inventory + pure supervision decisions | Must reuse existing observation facts; no production polling service |
| **WL-PWR-S02** | Supervise delegated dev run inside `LoopCoordinator` | S01 proves PM wakes only on material transitions |
| **WL-PWR-S03** | Converge recovery on one authoritative revoke | Next waiter acquires; former mutator cannot edit |
| **WL-PWR-S04** | Delete/route duplicate machinery and close out | Concept count does not grow; dogfood green |

### WL-PWR-S00 — retained incident proof (**COMPLETE**)

Record: [`docs/debuglog/WL_PWR_S00_Locus.md`](../debuglog/WL_PWR_S00_Locus.md).
Existing `WriteLockPostWorkerTests` retain the three demonstrated failures:

- post-worker/proof lock retention;
- kill during an in-prompt hang does not free the lane;
- kill during post-worker settlement does not free the lane.

These tests are evidence and regression seeds. They no longer dictate the
superseded L1/L2/L3 sequence.

### WL-PWR-S01 — simplification inventory + decision seam

Before production code:

1. Inventory every existing owner of liveness, Git observation, status
   projection, clocks, kill/cancel, and flock release.
2. Name what is reused, what is routed to one owner, and what will be deleted.
3. Add a pure, hermetic supervision decision seam using existing facts.
4. Prove no PM model call occurs for ordinary `wait`.

Required decisions:

| Observation | Decision |
| --- | --- |
| Active child, recent semantic progress | `wait` |
| Terminal child | `finished` |
| Stale progress + lane held + waiter blocked | `wakePM` |
| Commit/repo delta + stale progress + lane held | `wakePM` with Git evidence, never invented completion |
| Usage unavailable | Preserve `unknown`; never emit zero |
| Journal/identity/lane contradiction | `wakePM` with exact contradiction |

**Simplification gate:** reject S01 if it needs a new durable type, service,
store, lock, or JSON envelope.

### WL-PWR-S02 — parent supervision

Extend `LoopCoordinator` at the existing delegated-dev boundary:

- persist/retain `devRunId` as today;
- sample through the S01 decision seam with the existing injected sleeper;
- ordinary samples are local and token-free;
- on `wakePM`, invoke the next PM judgment turn with the compact observation;
- on `finished`, continue the existing PM review path;
- remove manual caller polling where this loop now owns the wait.

Do not route through `alln serve`. Do not create a watcher process. Do not
poll `alln` CLI output from engine code.

### WL-PWR-S03 — one authoritative revoke

Route PM revoke, kill, cancel, and clock expiry to one recovery owner. Preserve
identity checks and FIFO safety, but delete duplicated settlement decisions as
they converge.

Acceptance:

- former worker/coordinator is quiescent or identity-checked terminated;
- build flock is unlocked, not merely absent from metadata;
- next FIFO waiter acquires in under 5 seconds;
- blocked-waiter cancellation still withdraws only that waiter;
- docs-only/disjoint holders remain untouched;
- repeated revoke is idempotent.

### WL-PWR-S04 — delete and close out

- Remove superseded/manual supervision paths; do not leave aliases.
- Produce the before/after concept inventory.
- Run Deslop and Code Audit specifically for additive control-plane machinery.
- Promote only the durable `delegate implies supervise` and simplification laws
  to routed SSOT.
- Archive this packet when dogfood and Works Tests pass.

## Works Test (closeout)

| # | Scenario | Pass |
| --- | --- | --- |
| 1 | Active delegated child with progress | Supervisor waits locally; zero PM model turns |
| 2 | Commit(s) landed, then stale stream while lane blocks next AI | PM automatically wakes with sourced Git/activity/lane facts |
| 3 | No commit, stale stream while lane blocks next AI | PM automatically wakes; no commit requirement or invented completion |
| 4 | Telemetry unavailable | PM sees `unknown`, never false zero |
| 5 | PM chooses revoke | Former mutator cannot edit; next waiter acquires &lt; 5s |
| 6 | Child settles normally | Existing PM review continues; no duplicate watcher lifecycle |
| 7 | Dogfood | Three delegated mutating slices progress without founder prompting the PM |
| 8 | Simplification | Before/after inventory has no added truth owner, recovery path, or durable lifecycle |

## Inference bans

| Junction | Bad inference | Ban | Negative test |
| --- | --- | --- | --- |
| Git commit → run terminal | “Commit means done” | Commit is supplementary evidence only; no commit requirement | supervision test with valid no-commit work |
| No repo delta → no work | “Zero files means idle” | Report only no **observed** repo change | active reasoning fixture |
| Missing usage → zero usage | “No telemetry means zero tokens” | Preserve `unknown` | non-streaming source fixture |
| Worker silent → capacity | Silence invents vendor wait | Sourced signals only | existing RLR bans |
| `attentionRequired` → failure | Exit 0 means run finished | Observer complete ≠ run terminal | ORS tests |
| `kill` → lane free via metadata | Cancelled journal / empty holder.json frees build lane | Flock unlock or process death | T-M3 |
| `team reconcile` fixes live wedge | Reconcile should kill live coordinators | Reconcile identity-dead only | existing POS tests |
| Watcher → new service | Supervision needs a daemon | Parent `LoopCoordinator` owns it | architecture-policy / concept inventory |
| PM wake → automatic kill | Suspicion proves abandonment | PM receives evidence and chooses; hard clocks remain deterministic | stale-but-active fixture |

## Operator recovery (until shipped)

1. `alln ps --json` — holder id, `lane.state == held`, identity pid.
2. `alln kill <holder-run-id> --json`.
3. If lane still held ~30s: kill coordinator pid from identity (flock releases on
   process death).
4. Re-dispatch; `alln show <id> --stream` — parse terminal /
   `attentionRequired` payload, not exit code alone.

## Open follow-ups (out of scope)

- Museum / `alln gc` for ancient terminal rows.
- Vendor-specific warm ACP turn-complete / idle-TTL.
- `alln serve` as lane holder deadlock (ORS follow-up) — only close if the
  authoritative revoke actually covers that holder shape.

## Closeout checklist

- [x] S00 locus recorded; reject/pivot decision explicit — see `docs/debuglog/WL_PWR_S00_Locus.md`
- [ ] S01 inventory names reuse, convergence, and deletion before code
- [ ] S01 adds no service/store/lock/status contract
- [ ] S02 automatically wakes PM from sourced evidence without periodic model turns
- [ ] S03 proves former mutator stopped **and** next waiter acquired
- [ ] Kill/cancel/timeout/PM recovery route to one revoke owner
- [ ] Works Tests 1–8 green
- [ ] Before/after concept inventory has not grown
- [ ] Commit-required direction remains rejected
- [ ] AGENTS one-liner if law sticks
- [ ] Archive packet
