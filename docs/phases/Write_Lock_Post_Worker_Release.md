# Write Lock Post-Worker Release

Status: **OPEN — incident reproduced twice; fix not started**
Owner: AllnighterEngine (`RunService`, `ExecutionLaneRegistry` / `ExecutionLaneFlock`,
`KillSettlement`, `ProcessOwnershipSurface`)
Created: 2026-08-04
Updated: 2026-08-04

Related: archived [`Run_Lifecycle_Reliability.md`](../archive/phases/Run_Lifecycle_Reliability.md)
(RLR-L3 phases, RLR-L5 kill settlement) · [`One_Run_Surface.md`](One_Run_Surface.md)
(attention-required stream exit; known follow-up on killed-run lane deadlock) ·
code SSOT `RunService.swift`, `ExecutionLane.swift`, `ExecutionLaneFlock.swift`,
`ProcessOwnershipSurface.swift`, `RunClockEnforcer.swift`

## Founder intent

A mutating run that has **finished editing the repo** must not block every later
mutating run on that root. Queueing behind an active worker is correct; queueing
behind a coordinator that is only settling, rendering a report, or waiting on a
warm session tail is not.

Agents already pay for parallel Teams. A zombie lane holder turns a healthy FIFO
into an hour-long outage and trains harnesses to misread `attentionRequired`
exit 0 as “done.”

## Product value

Allnighter's default mutating path (`default_chat` / `cursor_agent` warm ACP) is
the hero loop for attended bench work. When slice B or C commits, passes tests,
and goes silent for 20–40 minutes while still holding `repoWriteLock`, the product
is lying: the journal says `running` / `phase: working`, `alln ps` shows a live
coordinator, and the next slice sits in `waitingForWriteLock` until someone kills
the stuck process by hand.

## Incident classification

Tier: **T3 Critical** — core mutating path, repeated dogfood, multi-slice outage.

Bug fingerprint:

```text
mutating alln run (warm cursor_agent)
  -> worker commits / finishes visible work
  -> coordinator stays running inside RunService.runExecution
  -> write lock held until runExecution returns
  -> warm.prompt() or post-worker settlement never completes
  -> next run queues at attentionRequired / sourcedBlocker for 20–40m
  -> operator kills run; lane frees only when coordinator process exits
```

### Evidence — 2026-08-04 (`Ikiro.Studio`)

Dogfood on `~/Documents/GitHub/Ikiro.Studio` (parallel slices A–E via `alln run`).

| Slice | Run id (prefix) | Symptom | Git / work truth | Journal truth |
| --- | --- | --- | --- | --- |
| **B** | (prior session) | ~40m silence after commit `e2476cc1` | Installer landed | Coordinator `running`, lock held |
| **C** | `641A3C68` | ~19m silence after connect work | `d93bdeca`, `cf9126f5` at 10:39 AM PT | `cancelled`, `phase: working`, **no `repoDelta`**; last activity `17:41:18Z`; cleared `18:00:52Z` |
| **E** | `7B7BDEA9` | Dispatched after manual clear | — | Acquired lane `18:00:59Z` (~8s after C cleared) |

Supporting observations (same day):

