# Capacity Warm Bench

Status: **OPEN — founder priority (2026-08-03). Trust first; then instant.**
Owner: AllnighterEngine (`CapacityFetch`) + AllnighterMac
(`CapacityResidentService` TBD, **Dock app only**) + AllnighterCLI
Created: 2026-08-02
Updated: 2026-08-03 (Spec Review Min in flight — scheduler architecture)
Supersedes: archived [`Capacity_Phase1_Recovery.md`](../archive/phases/Capacity_Phase1_Recovery.md)

**Cross-doc:** Plan-time menu capacity stays **OFF** until **Resident trust gate**
(suspends QABC-S00d). Runtime park/substitute from
[`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md) **unchanged**.

Phases are ephemeral. At closeout: promote product law into help / teaching /
`Product_Vocabulary.md`; code remains SSOT; archive this packet.

---

## Final product lock (2026-08-03)

| Decision | Lock |
| --- | --- |
| **Host** | **Main Dock app only** — capacity is a reason to keep Allnighter open (share of mind). Same process Codex CLI already needs. |
| **Menu bar residency** | **Non-goal for v1** — deferred; removes MenuBarExtra dual-lifecycle |
| **Instant how** | In-memory snapshot + local socket while app is open — **not** live probe in 1s |
| **Background acquire** | **Silent schedule** of existing one-shot six-seat PTY (`CapacityFetch`) |
| **Default interval** | **30 minutes** (settings-tunable) |
| **Paint / honesty** | Always show age; hard-expire painted % at **~15 min** (schedule may be lazier than paint) |
| **Post-run** | Refresh **that CLI** when an Allnighter run on it settles — **if easy**; else skip (schedule covers) |
| **Settings** | Capacity feature ON/OFF + interval; optional start-at-login later |
| **App quit** | Socket gone → CLI cold path (honest, slow). Not a big ask if users want instant. |
| **Warm / persistent PTYs** | **Rejected for v1** — later only if dogfood proves schedule too heavy/slow |

**One-liner:** Dock app open → silent 30m one-shot probes + optional post-run seat
refresh → socket serves strip/CLI in &lt;250 ms. App closed → cold live or unknown.

### Spec Review Min — scheduler (in flight)

**Goal:** a super-simple, reliable silent scheduler that just works. Architecture
above has never had Spec Review on the **timer / single-flight / wake / settings**
surface — only Sol Doc Review on resident-vs-warm.

| Field | Value |
| --- | --- |
| Team | `code_spec_review_min` |
| Status | **In flight** — fold Lead Call here when landed |
| Focus | Scheduler simplicity + reliability (not warm PTY, not menu bar) |

---

## Effort: warm PTY vs schedule (dev-day estimates)

Estimates are calendar **focused eng days** after S00 CLI honesty is green.
Single engineer, includes tests named in trust gate — not wall-clock with
context-switch tax.

| Work | **Warm six-PTY + menu bar** (old plan) | **Dock + scheduled one-shot** (now) |
| --- | ---: | ---: |
| Persistent session pool (resync, death, idle teardown, RAM) | 6–9 | **0** (deferred) |
| Menu bar residency / dual process story | 2–4 | **0** |
| Resident service + single-flight + strip wire | 3–4 | 3–4 |
| Silent schedule + wake + settings interval | 1–2 | 1–2 |
| Post-run seat refresh (if easy) | 1 | 0.5–1 |
| `capacity.sock` + CLI fallback | 2–3 | 2–3 |
| Login / first-launch explainer | 1–2 | 0–1 (optional; Dock already open) |
| Cancel/reap/PGID + trust proofs / soak | 4–6 | 3–4 (fewer failure modes) |
| **Subtotal after S00** | **~19–31** | **~10–15** |
| S00 CLI cutover remaining (either path) | 2–3 | 2–3 |
| **Total to “instant while app open”** | **~21–34** | **~12–18** |

**Roughly half the post-honesty work** — and far less memory at idle (no six hung
CLIs). Warm PTY only earns its days if measured refresh cost after schedule ships
is still unacceptable.

---

## Doc Review — GPT-5.6 Sol (2026-08-03)

Team: `code_doc_review` · seat `model_gpt_sol` ·
`13169420-BDF9-4E23-B48D-40DC3A25C42D` · **Partial**

Accepted and still in force: scheduled one-shot over persistent warm PTYs;
`CapacityResidentService` actor; no cache file; socket read-only; per-seat
latest-attempt; plan-time blocked until trust gate; no `alln serve` as owner.

**Superseded by founder lock same day:** menu-bar default-on residency → **Dock
app only**; ~5 min schedule → **30 min silent default** with separate paint gate.

---

## Product law

1. **Live or absent** — % only from successful live PTY still inside the paint gate.
2. **PTY only, all six** — no disk for capacity display.
3. **Nothing on the main thread.**
4. **One output contract** — windows → projection → renderer.
5. **One cold acquire owner** — `CapacityFetch`.
6. **One resident owner** — `CapacityResidentService` in the **Dock app** process.
7. **Latest attempt wins per seat** — failed refresh → unknown immediately.
8. **Instant = delivery**, not observation time — always honest age.
9. **Schedule is silent only** — never user-visible “probing…” on the timer path
   (strip may show age/warming; no modal, no beach ball).
10. **Dumb routing until trust gate** — menu/bootstrap omit `capacity`.
11. **Runtime unchanged.**

---

## Paint matrix

History / disk **never** paint as live.

| Surface | When % may appear | Behavior |
| --- | --- | --- |
| **Dock strip (app open)** | Per-seat paint gate (~15 min success age) | Schedule fills snapshot silently; Refresh = loud explicit |
| **Dock strip launch** | After first successful sample this process | Else unknown + Refresh CTA |
| **After wake** | Never keep pre-sleep paint | Stale → warming → one refresh |
| **`alln capacity` (app open + sock)** | Socket &lt;250 ms | Same gated snapshot as strip |
| **`alln capacity` (app quit)** | Cold live PTY | Measured budget — not “~5s” |
| **Socket miss** | — | One try; stderr + cold; no retry loop |
| **`--source`** | Targeted probe | **Full six-row table**; others `neverSampled` |
| **menu / bootstrap** | Never until trust gate | Key absent |
| **Post-run hook** | That seat after settle | Independent of 30m timer |
| **Runtime failure** | Vendor observation | Unchanged |

---

## CWB-S00 — honesty cut

### Done

| Item | Notes |
| --- | --- |
| Six-seat PTY re-wire | `probeableSources` = 6; disk acquire deleted |
| `CapacityFetch` | Live-only Engine acquire |
| Mac strip placeholders + Refresh | Off-main; needs cancel/reap hardening |
| Hero binding | Tightest pool, not Fable-over-primary |

### Remaining (CLI — coordinate `alln` rebuild)

| Item | Notes |
| --- | --- |
| Wire CLI to `CapacityFetch` / later socket | Kill hydrate-as-live; bare = live or resident |
| Omit `menuCapacity` key | Until trust gate |
| Delete `--cached` / `--no-refresh` | Usage error |
| Teaching / contract | With cutover, not standalone slice |
| Cancel / single-flight / quit reap | Open gaps before resident soak |

Codex/Grok parsers already shipped (`ac65bddf`); do not re-spike.

---

## Gaps (before / during resident)

1. Cancel outer task ≠ cancel detached PTY — acquisition-scoped cancel + registry.
2. Global `terminateAllActiveProbes` cross-kills — **single-flight** resident.
3. App quit PGID reap + proof.
4. Per-seat `lastAttemptAt` / `lastSuccessfulObservationAt` (memo unsuitable).
5. Honest cold latency (budgets, not `~5s`).
6. Probe dump privacy caps.
7. Loud unknown / warming / expired / auth.

---

## Resident architecture (v1)

```
Dock Allnighter.app
  └─ CapacityResidentService (actor)
        ├─ silent timer (default 30m)
        ├─ wake / clock jump
        ├─ post-run seat refresh (if easy)
        ├─ explicit Refresh (user)
        ├─ single-flight → CapacityFetch (six one-shot PTYs)
        ├─ in-memory ResidentCapacitySnapshot
        └─ capacity.sock  ──►  alln capacity / strip
```

| Piece | Role |
| --- | --- |
| `CapacityFetch` | One-shot acquire (unchanged Engine) |
| `CapacityResidentService` | Schedule, single-flight, freshness, socket, quit reap |
| `ResidentCapacitySnapshot` | Versions, generation, per-seat times, gated rows |
| `capacity.sock` | `0700` dir, `0600` sock, `getpeereid`; read-only; no token |
| Strip | Projection only |
| Settings | Feature ON/OFF, interval (10/15/30/60), optional login later |

### Explicit non-goals (v1)

- Menu bar / MenuBarExtra residency
- Persistent warm PTY pool
- On-disk resident cache
- `alln serve` as capacity owner
- CLI-spawned forever helper
- Plan-time injection before trust gate

### Why Dock-only

Less is more: one process, one “keep the app open” story (Codex + capacity),
share of mind, no menu-bar dual state. Users who want instant keep the Dock app
running — not a big ask.

---

## Failure modes

| Scenario | Behavior |
| --- | --- |
| Probe / parse fail | Unknown + reason |
| Timer tick while Refresh in flight | Coalesce (single-flight) |
| App quit | Reap PGIDs; socket gone; CLI cold |
| Socket miss / bad version | Cold / omit once |
| Sleep / wake | Immediate stale; one refresh |
| Feature OFF in settings | No schedule; strip CTA; CLI cold only |
| Post-run hard | Skip; rely on schedule (must not block run teardown) |

---

## Implementation slices

| Slice | Scope | Est. | Gate |
| --- | --- | --- | --- |
| **CWB-S00** | CLI honesty + cancel/reap | 2–3d | S00 checklist |
| **CWB-S01** | `CapacityResidentService` + 30m silent schedule + strip + settings ON/OFF/interval | 4–6d | Single-flight, wake, heartbeat, no orphans |
| **CWB-S02** | Socket + CLI fast/cold | 2–3d | 100× p95 &lt;250 ms, zero PTYs on hit |
| **CWB-S03** | Post-run seat refresh (if easy) + optional login + plan-time only after gate | 1–2d | Trust gate |

**Was (warm + menu bar):** ~21–34d end-to-end after honesty.  
**Now (Dock + schedule):** ~12–18d end-to-end after honesty.

---

## S00 ship gate

- [x] No disk Codex/Grok in acquire
- [ ] CLI never hydrates history as live
- [x] Failed probe → unknown
- [ ] Acquisition-scoped cancel; no cross-refresh terminate races
- [ ] Bare `alln capacity` live or resident
- [ ] `--cached` / `--no-refresh` gone
- [ ] menu/bootstrap: no `capacity` key
- [ ] `--source` → six-row table
- [x] Launch unknown / CTA
- [ ] Quit reap proof
- [ ] VendorSubstitution / LoopCoordinator park regression filters
- [ ] Founder dogfood CLI vs `/usage` + Mac Refresh

---

## Resident trust gate

| Proof | Catches |
| --- | --- |
| Socket spy: 100 queries, p95 &lt;250 ms, **zero** new PTYs | Accidental probe on read |
| Cold fallback: missing / hung / bad version | Silent stale / hang |
| Single-flight: timer + strip + N CLI | Duplicate / cross-kill |
| Per-seat freshness fixture | Old % after failed attempt |
| Sleep/wake | Hours-old paint |
| App-kill PGID ledger | Orphans |
| Main-actor heartbeat during max acquire | Beach ball |
| Installed app + real CLI auth | PATH / Keychain / TCC |
| Live canary vs `/usage` (60s) | Parser drift |
| Soak ≥8h: RSS/CPU, child count, no dump growth | Leaks (schedule must stay quiet) |
| Feature OFF: no timer probes | Settings lie |
| Accuracy dogfood ledger | Trust target |

Fast wrong snapshot = **failure**.

---

## Truth owner

| Layer | Owner |
| --- | --- |
| Vendor I/O + parse | `CapacityProbe` |
| One-shot acquire | `CapacityFetch` |
| Schedule / freshness / socket / quit | `CapacityResidentService` (Dock) |
| Transport | CLI |
| Strip projection | `CapacityStripModel` |
| Render | `CapacityStripRenderer` |
| Runtime park | `CapacityObservation` (untouched) |

---

## Why this is enough

| Choice | Gain |
| --- | --- |
| Schedule not warm PTY | ~½ the eng days; idle RAM stays small |
| Dock not menu bar | One residency story; less UI/lifecycle |
| 30m silent + 15m paint | Lazy probes; honest display |
| Post-run if easy | Fresh after burn without hammering timer |
| App open required | Aligns with Codex; builds share of mind |

**Lying is never acceptable while waiting for instant.** Instant is a socket on a
gated snapshot owned by the Dock app — nothing fancier.
