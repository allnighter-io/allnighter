# Capacity Serve Refresh Polish

Status: **IN FLIGHT — S02+S01+S04 SHIPPED; next S03 (S05 deferred).**
  Founder authorized 2026-08-09. Each slice: DeepSeek V4 Pro implement → host
  audit → focused proof → commit. OpenCode bugs →
  `docs/qa/opencode-mutating-commit/OPENCODE_BUG_LOG.md`.
  **CRS-S02:** `70a961bd` — margin 2m + jitter 60; audit CLEAN.
  **CRS-S01:** `5e30f3f2` — scope wiring; audit CLEAN.
  **CRS-S04:** Pro `7f16c87b` (async+backoff+historyWriteFailed) + host
  `8a0e7306` (mid-probe cancel poller Works Test). Audit: Pro deferred
  sibling poller → host fixed. SchedulerTests 21/21.
Owner: AllnighterEngine (`CapacityRefreshScheduler`, `ServeDaemon`,
`CapacityFetch`, `CapacityHistoryStore`; app peer `CapacityResidentService`)
Created: 2026-08-09 | Updated: 2026-08-09 (authorized)
Parent: [`Probe_Freshness.md`](Probe_Freshness.md) PF-S03 (SHIPPED —
`CapacityRefreshScheduler`) · supersedes Dock-only host lock per §0.2
Related: [`Capacity_Warm_Bench.md`](Capacity_Warm_Bench.md) (host lock still
stale vs §0.2 — not this packet's job)
Audits (read-only OpenCode dogfood 2026-08-09): DeepSeek V4 Pro `A655F640` ·
Qwen 3.7 Plus `5DD71ADC`
Harden pass 2026-08-09 (docs-only, no code authorized): re-verified every
citation against `CapacityRefreshScheduler.swift` / `CapacityFetch.swift` /
`CapacityHistoryStore.swift` / `CapacityResidentService.swift` /
`ServeDaemon.swift`; tightened S02 jitter spec (positive-only, matches
`DefaultPendingWakeSleeper`); sharpened S01↔S04 cancel coupling (sync refresh
cannot kill mid-probe); clarified S03↔S04 backoff interaction and the
failure-ledger concurrency rule; added two Rejected rows and two invariants.
Status is still **docs-only**: open design points named in §CRS-S03 / §CRS-S04
must be ruled before any slice goes Ready.

---

## If you only read one thing

PF-S03 re-homed automatic capacity refresh into `alln serve` so the bench
refreshes without the Dock app open. History-recency coordination (no
cross-process lock) is the right shape and stays. Dual OpenCode audits found
residuals that waste probes under load, can strand PTYs on serve shutdown, and
can leave failed seats stale for a full gate window.

| ID | Sev | Defect | Slice |
| --- | --- | --- | --- |
| **CRS-S01** | High | Serve refresh has no `CapacityProbeScope` — SIGTERM mid-probe orphans vendor PTYs | Probe scope + cancel on serve shutdown |
| **CRS-S02** | High | Serve can start a full refresh while the app's in-flight probe has not yet written history (~6s race); zero tick jitter can align the windows | Freshness margin + tick jitter |
| **CRS-S03** | High | Partial probe success marks history "fresh"; failed seats wait the full 30m gate with no retry | Failed-attempt / partial-retry ledger |
| **CRS-S04** | Med | Sync `refresh` blocks the serve `TaskGroup`; no backoff when probes already fail under load | Async refresh + failure backoff |
| **CRS-S05** | Low | `shouldRefresh` decodes all source history JSON every 5m for a boolean | O(1) freshness stamp (optional) |

Ship **S02 → S01 → S04 → S03**; S05 only if profiling shows the tick IO
matters (see §Suggested ship order for the rationale). Preserve the founder
ruling and the no-lock design.

---

## Cross-slice invariants

1. **No new arbiter.** History recency (and any new attempt ledger) remains a
   durable shared fact both the Dock resident and serve can read. Do not add a
   lease, socket lock, or "who owns refresh" process claim.
2. **Feature OFF → zero probes** from serve (CWB-S01b). Every tick still
   consults `CapacityFeatureSettingsPersistence` before refreshing.
3. **One freshness clock** — `CapacityPaintGate.gateInterval`. A serve-only
   *margin* (S02) may sit *on top of* that clock; it must not invent a second
   competing window constant that paint/CLI disagree with.
4. **Worst concurrent start is still tolerated** after S02; S02 shrinks the
   window, it does not claim to eliminate coincidence. Corruption is still
   forbidden; wasted probe under coincidence remains acceptable.
5. Capacity remains **informational** — never a run veto. This packet does not
   touch menu readiness, park/sub, or substitute policy.
6. **S03's failure ledger follows the same unlocked-writer rule as
   `CapacityHistoryStore`.** No new cross-process lock, lease, or arbiter
   (invariant 1); atomic replace + heal-on-next, exactly as window records do.
   A failed/empty attempt is a durable shared fact both processes may write.
7. **S04 backoff tracks bench-level failure, not partial-seat failure.**
   "Consecutive refresh failures" means *no successful observation was recorded
   this attempt* (full-bench probe produced nothing durable) **or** the durable
   record write itself failed. Any partial success (≥1 source recorded) resets
   the backoff; the still-failed sources are retried on S03's per-source window,
   not under S04's exponential delay. This keeps a loaded box from re-hammering
   only when nothing is getting through, without stranding a single flaky seat
   behind a 30m backoff.

---

## What's solid (do not relitigate)

- History-recency as cross-process freshness (`CapacityRefreshScheduler.swift`
  design commentary; both writers go through `CapacityFetch.liveSnapshot`).
- Feature OFF guard inside `shouldRefresh`.
- Shared `CapacityPaintGate.gateInterval`; `tickInterval` (5m) is poll cadence
  only.
- Existing scheduler unit coverage for empty / fresh / stale / boundary /
  feature-off / multi-source max (`CapacityRefreshSchedulerTests`).

---

## Rejected

| Idea | Why rejected |
| --- | --- |
| Reintroduce a Dock-only or serve-only host lock / lease | Founder ruling PF §0.2; arbiter that can drift is worse than a shared durable fact. |
| Merge serve's per-tick scope into a process-global probe kill set | Violates the CWB-S00a law — `CapacityProbeScope` exists precisely so a timeout/quit never cross-kills another in-flight acquire's PTYs. The serve scope must be one acquisition-wide scope per refresh, identical in shape to `CapacityResidentService`'s `makeScope()`. |
| Symmetric `±` tick jitter (sign-flipped earlier *and* later) | Positive-only `0…jitterSeconds` (the existing `DefaultPendingWakeSleeper.sleep` semantics in `PendingWakeScheduler.swift:13`) already dephases the serve tick from the app's 30m deadline over a few cycles; symmetric jitter needs a sleeper change for no measurable gain. Use positive-only. |
| Kill the Dock resident and make serve the sole producer | Out of scope; app wake / strip UX still needs the resident. Polish serve, don't delete the peer. |
| Lengthen `tickInterval` alone as the S02 fix | Masks S02 alignment; slows "app just quit" catch-up. Prefer margin + positive jitter (invariant 3). |
| Soften history merge locking / file locks for concurrent writers | Store already documents unlocked concurrent writers + heal-on-next; S03 adds attempt facts, not file locks. |
| Targeted per-seat refresh as v1 of this packet | Nice; fold into S03's "retry failed only" if natural, else defer. Full-bench remains OK for empty history. |
| Native-channel migration (no PTY) as the fix | Owned by [`Capacity_Native_Channels.md`](Capacity_Native_Channels.md); orthogonal. |

---

## CRS-S01 — Probe scope + cancel on serve shutdown

### Defect

Default serve refresh is `{ _ = CapacityFetch.liveSnapshot() }` with no
`probeScope` (`CapacityRefreshScheduler.swift` init). The Dock resident passes a
`CapacityProbeScope` and can `terminate()` on shutdown / supersede
(`CapacityResidentService`). Serve SIGTERM mid-refresh leaves vendor PTYs
running.

### Fix design

1. Own a `CapacityProbeScope` for the serve-hosted loop (ServeDaemon wiring or
   a new scheduler field), one fresh scope per refresh — the same shape as
   `CapacityResidentService.makeScope()` (`CapacityResidentService.swift:174`).
2. Pass it into `CapacityFetch.liveSnapshot(probeScope:)` so the probe children
   register into it (`CapacityAcquisition.windows` already threads `probeScope`
   through to `CapacityProbeRequest.scope`).
3. On serve shutdown / `isCancelled`, `terminate()` the in-flight scope before
   exiting the loop — the CWB-S00a scoped-kill law; never a global probe sweep.
4. **Honest limitation while `refresh` stays sync:** a sync `refresh()` blocks
   the loop, so `terminate()` runs only *after* the probes return — which is a
   no-op (PIDs already reaped by their owning probe). S01 alone wires the
   scope; S04 (async `refresh`) is what makes `terminate()` actually interrupt a
   probe mid-flight. Ship S01 first only as the wiring that S04 unlocks.

### Works Test

Unit: an injected refresh that owns the scope via `liveSnapshot(probeScope:)`
records into it; on cancel the loop calls `terminate()` once and the recorded
PIDs are reaped by the spy terminator. **Two phases:**
- *Wiring (S01 alone, sync refresh):* prove scope is created per refresh,
  passed through, and `terminate()` is invoked on shutdown — assert the spy
  reaper sees an empty set (probes already finished) so this proves **wiring,
  not mid-probe kill**.
- *Mid-probe kill (after S04):* injected refresh suspends on an `async` latch;
  cancel fires `terminate()` while the probe is still in flight; the spy reaper
  sees the registered PIDs and the awaiting refresh returns promptly.

Manual / dogfood waiver OK only if the unit phase above is green.

---

## CRS-S02 — Freshness margin + tick jitter

### Defect

Serve decides "stale" at exactly `gateInterval` while the app may already be
probing but has not yet recorded history (~6s in-flight window). Audits:
~2% coincidence per cycle at random phase; **100%** if a fixed 5m tick aligns
with the app's 30m deadline (`jitterSeconds: 0` today).

Double probe under load is the documented failure mode (2-of-6 seats), not
"one wasted refresh."

### Fix design

1. Serve `shouldRefresh` uses `gateInterval + margin` (suggested **2 minutes**)
   so an in-flight app refresh can commit before serve treats history as absent.
   The 2m figure matches `CapacityResidentService.acquireFloor` (120s) — once
   the app has had a full floor to land its write, serve can safely treat the
   window as unclaimed.
2. Pass non-zero `jitterSeconds` on the tick sleep (suggested **60 seconds,
   positive-only**). `DefaultPendingWakeSleeper` already implements positive
   jitter (`PendingWakeScheduler.swift:13`: `Int.random(in: 0...Int(jitterSeconds))`),
   so a 60s value delays each serve tick by 0–60s; over a 30m cycle (6 ticks)
   that drifts the catch-tick by ~3m on average and breaks the jitter=0 lockup
   within a few cycles. Make the value an injected scheduler field (default 60,
   0 in tests) so the existing `CapacityRefreshSchedulerTests` continues to
   assert deterministic ticks.
3. Document that margin is **serve-side only** — paint/CLI freshness disclosure
   still uses `gateInterval` (invariant 3). The existing
   `CapacityPaintGate.liveExpiryInterval` (45m) already extends paint grace for
   open strips; this margin serves the symmetric role for the refresh *trigger*,
   not the paint.

### Works Test

- Unit: history aged `gateInterval` but `< gateInterval + margin` → serve does
  not refresh; aged past `gateInterval + margin` → does.
- Unit: sleeper invoked with the configured `jitterSeconds` (default > 0 in
  production wiring, 0 in deterministic unit tests).
- Boundary: `gateInterval + margin` exact ⇒ refresh (consistent with the
  existing `testFreshnessBoundaryIsExactAndShared` boundary convention).

---

## CRS-S03 — Failed-attempt / partial-retry ledger

### Defect

`CapacityHistoryStore.record` skips windows with `unknownReason != nil`.
`newestObservation` is `max(observedAt)` over **successes only**. If 4/6 seats
succeed under load, history looks fresh and the 2 failures wait a full 30m gate.

### Fix design

1. Persist a lightweight per-source **attempt** (or failure) timestamp separate
   from successful windows — or an equivalent durable signal both processes can
   read (invariant 1). It must obey the same unlocked-writer rule as
   `CapacityHistoryStore` (invariant 6): atomic temp+rename, no cross-process
   lock, heal-on-next observation. One file per source (or one small envelope
   beside `Capacity/<source>.json`) keeps concurrent writers on disjoint files.
2. `shouldRefresh` (serve) becomes true when:
   - no successful observation within the serve freshness rule (S02), **or**
   - any source in `CapacityAcquisition.benchSourceOrder` has a failed/empty
     attempt older than a short retry window (suggested **5 minutes**, aligned
     with `tickInterval`). A failed attempt *newer* than the retry window is the
     backoff guard for that source — don't retry it yet.
3. Prefer retrying **failed sources only** (single-seat `liveSnapshot(refreshSource:)`)
   when that path already exists for the resident; else full-bench refresh
   remains acceptable for v1 of this slice. Note: single-seat refresh reuses the
   same `liveSnapshot` per-source path the CLI's `--refresh --source` already
   takes, so it does not add a new acquire surface.
4. Do not invent capacity values for failed seats — absence stays absence;
   only the *retry schedule* changes. `CapacityWindow.unknownReason` is preserved
   verbatim through projection; nothing in this slice paints a failed seat as a
   vendor-stated fact.
5. **Interaction with S04:** S04's backoff is bench-level (invariant 7). A
   partial refresh where some source recorded a success resets S04 backoff; the
   remaining failed sources are retried per S03's per-source window, not under
   S04's exponential delay. Only when the entire attempt produced nothing
   durable (or the record write itself failed) does S04 delay the *next whole
   attempt*, during which S03's per-source retry clocks also wait.

### Works Test

- Unit: 4 success + 2 failure records → `shouldRefresh` true before gate
  expiry when the 2 failures' attempt timestamps are stale past the retry
  window.
- Unit: 4 success + 2 failure records where the failures are *newer* than the
  retry window → `shouldRefresh` false (backoff guard holds for this turn).
- Unit: all-success fresh history → still false.
- Unit: a source present in `benchSourceOrder` with no success record *and* no
  attempt record at all → refresh (cold case, preserved).
- Prove failed seats are not painted as vendor-stated facts: a stored `unknown`
  attempt projects as an unknown, never as a window with `usedPercent` /
  `resetAt`.

---

## CRS-S04 — Async refresh + failure backoff

### Defect

`refresh` is `@Sendable () -> Void` (`CapacityRefreshScheduler.swift:44`) and
runs PTY work synchronously inside the serve loop, blocking a cooperative
thread in the shared pool that Pending / Boost / VendorBackoffReconciler /
NotificationScheduler also run on (each is its own `withTaskGroup` child task in
`ServeDaemon.run`, but the pool is shared). On probe failure there is no
backoff — the loop retries every 5m and can add load when the box is already
failing probes. `isCancelled` is only checked between ticks, so shutdown waits
out an in-flight sync probe, and a PTY orphaned mid-probe is killed only when
its own probe timeout fires — not by serve's cancel signal (CRS-S01 even with
the scope is a no-op until this slice).