- `alln show <queued-id> --stream` correctly emits
  `attentionRequired` / `sourcedBlocker` / `status: queued` — queue semantics are
  fine; harness misread exit 0 (documented in ORS; not this packet's primary fix).
- A **22-hour-old timed-out** run still visible in inventory — stale terminal cleanup
  is a separate hygiene item (`alln gc` prunes records; does not reap live lane
  holders). Track as follow-up, not WL-PWR scope.
- `One_Run_Surface.md` already notes: “Killed run deadlocks the repo write lock
  when its recorded owner is the shared `alln serve` daemon” — same family, different
  holder shape; WL-PWR-S02 must not regress that case.

### What is NOT broken (do not re-litigate)

- FIFO queueing and `attentionRequired` stream boundary (ORS-S02b2) — working as designed.
- `RunWriteLock.waitToAcquire` timeout (30m) — last-resort, not the product story.
- `alln team reconcile` — reaps **identity-dead** owners only; a live coordinator
  wedged post-worker is `ownedLive` and correctly skipped.

## Root cause

**Truth owners**

| Layer | Owner | Role |
| --- | --- | --- |
| Lane admission | `ExecutionLaneRegistry` + `ExecutionLaneFlock` | One build-class holder per canonical repo root |
| Lock lifetime in a foreground run | `RunService.run` → `runExecution` | Acquire before worker; release after full execution returns |
| Worker completion | `WorkerRunOutcome` / warm `prompt()` stream | Mutating work finishes here |
| External stop | `KillSettlement` + `ProcessOwnershipSurface.killRun` | Journal terminal; worker group signals |
| Stale holder reap | `ExecutionLaneRegistry.reconcile` | Identity-dead holders only |

**Lie-prone layer:** treating “worker committed” or “stream went quiet” as “run
terminal.” Git and the vendor CLI can finish while the coordinator still holds the
lane for proof, stage append, PM-turn write, or an open warm ACP session.

### Mechanism 1 — lock scope too wide (primary)

Today `RunService` holds `lockToken` for the **entire** `runExecution`, including
post-worker proof, `persistTerminalRun`, and plan-stage append. Release happens only
at the bottom of `run()`:

```text
runExecution(...)   // worker + proof + terminal persist
await writeLock.release(lockKey, token: lockToken)
```

For warm `cursor_agent`, the coordinator blocks on `await warm.prompt(...)` until
the ACP stream ends. The agent may commit and stop emitting events while that call
remains open. The journal stays `running` / `phase: working`; the lane stays held.

RLR-L3 already names post-worker phases (`proving`, `settling`) that should not imply
build-lane exclusivity for the full coordinator lifetime — they were never wired to
early release.

### Mechanism 2 — kill clears journal, not lane metadata (secondary)

`ProcessOwnershipSurface.killRun` withdraws FIFO **waiter** files when
`blocker != nil` (queued behind another holder). It does **not** call
`ExecutionLaneFlock.removeHolder(laneKey:id:)` for a run that was **actively
holding** the lane.

`KillSettlement` intentionally does not SIGTERM an `inProcess` coordinator (receipt,
not a PG-kill target). Killing the warm worker can leave the `alln run` process
alive inside `runExecution`, still holding the in-process token and OS flock until
the process exits.

`RunClockEnforcer.fire` withdraws waiters on terminal clock fire but likewise does
not clear an active holder entry for the firing run id.

`RunLifecycleReliabilityWorksTest` already manually calls `removeHolder` after clock
settlement — product code does not.

## Binding decision

Two coordinated changes. **Both** are required; S01 alone leaves kill/cancel gaps;
S02 alone does not fix the common “worker done, coordinator quiet” path.

### WL-PWR-L1 — release build lane when worker work ends

After the single execution worker reaches a **terminal worker outcome**
(`done` / `failed` / `timedOut` / etc.) and any in-flight mutating subprocess work
is finished, **release the repo write lock before** proof, settlement, stage append,
and `persistTerminalRun`.

- Set journal `phase` to `proving` (when `proofCommand` present) or `settling`
  (otherwise) in the same revision that clears the in-process hold, if the run is
  still non-terminal.
- Harness proof (`RunProofRunner`) **already** re-acquires the lane under
  `ExecutionLaneSite.harnessProof` — no new parallel lane system.
- Vendor park, substitution retry, and capacity branches that return early must
  continue to release the lock exactly as today (park-before-return invariant).
- Answer / read-only paths unchanged (never took the lock).

### WL-PWR-L2 — external terminal must drop lane holder metadata

When any path stamps a mutating run terminal from **outside** the holder's
`runExecution` stack — `kill`, `cancel`, `RunClockEnforcer.fire`, and explicit
`reconcile` that reaps a holder — also call
`ExecutionLaneFlock.removeHolder(laneKey: ExecutionLane.key(repoRoot:), id: runId)`
(and unlock any reconciled in-process state) so the FIFO queue can advance even if
the coordinator process is wedged.

Gate: only when the run id matches a holder entry for that root (do not strip
unrelated docs-only scoped holders per PO-S06).

## User-visible claim

```text
When the worker is done editing, the next mutating run on this repo may start —
even if Allnighter is still writing the receipt.
```

## Non-goals (this packet)

- Changing `attentionRequired` exit codes (harness education stays in ORS / agent rules).
- Background `alln serve` sweeper for stale coordinators (defer unless S01+S02 insufficient).
- Automatic `alln team reconcile` on every `ps` (RLR contract: `ps` never kills).
- Fixing warm-session hang at the vendor driver (may still happen; must not hold the lane).
- Stale terminal record GC / museum row policy (separate hygiene).

## Slices

| Slice | Goal | Touch |
| --- | --- | --- |
| **WL-PWR-S00** | Freeze repro + failing test | Hermetic two-run test: holder's worker completes; coordinator block simulates post-worker hang; second run must acquire lane without waiting for holder process exit |
| **WL-PWR-S01** | WL-PWR-L1 early release | `RunService.runExecution` / `run()` lock lifetime; phase transitions |
| **WL-PWR-S02** | WL-PWR-L2 kill/clock/reconcile holder drop | `ProcessOwnershipSurface.killRun`, `AsyncTeamService.cancel`, `RunClockEnforcer.fire`; shared helper if needed |
| **WL-PWR-S03** | Closeout | Deslop, promote one-line law to `AGENTS.md` router if needed, archive packet |

### WL-PWR-S00 — evidence + test (do first)

Deliverables:

1. One hermetic engine test that fails on current `main` and passes after S01:
   - Run A acquires lane, worker outcome `.done`, A's `runExecution` blocks on injectable gate.
   - Run B on same root must `waitToAcquire` successfully within a short bound.
2. Incident note in `docs/debuglog/` (optional) pointing at run ids above — not SSOT.

Proof:

```bash
scripts/swift-test.sh --filter WriteLockPostWorker
```

### WL-PWR-S01 — early release

Read:

- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift` (`run`, `runExecution`)
- `Packages/AllnighterCore/Sources/AllnighterEngine/ExecutionLane.swift`
- `docs/archive/phases/Run_Lifecycle_Reliability.md` § RLR-L3 (phases)

Change:

- Factor lock release to immediately after worker terminal outcome is known and
  recorded (before proof / terminal persist).
- Clear `lockToken` after release so the outer `run()` defer path stays idempotent.
- Stamp `phase` → `proving` | `settling` while journal remains non-terminal.

Do not:

- Release before worker outcome is terminal (running worker still needs the lane).
- Release on vendor park without the existing park-before-return path.

Proof: S00 test green + existing `ExecutionWriteLockTests` / `RunAcceptanceBoundaryTests` green.

### WL-PWR-S02 — external terminal drops holder

Read:

- `ProcessOwnershipSurface.swift` (`killRun`)
- `AsyncTeamService.swift` (`cancel`)
- `RunClockEnforcer.swift` (`fire`)
- `ExecutionLaneFlock.swift` (`removeHolder`)

Change:

- Shared `releaseLaneHolderIfRecorded(run:)` (name TBD) invoked from each external
  terminal path when the run was mutating and matched holder metadata.
- Extend `RunAcceptanceBoundaryTests` kill-while-holding scenario: after kill, lane
  `holder.json` empty and next waiter grantable without waiting for coordinator exit.

Proof:

```bash
scripts/swift-test.sh --filter RunAcceptanceBoundary
scripts/swift-test.sh --filter KillSettlement
scripts/swift-test.sh --filter WriteLockPostWorker
```

## Works Test (closeout)

| # | Scenario | Pass criteria |
| --- | --- | --- |
| 1 | Worker done, coordinator hung (injected) | Second mutating run acquires lane &lt; 5s |
| 2 | Active holder killed via `alln kill` | `holder.json` cleared; queued run advances |
| 3 | Proof command after early release | Proof still runs under `harnessProof` claim; journal `proofResult` populated |
| 4 | Vendor park unchanged | Parked run still releases lock before return (regression) |
| 5 | Dogfood replay | Two consecutive `alln run` mutating slices on one repo without manual kill between them when first worker finishes cleanly |

Item 5 is founder/dogfood waiver acceptable if 1–4 are green and Studio replay is
scheduled explicitly.

## Inference bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Worker commit → run terminal | `RunStore` / `TeamRun` | “Git has a commit, so the run is done” | Terminal lifecycle requires coordinator settlement path; lane may free earlier | S00: commit simulated, coordinator blocked — run still `running`, lane free |
| `attentionRequired` → failure | `alln show --stream` | “Exit 0 means the watched run finished” | Exit 0 at attention boundary is observer complete, not run terminal | Existing `OneRunSurfaceShowStreamTests` |
| `kill` → lane free | `ExecutionLaneFlock` | “Cancelled journal implies lock released” | External terminal must drop holder metadata | S02: kill holder, assert `holder.json` empty before coordinator exit |
| Early release → no proof | `RunProofRunner` | “Proof lost the lane forever” | Proof re-acquires under `harnessProof` | S01: proof runs after early release |
| Reconcile sweep | `RunStore.reconcileAll` | “`team reconcile` should fix live wedged holders” | Reconcile never kills identity-alive coordinators; this fix is in-run + kill path | `ProcessOwnershipSurfaceTests` scoped reap unchanged |

## Operator recovery (until shipped)

1. `alln ps --json` — find holder id + `lane.state == held`.
2. `alln kill <holder-run-id> --json`.
3. If lane still held after ~30s, kill coordinator pid from `identity.pid` (flock
   releases on process death).
4. Re-dispatch; attach with `alln show <id> --stream` and **parse the terminal or
   `attentionRequired` payload**, not exit code alone.

## Open follow-ups (out of scope)

- Proactive coordinator wall-clock sweep in `alln serve` for `phase: settling` runs.
- `alln gc` / museum policy for ancient terminal rows still shown in `ps --all`.
- Warm `cursor_agent` session hang after turn complete (driver/session layer).
- `alln serve` as lane holder deadlock (`One_Run_Surface.md` known follow-up).

## Closeout

When S00–S02 are green and item 5 is waived or proven:

1. Promote WL-PWR-L1/L2 one-liners into `AGENTS.md` First Routing table (run/lane row).
2. Archive this packet to `docs/archive/phases/`.
3. Remove the duplicate “killed run deadlocks lock” bullet from `One_Run_Surface.md`
   known follow-ups if fixed.
