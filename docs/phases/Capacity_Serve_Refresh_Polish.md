# Capacity Serve Refresh Polish

Status: **OPEN — packet only; code unauthorized until Ready**
Owner: AllnighterEngine (`CapacityRefreshScheduler`, `ServeDaemon`,
`CapacityFetch`, `CapacityHistoryStore`; app peer `CapacityResidentService`)
Created: 2026-08-09 | Updated: 2026-08-09
Parent: [`Probe_Freshness.md`](Probe_Freshness.md) PF-S03 (SHIPPED —
`CapacityRefreshScheduler`) · supersedes Dock-only host lock per §0.2
Related: [`Capacity_Warm_Bench.md`](Capacity_Warm_Bench.md) (host lock still
stale vs §0.2 — not this packet's job)
Audits (read-only OpenCode dogfood 2026-08-09): DeepSeek V4 Pro `A655F640` ·
Qwen 3.7 Plus `5DD71ADC`

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

Ship **S01 → S02 → S03 → S04**; S05 only if profiling shows the tick IO matters.
Preserve the founder ruling and the no-lock design.

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
| Kill the Dock resident and make serve the sole producer | Out of scope; app wake / strip UX still needs the resident. Polish serve, don't delete the peer. |
| Fix by lengthening `tickInterval` alone | Masks S02 alignment; slows "app just quit" catch-up. Prefer margin + jitter. |
| Soften history merge locking / file locks for concurrent writers | Store already documents unlocked concurrent writers + heal-on-next; S03 adds attempt facts, not file locks. |
| Targeted per-seat refresh as v1 of this packet | Nice; fold into S03's "retry failed only" if natural, else defer. Full-bench remain OK for empty history. |
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
   scheduler field).
2. Pass it into `liveSnapshot(probeScope:)` (or the existing API the resident
   already uses).
3. On serve shutdown / `isCancelled`, terminate the scope before exiting the
   loop.
4. Prefer checking cancel between seat probes once S04 makes refresh async.

### Works Test

Unit: injected refresh receives a scope; cancel path calls terminate.
Manual / dogfood waiver OK if unit proves terminate is wired: start serve,
force a long fake refresh, cancel, assert terminate invoked.

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
2. Pass non-zero `jitterSeconds` on the tick sleep (suggested **±30s**);
   `PendingWakeSleeper` already accepts it.
3. Document that margin is **serve-side only** — paint/CLI freshness disclosure
   still uses `gateInterval` (invariant 3).

### Works Test

- Unit: history aged `gateInterval` but `< gateInterval + margin` → serve does
  not refresh; aged past margin → does.
- Unit: sleeper invoked with `jitterSeconds > 0`.

---

## CRS-S03 — Failed-attempt / partial-retry ledger

### Defect

`CapacityHistoryStore.record` skips windows with `unknownReason != nil`.
`newestObservation` is `max(observedAt)` over **successes only**. If 4/6 seats
succeed under load, history looks fresh and the 2 failures wait a full 30m gate.

### Fix design

1. Persist a lightweight per-source **attempt** (or failure) timestamp separate
   from successful windows — or an equivalent durable signal both processes can
   read (invariant 1).
2. `shouldRefresh` (serve) becomes true when:
   - no successful observation within the serve freshness rule (S02), **or**
   - any source has a failed/empty attempt older than a short retry window
     (suggested **5 minutes**, aligned with `tickInterval`).
3. Prefer retrying **failed sources only** when that API already exists; else
   full-bench refresh remains acceptable for v1 of this slice.
4. Do not invent capacity values for failed seats — absence stays absence;
   only the *retry schedule* changes.

### Works Test

- Unit: 4 success + 2 failure records → `shouldRefresh` true before gate
  expiry when failure attempts are stale past retry window.
- Unit: all-success fresh history → still false.
- Prove failed seats are not painted as vendor-stated facts.

---

## CRS-S04 — Async refresh + failure backoff

### Defect

`refresh` is `@Sendable () -> Void` and runs PTY work synchronously inside the
serve loop, blocking a cooperative thread shared with Pending / Boost /
backoff / notification schedulers. On probe failure there is no backoff — the
loop retries every 5m and can add load when the box is already failing probes.
`isCancelled` is only checked between ticks, so shutdown waits out an in-flight
sync probe.

Related: `CapacityFetch` `try? historyStore.record(...)` — if history cannot
be written, live windows return but history stays empty → **probe storm** every
tick. Backoff must cover "refresh ran but durable record failed."

### Fix design

1. Change `refresh` to `@Sendable () async -> Void` (update tests / injection).
2. Check `isCancelled` between seats (with S01 scope) so serve can exit promptly.
3. Track consecutive refresh failures (including record failure); exponential
   backoff **5 → 10 → 20 → 30m** (cap at gate), reset on durable success.
4. Log or surface a single non-spammy signal when history write fails (no silent
   `try?` forever without backoff).

### Works Test

- Unit: mock refresh throws / record fails → next attempt delayed per backoff.
- Unit: success resets backoff.
- Unit: cancel during async refresh terminates scope (with S01) without waiting
  full bench.

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
CRS-S01 (scope/cancel) → CRS-S02 (margin+jitter) → CRS-S03 (partial retry)
  → CRS-S04 (async+backoff) → CRS-S05 optional
```

S01 before S04 so cancel has something to terminate. S02 before relying on
serve+app coexistence under load. S03 before claiming load-sensitive benches
heal. S04 last among required — depends on async boundaries S01 wants.

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
