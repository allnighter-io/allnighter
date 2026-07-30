# Completion Delivery

Status: **OPEN — incident-driven (2026-07-30)**  
Audience: **agents dispatching work via `alln` CLI**  
Version: **v2 (2026-07-30)** — Spec Review Min (`code_spec_review_min`, run `19C9113F`)

Origin: PM agent (Opus) told the founder a dev worker was still running after
`alln run` had already completed (`endReason: completed`, commit landed). The PM
polled relay-shaped status (`running`, no terminal facts) instead of running the
returned waiter. **Humans already get Mac notifications** (URN, `alln serve`).
**Agents do not.** That is the gap.

Phases are ephemeral. Closeout: promote law to `TeachingSnippet` / contracts;
archive this packet.

Related (orthogonal — do not merge scope):

| Packet | Role |
| --- | --- |
| archived [`PM_Turn_Delivery.md`](../archive/phases/PM_Turn_Delivery.md) | Shipped parent delivery contract — blocking / wait / wake, `pmTurn`, detached waiter acks |
| [`Agent_Visible_Queuing.md`](Agent_Visible_Queuing.md) | Honest status **when polled** (queue, stall, `--read-only`); lifecycle `running` ≠ progress |
| [`Observed_Usage_On_Receipts_And_Live_Status.md`](Observed_Usage_On_Receipts_And_Live_Status.md) | Tok/duration on live lines (garnish, not completion) |
| [`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md) | Resume after **seat death**; WRC-S01 human notify on `awaitingPM` |
| archived [`Unattended_Round_Notification.md`](../archive/phases/Unattended_Round_Notification.md) | Mac banner when app closed — **shipped**; not agent delivery |

---

## Product law

```text
When work you dispatched reaches terminal, you must learn it without guessing.
```

| Caller | Default | Detached (`--no-wait`) |
| --- | --- | --- |
| **Agent (CLI)** | Blocking dispatch returns terminal payload | Ack includes `delivery.path=wait` + **one exact waiter command** — run it **once**; terminal JSON is the notification |
| **Human (Mac)** | Same + optional banner via `alln serve` (URN) | Banner when app closed |

**Banned for agents:**

- Treating lifecycle `running` as evidence of progress (AVQ law — use stall/progress
  signals or terminal facts).
- Polling the wrong surface (relay aggregate while the linked `devRunId` worker is
  terminal).
- Building a custom poll loop when a **bounded waiter** already exists in the ack.

**Terminal receipt / artifact is not live delivery.** OUR adds usage chrome later.
It does not replace completion delivery.

---

## 90 / 10 — what we already have

Most of the machinery exists. Agents ignore it or status projection lies when polled.

| Path | Existing waiter (contract today) | Gap |
| --- | --- | --- |
| `alln run --no-wait` | `delivery.command` → `alln team status <id> --wait-for terminal --timeout … --json` | PM skips it; polls relay instead |
| `pair pilot handoff --no-wait` | `pilot status --relay <id> --wait-for parked --timeout … --json` | Same |
| `pair relay*` `--no-wait` | `relay-status --wait-for terminal …` | Same |
| `pair pilot handoff` (default) | **Blocks** through dev turn | PM left the blocking call |
| Relay dev turn settlement | `RelayCoordinator` → `awaitingPM` + `devTurnFinished` (**shipped** ~`RelayCoordinator.swift:577`) | — |
| `pilot status` / `relay-status` projection | — | **`devRunId` / terminal facts not surfaced** (`PilotCLI` has no dev-leg projection) |

**10% work hypothesis:** do **not** build a new notification daemon or alias verb.
Make **(a)** status projection honest, **(b)** waiters unblock on parked truth,
**(c)** prove with a failing fixture first.

---

## Truth owners

| Concern | Owner |
| --- | --- |
| Run reaches terminal | Run journal (`endReason`, `status`, worker `finishedAt`) |
| Relay round settles | `RelayCoordinator` + persisted `RelayState` / `RelayRound` (park at `awaitingPM` **shipped**) |
| Deliverable PM boundary | `PMTurnJSON` / `PMTurnStore` |
| **Agent delivery (blocking)** | `--wait-for` on `team status`, `pilot status`, `relay-status` (observers, not truth) |
| **Agent delivery (detached ack)** | `DetachedDispatch.waitDelivery` / `wakeDelivery` → `delivery.path=wait` + `delivery.command` |
| **Relay snapshot honesty** | One shared dev-leg projection helper for `PilotCLI` + `relay-status`; extends `StreamLiveness` — no second liveness arbiter |
| Human banner | `NotificationScheduler` + Mac (URN — do not redo) |
| Agent teaching | `TeachingSnippet` (waiter reflex **shipped** ~line 31); add `devRunId` law only |

**Settlement boundary:** worker journal terminal ≠ round settled. Proof, write-scope
evaluation, and persistence can still run after the dev journal goes terminal. The
finished boundary is persisted PM turn + relay state — not journal-terminal alone.

---

## Dev-leg projection states

Status reads must distinguish three states (fixture must assert 2 vs 3):

| State | Worker journal | Round / settlement | Status must show |
| --- | --- | --- | --- |
| 1 — running | non-terminal | dev in flight | honest `running` + live nextAction |
| 2 — settling | terminal | proof / settlement in progress | worker terminal facts + settling (not aggregate `running` lie) |
| 3 — parked | terminal | `awaitingPM` / escalated | parked + `devRunId` / `devEndReason` / commit + review nextAction |

---

## Core promise (agent)

After you dispatch work, exactly one of these must be true:

1. **You stayed on a blocking call** — it returned terminal JSON (handoff default).
2. **You used `--no-wait`** — you ran the **printed `delivery.command` once** and
   it returned terminal / parked JSON.
3. **You poll intentionally** — `alln team status <devRunId> --json` or
   `pilot status --wait-for parked` — never relay aggregate `running` alone.

There is no fourth path where “I'll check later” works reliably.

---

## Slices (minimal)

### CD-S01a — Fixture + dev-leg projection (hero)

**Problem:** PM polls `pilot status` / `relay-status`, sees aggregate `running`,
while linked `devRunId` is already terminal. Waiter may be correct; projection
lies.

**Already shipped (do not re-build):**

- Round parks at `awaitingPM` on dev-turn settlement (`RelayCoordinator`).
- `pilot status --wait-for parked` waiter exists and is printed in detached acks.

**Fix (the actual gap):**

1. **First commit:** failing fixture reproducing “worker terminal, status says
   `running`” (distinguishes projection gap vs settlement bug vs agent misuse).
2. **One shared projection helper** for `pilot status` + `relay-status` surfacing
   `devRunId`, `devRunStatus`, `devEndReason`, optional commit/head — extends
   `StreamLiveness`, reconcile-on-read for the dev leg.
3. `nextAction` = review dev / continue handoff when dev leg is terminal (not
   `waitForStatus` on a dead dev).

**Works tests:** CD-WT-01 (hero), CD-WT-02, CD-WT-03 — see Proof section.

**Out of scope:** new commands, Mac notifications, token display.

### CD-S01b — Coordinator settlement fix (conditional)

Only if CD-S01a fixture proves the parked transition is missed on a real path
(despite shipped `awaitingPM` code). Do not touch coordinator before the fixture.

### CD-S02 — Detached-ack audit (pilot / relay paths)

**Problem:** ack JSON may bury `delivery.command` on some detached paths; agents
improvise polls.

**Fix:** Audit `pilot handoff` and `relay*` detached acks — every path emits
`delivery.path=wait` + copy-paste `delivery.command` when not blocking.
(`alln run --no-wait` already ships via `DetachedDispatch.waitDelivery`.)

**Cut:** `alln wait <run-id>` alias — second spelling of an existing verb;
contradicts one-reflex teaching and the 90/10 bet.

**Works test:** CD-WT-04.

### CD-S03 — One teaching line (same PR as S01a)

`TeachingSnippet` already teaches “run `delivery.command` once.” Add only:

```text
Relay running ≠ dev running — check devRunId.
```

**Works test:** parse teaching body for `devRunId` law (not a full new slice).

---

## Explicit non-goals (v1)

- New agent push transport (WebSocket, MCP, email, file tail daemon).
- `alln wait` alias verb.
- Replacing URN Mac banners.
- AVQ full stall matrix (supporting; not completion delivery).
- OUR token/duration lines.
- Auto-resume PM without explicit agent action (WRC guard deferred for good reason).
- “Park when linked worker journal is terminal” as an invariant (races proof/settlement).

---

## Dependency order

```text
CD-S01a  (failing fixture → shared dev-leg projection)  ← ship first
    └──→ CD-S01b  (coordinator fix — only if fixture proves miss)
              └──→ CD-S02  (pilot/relay ack audit)
                        └──→ CD-S03  (one devRunId teaching line, same PR as S01a)
```

AVQ and OUR may proceed in parallel; they do not substitute for CD-S01a.

---

## Exit bar

Named Works Tests green (CD-WT-01–06). Simulated relay round:

- PM dispatches dev with `handoff --no-wait`, runs **only** returned
  `pilot status --wait-for parked` command.
- When dev finishes, waiter returns with parked + dev terminal facts.
- One-shot status (no `--wait-for`) never shows aggregate `running` for a dead
  dev leg.
- `pilot status` and `relay-status` agree on dev-leg facts (pair-equality).

Skeptical demo (dogfood, non-CI): Grok dev completes → Opus runs **only** waiter
command → parked JSON with commit hash.

---

## Risks

| Risk | Mitigation |
| --- | --- |
| Agents still skip waiter | Teaching + ack prominence; honest projection reduces wrong-surface poll harm |
| Settlement bug vs projection bug | CD-S01a fixture gates coordinator edits |
| Pilot vs relay-status drift | One projection helper; CD-WT-03 pair-equality |
| Two liveness arbiters | S01a extends `StreamLiveness`; no parallel truth path |
| Worker-terminal confused with round-settled | Three-state table + fixture asserts state 2 vs 3 |

---

## Proof — Works Tests

| ID | What |
| --- | --- |
| **CD-WT-01 (hero)** | Detached handoff → only `pilot status --wait-for parked` → parked + dev terminal facts |
| **CD-WT-02** | One-shot status never shows aggregate `running` for dead dev leg |
| **CD-WT-03** | `pilot status` and `relay-status` dev-leg pair-equality |
| **CD-WT-04** | `handoff --no-wait` ack has exact parked waiter; run only that command |
| **CD-WT-05** | Negative — dev still live → waiter stays blocked / honest timeout |
| **CD-WT-06** | Negative — dev terminal-failed still parks with failure facts visible |

```text
# Slice 1 (red-gated fixture first):
swift test --package-path Packages/AllnighterCore --filter RelayDevLegProjectionTests
swift test --package-path Packages/AllnighterCore --filter PilotRelayStatusParityTests

# Closeout wall:
swift test --package-path Packages/AllnighterCore && bash scripts/check.sh
```

Broad `--filter 'Pilot|Relay|Delivery|Detached'` is **not** exit-bar evidence —
it can stay green while CD-WT-01 is missing.