Related: `CapacityFetch.liveSnapshot` does `try? historyStore.record(...)`
(`CapacityFetch.swift:78`) — if history cannot be written, live windows return
but history stays empty → **probe storm** every tick. Backoff must cover
"refresh ran but durable record failed."

### Fix design

1. Change `refresh` to `@Sendable () async -> Void` (update tests / injection).
   Note `CapacityFetch.liveSnapshot` is itself synchronous and uses a
   `DispatchGroup.wait` internally (`CapacityAcquisition.windows`); the
   async wrapper lets the serve loop `await` it cooperatively instead of
   blocking its thread, and lets `cancelAll()` actually suspend the work.
2. **Cancellation is by scope-kill, not by polling between seats.**
   `CapacityAcquisition.windows` runs probes in **parallel** via a `DispatchGroup`
   on `.global(qos: .userInitiated)`, so there is no "between seats" check.
   With S01's scope owned by the loop, on cancel call `scope.terminate()` — the
   registered probe PIDs are SIGTERM'd, their DispatchGroup entries leave, and
   `liveSnapshot` returns promptly. This is exactly the pattern
   `CapacityResidentService.requestRefresh` uses for a full-bench supersede
   (`CapacityResidentService.swift:468`).
3. Track consecutive **bench-level** refresh failures (per invariant 7): a tick
   counts as a failure iff *no* source produced a durable success observation
   this attempt, **or** the `historyStore.record` write itself threw. Any
   partial success resets the counter. Exponential backoff **5 → 10 → 20 → 30m**
   (cap at `gateInterval`), reset on any partial success.
