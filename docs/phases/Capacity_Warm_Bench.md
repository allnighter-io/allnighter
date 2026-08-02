# Capacity Warm Bench

Status: **OPEN — founder priority (2026-08-02). Current path is a no-go.**
Owner: AllnighterMac (resident host) + AllnighterCore/Engine (`CapacityFetch`,
`CapacityWarmPool`, parsers, `CapacityStripRenderer`) + AllnighterCLI
(`alln capacity`)
Created: 2026-08-02
Supersedes direction in: archived
[`Capacity_Phase1_Recovery.md`](../archive/phases/Capacity_Phase1_Recovery.md)
(`refresh: false` default, disk-as-primary, cold PTY per request).
Composes with: [`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md)
(menu/bootstrap may read a **cached** snapshot — not a second acquisition path).

Phases are ephemeral. At closeout: promote product law into help / teaching /
operations; code remains SSOT; archive this packet.

---

## Verdict on what ships today

**No-go.** Capacity is the killer app **if** we nail it. Right now we have not.

Recent cleanup (2026-08-02) was necessary but insufficient:

- **Good:** one adapter per source; GUI and CLI share
  `CapacityDisplayAcquisition.snapshot`; one projection/renderer contract.
- **Still broken:** every acquire is a **cold** PTY boot or **stale** disk/history
  shortcut. 4–5s per seat (worse in series), trust dialogs, beach balls when
  work hits the main thread, and numbers that lie when `refresh: false` or disk
  hydrate paints old truth.

Manual `/usage` in a terminal is fast because the session is **warm**. We
cold-spawn four full CLIs every time. That is the wrong architecture, not a
tuning problem.

---

## Product law (founder, 2026-08-02)

1. **Capacity must be trustworthy or absent.** Stale % is worse than unknown.
2. **Fresh is the default.** `refresh: false` must never be the default anywhere
   user-facing capacity is shown (`alln capacity`, Mac strip, agent print).
3. **Disk is backup only.** Codex/Grok on-disk logs are fast but often stale —
   never primary truth. Use only when a live probe fails, labeled honestly.
4. **Nothing on the main thread.** Acquisition is always async/off-main; UI
   never beach-balls.
5. **30-minute display gate.** Paint a sample only if last **successful** live
   acquire was &lt; 30 minutes ago; show honest age. Older → refresh before
   paint, or show unknown while refreshing.
6. **One output contract.** `[CapacityWindow]` → `CapacityBenchProjection` →
   `CapacityStripRenderer`. Parsers and table shape are shared everywhere.

---

## The system (one app, two speeds, three options)

Zoom out: **one Mac app** owns warm capacity when the user opts in. CLI is fast
**only when that resident service is active**. Otherwise CLI is honest and slow.

```
                    ┌─────────────────────────────────────┐
                    │         Allnighter.app              │
                    │  (one binary — Dock + optional      │
                    │   menu bar icon)                    │
                    │                                     │
                    │  CapacityWarmPool (4 PTY kids)      │
                    │  capacity.sock (when menu bar ON)   │
                    └──────────────┬──────────────────────┘
                                   │
         Mac strip ────────────────┤ in-process, ~1s
         alln capacity ───────────┘ socket if resident, else cold ~4–5s
```

### Option A — Menu bar **on** (hero path)

**User setting:** “Show menu bar icon” (+ recommended “Start at login”).

| Surface | Behavior |
| --- | --- |
| Mac capacity strip | In-process warm pool → ~1s |
| `alln capacity` | Connect `capacity.sock` → same pool → ~1s |
| Background | Pool stays warm; idle teardown after 30 min with no requests |

Menu bar on = **“watch my bench”** mode. Not a second app — chrome on the same
`Allnighter.app` process.

### Option B — Menu bar **off**

| Surface | Behavior |
| --- | --- |
| Mac app windows | Still work; **no** resident pool, **no** socket |
| `alln capacity` | Cold probe per request (~4–5s concurrent PTY); progress on stderr |

User chose not to stay resident. Slow is honest, not broken.

### Option C — CLI-only (no app running)

Same as Option B: `alln capacity` → cold probe. Optional message:
*“Start Allnighter with menu bar enabled for instant capacity.”*

No fake parity. Mac resident mode is the hero.

---

## What we build (minimal moving parts)

| # | Piece | Responsibility |
| --- | --- | --- |
| 1 | **`CapacityWarmPool`** | Four capacity-only PTY children in `ProbeScratch`; boot once; `/usage` on demand; idle teardown; respawn on death |
| 2 | **`CapacityFetch`** | Single entry: warm pool if available → else cold `CapacityProbe`; always attempts live; 30 min cache law for *display while revalidating* |
| 3 | **`CapacityResidentService`** | Lives in **Mac app only**: owns pool + Unix socket when menu bar setting is on |
| 4 | **Socket contract** | One RPC: `GET_CAPACITY` → JSON or pre-rendered table; 50–100ms connect timeout; fail → CLI cold path |
| 5 | **Shared tail** | Existing parsers + `CapacityStripRenderer` — unchanged contract |

**Not in scope:** second daemon, `alln serve` hosting capacity, history hydrate
as current truth, disk-as-primary, separate GUI acquisition path.

### Settings (two toggles)

1. **Start at login** — recommended for capacity users; pool ready at session start.
2. **Show menu bar icon** — enables resident mode + socket (Option A). Off = Option B.

---

## What we delete (complexity removal)

| Remove | Why |
| --- | --- |
| `refresh: false` as default for `alln capacity` | Stale lies |
| History hydrate painted as live | Stale lies |
| Disk-as-primary for Codex/Grok | Stale lies |
| Cold spawn from Mac strip | App uses warm pool |
| Mac-only `hydrateFromHistory: false` vs CLI split | One `CapacityFetch` law |
| `alln serve` capacity ownership | App owns warm |

Keep: parsers, probe fail-closed reasons, Claude `allmodels` normalization,
TeachingSnippet “print full table verbatim”, `CapacityDisplayAcquisition` as
the projection entry (rewired to call `CapacityFetch`).

---

## CLI contract (after cutover)

```text
alln capacity              # always attempts fresh; uses socket if resident (~1s)
alln capacity --json       # same
alln capacity --source ID  # one seat; still via CapacityFetch
```

- Progress on stderr when cold or revalidating.
- Full six-row table on stdout (existing agent law).
- `--refresh` may remain as an explicit “force re-probe” alias during transition,
  then retire when default is always fresh.

**Menu / bootstrap:** may read a **read-only cache file** written by the resident
service (timestamp + windows) so `alln menu` never spawns — but that cache is
**derived** from the last successful warm fetch, never a second truth path.

---

## Implementation slices (suggested)

| Slice | Scope | Proof |
| --- | --- | --- |
| **CWB-S01** | `CapacityWarmPool` + `CapacityFetch` in Engine; kill `refresh:false` default; 30 min gate | Unit: pool serves `/usage` from fixture PTY; fetch never hydrates stale history as live |
| **CWB-S02** | Mac app: resident service on menu-bar setting; strip uses in-process fetch | Mac test: strip populates off main actor; no placeholder stale % |
| **CWB-S03** | `capacity.sock` + CLI fast path when resident | Integration: app running + menu on → `alln capacity` &lt; 2s; menu off → cold |
| **CWB-S04** | Settings UI: login item + menu bar toggle; teardown on toggle off | Manual: toggle off → socket gone → CLI cold |
| **CWB-S05** | Delete dead paths; update help/teaching; archive Phase 1 recovery doc | `rg refresh:false` no user-facing default; help matches law |

---

## Success criteria

- Founder opens app (menu bar on) → strip shows six rows in **&lt; 2s** without
  main-thread block.
- `alln capacity` with app resident → **same numbers**, **&lt; 2s**.
- `alln capacity` with app quit or menu bar off → cold, **~5s**, honest progress,
  no stale history painted as live.
- No sample older than 30 minutes shown without a visible “refreshing” / unknown state.
- Zero duplicate acquisition logic between GUI and CLI.

---

## Open questions (founder)

1. **Force re-probe flag** — keep `--refresh` as alias forever, or delete after cutover?
2. **Login item default** — on by default for new installs, or opt-in?
3. **Codex/Grok in warm pool** — PTY `/usage` for all six, or disk re-read inside
   warm path only as optimization (still live attempt first)?

Default recommendation: PTY for all six in the pool (symmetry, one mechanism);
disk only on probe failure with explicit `sourceTier` / age labeling.
