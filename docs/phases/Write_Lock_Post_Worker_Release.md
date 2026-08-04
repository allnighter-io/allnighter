# Write Lock Post-Worker Release

Status: **OPEN — SPIKE FIRST (S00). Implementation gated on locus proof.**
Owner: AllnighterEngine (`RunService`, `ExecutionLaneRegistry` /
`ExecutionLaneFlock`, `KillSettlement`, `ProcessOwnershipSurface`)
Created: 2026-08-04
Updated: 2026-08-04 (pre-implementation skeptic revision)

Related: archived
[`Run_Lifecycle_Reliability.md`](../archive/phases/Run_Lifecycle_Reliability.md)
(RLR-L3 phases, RLR-L5 kill settlement) ·
[`One_Run_Surface.md`](One_Run_Surface.md) (attention-required stream exit;
known follow-up on killed-run lane deadlock) · code SSOT `RunService.swift`,
`ExecutionLane.swift`, `ExecutionLaneFlock.swift`,
`ProcessOwnershipSurface.swift`, `RunClockEnforcer.swift`,
`KillSettlement.swift`

## Founder intent

A mutating run that is **no longer allowed to edit the repo** must not block
the next mutating run on that root. Queueing behind an active worker (or
harness proof that mutates) is correct. Queueing behind a coordinator that is
only writing a receipt, or wedged after mutation authority ended, is not.

## Product value

Default mutating path (`default_chat` / warm ACP) is the attended bench hero
loop. Multi-slice dogfood on one root becomes an outage when the next slice
sits in `waitingForWriteLock` for tens of minutes while the prior coordinator
is silent. Operators then kill by hand and harnesses learn the wrong lesson
from `attentionRequired` exit 0 (ORS — **out of scope** here).

## Binding product law (target)

```text
Build lane = exclusive mutate authority on the canonical root.
Hold only while this run (worker and/or harnessProof for this run) may mutate.
Release when mutation authority ends — not when the coordinator process exits.
External terminal must free the OS flock (unlock or process death), not only
journal status / holder.json cosmetics.
```

RLR-L3 already names phases `proving` | `settling` for **journal visibility**.
This packet **adds** lock-lifetime coupling to those phases. That is a new law,
not “finish unfinished RLR.”

## Incident classification

| Field | Value |
| --- | --- |
| Severity (outage) | **T3** if multi-slice mutating FIFO is blocked ≥ ~15m with no active mutation — dogfood 2026-08-04 supports this |
| Diagnosis confidence | **Low–medium until S00** — hang locus not proven |
| Work posture until S00 | **Spike**, not feature implement |

### Evidence — 2026-08-04 (`Ikiro.Studio`)

| Slice | Run id | Symptom | Git / work truth | Journal truth |
| --- | --- | --- | --- | --- |
| B | (prior) | ~40m silence after commit `e2476cc1` | Installer landed | Coordinator `running`, lock held |
| C | `641A3C68` | ~19m silence after connect work | `d93bdeca`, `cf9126f5` ~10:39 PT | `cancelled`, `phase: working`, no `repoDelta`; last activity `17:41:18Z`; cleared `18:00:52Z` |
| E | `7B7BDEA9` | After manual clear | — | Acquired lane ~8s after C cleared |

**What this proves:** live coordinator + held lane after visible worker commits;
FIFO queue semantics work (`attentionRequired` / `sourcedBlocker`); manual kill
eventually unblocks.

**What this does not prove:** whether the hang is (1) inside `warm.prompt`
before `WorkerRunOutcome`, (2) post-outcome proof/settlement/persist, or
(3) clock/kill failed to reap. **Do not implement L1 until S00 names the locus.**

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

## Proposed design (gated)

### WL-PWR-L1 — early release after mutation authority ends

**Only if S00 shows M1 (or M1+M3), not pure M2.**

After the single execution worker reaches a **terminal** `WorkerRunOutcome` and
any in-flight mutating subprocess for that turn is finished:

1. Capture `repoDelta` (and any other git snapshot that must reflect *this*
   worker) **before** release.
2. Release build lane (registry token + flock unlock) in the same control path
   that would have held until `runExecution` returned.
3. Clear `lockToken` so the outer `run()` release is idempotent no-op.
4. If run still non-terminal, stamp `phase` → `proving` (when `proofCommand`
   present) or `settling` in the **same journal revision** as the conceptual
   “no longer exclusive mutator” moment (RLR-L3 atomic style).
5. Harness proof **re-acquires** under `harnessProof` (already coded).
6. Park / substitution early returns keep today’s park-before-return release.
7. Answer / read-only paths unchanged.

### WL-PWR-L2 — external terminal frees the **flock**, not only metadata

**Required regardless of L1**, but the mechanism is **not** “call
`removeHolder` and hope.”

