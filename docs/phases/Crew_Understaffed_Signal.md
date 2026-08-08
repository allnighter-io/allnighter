# Crew Understaffed Signal

Status: **OPEN — reoriented 2026-08-08. Front-door + serialize-don't-drop.
Prior Spec Review stream/warning design is parked (not authorized).**
Owner: AllnighterCore (`TeamExplicitSeats` / resolve path) + spawn gate
(`DriverConcurrencyGate` / `acquireDriverSpawnGate`) + agent teaching
Created: 2026-08-07
Revised: 2026-08-08 — founder: audience is ~95% AI PMs (no human-notification
path); 8-seat teams **must** multi-seat the same CLI; read-only/judgment
fan-out is normal. Do **not** refuse same-driver crews.
Origin incidents:
- `F3B862ED` — explicit `--seat` Kimi + Cursor Sol + Cursor Opus; Opus
  `spawn gate timed out for cursor_agent` (never started). Sol held the only
  `cursor_agent` slot (~482s); gate waiter timeout is 300s → drop.
- Spec Review Min `7FF03849` — understaffed panel finished useful; nothing
  shouted (separate, deferred).

Related: archived [`Ephemeral_Teams.md`](../archive/phases/Ephemeral_Teams.md)
(`--seat`); code `DriverConcurrencyGate` / `DriverManifest.maxConcurrentSpawns`
(`cursor_agent`/`opencode`/`agy` = 1; claude/codex/grok unlimited); ORS
[`One_Run_Surface.md`](One_Run_Surface.md).

Phases are ephemeral. At closeout: promote teaching + vocabulary if needed;
code remains SSOT; archive this packet.

---

## Founder intake (locked)

```text
Audience:
  ~95% AI agents delegating and running. Human Mac banners / GUI rows are
  almost useless for this problem. Design for CLI→CLI PMs only.

Intent:
  Stop the preventable class where a PM staffs a judgment crew, two seats share
  a spawn-gated CLI, and the second seat is silently dropped after a gate
  timeout while the first is still running — panel looks "dispatched," finishes
  understaffed.

Not the intent:
  Ban multiple seats on the same CLI. Large teams (Spec Review Max, Bug Hunt
  Max, Growth, …) MUST put several agents on Claude / Codex / Cursor / etc.
  Read-only / judgment fan-out is normal and desired when the driver allows it.

Product value:
  Same-CLI multi-seat either runs (parallel if safe, serial if gated) or the
  PM is told at the front door how it will run — never a quiet timeout-fail
  that looks like the model was broken.
```

---

## Product promise

```text
On a judgment / read-only team, every accepted crew seat either runs to a real
terminal (done/failed for its own work) or the accept/dry-run already told the
PM that N seats on driver D will serialize. A spawn gate never turns "wait your
turn" into "you failed" while a sibling on the same team still holds the slot.
```

---

## Why blanket refuse is wrong (80/20 trap)

| Idea | Verdict |
| --- | --- |
| Refuse any `--seat` crew with 2+ models on the same driver | **Rejected.** An 8-seat team cannot staff 8 distinct CLIs. Same-CLI multi-seat is required. |
| Refuse only when `maxConcurrentSpawns == 1` | **Rejected as refuse.** Still blocks legitimate dual-Cursor / dual-OpenCode juries; the right behavior is serialize, not ban. |
| Human notification / Mac banner when a seat dies | **Rejected.** Wrong audience. |
| Mid-run reseat / stream warning / observation bloat as v1 | **Parked.** Useful later for unpreventable deaths (rate limit, serve busy); not the 80/20. |

### What `F3B862ED` actually was

`cursor_agent` declares `maxConcurrentSpawns: 1` (real race on
`~/.cursor/cli-config.json` — concurrent Cursor processes are unsafe even for
read-only prompts). Gate correctly serializes. Bug: waiter **times out at 300s**
and settles `failed` / never started while Sol still ran ~8 minutes. Fail-soft
panel continued 2/3. PM learned nothing at accept time.

OpenCode Bug Hunt Max (`A347D821`) shows the same gate-timeout drop class on
`opencode` (=1).

Parallel-safe drivers (claude / codex / grok, no limit) already multi-seat fine
on 8-wide teams. Do not “fix” them.

---

## Simple design (authorized v1)

Two moves only. No new commands. No human notify. No stream schema work.

### CHS-S01 — Serialize, don't drop (runtime)

For seats competing on a driver with `maxConcurrentSpawns` set:

- Keep the gate (do not claim concurrent Cursor/OpenCode/agy is safe).
- **Same team-run waiters must not die on the acquire timeout** while a sibling
  seat from that run still holds (or is queued for) the slot. Prefer: unbounded
  wait for in-team gate acquisition, or a timeout ≥ the seat's own invoke
  timeout — never a short global 300s that is shorter than a normal Spec Review
  seat.
