# Capacity Warm Bench

Status: **OPEN — founder priority (2026-08-02). Current path is a no-go.**
Owner: AllnighterMac (`CapacityResidentService`) + AllnighterEngine
(`CapacityWarmPool`, `CapacityFetch`) + AllnighterCore (parsers,
`CapacityStripRenderer`) + AllnighterCLI (`alln capacity`)
Created: 2026-08-02
Updated: 2026-08-02 (founder ruling + Spec Review Min)
Supersedes direction in: archived
[`Capacity_Phase1_Recovery.md`](../archive/phases/Capacity_Phase1_Recovery.md)
(`refresh: false` default, disk-as-primary, cold PTY per request).
Composes with: [`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md)
(menu/bootstrap reads a **derived cache file** — never a second acquisition path).

Phases are ephemeral. At closeout: promote product law into help / teaching /
operations; code remains SSOT; archive this packet.

---

## Spec Review Min (2026-08-02)

**Lead call: Ready.** Founder closed the remaining forks (2026-08-02). Work can
start on CWB-S01.

### Impact ledger (accepted)

| Change | Lens | Severity | Why |
| --- | --- | --- | --- |
| Warm pool = **six PTY seats** (all bench CLIs) | Premise + Proof | **blocking** | Bench is six CLIs; disk re-read is **not** live — logs update only when that CLI ran. Codex/Grok get warm PTY like the other four. |
| **No disk-as-acquire** anywhere | Premise | **blocking** | Disk is backup on probe failure only, labeled with age — never primary truth |
| Menu bar **on by default** + first-launch explainer | Delivery | material | Capacity is the hero; resident mode is the product contract |
| Menu bar **off** = loud Refresh + Settings CTA banner | Delivery | material | Slow path must be visible, not silent degradation |
| Menu bar off + app open = cold strip (honest) | Failure modes | material | No hidden fast path inside the app when resident is off |
| Split **display TTL** (30 min) vs **pool idle teardown** (30 min, independent) | Failure modes | material | Same number, different jobs |
| Socket **warming** state: CLI waits ≤2s or falls back cold with stderr note | Failure modes | material | Boot window must not lose the fast path silently |
| `CapacityFetch` replaces `CapacityDisplayAcquisition` as acquire SSOT | Foundation | material | One acquire owner |
| Menu cache file: `AllnighterPaths` + `generatedAt` + refuse if &gt; 30 min | Proof + Delivery | material | QABC menu zero-spawn must not become zero-truth |
| CWB-S01 before Mac/socket work | Sequencing | material | Pool + fetch law green before resident service |
| Named proof commands per slice | Proof | material | "&lt; 2s" without a command is decoration |

### Rejected (recorded)

| Finding | Lens | Rejection |
| --- | --- | --- |
| Codex/Grok = live disk re-read in warm pool | Premise | **Rejected by founder.** Disk without a concurrent CLI run is stale. Not faster than PTY when honest. |
| Reuse `WarmWorkerPool` for capacity | Foundation | Run workers are repo-scoped and mutating-adjacent — wrong lifecycle |
| `alln serve` as socket host | Wildcard | Second host; one Mac app only |
| Login item opt-in by default | Delivery | **Rejected.** Capacity-first product; start at login **on by default** (user can disable) |
| Delete `--refresh` in v1 | Cut | Keep as transition alias; delete in CWB-S05 |

### Founder rulings (closed)

| Decision | Ruling |
| --- | --- |
| All six seats | Warm **PTY** for Codex, Claude, Cursor, Grok, Kimi, Agy — one mechanism |
| Disk | Backup only when live probe fails; never acquire path |
| Menu bar | **On by default**; first launch shows one-screen explainer (skippable) |
| Start at login | **On by default**; disable in Settings |
| Menu bar off UX | Strip stays; **prominent Refresh** + banner: *"Want live capacity? Turn on menu bar in Settings"* |

*Min tier note: proof findings above are not refuted by a second seat — treat as checklist.*

---

## Verdict on what ships today

**No-go.** Capacity is the killer app **if** we nail it. Right now we have not.

Recent cleanup (2026-08-02) was necessary but insufficient:

- **Good:** one adapter per source; GUI and CLI share one projection/renderer contract.
- **Still broken:** every acquire is a **cold** PTY boot or **stale** disk/history
  shortcut. 4–5s per seat, trust dialogs, main-thread blocking, and numbers that
  lie when `refresh: false` or disk/history hydrate paints old truth.

Manual `/usage` in a terminal is fast because the session is **warm**. We
cold-spawn full CLIs every time. That is the wrong architecture, not a tuning
problem.

---

## Why this simplifies (not just adds)

**User mental model (two modes, one sentence):**

> Menu bar on = instant capacity. Menu bar off = tap Refresh and wait, or turn
> menu bar back on.

| Today (unusable) | After cutover |
| --- | --- |
| `refresh:false` vs `--refresh` vs history hydrate vs disk-primary | One `CapacityFetch` law |
| GUI and CLI divergent trust rules | Same fetch, same numbers |
| Cold boot every request | Warm pool when resident |
| Stale disk painted as live | PTY or unknown |
| Beach ball risk | Always off main actor |

**Engineering trade:** add one subsystem (`CapacityWarmPool` + resident service);
**delete** stale-path spaghetti. Net simpler product; bounded new code (~2–3 weeks).

---

## Founder intent

**Product value:** trustworthy, fast bench capacity — the daily glance surface.
**Trusted workflow slice:** see six seats, honest ages, &lt; 2s when resident,
never beach-ball.
**Non-goals:** second daemon, `alln serve` capacity, history-as-live, disk-as-acquire,
CLI fast path when resident is off.

---

## Product law (founder, 2026-08-02)

1. **Capacity must be trustworthy or absent.** Stale % is worse than unknown.
2. **Fresh is the default.** `refresh: false` must never be the default anywhere
   user-facing capacity is shown.
3. **Live probe only.** All six seats acquire via warm or cold **PTY** (`/usage`
   or vendor equivalent). **Disk is never an acquire path** — only an honest
   backup label when a live probe fails, with age shown.
4. **Nothing on the main thread.** Acquisition is always async/off-main.
5. **30-minute display gate.** Paint only if last **successful** live acquire
   for that seat was &lt; 30 minutes ago; show honest age. Older → unknown or
   "refreshing" until a new sample lands.
6. **One output contract.** `[CapacityWindow]` → `CapacityBenchProjection` →
   `CapacityStripRenderer`.
7. **One acquire owner.** `CapacityFetch` only.

---

## The system (one app, two speeds)

**One Mac app** owns warm capacity when menu bar is on. CLI is fast **only when
that resident service is active**.

```
                    ┌─────────────────────────────────────┐
                    │         Allnighter.app              │
                    │  menu bar ON by default             │
                    │                                     │
                    │  CapacityWarmPool (6 warm PTYs)      │
                    │  capacity.sock                      │
                    └──────────────┬──────────────────────┘
                                   │
         Mac strip ────────────────┤ in-process CapacityFetch, ~1s
         alln capacity ───────────┘ socket → same fetch, else cold ~4–5s
```

### Option A — Menu bar **on** (default, hero path)

| Surface | Behavior |
| --- | --- |
| Mac capacity strip | Auto-refresh via warm pool; ~1s; age chips honest |
| `alln capacity` | Socket → same pool → ~1s |
| Background | Pool warm; idle teardown after 30 min with no requests |
| First launch | One screen: *"Allnighter watches your AI bench. Menu bar on = instant capacity."* Toggle default **on** |

Menu bar on = **"watch my bench."** Start at login **on by default** so pool is
ready before the user opens a window.

### Option B — Menu bar **off** (user opt-out)

| Surface | Behavior |
| --- | --- |
| Mac strip | **Cold** fetch per Refresh (~4–5s, off main actor) |
| Strip chrome | **Prominent Refresh** button + persistent banner: *"Want live capacity? Turn on menu bar in Settings"* |
| `alln capacity` | Cold probe; progress on stderr |
| Resident | No pool, no socket — torn down immediately when toggled off |

Slow is honest and **visible**. User chose off; the CTA explains how to get fast back.

### Option C — CLI-only (no app running)

Same as Option B. Stderr hint:
*“Start Allnighter with menu bar enabled for instant capacity.”*

---

## What we build (minimal moving parts)

| # | Piece | Responsibility |
| --- | --- | --- |
| 1 | **`CapacityWarmPool`** | Six warm PTY children (all `benchSourceOrder` seats) in `ProbeScratch`; `/usage` on demand; boot once; idle teardown; respawn on death |
| 2 | **`CapacityFetch`** | Acquire SSOT: warm pool if resident → else cold `CapacityProbe`; 30 min display gate; never history/disk as live |
| 3 | **`CapacityResidentService`** | Mac app: owns pool + socket when menu-bar setting is on |
| 4 | **Socket contract** | `GET_CAPACITY` → JSON; 100ms connect timeout; `warming` → wait ≤2s else cold + stderr |
| 5 | **Menu cache file** | Resident writes snapshot after successful fetch; `alln menu` reads only if `generatedAt` &lt; 30 min |
| 6 | **Mac strip UX** | Off-mode: loud Refresh + Settings CTA banner; on-mode: normal age chips |
| 7 | **First-launch sheet** | Menu bar explainer; default on |
| 8 | **Shared tail** | Existing parsers + `CapacityStripRenderer` |

**Not in scope:** second daemon, `alln serve`, `WarmWorkerPool` reuse, disk-as-acquire,
history hydrate as current truth.

### Settings (two toggles, both default **on**)

1. **Show menu bar icon** — resident mode + socket. **The capacity contract.**
2. **Start at login** — app (and pool when menu bar on) ready at session start.

User can disable either in Settings.

### Resident cost (honest)

~6 idle CLI processes when menu bar on: ~200–800 MB RAM, negligible CPU/battery
idle. One-time boot cost at login. Acceptable for a capacity-first product —
same class as Dropbox, 1Password, Raycast staying resident.

---

## What we delete (complexity removal)

| Remove | Why |
| --- | --- |
| `refresh: false` as default | Stale lies |
| History hydrate painted as live | Stale lies |
| Disk-as-acquire for Codex/Grok | Stale lies |
| `CapacityAcquisition` disk-primary path for capacity display | Replaced by PTY |
| Cold spawn from Mac strip when resident | Warm pool |
| `CapacityDisplayAcquisition` as acquire owner | → `CapacityFetch` |
| `alln serve` capacity ownership | App owns warm |

Keep: parsers, probe fail-closed reasons, Claude `allmodels` normalization,
TeachingSnippet “print full table verbatim”.

---

## CLI contract (after cutover)

```text
alln capacity              # CapacityFetch (socket if resident, else cold)
alln capacity --json       # same
alln capacity --source ID  # one seat
alln capacity --refresh    # transition alias; delete CWB-S05
```

- Progress on stderr when cold, warming, or revalidating.
- Full six-row table on stdout (existing agent law).

---

## Failure modes (named)

| Scenario | Behavior |
| --- | --- |
| Pool child dies | Respawn on next fetch; seat unknown until back |
| Socket up, pool warming | CLI waits ≤2s; else cold + stderr note |
| Live probe fails for one seat | Unknown; disk never painted as current |
| Menu cache &gt; 30 min | Omit capacity from menu JSON (fail-open for seating) |
| Menu bar toggled off | Tear down pool + socket; show strip CTA |
| User force-quits app | Socket gone; CLI cold |

---

## Implementation slices

| Slice | Scope | Works Test | Est. |
| --- | --- | --- | --- |
| **CWB-S01** | `CapacityWarmPool` (6 PTY) + `CapacityFetch`; kill stale paths; Codex/Grok PTY adapters; 30 min gate | `scripts/swift-test.sh --filter CapacityFetch` | 5–8d |
| **CWB-S02** | Resident service; strip on fetch; menu-bar gate; off-mode Refresh + CTA banner | `xcodebuild test … CapacityStripModelTests` | 2–3d |
| **CWB-S03** | `capacity.sock` + CLI fast path | Menu on: `time alln capacity` &lt; 2s | 2d |
| **CWB-S04** | Settings (defaults on); first-launch sheet; login item; teardown on toggle | Manual + toggle proof | 2d |
| **CWB-S05** | Delete dead paths; help/teaching; archive Phase 1 doc | Help + TeachingSnippet tests | 2–3d |

**Order:** S01 → S02 → S03 → S04 → S05.

**Total estimate:** ~2–3 weeks one focused engineer, plus dogfood. **Risk bumpers:**
Claude trust in warm pool (+2–3d), Codex/Grok PTY maturity (+2–4d each if greenfield).

---

## Success criteria

- Menu bar on (default), app open → strip **&lt; 2s**, no main-thread block.
- Same state → `alln capacity` **same numbers**, **&lt; 2s**.
- Menu bar off → cold **~5s**, loud Refresh + CTA visible, no stale %.
- No seat painted with sample age &gt; 30 min without "refreshing" / unknown.
- Single acquire implementation (`CapacityFetch`) for CLI, strip, and socket.
- Disk never appears as current truth in strip or CLI table.

---

## Truth owner / lie-prone layers

| Layer | Owner | Lie risk |
| --- | --- | --- |
| Acquire | `CapacityFetch` | Disk/history painted as live |
| Warm pool | `CapacityWarmPool` | Stale PTY capture / dead child |
| Resident lifecycle | `CapacityResidentService` | Socket up but pool cold |
| Render | `CapacityStripRenderer` | None if acquire is honest |
| Menu envelope | Derived cache file | Stale cache in `alln menu` |

Code SSOT targets: `CapacityWarmPool.swift`, `CapacityFetch.swift`,
`CapacityResidentService.swift` (Mac), `AllnighterCLI.runCapacity`.
