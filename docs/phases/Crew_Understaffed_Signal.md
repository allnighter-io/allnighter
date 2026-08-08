# Crew Understaffed Signal

Status: **OPEN — hardened 2026-08-08 (DeepSeek V4 Pro `09E19604` + Kimi K3
via kimi `62F74094`). CHS-S01/S02 Ready to authorize after this doc. Not coded.**
Owner:
- **CHS-S01 (AgentOS):** `GatedWorkerRunner.invoke` →
  `DriverConcurrencyGate.acquire` (default timeout is exactly **300s** today)
- **CHS-S02 (Allnighter):** `RunService` post-resolve dry-run / accept warnings
  over resolved seats (effective spawn limit), not `TeamExplicitSeats` alone
Created: 2026-08-07
Revised: 2026-08-08 — serialize-don't-drop; AI PMs only; reviews applied
Origin:
- `F3B862ED` — `--seat` Kimi + Cursor Sol + Cursor Opus; Opus
  `spawn gate timed out for cursor_agent` (never started) while Sol held the
  only slot ~482s > 300s gate timeout
- `A347D821` — Bug Hunt Max; `model_opencode_deepseek_v4_pro` +
  `model_opencode_glm_5_2` both `spawn gate timed out for opencode`

Related: archived [`Ephemeral_Teams.md`](../archive/phases/Ephemeral_Teams.md);
AgentOS `DriverConcurrencyGate` / `GatedWorkerRunner`;
`RunDryRunJSON` / `ResolvedTeamRun.warnings`; ORS
[`One_Run_Surface.md`](One_Run_Surface.md).

Phases are ephemeral. Closeout: promote teaching; code SSOT; archive.

---

## Founder intake (locked)

```text
Audience: ~95% AI CLI PMs. Human Mac banners are out of scope.

Intent: Stop preventable silent drops when judgment crews multi-seat a
spawn-gated CLI (cursor_agent / opencode / agy at maxConcurrentSpawns=1).

Not the intent: Refuse same-CLI multi-seat. Large teams (8+) must place several
agents on one CLI. Read-only / judgment fan-out is normal. Parallel-safe
drivers (claude / codex / grok, no limit) need no change.
```

---

## Product promise

```text
A judgment seat waiting on a spawn gate runs when the slot frees (or fails for
a real worker/wall reason) — never "spawn gate timed out" while it was only
waiting its turn. Dry-run names which drivers will serialize before the PM
spends the panel.
```

---

## Rejected approaches

| Idea | Why rejected |
| --- | --- |
| Refuse same-CLI `--seat` / crew | 8-seat teams require same-CLI multi-seat |
| Refuse only when `maxConcurrentSpawns == 1` | Still bans legitimate dual-Cursor juries; serialize instead |
| Human / Mac / URN notification | Wrong audience |
| Team-identity in the gate (“in-team waiters only”) | Cross-repo plumbing through `WorkerInvocation`; contradicts simple v1 |
| Stream `crew_understaffed` / mid-run reseat as v1 | Parked (CHS-S03+) |
| Raise Cursor/OpenCode concurrency without AgentOS proof | Config race is real even for read-only prompts |

---

## Simple design (authorized)

### CHS-S01 — Serialize, don't drop (AgentOS)

**Decision (locked):** In `GatedWorkerRunner.invoke`, pass
`timeout:` to `DriverConcurrencyGate.acquire` equal to **that seat's invoke
timeout** (`manifest.invoke.timeoutSeconds`), not the hardcoded **300s**
default. No team-run id. No Allnighter-only decorator required for v1.

Why this over unbounded wait: a hung sibling must not block forever; invoke
timeout is already the seat's allowed life. Why this over “in-team only”:
covers F3B862ED and cross-run waits (team seat behind a single-lane chat)
without new identity fields.

**Wall clock:** Gate wait **counts** against the run/seat wall
(`RunClockEnforcer`). Serialization can make a panel longer; that is honest.
A seat that starts after a long wait and then hits wall fails as wall/timeout —
**not** as spawn-gate-timeout. Do not claim “understaffed fixed” if the only
change was the reason string.

**Stale name:** `acquireDriverSpawnGate` is **dead** (CR-08). Do not teach it.
Live path: `GatedWorkerRunner` → `DriverConcurrencyGate.acquire`.

**Injection seam for tests:** `GatedWorkerRunner` / gate acquire must accept an
overridable timeout (or test double) so CI need not wait >300s.