- When the slot frees, the waiter runs. Read-only / judgment stays fail-soft for
  real worker failures; gate wait is not a worker failure.

Truth owner: `acquireDriverSpawnGate` / `DriverConcurrencyGate` call sites used
by team fan-out (`CatalogRunCoordinator` / `RunService`). Scope the “don't drop”
rule to judgment / non-mutating team fan-out first if a global change is risky.

### CHS-S02 — Front-door honesty (accept + dry-run)

When resolving `--seat` (and dry-run), if crew model ids map to a driver whose
`maxConcurrentSpawns` is `N` and this crew asks for more than `N` on that
driver:

- **Do not refuse** (large teams need this).
- Emit a clear, stable message on dry-run / accept JSON (warning or structured
  note the PM already reads) naming driver, limit, model ids, and that those
  seats will **run serially**.

Example shape (illustrative):

```text
code: seat_driver_serialized
message: cursor_agent allows 1 concurrent spawn; seats model_cursor_gpt_sol +
  custom_cursor_agent_opus_5_cursor will run one after another (not in parallel).
```

Teaching: `--seat` may place multiple models on one CLI; gated CLIs serialize;
after dry-run, read that note before spending a long panel.

Truth owner: `TeamExplicitSeats.resolve` (or the resolve/dry-run projector that
already surfaces seat lineup) + `HelpTopicRegistry`.

### Explicitly out of v1

- Refusing same-CLI crews
- Raising `cursor_agent`/`opencode` concurrency without a separate AgentOS proof
  (config race is real; read-only prompt does not remove it)
- `crew_understaffed` stream frames / mapper warnings (parked)
- `attentionRequired` mid-panel (parked — revisit only if serialize-don't-drop
  + front-door note still leave AI PMs blind)
- Mac / URN / human banners
- Mid-run reseat
- Changing built-in 8-seat team rosters

---

## Current state

| Piece | State |
| --- | --- |
| `maxConcurrentSpawns` | Data on driver manifest; cursor/opencode/agy = 1 |
| Gate | Serializes correctly |
| Gate acquire timeout | ~300s → **drops** long-waiting siblings (`F3B862ED`) |
| `--seat` resolve | Readiness / count / compatibility — **no** serialize note |
| Large judgment teams | Must multi-seat same CLI — working as designed when ungated |
| Human notifications | Shipped for humans; **irrelevant** to this packet |

---

## Inference bans

| Junction | Forbidden inference | Ban |
| --- | --- | --- |
| Two seats share a driver | Invalid crew / refuse | Large teams require it |
| Read-only prompt | Concurrent Cursor is safe | Gate=1 is about process/config races, not write policy |
| Gate timeout failure | Model/auth broken | It was still waiting its turn |
| Dry-run silent on serialize | Seats will fan out in parallel | Must name serial drivers |
| Understaffed panel | Need human banner | AI PM surface only |

---

## Works Test

```text
CHS-S01:
  Fixture or host: judgment --seat with 2 models on cursor_agent (or test double
  with maxConcurrentSpawns=1), first seat held longer than former 300s timeout.
  Assert: second seat eventually starts (or still waiting), never
  errorReason "spawn gate timed out for …" while sibling active.
  Negative: real worker failure (auth, nonzero exit) still fails that seat.

CHS-S02:
  alln run … --team code_spec_review_min \
    --seat <cursor_a> --seat <cursor_b> --seat <other> --dry-run --json
  Assert: surfaces seat_driver_serialized (or equivalent) naming cursor_agent,
  limit 1, both model ids; exit success (not refused).
  Negative: three claude/codex seats with no spawn limit → no serialize note.
  Help search: "spawn gate", "same CLI", "serialize seats", "concurrent seats".
```

```text
scripts/swift-test.sh --filter 'TeamExplicitSeats|DriverConcurrency|SpawnGate'
# plus focused dry-run / resolve tests
bash scripts/check.sh   # closeout ONLY
```

---

## Done when

- Dual Cursor (or dual OpenCode) on a judgment `--seat` crew no longer loses a
  seat to gate timeout while a sibling holds the slot.
- Dry-run/accept names serial drivers before the PM spends the panel.
- Teaching finds it; no human-notification work claimed.
- Parked stream/warning design not started.

---

## History / parking lot

### Spec Review Min `7FF03849` (2026-08-07) — Ready on old design

Locked stream-frame `crew_understaffed` warnings, Core cause helper, etc.
**Superseded by this reorientation** for v1. Keep as deferred CHS-S03+ only if
S01/S02 dogfood still leave AI PMs blind on *unpreventable* deaths (rate limit,
serve busy, true crash).

### Audience correction (2026-08-08)

GUI parity and Mac banners are not part of the trusted workflow. CLI contract
for agent PMs only.