4. Log or surface a single non-spammy signal when a history write fails — one
   line per backoff entry, not per tick. Replace silent `try?` forever without
   backoff with one audible signal that the record path is unhealthy.

### Works Test

- Unit: mock refresh throws / `historyStore.record` fails with all sources
  unknown → next attempt delayed per the 5/10/20/30 schedule and a single signal
  is emitted.
- Unit: mock refresh records a single source success → backoff **resets** even
  though other sources failed (invariant 7); S03 governs retrying the failed
  ones on its own window.
- Unit: cancel during the async refresh calls `scope.terminate()` (with S01)
  and the awaiting refresh returns without waiting for the full bench.
- Unit: a healthy refresh settles, backoff is at zero, and the loop sleeps for
  the normal `tickInterval` on the next cycle.

---

## CRS-S05 — O(1) freshness stamp (optional)

### Defect

Every 5m tick, `shouldRefresh` → `lastKnownWindows` decodes all bench source
JSON files just to take `max(observedAt)`.

### Fix design

Maintain a single durable (or actor-cached) newest-success timestamp updated
whenever `liveSnapshot` / `record` commits successes. `shouldRefresh` reads
that stamp. Keep full per-source files as SSOT for windows; stamp is derived.

### Works Test

Unit: stamp matches `max(observedAt)` after record; serve path does not need
full decode for the boolean (can assert via injection / spy).

