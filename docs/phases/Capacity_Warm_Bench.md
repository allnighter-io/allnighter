# Capacity Warm Bench

Status: **OPEN — founder priority (2026-08-02). Current path is a no-go.**
Owner: AllnighterMac (`CapacityResidentService`) + AllnighterEngine
(`CapacityWarmPool`, `CapacityFetch`) + AllnighterCore (parsers,
`CapacityStripRenderer`) + AllnighterCLI (`alln capacity`)
Created: 2026-08-02
Updated: 2026-08-02 (CWB-S00: dumb routing + disk killed)
Supersedes direction in: archived
[`Capacity_Phase1_Recovery.md`](../archive/phases/Capacity_Phase1_Recovery.md)
(`refresh: false` default, disk-as-primary, cold PTY per request).
Composes with: [`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md)
(runtime vendor park/substitute **unchanged**). Plan-time menu/bootstrap capacity
from QABC-S00d is **disabled in S00**; re-enabled only from a trusted resident
cache in S01+ (see below).

Phases are ephemeral. At closeout: promote product law into help / teaching /
operations; code remains SSOT; archive this packet.

---

## Spec Review Min (2026-08-02)

**Lead call: Ready.** Start **CWB-S00** first — honest cold path before warm pool.

### Impact ledger (accepted)

| Change | Lens | Severity | Why |
| --- | --- | --- | --- |
| **CWB-S00** before warm pool | Sequencing | **blocking** | Ship trust + cleanup (menu-bar-off world) before speed |
| Warm pool = **six PTY seats** (all bench CLIs) | Premise + Proof | **blocking** | One mechanism; disk is never live |
| **Kill disk for Codex/Grok entirely** — no fallback | Premise | **blocking** | Disk without a concurrent CLI run is stale; live or **no data** |
| Menu bar **on by default** + first-launch explainer (S04+) | Delivery | material | Deferred until after S00 |
| Menu bar **off** = loud Refresh + banner (S00 ships this) | Delivery | material | Baseline contract before resident mode exists |
| `CapacityFetch` replaces `CapacityDisplayAcquisition` as acquire SSOT | Foundation | material | One acquire owner; `warmPool` param nil in S00 |
| Split **display TTL** (30 min) vs **pool idle teardown** (30 min) | Failure modes | material | S00 uses display TTL only; pool teardown in S01+ |
| **Plan-time capacity OFF** in menu/bootstrap (S00) | Premise + Delivery | **blocking** | `menuCapacity()` feeds stale `refresh:false` data; agents route on fake % — worse than no data |
| Named proof commands per slice | Proof | material | "&lt; 2s" without a command is decoration |

### Rejected (recorded)

| Finding | Lens | Rejection |
| --- | --- | --- |
| Codex/Grok disk as fallback on probe failure | Premise | **Rejected by founder.** Not trustworthy — live or unknown only |
| Codex/Grok = live disk re-read | Premise | Rejected earlier |
| Reuse `WarmWorkerPool` | Foundation | Wrong lifecycle |
| `alln serve` as socket host | Wildcard | One Mac app only |

### Founder rulings (closed)

| Decision | Ruling |
| --- | --- |
| All six seats | **PTY only** — live probe or unknown |
| Codex/Grok disk | **Deleted** from capacity acquire — not primary, not fallback |
| Live or absent | Successful live PTY sample, or seat shows unknown — never stale % |
| **CWB-S00 first** | Menu-bar-off world: cold `CapacityFetch`, loud Refresh, code cleanup |
| Menu bar on (S02+) | Warm pool + socket + fast CLI — additive on S00 |
| Menu bar | On by default when built (S04); off = S00 behavior |
| Menu bar off UX (S00) | Banner: *"Tap Refresh for live capacity"* (Settings CTA added S02) |
| **Dumb routing (S00)** | `alln menu` / `alln bootstrap` omit `capacity` — routing uses catalog only (ready/enabled/blocked) |
| Runtime capacity | **Unchanged** — `CapacityObservation` from failed runs still drives park/substitute/wake |

---

## Verdict on what ships today

**No-go.** Capacity is the killer app **if** we nail it. Right now we have not.

Recent cleanup (2026-08-02) was necessary but insufficient:

- **Good:** one adapter per source; GUI and CLI share one projection/renderer contract.
- **Still broken:** cold PTY boot, stale disk/history shortcuts, `refresh: false`,
  main-thread blocking, lying %.

---

## Phased delivery

| Phase | What ships | User experience |
| --- | --- | --- |
| **S00** (now) | Honest cold path; disk killed; **dumb routing**; code cleanup | Tap Refresh → real % or unknown; menu has no capacity block |
| **S01–S05** (later) | Warm pool, socket, menu bar, defaults | &lt; 2s when resident |

S00 is the **menu-bar-off baseline**. Everything after is additive speed.

---

## Why this simplifies (not just adds)

**User mental model after S00:**

> Tap Refresh → live capacity or unknown. No fake numbers.

**After full cutover:**

> Menu bar on = instant. Off = tap Refresh and wait.

| Today (unusable) | After S00 | After S01+ |
| --- | --- | --- |
| `refresh:false`, history hydrate, disk-primary | One `CapacityFetch` cold law | + warm pool when resident |
| Stale Codex/Grok from disk | PTY or unknown | Same, faster when warm |
| Stale plan-time capacity in menu/bootstrap | `capacity: null` — agents run `alln capacity` explicitly | Trusted resident cache only (S01+) |
| Beach ball risk | Off main actor | Same |

---

## Founder intent

**Product value:** trustworthy bench capacity — daily glance surface.
**S00 slice:** stop lying; live-on-refresh or absent; loud Refresh in Mac app;
**dumb routing** (no capacity in menu/bootstrap).
**Non-goals (S00):** warm pool, socket, menu bar settings, login item,
plan-time capacity injection.

---

## Product law (founder, 2026-08-02)

1. **Live or absent.** A seat shows a % only after a **successful live PTY
   acquire in this process**. Otherwise unknown. No exceptions.
2. **Fresh is the default.** `refresh: false` must never be the default anywhere
   user-facing capacity is shown.
3. **PTY only — all six seats.** Codex, Claude, Cursor, Grok, Kimi, Agy —
   same mechanism. **No disk path for capacity** — not primary, not fallback.
   Delete `CodexCapacityLog` / `GrokCapacityLog` from acquire; keep parsers
   only if still used by PTY capture text.
4. **Nothing on the main thread.** Acquisition always async/off-main.
5. **30-minute display gate.** Paint only if last **successful live** acquire
   for that seat was &lt; 30 minutes ago; show honest age. Older → unknown or
   "refreshing" until a new live sample lands.
6. **One output contract.** `[CapacityWindow]` → `CapacityBenchProjection` →
   `CapacityStripRenderer`.
7. **One acquire owner.** `CapacityFetch` only (`warmPool: nil` in S00).
8. **Dumb routing (S00).** `alln menu --json`, `alln menu show`, and
   `alln bootstrap --json` **omit** the `capacity` block. Seating/routing uses
   catalog truth only (`ready`, `enabled`, `blockedReason`). Capacity is
   opt-in via explicit `alln capacity` — never silently injected stale numbers.
9. **Runtime capacity unchanged.** `CapacityObservation` from vendor failures
   (rate limits, parks, substitution) is real execution signal — not strip/menu
   data. Do not touch `VendorBackoffReconciler`, `VendorSubstitutionPolicy`,
   or `LoopState.capacityPark` in S00.

---

## The system (target end state)

```
                    ┌─────────────────────────────────────┐
                    │         Allnighter.app              │
                    │  menu bar ON (S04+, default on)     │
                    │  CapacityWarmPool (6 warm PTYs)      │
                    │  capacity.sock                      │
                    └──────────────┬──────────────────────┘
                                   │
         Mac strip ────────────────┤ CapacityFetch → warm or cold
         alln capacity ───────────┘ socket if resident, else cold
```

**S00 ships the bottom of this diagram with `warmPool = nil` everywhere.**

### Option B / S00 — Menu bar off (baseline — ship first)

| Surface | Behavior |
| --- | --- |
| Mac strip | Unknown until user taps **Refresh**; cold live PTY ~4–5s; off main actor |
| Strip chrome | **Prominent Refresh** + banner: *"Tap Refresh for live capacity"* |
| `alln capacity` | Cold live PTY all six seats; progress on stderr; unknown on failure |
| `alln menu` / `alln bootstrap` | **`capacity` omitted** — dumb routing; no stale plan-time numbers |
| Warm pool / socket | **Not built** |

### Option A — Menu bar on (S01–S05)

| Surface | Behavior |
| --- | --- |
| Mac strip | Auto-refresh via warm pool; ~1s |
| `alln capacity` | Socket → warm pool → ~1s |
| Strip chrome (off toggle) | Banner: *"Want live capacity? Turn on menu bar in Settings"* |

### Option C — CLI-only, no app

Same as S00 cold path. After S03, stderr hint when resident available.

---

## What we build

### S00 (ship now)

| Piece | Responsibility |
| --- | --- |
| **`CapacityFetch`** | Acquire SSOT: `warmPool: nil` → cold `CapacityProbe` all six seats; 30 min display gate; live or unknown |
| **Kill disk acquire** | Remove Codex/Grok disk path from `CapacityAcquisition`; delete disk fallback/hydrate |
| **Kill stale paths** | `refresh:false` default, history-as-live, `CapacityDisplayAcquisition` hydrate |
| **Mac strip** | Loud Refresh; banner; off-main fetch; no % until live success |
| **`alln capacity`** | Always cold live PTY; full six-row table |
| **Dumb routing** | `menuCapacity()` returns `nil`; omit from `MenuCLI`, `runBootstrap`; no capacity on `menu show` model detail |
| **Codex/Grok PTY** | Wire into `CapacityProbe.probeableSources`; `/status` or `/usage` as needed |

`CapacityFetch` API must accept optional `warmPool` from day one so S01 plugs in
without rewrite:

```swift
CapacityFetch.windows(now:refresh:warmPool: nil)  // S00
CapacityFetch.windows(now:refresh:warmPool: pool) // S01+
```

### S01–S05 (later)

| Piece | When |
| --- | --- |
| `CapacityWarmPool` | S01 |
| `CapacityResidentService` + socket | S02–S03 |
| Menu bar settings + first-launch sheet + login item | S04 |
| Menu capacity from resident cache (trusted, &lt; 30 min) | S01+ (after warm pool writes cache) |
| Help/teaching cleanup; archive Phase 1 doc | S05 |

---

## What we delete

### CWB-S00 (ship in S00)

| Remove | Why |
| --- | --- |
| `refresh: false` as default | Stale lies |
| History hydrate painted as live | Stale lies |
| **Codex/Grok disk acquire entirely** | Not trustworthy — live or unknown |
| `CapacityAcquisition.diskOnlySources` capacity path | PTY only for display |
| `CapacityDisplayAcquisition` hydrate / snapshot as acquire owner | → `CapacityFetch` |
| Mac strip auto-paint from history on launch | Unknown until Refresh |
| **Plan-time `menuCapacity()` injection** | Stale `refresh:false` poisons agent routing |
| QABC menu capacity block (S00) | Re-enable only from resident live cache in S01+ |

### CWB-S01–S05 (later)

| Remove | When |
| --- | --- |
| Cold spawn from Mac strip when resident | S02 (warm pool) |
| `alln serve` capacity ownership | Never |

Keep: PTY parsers, probe fail-closed reasons, Claude `allmodels` normalization,
TeachingSnippet “print full table verbatim”.

---

## CLI contract

### S00

```text
alln capacity              # cold live PTY all six seats (~5s)
alln capacity --json       # same
alln capacity --source ID  # one seat, live PTY
alln capacity --refresh    # transition alias (same as bare after S00)
```

- Progress on stderr.
- Full six-row table on stdout.
- Failed seat = unknown row, not disk/history %.

### Menu / bootstrap (S00)

```text
alln menu --json           # capacity key absent or null — dumb routing
alln bootstrap --json      # same
alln menu show model:X     # no capacity on model detail
```

Agents that need quota before seating run `alln capacity` explicitly (slow but
honest in S00). Teaching: menu selection uses `ready` / `blockedReason` only.

### After S01+

Socket fast path when menu bar resident; else S00 cold behavior. Menu/bootstrap
may re-inject `capacity` **only** from resident-written cache file when
`generatedAt` &lt; 30 min and every row is from a live acquire.

---

## Routing: two capacity worlds (do not conflate)

| Layer | Source | S00 | Trust |
| --- | --- | --- | --- |
| **Display** | `alln capacity`, Mac strip | Live PTY or unknown | User/agent opt-in |
| **Plan-time** | `alln menu` / bootstrap | **Off** (`capacity: null`) | N/A — no fake routing |
| **Runtime** | Vendor failure on run | **On** (unchanged) | Real `CapacityObservation` |

QABC plan-time injection (`menuCapacity` + `refresh: false`) caused agents to
route on stale disk/history %. S00 removes that. Runtime park/substitute/wake
stays — that is the vendor telling you no, not a strip guess.

---

## Failure modes

| Scenario | S00 behavior |
| --- | --- |
| Live PTY fails for one seat | **Unknown** — never disk, never history |
| Live PTY fails for all seats | Six unknown rows; exit 0 |
| User never taps Refresh (Mac) | Strip shows unknown / empty — no stale % |
| Sample &gt; 30 min old | Unknown or "refreshing" until new live sample |
| Probe timeout | Unknown with `probeTimeout` reason |

| Scenario | S01+ behavior |
| --- | --- |
| Pool child dies | Respawn; unknown until back |
| Socket warming | CLI waits ≤2s; else cold |
| Menu bar toggled off | Tear down pool; revert to S00 |

---

## Implementation slices

| Slice | Scope | Works Test | Est. |
| --- | --- | --- | --- |
| **CWB-S00** | `CapacityFetch` cold-only; kill disk/history/`refresh:false`; six-seat PTY; **dumb routing** (`menuCapacity` nil); Mac loud Refresh + banner; CLI live cold | `CapacityFetch` + `MenuCapacityInjectionCLITests` assert `capacity` null; `CapacityStripModelTests`; no disk in acquire | **~1w** |
| **CWB-S01** | `CapacityWarmPool` (6 PTY); plug into `CapacityFetch` | `scripts/swift-test.sh --filter CapacityWarmPool` | 5–8d |
| **CWB-S02** | `CapacityResidentService`; strip auto-refresh when pool available; Settings CTA when off | `CapacityStripModelTests` | 2–3d |
| **CWB-S03** | `capacity.sock` + CLI fast path when resident | `time alln capacity` &lt; 2s with app + menu on | 2d |
| **CWB-S04** | Settings (menu bar + login, defaults on); first-launch sheet; teardown on toggle | Manual | 2d |
| **CWB-S05** | Delete remaining dead code; help/teaching; archive Phase 1 doc | Help + TeachingSnippet tests | 2–3d |

**Order:** **S00 → S01 → S02 → S03 → S04 → S05.** Do not start warm pool until S00 is green.

**Total after S00:** ~2 weeks additional for S01–S05.

---

## Success criteria

### CWB-S00 (ship gate)

- `alln capacity` never reads Codex/Grok disk for display.
- `alln capacity` never hydrates history as live.
- Failed live probe → unknown seat, not stale %.
- Mac strip: no % until user Refresh succeeds (or sample &lt; 30 min from prior live success).
- No main-thread block during fetch.
- `alln menu --json` and `alln bootstrap --json` have **no** `capacity` block (or `null`).
- `MenuCapacityInjectionCLITests` proves zero probe spawn on menu read **and** no capacity payload.
- Runtime `CapacityObservation` / vendor park / substitution **unchanged**.
- `rg` shows no `diskOnlySources` in capacity display acquire path.

### Full cutover (S01–S05)

- Menu bar on → strip and CLI **&lt; 2s**.
- Menu bar off → S00 behavior (cold, loud Refresh).
- Disk never appears as current truth anywhere.

---

## Truth owner / lie-prone layers

| Layer | Owner | Lie risk |
| --- | --- | --- |
| Acquire | `CapacityFetch` | Disk/history painted as live |
| Plan-time menu | `menuCapacity()` → **nil in S00** | Stale % steers agent routing |
| Runtime execution | `CapacityObservation` on run failure | Unchanged — trustworthy |
| Warm pool (S01+) | `CapacityWarmPool` | Dead child / stale capture |
| Resident (S02+) | `CapacityResidentService` | Socket up but pool cold |
| Render | `CapacityStripRenderer` | None if acquire is honest |

Code SSOT targets: `CapacityFetch.swift`, `AllnighterCLI.menuCapacity` (nil in S00),
`MenuCLI.swift`, `AllnighterCLI.runBootstrap`, `AllnighterCLI.runCapacity`.
