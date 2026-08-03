# Capacity Warm Bench

Status: **OPEN — founder priority (2026-08-03). Trust first; then instant.**
Owner: AllnighterEngine (`CapacityFetch`) + AllnighterMac
(`CapacityResidentService` TBD, **Dock app only**) + AllnighterCLI
Created: 2026-08-02
Updated: 2026-08-03 (CWB-S01a resident actor + single-flight + paint gate shipped;
displayMemo retired — resident snapshot is the one launch truth)
Supersedes: archived [`Capacity_Phase1_Recovery.md`](../archive/phases/Capacity_Phase1_Recovery.md)

**Cross-doc:** Plan-time menu capacity stays **OFF** until **Resident trust gate**
(suspends QABC-S00d). Runtime park/substitute from
[`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md) **unchanged**.

Phases are ephemeral. At closeout: promote product law into help / teaching /
`Product_Vocabulary.md`; code remains SSOT; archive this packet.

---

## Spec Review Min — silent scheduler (2026-08-03)

Team: `code_spec_review_min` · run `A01CC438-65E2-4C59-8979-3B681A51AB5F` ·
**Lead call: Ready**

**Asked:** How should the silent capacity scheduler be timed and hardened so it
just works?

**Call:** One freshness constant — schedule interval = paint gate = **30 min**
fixed (v1). Before any timer ships, replace global `terminateAllActiveProbes`
with **acquisition-scoped** cancel so a timer timeout cannot kill explicit Refresh.

### Locked recommendations (accepted)

| Decision | Lean |
| --- | --- |
| Interval vs paint | **Paint = schedule = 30m fixed**; no interval picker in v1; age always shown |
| Pre-scheduler harden | **CWB-S00a** — per-acquisition probe registry; timeout kills only its generation |
| Timer primitive | One **monotonic deadline** rearmed after settle; `Task.sleep` + injectable clock; `NSWorkspace` wake; `ProcessInfo.beginActivity` (App Nap); clock jump = wake; **no catch-up burst** |
| Funnel | One `requestRefresh(reason:)` — single-flight; waiters coalesce; full supersedes targeted; **2-min floor** across triggers |
| Freshness owner | Retire `CapacityFetch.displayMemoTTL` when resident lands — **one** clock |
| Feature OFF | Scoped cancel in-flight; zero probes all triggers; socket answers **disabled**; strip Enable CTA |
| Startup (ON) | **Immediate silent** acquisition — not “unknown + click Refresh” |
| Post-run | Boolean: settlement observed **in Dock app process** ∧ ON ∧ no acquire in flight; else **cut** (schedule covers) |
| Slice split | **S01a** actor + single-flight + explicit Refresh → **S01b** timer + wake + ON/OFF |

### Rejects (accepted)

| Reject | Why |
| --- | --- |
| Interval picker 10/15/30/60 in v1 | 60m vs any fixed paint gate is absurd; ON/OFF enough |
| 30m schedule + 15m paint | Blank strip ~half of every cycle by arithmetic |
| Memo + resident as parallel freshness | Green suite over real defect |
| Socket write/RPC for post-run | Breaks read-only socket for optional feature |
| Per-seat timers | Six single-flight problems |
| “If easy” as prose | Unfalsifiable until boolean above |
| Repeating `Timer` / free sleep loop / `NSBackgroundActivityScheduler` as owner | Wrong wake/coalesce vs one rearmed deadline |
| Defer App Nap to soak | Determines the primitive — decide before build |
| Trust-gate rows that cannot fail | Bundle into named Works Tests with fail predicates |

### Contrarian (not blocking)

- **15m both** — revisit after first soak if age labels show idle glances dominate.
- **No timer, events only** — simpler; fails on idle vendor resets (strip stuck low).

### Prior Sol Doc Review (still in force)

`code_doc_review` / Sol · `13169420-…` · scheduled one-shot over warm PTY; Dock
path later locked by founder; no cache file; socket read-only; plan-time blocked;
no `alln serve` as owner. **Superseded here:** dual 30m/15m freshness → one clock;
menu-bar residency already non-goal.

---

## Final product lock

| Decision | Lock |
| --- | --- |
| **Host** | **Main Dock app only** — reason to keep Allnighter open; same process Codex needs |
| **Menu bar residency** | **Non-goal v1** |
| **Instant** | Socket on in-memory gated snapshot while app open — not live probe in 1s |
| **Background** | Silent scheduled one-shot `CapacityFetch` (six disposable PTYs) |
| **Freshness** | **One constant:** schedule interval = paint gate = **30 min** fixed (v1). Age always shown; hard-expire at that constant |
| **Settings** | Capacity **ON/OFF only** (v1) — no interval picker |
| **Post-run** | That CLI when boolean true (in-process settlement ∧ ON ∧ idle); else cut |
| **App quit** | Socket gone → CLI cold. Hard crash → next-launch reconcile (never claim sync crash cleanup) |
| **Warm PTYs** | Rejected v1 |

**One-liner:** Dock open + ON → silent 30m one-shots (+ launch/wake/Refresh/post-run)
→ socket &lt;250 ms. OFF or quit → honest cold / disabled / CTA.

---

## Effort: warm PTY vs schedule

| Path | After S00 honesty | End-to-end (incl. S00 CLI + S00a) |
| --- | ---: | ---: |
| Warm six-PTY + menu bar | ~19–31d | **~21–34d** |
| **Dock + silent schedule (now)** | ~10–15d | **~12–18d** |

S00a scoped-kill is **required** on either path (~1–2d) before a timer is safe.

---

## Product law

1. Live or absent — successful live PTY inside the **one** freshness constant.
2. PTY only, all six — no disk for display.
3. Nothing on the main thread — timer ticks never wait on probes.
4. One output contract — windows → projection → renderer.
5. One cold acquire owner — `CapacityFetch`.
6. One resident owner — `CapacityResidentService` (Dock actor).
7. Latest attempt wins per seat — failed refresh → that seat unknown.
8. Instant = delivery latency; age always honest.
9. **Silent schedule** — no modal; ticks never repaint “warming”; probe I/O off main.
10. One `requestRefresh` funnel — no second timer story.
11. Dumb routing until trust gate.
12. Runtime park/substitute untouched.

---

## Paint matrix

| Surface | Behavior |
| --- | --- |
| **Strip (ON)** | Paint if success age &lt; 30m and latest attempt not failed; else unknown |
| **Strip launch (ON)** | Immediate silent acquire; warming until first success — **not** CTA-first |
| **Strip (OFF)** | Enable CTA; no probes |
| **Wake / clock jump** | Mark stale → one `requestRefresh(.wake)` — no catch-up burst |
| **`alln capacity` (app ON + sock)** | Snapshot or `disabled` if OFF |
| **`alln capacity` (app quit)** | Cold live PTY (measured budget) |
| **Socket miss** | One try; cold; no retry loop |
| **`--source`** | Full six-row table; unprobed = `neverSampled` |
| **menu / bootstrap** | No `capacity` until trust gate |
| **Runtime failure** | `CapacityObservation` unchanged |

---

## Scheduler contract

Implementers must not invent a second timer. All capacity acquires in the Dock
app go through **`CapacityResidentService.requestRefresh(reason:)`**.

### Triggers (exhaustive)

| Reason | When |
| --- | --- |
| `.launch` | App up + feature ON → immediate silent acquire |
| `.deadline` | Monotonic deadline fired (default 30m after last **settle**) |
| `.wake` | `NSWorkspace` wake or detected clock jump |
| `.userRefresh` | Strip Refresh control |
| `.postRun(source)` | In-process run settlement for that driver (boolean gate) |
| *(socket)* | **Never** starts acquire — read-only snapshot only |

### Coalescing / single-flight

- At most **one** in-flight `CapacityFetch` generation.
- Concurrent requests wait on that generation (coalesce); do not queue a second full bench behind it.
- Full-bench request supersedes in-flight targeted seat refresh (cancel targeted generation with **scoped** kill).
- **2-minute floor** between acquire **starts** (all reasons) — prevents storming.
- Deadline **rearmed after settle** (success or fail), not after schedule fire alone.
- No catch-up burst after sleep (one wake refresh, then normal deadline).

### Timer primitive

- Own a single **next-deadline** (monotonic / injectable clock for tests).
- Wait with `Task.sleep` until deadline (or cancel on OFF / quit).
- Hold `ProcessInfo.beginActivity` (userable) around waits so **App Nap** does not delay hours.
- Observe wake; treat large wall-clock jumps as wake.
- **Reject** as schedule owner: repeating `Timer`, free-running sleep loop,
  `NSBackgroundActivityScheduler`.

### Silence

- No modal, toast, or Dock bounce on timer ticks.
- No main-actor probe I/O; no beach ball.
- Timer ticks **do not** flip strip to “warming” (only launch / explicit Refresh /
  wake may show warming).

### Feature OFF

- Cancel in-flight generation (**scoped**).
- Zero probes from every trigger.
- Socket responds **disabled** (not a stale snapshot).
- Strip: Enable CTA.
- No read of retired process memo as live %.

### Quit vs crash

| | Behavior |
| --- | --- |
| **Graceful quit** | Scoped cancel; PGID reap; unlink socket |
| **Hard kill** | No sync cleanup claim; **next launch** reconciles orphans / stale socket |

### Post-run boolean (“if easy”)

```
postRunRefreshAllowed =
  featureON
  && settlementObservedInDockAppProcess
  && !acquireInFlight
```

Else **cut** — 30m schedule + launch/wake cover it. Do **not** add socket write
RPC to reach CLI-only settlements.

---

## CWB-S00 — honesty cut

### Done

| Item | Notes |
| --- | --- |
| Six-seat PTY re-wire | Disk acquire deleted |
| `CapacityFetch` | Live-only; memo **retired at S01a** |
| Mac strip placeholders / Refresh | Scoped cancel via `CapacityProbeScope` |
| Hero binding | Tightest pool |
| **CWB-S00a** | Acquisition-scoped probe registry + cancel; quit PGID ledger; scoped-kill tests (`b464ca491e`) |

### Remaining

| Slice | Scope |
| --- | --- |
| **CWB-S00b** | CLI → live/`CapacityFetch`; omit menu capacity; delete `--cached`; six-row `--source` (coordinate `alln` rebuild) |

Codex/Grok parsers shipped (`ac65bddf`) — do not re-spike.

---

## Gaps (owned by S00a / S01)

1. Global `terminateAllActiveProbes` → **S00a DONE** scoped registry.
2. Detached cancel lie → **S00a DONE** (strip cancel now scoped).
3. Quit reap proof → graceful quit hook in S00a; **kill -9 dogfood remains** at trust gate (socket unlink is S02).
4. Dual freshness (memo vs paint) → **S01a DONE** — `CapacityFetch.displayMemo`
   retired; `CapacityResidentService` snapshot is the one launch/paint truth.
5. Cold latency honesty (budgets, not `~5s`).
6. Probe dump privacy.
7. Loud unknown / disabled / expired.
8. **GUI proof debt (pre-existing):** `CapacityStripView.swift`,
   `AllnighterMacApp.swift`, `RoutingComposer.swift` changed since the proof
   baseline (`dea7f813`) before S01a without fresh surface proof; S01a's own
   `HomeView.swift` change is waived as non-visible in `WAIVERS.manifest`. The
   capacity strip surface still owes a real `gui_proof` + watcher pass.

---

## Resident architecture (v1)

```
Dock Allnighter.app
  └─ CapacityResidentService (actor)
        ├─ requestRefresh(reason)   ← only funnel
        ├─ monotonic deadline (30m)
        ├─ wake / App Nap activity
        ├─ single-flight → CapacityFetch
        ├─ ResidentCapacitySnapshot
        └─ capacity.sock (read-only)
```

| Non-goal v1 |
| --- |
| Menu bar residency |
| Persistent warm PTY |
| On-disk cache |
| `alln serve` as owner |
| CLI forever-helper |
| Interval picker |
| Plan-time before trust gate |

---

## Failure modes

| Scenario | Behavior |
| --- | --- |
| Probe fail | Seat unknown |
| Timer + Refresh overlap | Single-flight coalesce (contract) |
| Timer timeout | Scoped kill **only that generation** |
| OFF mid-acquire | Scoped cancel; socket disabled |
| App quit | Reap + unlink |
| Socket miss | Cold once |
| Post-run not in Dock | Cut |
| App Nap | beginActivity — prove in dogfood |

---

## Implementation slices

| Slice | Scope | Est. | Gate |
| --- | --- | --- | --- |
| **CWB-S00a** | Scoped registry/cancel; quit reap basics | 1–2d | `CapacityAcquisitionScopedKill` |
| **CWB-S00b** | CLI honesty cut | 2–3d | No hydrate-as-live; no menu capacity |
| ~~**CWB-S01a**~~ ✅ Done 2026-08-03 | Resident actor + single-flight + explicit Refresh + launch paint (memo retired; no timer/socket) | 3–4d | `CapacitySingleFlight`, paint gate tests |
| **CWB-S01b** | Deadline timer + wake + ON/OFF + App Nap activity | 2–3d | `CapacityFeatureOff`, `CapacityWakeCoalesce` |
| **CWB-S02** | Socket + CLI fast/cold (**after** S00b) | 2–3d | Spy 100× p95 &lt;250 ms, zero PTYs |
| **CWB-S03** | In-process post-run only | 0.5–1d | Boolean gate tests |

---

## Ship gates

### S00a

```text
scripts/swift-test.sh --filter CapacityAcquisitionScopedKill
# two concurrent acquires; timeout of A must not reap B's probes
```

### S01a (+ shared)

```text
scripts/swift-test.sh --filter CapacitySingleFlight
scripts/swift-test.sh --filter CapacityPaintGate
# fake clock: age 29m59s paints; 30m00s → unknown; failed attempt → that seat unknown
```

### S01b

```text
scripts/swift-test.sh --filter CapacityFeatureOff
scripts/swift-test.sh --filter CapacityWakeCoalesce
```

### Resident trust gate (dogfood / lifecycle — not fakeable unit rows)

| Proof | Catches |
| --- | --- |
| Socket spy 100× p95 &lt;250 ms, zero PTYs | Read triggering probes |
| Cold fallback miss/hang/bad version | Hang / stale |
| kill -9 mid-probe → next launch empty PGID + stale sock | Orphans (graceful ≠ crash) |
| App Nap: deadline fires within tolerance while windowless | Silent schedule death |
| Live canary vs `/usage` | Parser drift |
| Soak ≥8h RSS/CPU/children/dumps | Leaks |
| Feature OFF: zero timer probes | Settings lie |
| Accuracy dogfood ledger | Trust |

---

## Truth owner

| Layer | Owner |
| --- | --- |
| Vendor I/O | `CapacityProbe` (scoped registries) |
| One-shot | `CapacityFetch` (display memo retired at S01a) |
| Schedule / freshness / socket | `CapacityResidentService` (S01a: funnel + single-flight + snapshot + paint gate; timer S01b) |
| Transport | CLI |
| Strip | `CapacityStripModel` (projection) |
| Runtime | `CapacityObservation` |

---

## Why this is enough

| Choice | Gain |
| --- | --- |
| One 30m freshness clock | No blank-by-design half-cycle |
| S00a before timer | Timer cannot kill user Refresh |
| Named scheduler contract | No second timer invention |
| Dock only + ON/OFF | Less UI; share of mind |
| Schedule not warm PTY | ~½ eng days; low idle RAM |

**Lying is never acceptable while waiting for instant.** Instant is a socket on a
30-minute-gated snapshot owned by the Dock app — with a silent scheduler that
cannot cross-kill itself.