### CHS-S02 — Front-door honesty (Allnighter)

**Decision (locked):** After team resolve (all staffing paths — `--seat` **and**
default capability-staffed crews), group resolved crew seats by `driverId`,
compare count to **effective** spawn limit
(`RunService.spawnConcurrencyLimit` override if set, else
`manifest.maxConcurrentSpawns`). If count > limit, append a **flat string** to
`ResolvedTeamRun.warnings` (already flows to dry-run + `TeamRunJSON.warnings`).
**Do not refuse.**

Example warning string (exact shape for implementers):

```text
seat_driver_serialized: cursor_agent allows 1 concurrent spawn; model_cursor_gpt_sol, custom_cursor_agent_opus_5_cursor will run one after another
```

Primary surface: **`--dry-run --json`**. Accept/show inherit the same warnings
channel — no new schema field, no `code:` object.

Truth owner: `RunService` (has `DriverRegistry` + resolved seats), not
`TeamExplicitSeats.resolve` alone (no registry / no warnings channel on success).

Teaching: help search hits `spawn gate`, `same CLI`, `serialize seats`,
`concurrent seats`.

### Out of v1

- Refusing same-CLI crews
- Raising `maxConcurrentSpawns` without a separate AgentOS proof
- Stream warnings / `attentionRequired` / reseat / human banners
- Built-in roster changes

---

## Current state

| Piece | State |
| --- | --- |
| `maxConcurrentSpawns` | cursor/opencode/agy = 1; claude/codex/grok unlimited |
| Gate | Serializes FIFO correctly |
| Acquire timeout | Exactly **300s** default in AgentOS `DriverConcurrencyGate` — drops long siblings |
| Live call site | `GatedWorkerRunner.invoke` (AgentOS) — does not pass custom timeout today |
| Dry-run seats | Carry `driverId`; no serialize warning yet |
| Human notifications | Irrelevant to this packet |

---

## Inference bans

| Junction | Forbidden inference |
| --- | --- |
| Two seats share a driver | Invalid crew → refuse |
| Read-only prompt | Concurrent Cursor is safe (gate=1 is process/config race) |
| `spawn gate timed out` | Model/auth broken (it was still waiting) |
| Dry-run silent | Seats will fan out in parallel on a gated driver |
| Seat died after long serialize wait | Model broken (check wall / real worker reason) |
| Manifest limit alone | Effective limit (honor `spawnConcurrencyLimit` override) |

---

## Works Test

```text
CHS-S01 (AgentOS):
  Inject short acquire timeout (or test double maxConcurrentSpawns=1).
  Sibling holds longer than old 300s default; waiter must start after release
  and reach a real terminal — never errorReason "spawn gate timed out for …"
  while only waiting.
  Wall case: waiter survives gate; if wall expires, terminal is wall/timeout
  class — not spawn-gate-timeout.
  Negative: real worker failure still fails that seat.

CHS-S02 (Allnighter):
  Dry-run capability-staffed team (no --seat) with 2+ seats on a gated driver
  → warnings contain seat_driver_serialized …; canStart true.
  Dry-run with spawnConcurrencyLimit override that removes the bottleneck
  → no false serialize warning.
  --seat dual Cursor + one other → same warning; not refused.
  Three ungated seats → no serialize warning.
```

```text
# Allnighter
scripts/swift-test.sh --filter 'TeamExplicitSeats|RunDryRun|SpawnSerial'
# AgentOS (this clone's AgentOS test path — do not expect gate tests under AllnighterCore)
# filter GatedWorkerRunner|DriverConcurrencyGate
bash scripts/check.sh   # closeout ONLY
```

---

## Done when

- Dual Cursor / dual OpenCode on a judgment crew no longer loses a seat to the
  300s gate timeout while a sibling holds the slot.
- Dry-run names serial drivers for `--seat` **and** default wide teams.
- Teaching finds it; no human-notification work.
- CHS-S03 stream/warning design stays parked.

---

## Review record

| Reviewer | Run | Verdict |
| --- | --- | --- |
| DeepSeek V4 Pro (opencode) | `09E19604` | S01 Ready with notes (pick timeout path); S02 Partial → owners/channel fixed here |
| Kimi K3 (kimi) | `62F74094` | Partial → owner, timeout decision, wall clock, S02 scope/channel, Works Test — applied |

Parked prior Spec Review Min `7FF03849` locked the old stream-warning design;
superseded for v1.
