# Capacity Warm Bench

Status: **OPEN — founder priority (2026-08-03). Trust first; then instant.**
Owner: AllnighterEngine (`CapacityFetch`) + AllnighterMac
(`CapacityResidentService` TBD) + AllnighterCLI (`alln capacity`)
Created: 2026-08-02
Updated: 2026-08-03 (Doc Review: GPT-5.6 Sol / `code_doc_review` —
`13169420-BDF9-4E23-B48D-40DC3A25C42D`)
Supersedes: archived [`Capacity_Phase1_Recovery.md`](../archive/phases/Capacity_Phase1_Recovery.md)
(`refresh: false` default, disk-as-primary, cold PTY per request).

**Cross-doc:** Plan-time menu capacity injection stays **OFF** until the
**Resident trust gate** below is green (suspends QABC-S00d). Runtime
park/substitute from [`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md)
**unchanged**.

Phases are ephemeral. At closeout: promote product law into help / teaching /
`Product_Vocabulary.md`; code remains SSOT; archive this packet.

---

## Doc Review — GPT-5.6 Sol (2026-08-03)

Team: `code_doc_review` · seat `model_gpt_sol` · run
`13169420-BDF9-4E23-B48D-40DC3A25C42D`

**Lead call: Partial** — honesty direction and one-probe-per-CLI stand; the
appendix “six warm PTYs” resident design is **not** the first build. Simpler
rival locked below.

### Locked recommendations (accepted)

| Recommendation | Why |
| --- | --- |
| **Scheduled one-shot probes**, not persistent warm PTYs, for first resident | Reuses proven `CapacityProbe` spawn→parse→kill; avoids unproven session resync / child-death recovery |
| **`CapacityResidentService` actor** in Mac app | Sole owner of schedule, single-flight acquire, per-seat state, socket |
| **Keep `CapacityFetch`** as one-shot Engine owner | Resident schedules and caches; Engine still acquires |
| **No resident cache file** | File outlives app, races, becomes a second truth owner |
| **Socket = cross-process read only** | 250 ms deadline; miss → CLI cold path / menu omit |
| **Per-seat freshness** (not snapshot-wide) | Latest attempt authoritative; failed refresh paints unknown |
| **Hard paint gate ~10 min**; refresh ~5 min + wake + after capacity-consuming runs | 30 min process memo is too long for trust |
| **Menu bar + login default on** after trust gate | Preserve founder ruling; explainer + opt-out; do **not** ship defaults early |
| **Collapse S01 warm + S02 resident** | Background acquire needs a resident owner; no orphan warm-pool slice |
| **Plan-time still blocked** until Resident trust gate | Stale routing poisons seating |

### Explicit rejects (accepted)

- Persistent six-PTY sessions in the **first** resident release
- Disk / history fallback for painted %
- Cross-launch resident cache file
- `alln serve` or a second daemon as capacity owner
- Socket retry loops (one bounded attempt, then cold / omit)
- Snapshot-wide “ready” boolean
- Plan-time injection before trust gate
- Calling “instant” proven by `time alln capacity` alone (fast wrong = still fail)
- Silently flipping start-at-login to opt-in before trust gate (default-on stands)

### Founder / prior rulings still in force

| Decision | Ruling |
| --- | --- |
| All six seats | **PTY only** — live probe or unknown |
| Codex/Grok disk | **Deleted** from capacity display acquire |
| Live or absent | Successful live PTY sample, or unknown — never stale % |
| Dumb routing (until trust gate) | `alln menu` / bootstrap **omit** `capacity` |
| Runtime capacity | **Unchanged** — `CapacityObservation` on vendor failure |
| Nothing on main thread | Beach ball = always a bug |

---

## Verdict

**S00 honesty:** Core/Engine/Mac largely done; CLI cutover still pending (do not
rebuild installed `alln` until coordination clears).

**Resident / instant:** Packet was not ready — appendix assumed persistent warm
PTYs without proving today’s disposable probe can host them. **First resident
architecture is locked:**

> Allnighter.app periodically runs the existing six parallel **one-shot** PTY
> probes, owns the in-memory snapshot, and serves it over a local socket.
> Instant = fast delivery of a **recent live** observation — not a fake cache.

Persistent warm sessions remain a **later optimization** only if measured
refresh cost makes scheduled one-shots unacceptable.

---

## Product law

1. **Live or absent** — % only from a successful live PTY observation that still
   passes the paint gate.
2. **PTY only, all six seats** — no disk path for capacity display.
3. **Nothing on the main thread.**
4. **One output contract** — `[CapacityWindow]` → `CapacityBenchProjection` →
   `CapacityStripRenderer`.
5. **One cold acquire owner** — `CapacityFetch` (Engine).
6. **One resident owner** — `CapacityResidentService` (Mac app actor): schedule,
   single-flight, freshness, lifecycle, socket.
7. **Latest attempt wins per seat** — a failed refresh paints **unknown** for
   that seat immediately; prior success may live in diagnostics only.
8. **Instant describes delivery latency**, not observation age — always show
   honest age; hard-expire painted values (~10 min).
9. **Dumb routing until trust gate** — menu/bootstrap omit `capacity`.
10. **Runtime unchanged** — do not touch vendor park/substitute for display work.

---

## Paint matrix (single law per surface)

History store and disk logs **never** paint as live.

| Surface | When % may appear | Default | After live success |
| --- | --- | --- | --- |
| **Mac strip launch (no resident / cold)** | Never auto | Unknown + loud Refresh CTA | — |
| **Mac strip Refresh** | User taps | Spinner; off main; **single-flight** | % + honest age |
| **Mac strip (resident)** | Per-seat paint gate | Warming / unknown until fresh | % if last **success** &lt; ~10 min and latest attempt not failed |
| **Mac strip after wake** | Never keep pre-sleep paint | Mark stale → warming; one refresh | Same as resident |
| **`alln capacity` (app closed)** | Every invoke | Cold live PTY (measured p50/p95 — **not** “~5s”) | Table or unknown |
| **`alln capacity` (app + socket)** | Socket &lt; 250 ms | Resident snapshot | Same rows as strip |
| **Socket miss / hang / version mismatch** | — | Stderr note + **cold** path (CLI); no retry loop | — |
| **`alln capacity --source`** | Targeted | **Lock:** full six-row table; unprobed seats `neverSampled` (matches acquire) | Named seat live |
| **`alln menu` / bootstrap** | Never until trust gate | `capacity` key **absent** | After gate: socket-fresh only; omit if stale/unavailable |
| **Partial bench** | Per seat | Some % + some unknown/warming | Never one global “ready” |
| **Runtime run failure** | Vendor said no | `CapacityObservation` | Park/substitute/wake |

**Clarifications**
- Distinguish `lastAttemptAt` vs `lastSuccessfulObservationAt` per seat.
- Process-local 30 min memo (S00 Mac) is a **temporary** cold-path aid — resident
  path uses the shorter hard gate.
- CLI cold path has **no** memo.

---

## CWB-S00 — honesty cut (ship first)

### Already shipped: Codex + Grok cold PTY (do not re-spike)

| Asset | Location |
| --- | --- |
| Codex `/status` parser | `CodexCapacityProbe.swift` |
| Grok `/usage` parser | `GrokCapacityProbe.swift` |
| Founder fixtures | `CodexCapacityProbeTests`, `GrokCapacityProbeTests` |
| PTY plumbing | `CapacityProbe` — `/status` for codex |

Phase 1 recovery demoted them to disk; **re-wired** 2026-08-02.

### S00 status

| Item | Owner | State | Proof / note |
| --- | --- | --- | --- |
| Six-seat PTY re-wire | Core | **Done** | `probeableSources` = 6; disk acquire deleted |
| `CapacityFetch` | Engine | **Done** | Live-only acquire; memo semantics **not** resident-ready (see Gaps) |
| Mac strip launch / Refresh | Mac | **Done** | Placeholders + CTA; off-main Refresh |
| Hero binding (Fable vs primary) | Core/Mac | **Done** | Binding pool for hero/banner |
| CLI → `CapacityFetch` | CLI | **Pending** | Blocked on coordinated `alln` rebuild |
| `menuCapacity()` → omit key | CLI | **Pending** | With CLI cutover |
| Kill CLI history hydrate | CLI | **Pending** | Wire bare `alln capacity` to live / resident |
| Teaching / help / contract | CLI | **With cutover** | Not a standalone slice |
| Cancel / reap gaps | Core/Mac | **Open** | Outer `Task` cancel ≠ probe cancel; global terminate races (Sol) |

### CLI cutover (S00 remaining)

| Today (installed `alln`) | After S00 CLI |
| --- | --- |
| Bare = stale / no-spawn | Bare = cold live PTY **or** resident socket if up |
| `--refresh` | Alias of bare or removed |
| `--cached` / `--no-refresh` | Deleted — usage error |
| `--source` + `--refresh` | `--source` = live one seat; **output = full six-row table** |
| `menuCapacity()` injects | Key omitted until trust gate |

Do **not** claim cold latency as `~5s` — code budgets up to ~20s/seat (Claude ~35s)
plus group margin. Teach measured p50/p95 after dogfood.

### What S00 already deleted / still deletes

**Done:** disk acquire for display; Mac history-as-live on launch.

**Still:** CLI `refresh:false` default; `--cached`; CLI history hydrate as live;
plan-time injection; fold `CapacityDisplayAcquisition` into `CapacityFetch` for
CLI.

**Keep:** PTY parsers, fail-closed reasons, Claude `allmodels` normalization,
runtime `CapacityObservation`, TeachingSnippet verbatim table rule.

---

## Gaps (must fix before / during resident)

From Doc Review — do not ignore:

1. **Cancel lie** — `CapacityStripModel` cancels outer task; `Task.detached`
   acquire continues. Need acquisition-scoped cancel + child registry.
2. **Global `terminateAllActiveProbes`** can kill a newer refresh’s children —
   resident must be **single-flight**.
3. **App quit / orphan children** — name lifecycle hook + proof (PGID ledger).
4. **`CapacityFetch` memo** writes after every full attempt (including
   all-unknown) and uses one array `fetchedAt` — unsuitable for resident;
   per-seat success/attempt timestamps required.
5. **Cold latency honesty** — replace `~5s` with measured budgets.
6. **Probe dump privacy** — redaction / size caps / disable outside diagnostics.
7. **Unknown must be loud** — warming / expired / auth / parser distinct.

---

## Resident architecture (first release)

**Rival (locked):** scheduled one-shot six-seat probes + in-memory snapshot +
local socket. **Not** six long-lived PTY sessions.

### Components

| Piece | Responsibility |
| --- | --- |
| `CapacityFetch` | Unchanged one-shot Engine acquire |
| `CapacityResidentService` (Mac actor) | Timer / wake / post-run triggers; **one** in-flight acquire; per-seat state; paint gate; socket server |
| `ResidentCapacitySnapshot` | Envelope: protocol + contract versions, generation, service state, per-seat attempt/success times, provenance, gated rows |
| `capacity.sock` | Read-only request; owner-only dir `0700`, socket `0600`, `getpeereid` UID check; reject bad protocol; **no** token |
| Strip / menu bar UI | **Projection only** — must not own acquisition |
| CLI | Prefer socket (&lt;250 ms); else cold `CapacityFetch` |

### Lifecycle

- Start with app process (menu-bar residency enabled) — **not** `alln serve`.
- Refresh: app start, every **~5 min**, wake / clock jump, after Allnighter runs
  that may burn quota, explicit Refresh.
- Hard-expire painted success after **~10 min** per seat.
- On wake: mark all painted values stale → show warming/unknown → single refresh.
- Teardown: reap every tracked PGID; remove socket; no orphans.

### Explicit non-goals (v1 resident)

- Persistent warm PTY pool (`CapacityWarmPool` deferred)
- On-disk resident cache
- Second daemon / `alln serve` ownership
- Plan-time injection before trust gate

### Menu bar / login

Founder ruling preserved: **default on** when shipping resident, with
first-launch explainer and clear opt-out. **Do not enable defaults** until
Resident trust gate is green. Menu-bar visibility ≠ service ownership — service
is process-owned.

---

## Routing: three worlds

| Layer | Source | Until trust gate | After trust gate |
| --- | --- | --- | --- |
| **Display** | Strip / `alln capacity` | Live PTY or unknown | Resident snapshot or cold live |
| **Plan-time** | menu/bootstrap | **Off** (key absent) | Socket-fresh only; omit if bad |
| **Runtime** | Vendor on failure | **On** | Unchanged |

---

## Failure modes

| Scenario | Behavior |
| --- | --- |
| PTY / parser fail | Unknown + reason — never disk |
| Parallel cold timeout | Per-seat unknown; progress stderr; exit 0 |
| Auth / TCC / missing binary | Distinct unknown reasons; doctor surfaces class |
| Concurrent Refresh / strip / CLI | **Single-flight** coalesce; no global cross-kill |
| Cancel Refresh | Cancel **acquire + children**, not only UI task |
| App quit / kill | Reap tracked PGIDs; socket gone; CLI falls cold |
| Socket miss / hang / bad version | One attempt; CLI cold; menu omit |
| Sleep / wake | Immediate stale; one refresh |
| Partial bench | Paint per seat; never one “ready” bit |
| Parser drift | Live canary vs manual `/usage` |
| Probe dump growth | Cap / redact / disable outside diagnostics |
| Agent expects instant bare CLI | Teaching: resident ≈ instant; cold = measured budget |

---

## Implementation slices

| Slice | Scope | Gate |
| --- | --- | --- |
| **CWB-S00** | Finish CLI honesty cut + cancel/reap fixes named in Gaps | S00 ship gate |
| **CWB-S01** | `CapacityResidentService` + scheduled one-shot + strip consume | Single-flight, wake, main-actor heartbeat, no orphans |
| **CWB-S02** | `capacity.sock` + CLI fast path + cold fallback | Spy: 100 queries p95 &lt;250 ms, zero new PTYs |
| **CWB-S03** | Menu bar / login defaults + optional plan-time injection | **Resident trust gate** green |

Persistent warm PTY pool: only if S01–S02 dogfood shows refresh cost is the
bottleneck — new packet, not sneak into S01.

---

## S00 ship gate

**Acquire**
- [x] No Codex/Grok disk in `CapacityAcquisition`
- [ ] CLI never hydrates history as live
- [x] Failed probe → unknown
- [ ] Acquisition-scoped cancel + no cross-refresh terminate races

**CLI / menu**
- [ ] Bare `alln capacity` = live (or resident when up)
- [ ] `--cached` / `--no-refresh` gone
- [ ] menu/bootstrap: no `capacity` key
- [ ] `--source` → full six-row table (document + test)

**Mac**
- [x] Launch unknown / CTA
- [x] Refresh off main (improve cancel)
- [ ] Quit reap proof

**Runtime regression**
- [ ] `VendorSubstitutionPolicy` / LoopCoordinator capacity park filters

**Dogfood**
- [ ] Founder: CLI vs manual `/usage` ledger
- [ ] Founder: Mac Refresh matches CLI same session

---

## Resident trust gate (before defaults / plan-time)

| Proof | Catches |
| --- | --- |
| Socket spy: 100 queries, p95 &lt;250 ms, **zero** new PTYs | Socket triggering probes |
| Cold fallback: missing / hung / bad version socket | Silent stale or infinite wait |
| Single-flight: scheduler + strip + N CLI clients | Duplicate PTYs / cross-kill |
| Per-seat freshness: success → fail → stale → recovery | Old % masking failure |
| Sleep/wake / clock-jump fixture | Hours-old paint after wake |
| Abrupt app-kill PGID ledger | Orphans / stale socket |
| Main-actor heartbeat during max-budget six-seat acquire | Beach ball |
| Installed-app + real CLI credentials | PATH / Keychain / TCC |
| Live canary vs manual `/usage` within 60s (all six) | Parser drift |
| Soak (≥8h): bounded RSS/CPU, stable children, no dump growth | Leaks / respawn storms |
| Menu omit when stale/unavailable | Plan-time poison |
| Accuracy dogfood ledger | The actual trust target |

Fast delivery of a wrong snapshot is **failure**.

---

## Truth owner

| Layer | Owner | Lie risk |
| --- | --- | --- |
| Vendor I/O + parse | `CapacityProbe` | Wrong surface / drift |
| One-shot acquire | `CapacityFetch` | Memo as success; hydrate |
| Schedule / freshness / socket | `CapacityResidentService` | Stale paint; dual owners |
| Transport pick | CLI | Socket hang; wrong fallback |
| View projection | `CapacityStripModel` | Owning acquire; cancel lie |
| Render | `CapacityStripRenderer` | Age/pool/unknown presentation |
| Plan-time | menu/bootstrap | Stale seating (off until gate) |
| Runtime | `CapacityObservation` | Unchanged |

Code SSOT today: `CapacityFetch.swift`, `CapacityAcquisition.swift`,
`CapacityProbe.swift`, `CapacityStripModel.swift`.  
CLI resume: `AllnighterCLI.runCapacity`, `menuCapacity`.  
Next: `CapacityResidentService.swift` + `ResidentCapacitySnapshot`.

---

## Why this simplifies

| Delete / defer | Gain |
| --- | --- |
| Persistent warm PTY v1 | No session state machine; reuse working probes |
| Resident cache file | One truth owner (memory + socket) |
| Separate warm-pool slice | Resident owns background acquire |
| Stale menu routing | Agents stop seating on fake % |
| History-as-live | Live or unknown |
| Adversarial transcript sprawl | Laws folded into this packet |

**Lying is not acceptable while waiting for instant.** Instant is additive on top
of honesty — via resident **scheduled** probes, not a second truth path.
