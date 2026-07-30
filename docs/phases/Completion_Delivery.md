# Completion Delivery

Status: **OPEN — incident-driven (2026-07-30)**  
Audience: **agents dispatching work via `alln` CLI**  
Version: **v1 (2026-07-30)**

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
| [`Agent_Visible_Queuing.md`](Agent_Visible_Queuing.md) | Honest status **when polled** (queue, stall, `--read-only`) |
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

- Inventing “still running” from lifecycle `running` without `endReason` / `finishedAt` / commit.
- Polling the wrong surface (relay aggregate while watching a `devRunId` worker).
- Building a custom poll loop when a **bounded waiter** already exists in the ack.

**Terminal receipt / artifact is not live delivery.** OUR adds usage chrome later.
It does not replace completion delivery.

---

## 90 / 10 — what we already have

Most of the machinery exists. Agents ignore it or it lies when polled.

| Path | Existing waiter (contract today) | Gap |
| --- | --- | --- |
| `alln run --no-wait` | `delivery.command` → `alln team status <id> --wait-for terminal --timeout … --json` | PM skips it; polls relay instead |
| `pair pilot handoff --no-wait` | `pilot status --relay <id> --wait-for parked --timeout … --json` | Same |
| `pair relay*` `--no-wait` | `relay-status --wait-for terminal …` | Same |
| `pair pilot handoff` (default) | **Blocks** through dev turn | PM left the blocking call |
| `alln team status --wait-for terminal` | Blocks until terminal; returns `pmTurn` / result | Underused; not linked in relay snapshot |

**10% work hypothesis:** do **not** build a new notification daemon for agents.
Make **(a)** waiters trustworthy, **(b)** settlement unblock them, **(c)** every
dispatch ack scream the one command, **(d)** teach one reflex.

---

## Truth owners

| Concern | Owner |
| --- | --- |
| Run reaches terminal | Run journal (`endReason`, `status`, worker `finishedAt`) |
| Relay dev turn completes | `RelayCoordinator` → round parked / `devTurnFinished` |
| **Agent delivery (blocking)** | Existing `--wait-for` on `team status`, `pilot status`, `relay-status` |
| **Agent delivery (detached ack)** | `delivery.path=wait` + `delivery.command` on dispatch ack JSON |
| **Relay snapshot honesty** | `PilotCLI` / relay status must reflect linked `devRun` terminal (not `running` lie) |
| Human banner | `NotificationScheduler` + Mac (URN — do not redo) |
| Agent teaching | `TeachingSnippet` / bootstrap — one waiter reflex |

---

## Core promise (agent)

After you dispatch work, exactly one of these must be true:

1. **You stayed on a blocking call** — it returned terminal JSON (handoff default).
2. **You used `--no-wait`** — you ran the **printed `delivery.command` once** and
   it returned terminal / parked JSON.
3. **You poll intentionally** — `alln team status <devRunId> --json` or
   `pilot status --wait-for parked` — never relay `running` alone.

There is no fourth path where “I'll check later” works reliably.

---

## Slices (minimal)

### CD-S01 — Relay dev turn → parked truth (hero)

**Problem:** PM polls `pilot status` / relay JSON, sees `running`, while `devRunId`
is already terminal. Waiter never unblocks; agent hallucinates progress.

**Fix (small, high leverage):**

On dev run terminal settlement, `RelayCoordinator` must:

1. Transition round to **parked** (`awaitingPM` / escalated) when dev turn completes.
2. Project on **next** `pilot status` / `relay-status` read (and on waiter wake):
   - linked `devRunId`, `devRunStatus`, `devEndReason`, optional commit/head
   - `nextAction` = review dev / continue handoff (not `waitForStatus` on a dead dev)
3. Never show aggregate `running` for the dev leg when journal says terminal.

**Works test:** dispatch dev via relay → without `team status`, run
`pilot status --wait-for parked --timeout 600 --json` → returns parked + dev
terminal facts + pm turn path. Fixture: dev completes while PM idle → one status
read shows terminal dev (not “still running”).

**Out of scope:** new commands, Mac notifications, token display.

### CD-S02 — Dispatch ack enforcement + `alln wait` alias (optional sugar)

**Problem:** ack JSON buries `delivery.command`; agents improvise polls.

**Fix:**

1. Audit `alln run`, `pilot handoff`, `relay*` detached acks — every path emits
   `delivery.path=wait` + copy-paste `delivery.command` when not blocking.
2. Add **`alln wait <run-id> --json`** as documented alias for
   `alln team status <id> --wait-for terminal --timeout <default> --json`
   (one verb agents can memorize).
3. Contract + help search: `wait`, `completion`, `delivery`, `terminal`.

**Works test:** `alln run --no-wait` ack contains waiter; `alln wait <id>` blocks
to same terminal JSON as `team status --wait-for terminal`.

### CD-S03 — Teach the waiter reflex (same PR as S01 or S02)

**Bootstrap / `TeachingSnippet` one block:**

```text
After --no-wait: run delivery.command once — that IS your notification.
Never claim running without endReason. Relay running ≠ dev running — check devRunId.
```

**Works test:** parse teaching body for waiter + devRunId law.

---

## Explicit non-goals (v1)

- New agent push transport (WebSocket, MCP, email, file tail daemon).
- Replacing URN Mac banners.
- AVQ full stall matrix (supporting; not completion delivery).
- OUR token/duration lines.
- Auto-resume PM without explicit agent action (WRC guard deferred for good reason).

---

## Dependency order

```text
CD-S01  (relay/pilot snapshot honest + waiter unblocks)  ← ship first
    └──→ CD-S02  (wait alias + ack audit)
              └──→ CD-S03  (teaching)
```

AVQ and OUR may proceed in parallel; they do not substitute for CD-S01.

---

## Exit bar

Simulated relay round:

- PM dispatches dev with `handoff --no-wait`, runs **only** returned
  `pilot status --wait-for parked` command.
- When dev finishes, waiter returns within one poll interval with parked +
  dev terminal facts.
- PM **cannot** truthfully say “still running” without ignoring JSON.

Evidence: coordinator settlement + pilot status projection + waiter integration test.

---

## Risks

| Risk | Mitigation |
| --- | --- |
| Agents still skip waiter | Teaching + ack prominence; fail reviews that poll relay only |
| `wait-for` blocked on settlement bug | CD-S01 fixes coordinator → parked transition |
| Pilot vs relay-status drift | One projection helper; both surfaces tested in S01 |

---

## Proof

```text
swift test --package-path Packages/AllnighterCore --filter 'Pilot|Relay|Delivery|Detached'
bash scripts/check.sh
```

Skeptical demo: Grok dev completes → Opus runs **only** waiter command → gets
parked JSON with commit hash — no manual `team status` archaeology.
