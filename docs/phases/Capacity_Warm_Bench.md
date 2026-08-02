# Capacity Warm Bench

Status: **OPEN — founder priority (2026-08-02). Current path is a no-go.**
Owner: AllnighterMac (`CapacityResidentService`) + AllnighterEngine
(`CapacityWarmPool`, `CapacityFetch`) + AllnighterCore (parsers,
`CapacityStripRenderer`) + AllnighterCLI (`alln capacity`)
Created: 2026-08-02
Updated: 2026-08-02 (Spec Review Min pass)
Supersedes direction in: archived
[`Capacity_Phase1_Recovery.md`](../archive/phases/Capacity_Phase1_Recovery.md)
(`refresh: false` default, disk-as-primary, cold PTY per request).
Composes with: [`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md)
(menu/bootstrap reads a **derived cache file** — never a second acquisition path).

Phases are ephemeral. At closeout: promote product law into help / teaching /
operations; code remains SSOT; archive this packet.

---

## Spec Review Min (2026-08-02)

**Lead call: Partial → work can start on CWB-S01/S02.** One founder fork remains
(login-item default). Engineering leans are closed.

### Impact ledger (accepted)

| Change | Lens | Severity | Why |
| --- | --- | --- | --- |
| Warm pool = **six seats**, not four | Premise + Proof | **blocking** | Bench is six CLIs (`benchSourceOrder`); "4 PTY kids" dropped Codex/Grok and would ship a lying strip |
| Codex/Grok in pool = **live disk re-read**, not PTY (v1) | Premise | material | No shipped PTY adapter for disk seats; live log re-read inside pool is fresh enough; disk-only-as-primary stays dead |
| Menu bar **off** + app open = cold strip (honest) | Failure modes | material | Option B previously implied windows work but omitted strip behavior |
| Split **display TTL** (30 min) vs **pool idle teardown** (30 min, independent) | Failure modes | material | Same number, different jobs — conflating them causes torn-down pool while UI still paints |
| Socket **warming** state: CLI waits ≤2s or falls back cold with stderr note | Failure modes | material | Connect timeout alone loses the fast path during boot |
| `CapacityFetch` replaces `CapacityDisplayAcquisition` as acquire SSOT; snapshot becomes thin wrapper | Foundation | material | Two names for one job was a lie-prone layer |
| Menu cache file: `AllnighterPaths` + `generatedAt` + refuse if &gt; 30 min | Proof + Delivery | material | QABC menu zero-spawn must not become zero-truth |
| CWB-S01 before Mac/socket work | Sequencing | material | Pool + fetch law must be green before resident service |
| Named proof commands per slice | Proof | material | "&lt; 2s" without a command is decoration |

### Rejected (recorded)

| Finding | Lens | Rejection |
| --- | --- | --- |
| Reuse `WarmWorkerPool` for capacity | Foundation | Run workers are repo-scoped, mutating-adjacent, and keyed by thread — wrong lifecycle. Capacity-only pool stays separate. |
| `alln serve` as socket host when app closed | Wildcard | Second host; founder chose one Mac app. Serve stays out of capacity. |
| Delete `--refresh` in v1 | Cut | Keep as no-op alias through cutover; delete in CWB-S05 after help/teaching migrate. |

### Open question (founder)

| Fork | Options | Recommendation |
| --- | --- | --- |
| Login item default | A) on for new installs B) opt-in | **B opt-in** — menu bar toggle is the capacity contract; login item is convenience, not required for correctness |

*Min tier note: proof findings above are not refuted by a second seat — treat as checklist, not gospel.*

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

## Founder intent

**Product value:** trustworthy, fast bench capacity — the daily glance surface.
**Trusted workflow slice:** see six seats, honest ages, refresh in &lt; 2s when
resident, never beach-ball.
**Non-goals:** second daemon, `alln serve` capacity, history-as-live, disk-as-primary,
CLI parity when resident service is off.

---

## Product law (founder, 2026-08-02)

1. **Capacity must be trustworthy or absent.** Stale % is worse than unknown.
2. **Fresh is the default.** `refresh: false` must never be the default anywhere
   user-facing capacity is shown (`alln capacity`, Mac strip, agent print).
3. **Disk is backup only.** Codex/Grok log re-read is a **live** read inside
   fetch, never stale-as-primary. On probe failure, label `sourceTier` and age.
4. **Nothing on the main thread.** Acquisition is always async/off-main; UI
   never beach-balls.
5. **30-minute display gate.** Paint only if last **successful** acquire for that
   seat was &lt; 30 minutes ago; show honest age. Older → unknown or
   "refreshing" until a new sample lands.
6. **One output contract.** `[CapacityWindow]` → `CapacityBenchProjection` →
   `CapacityStripRenderer`. Parsers and table shape are shared everywhere.
7. **One acquire owner.** `CapacityFetch` is the only path to windows; CLI,
   Mac strip, and resident socket all call it.

---

## The system (one app, two speeds, three options)

**One Mac app** owns warm capacity when the user opts in. CLI is fast **only
when that resident service is active**. Otherwise CLI is honest and slow.

```
                    ┌─────────────────────────────────────┐
                    │         Allnighter.app              │
                    │  (one binary — Dock + optional      │
                    │   menu bar icon)                    │
                    │                                     │
                    │  CapacityWarmPool (6 seats)         │
                    │  capacity.sock (menu bar ON)        │
                    └──────────────┬──────────────────────┘
                                   │
         Mac strip ────────────────┤ in-process CapacityFetch, ~1s
         alln capacity ───────────┘ socket → same fetch, else cold ~4–5s
```

### Option A — Menu bar **on** (hero path)

**Settings:** “Show menu bar icon” (+ optional “Start at login”).

| Surface | Behavior |
| --- | --- |
| Mac capacity strip | In-process `CapacityFetch` → warm pool → ~1s |
| `alln capacity` | `capacity.sock` → same fetch → ~1s |
| Background | Pool stays warm; **idle teardown** after 30 min with no capacity requests (independent of display TTL) |

Menu bar on = **“watch my bench”** mode. Same process — not a second app.

### Option B — Menu bar **off**

| Surface | Behavior |
| --- | --- |
| Mac app (any window, including strip) | **Cold** `CapacityFetch` per request — same as CLI, ~4–5s, off main actor |
| `alln capacity` | Cold probe; progress on stderr |
| Resident | No pool, no socket |

Slow is honest. Opening the strip without resident mode does not get a hidden fast path.

### Option C — CLI-only (no app running)

Same as Option B. Optional stderr hint:
*“Start Allnighter with menu bar enabled for instant capacity.”*

---

## What we build (minimal moving parts)

| # | Piece | Responsibility |
| --- | --- | --- |
| 1 | **`CapacityWarmPool`** | Six seats: four PTY children (Claude, Cursor, Kimi, Agy) + live disk re-read for Codex/Grok inside the pool worker; `ProbeScratch` cwd; boot once; idle teardown; respawn on death |
| 2 | **`CapacityFetch`** | **Acquire SSOT.** Warm pool if resident → else cold `CapacityProbe`; enforces 30 min display gate; never paints history as live |
| 3 | **`CapacityResidentService`** | Mac app only: owns pool + Unix socket when menu-bar setting is on |
| 4 | **Socket contract** | `GET_CAPACITY` → JSON; connect timeout 100ms; if `warming`, block ≤2s then cold fallback with stderr note |
| 5 | **Menu cache file** | Resident writes `AllnighterPaths` snapshot after each successful fetch; `alln menu` reads only if `generatedAt` &lt; 30 min — else omit capacity block |
| 6 | **Shared tail** | Existing parsers + `CapacityStripRenderer` |

**Not in scope:** second daemon, `alln serve` hosting capacity, `WarmWorkerPool` reuse,
history hydrate as current truth, separate GUI acquisition path.

### Settings (two toggles)

1. **Show menu bar icon** — enables resident mode + socket (Option A). **This is the capacity contract.**
2. **Start at login** — optional convenience; opt-in (founder default **off**).

---

## What we delete (complexity removal)

| Remove | Why |
| --- | --- |
| `refresh: false` as default for `alln capacity` | Stale lies |
| History hydrate painted as live | Stale lies |
| Disk-as-primary for Codex/Grok | Stale lies |
| Cold spawn from Mac strip when resident | App uses warm pool |
| `CapacityDisplayAcquisition` as acquire owner | Fold into `CapacityFetch`; keep snapshot as CLI/GUI render helper only |
| `alln serve` capacity ownership | App owns warm |

Keep: parsers, probe fail-closed reasons, Claude `allmodels` normalization,
TeachingSnippet “print full table verbatim”.

---

## CLI contract (after cutover)

```text
alln capacity              # CapacityFetch (socket if resident, else cold)
alln capacity --json       # same
alln capacity --source ID  # one seat
alln capacity --refresh    # transition alias for force re-probe; delete CWB-S05
```

- Progress on stderr when cold, warming, or revalidating.
- Full six-row table on stdout (existing agent law).

---

## Failure modes (named)

| Scenario | Behavior |
| --- | --- |
| Pool child dies | Respawn on next fetch; seat unknown until back |
| Socket up, pool warming | CLI waits ≤2s; else cold + stderr `capacity: resident warming, cold fallback` |
| Fetch fails for one seat | Unknown for that seat; do not paint history as live |
| Menu cache &gt; 30 min | Omit capacity from menu JSON (fail-open for seating) |
| Menu bar toggled off | Tear down pool + socket immediately |
| User force-quits app | Socket gone; CLI cold |

---

## Implementation slices

| Slice | Scope | Works Test |
| --- | --- | --- |
| **CWB-S01** | `CapacityWarmPool` + `CapacityFetch`; kill `refresh:false` default; 30 min display gate | `scripts/swift-test.sh --filter CapacityFetch` — includes fixture PTY + assert no history-as-live |
| **CWB-S02** | Mac resident service; strip via in-process fetch; menu-bar gate | `xcodebuild test … -only-testing:AllnighterMacTests/CapacityStripModelTests` + assert no `MainActor` block in fetch path |
| **CWB-S03** | `capacity.sock` + CLI fast path | App running, menu on: `time alln capacity` &lt; 2s; menu off: cold path, no socket |
| **CWB-S04** | Settings toggles; teardown on menu-bar off | Manual: toggle off → `test ! -S …/capacity.sock` |
| **CWB-S05** | Delete dead paths; `HelpTopicRegistry`, `TeachingSnippet`, archive Phase 1 doc | `scripts/swift-test.sh --filter HelpTopicRegistryTests,TeachingSnippetTests` |

**Order:** S01 → S02 → S03 → S04 → S05. Do not build socket before fetch law is green.

---

## Success criteria

- Menu bar on, app open → strip **&lt; 2s**, no main-thread block.
- Same state → `alln capacity` **same numbers**, **&lt; 2s**.
- Menu bar off or app quit → cold **~5s**, honest progress, no stale history as live.
- No seat painted with sample age &gt; 30 min without "refreshing" / unknown.
- Single acquire implementation (`CapacityFetch`) for CLI, strip, and socket.

---

## Truth owner / lie-prone layers

| Layer | Owner | Lie risk |
| --- | --- | --- |
| Acquire | `CapacityFetch` | History/disk painted as live |
| Resident lifecycle | `CapacityResidentService` | Socket up but pool cold |
| Render | `CapacityStripRenderer` | None if acquire is honest |
| Menu envelope | Derived cache file | Stale cache in `alln menu` |

Code SSOT targets: `CapacityWarmPool.swift`, `CapacityFetch.swift`,
`CapacityResidentService.swift` (Mac), `AllnighterCLI.runCapacity`.