When kill / cancel / clock stamps terminal (or verified stop) for a run that
**held** the build lane:

| Step | Requirement |
| --- | --- |
| Cooperative | Holder’s `runExecution` must observe terminal (or cancel token), call `writeLock.release` / registry `release`, exit cleanly. |
| Flock | Waiters must observe **unlocked** `lane.lock` (or dead holder process), not merely missing `holder.json`. |
| Metadata | `removeHolder` / withdraw waiter as today for blocked waiters; do not strip unrelated docs-only holders (PO-S06). |
| Unresponsive | Bounded grace then escalate coordinator kill **only** per RLR-L5 orphan/force path — document; do not invent silent PG-kill of all inProcess holders. |

S02 acceptance is: **next waiter can acquire within bound after kill**, with
holder process either unlocked or dead — not “holder.json empty while flock
still held.”

### WL-PWR-L3 — if S00 shows pure M2 (pivot)

Do **not** ship L1 as the primary fix. Pivot packet (or expand S01) to:

- cancel / abort of `warm.prompt` await on idle/wall/kill, **and/or**
- turn-complete / session hygiene so ACP prompt ends when the agent turn ends,
  **and**
- post-worker or global wall so outage is bounded.

L2 cooperative cancel still applies.

## When to REJECT early release (L1)

Reject or defer L1 if any of:

1. S00 shows hang **inside** worker stream before terminal outcome (pure M2).
2. Proof after early release cannot reliably re-acquire or races mutate
   (Works Test 3 fails with a real root cause, not flake).
3. Dogfood shows second run corrupting first run’s intended tree because warm
   session still mutates after “terminal” outcome (false terminal).
4. Implementation requires a second parallel lock system or weakens
   one-mutating-worker-per-root.
5. S00 cannot produce a hermetic failing test that fails on `main` for the
   claimed mechanism.

## Non-goals

- `attentionRequired` exit codes (ORS).
- Background `alln serve` sweeper for settling phases (defer until L1+L2 proven
  insufficient).
- Auto-reconcile on every `ps` (RLR: `ps` never kills).
- Full vendor warm-driver hang fix as the only deliverable (may be pivot L3).
- Museum / `alln gc` hygiene for ancient terminal rows.

## Slices

| Slice | Goal | Gate |
| --- | --- | --- |
| **WL-PWR-S00** | Locus proof + failing hermetic tests | **Required before S01/S02 code** |
| **WL-PWR-S01** | L1 early release (if M1) | S00 locus ∈ {M1, M1+M3}; reject list clear |
| **WL-PWR-S02** | L2 external terminal frees flock | Can start after S00 even if L1 rejected; must not be metadata-only |
| **WL-PWR-S03** | Closeout | Deslop, AGENTS router one-liner if law sticks, archive |

### WL-PWR-S00 — locus spike + tests (do first)

**Deliverables**

1. **Locus decision record** (short, in this packet or `docs/debuglog/`): for
   one reproduced hang (hermetic preferred, Studio acceptable with journal
   artifacts), classify M1 / M2 / M3 with evidence:
   - Was `WorkerRunOutcome` / answer terminal recorded before silence?
   - Was `lastActivityAt` advancing? Did idle/wall evaluate/fire?
   - After `alln kill`, did `lane.lock` flock clear before coordinator death?
2. **Hermetic tests that fail on current `main`** (filter
   `WriteLockPostWorker`):

| Test id | Setup | Pass criteria (after fix) | Falsifies |
| --- | --- | --- | --- |
| **T-M1** | Run A: worker → `.done`; injectable gate blocks post-worker path while still holding lock (today). Run B waits. | After S01: B acquires in &lt; 5s without A process exit | “Lock must span settlement” |
| **T-M2** | Run A: injectable warm stream never ends; no worker terminal. | Document: L1 must **not** claim to fix; cancel/clock must free lane or test marked pivot | “Early release fixes warm hang” |
| **T-M3** | Run A holds lane mid-worker or post-worker; external kill from **other** process. | After S02: B acquires in &lt; 5s; flock unlocked or A dead; not merely empty holder.json while flock held | “removeHolder alone frees lane” |
| **T-PROOF** | Proof command set; early release path. | Proof runs under `harnessProof`; `proofResult` set; no double exclusive build without claim | “Proof lost the lane forever” |
| **T-PARK** | Vendor park path. | Lock released before parked return (regression) | Park-before-return broken |

3. Optional Studio note with run ids above — not SSOT.

**Decision gate (end of S00)**

```text
if pure M2:
  reject L1 as primary; schedule L3 pivot (cancel/clock/warm end); still do L2
elif M1 or M1+M3:
  implement L1 + L2
elif pure M3:
  implement L2 first; L1 optional product improvement
```

Proof:

```bash
scripts/swift-test.sh --filter WriteLockPostWorker
```