**Defer** unless a profile shows tick cost; not on the critical dogfood path.

---

## Suggested ship order

```text
CRS-S02 (margin+jitter)  →  CRS-S01 (scope wiring)  →  CRS-S04 (async + backoff)
  → CRS-S03 (partial retry)  →  CRS-S05 optional
```

- **S02 first** — pure freshness predicate change; no cancel dependency, the
  smallest/safest slice, and the one with the loudest dogfood payoff (kills the
  30m serve/app coincidence window).
- **S01 then S04** — S01 wires the per-tick `CapacityProbeScope` but is a
  **wiring no-op until S04 ships**: with sync `refresh`, cancel runs after
  probes return. S04 makes the loop async so S01's `scope.terminate()` actually
  interrupts an in-flight probe. Ship S01 first as the field + child plumbing so
  S04 lands as the cancel + backoff behavior on top of existing wiring.
- **S03 after S04** — the partial-retry ledger's per-source retry window
  interacts with S04's bench-level backoff (invariants 6, 7); shipping S04
  first means S03's retry behavior is correct under backoff from day one
  rather than retrofitted.
- **S05 only if a profile shows tick decode cost.** Not on the dogfood path.

---

## Out of scope

- Reconciling `Capacity_Warm_Bench.md` Dock-only host lock prose (CWB owner).
- Native capacity channels / credential posture.
- Menu capacity paint, park/sub, Quota-Aware Continuity.
- LaunchAgent / login-item so serve survives reboot (PF-S03 already noted this
  as assumed, not claimed).
- Warm PTY pool / menu-bar resident.

---

## Closeout

When slices ship: promote keepable comments into code SSOT
(`CapacityRefreshScheduler` / history store), archive this packet, update
`docs/phases/README.md` + `AGENTS.md` capacity row. Do not leave living law
here.
)