### WL-PWR-S01 — early release (M1 only)

**Read:** `RunService.swift` (`run`, `runExecution`), `ExecutionLane.swift`,
RLR-L3 phase table.

**Change:** factor release to immediately after worker terminal + pre-release
git snapshot; phase → `proving`|`settling`; outer release idempotent.

**Do not:** release before worker terminal; break park-before-return; release
before capturing `repoDelta` for this worker.

**Acceptance**

- [ ] T-M1 green
- [ ] T-PROOF green
- [ ] T-PARK green
- [ ] Existing `ExecutionWriteLockTests` / relevant `RunAcceptanceBoundaryTests` green
- [ ] No second lock subsystem

### WL-PWR-S02 — external terminal frees flock

**Read:** `ProcessOwnershipSurface.killRun`, `AsyncTeamService.cancel`,
`RunClockEnforcer.fire`, `ExecutionLane.release`, `KillSettlement`.

**Change:** shared helper that is honest about cross-process limits, e.g.
`releaseLaneIfHeld(run:)` only works **in the holder process**; killer path
must (1) stamp terminal / cancel signal the holder observes, and/or
(2) after grace, escalate so process death unlocks flock. Tests must assert
**acquire success**, not only deleted `holder.json`.

**Acceptance**

- [ ] T-M3 green (B acquires without waiting for full wall timeout)
- [ ] Blocked waiter still withdrawn on kill (existing RLR-S02c behavior)
- [ ] Docs-only / disjoint holders not stripped (PO-S06)
- [ ] KillSettlement tests still pass for non-terminal partial kills (no premature
      lane free when outcome ≠ stopped, operator kill)

Proof:

```bash
scripts/swift-test.sh --filter WriteLockPostWorker
scripts/swift-test.sh --filter RunAcceptanceBoundary
scripts/swift-test.sh --filter KillSettlement
```

### WL-PWR-S03 — closeout

When acceptance green and dogfood item waived or proven: promote one-line law
to `AGENTS.md` First Routing (run/lane row); archive packet; trim ORS
follow-up bullet if L2 actually fixed serve-holder deadlock (only if proven —
do not claim).

## Works Test (closeout)

| # | Scenario | Pass |
| --- | --- | --- |
| 1 | Worker done, coordinator hung post-worker (injected) | Second mutating run acquires &lt; 5s |
| 2 | Active holder killed | Next run acquires &lt; 5s; flock not foreign-held by dead claim |
| 3 | Proof after early release | `harnessProof` claim; `proofResult` populated |
| 4 | Vendor park | Lock released before return |
| 5 | In-prompt hang (if S00 M2) | Documented pivot path green **or** explicit founder waiver |
| 6 | Dogfood | Two consecutive mutating slices without manual kill when first worker finishes cleanly — waiver OK if 1–4 green and replay scheduled |

## Inference bans

| Junction | Bad inference | Ban | Negative test |
| --- | --- | --- | --- |
| Git commit → run terminal | “Commit means done” | Terminal requires coordinator settlement; lane may free earlier | T-M1: run still `running`, lane free |
| Worker silent → capacity | Silence invents vendor wait | Sourced signals only | existing RLR bans |
| `attentionRequired` → failure | Exit 0 means run finished | Observer complete ≠ run terminal | ORS tests |
| `kill` → lane free via metadata | Cancelled journal / empty holder.json frees build lane | Flock unlock or process death | T-M3 |
| Early release → no proof | Proof cannot run | Re-acquire `harnessProof` | T-PROOF |
| `team reconcile` fixes live wedge | Reconcile should kill live coordinators | Reconcile identity-dead only | existing POS tests |
| Warm hang → L1 | ACP hang fixed by post-outcome release | S00 must show outcome exists | T-M2 |

## Operator recovery (until shipped)

1. `alln ps --json` — holder id, `lane.state == held`, identity pid.
2. `alln kill <holder-run-id> --json`.
3. If lane still held ~30s: kill coordinator pid from identity (flock releases on
   process death).
4. Re-dispatch; `alln show <id> --stream` — parse terminal /
   `attentionRequired` payload, not exit code alone.

## Open follow-ups (out of scope unless pivot)

- Serve-side sweeper for long `settling` / silent `working`.
- Museum / `alln gc` for ancient terminal rows.
- Warm ACP turn-complete / idle-TTL (likely L3 if M2).
- `alln serve` as lane holder deadlock (ORS follow-up) — only close if L2
  actually covers that holder shape.

## Closeout checklist

- [ ] S00 locus recorded; reject/pivot decision explicit
- [ ] S01 only if L1 accepted
- [ ] S02 proves acquire, not metadata
- [ ] Works Test 1–4 green; 5–6 waived or proven
- [ ] AGENTS one-liner if law sticks
- [ ] Archive packet