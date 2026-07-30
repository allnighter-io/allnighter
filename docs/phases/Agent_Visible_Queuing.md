# Agent-Visible Status

Status: **OPEN — incident-driven (2026-07-30)**
Audience: **agents using `alln`** (humans are rare on this surface)
Created: 2026-07-30
Revised: 2026-07-30 (add running≠advancing / progressStale incident)
Origin:
- **Queue:** An agent dispatched three mutating runs and had no idea they were
  queued. Work appeared to "do nothing."
- **Liveness:** The same agent polled `status: running` and `HB_AGE` for hours
  while Grok was stalled. The answer was in `progressStale: true` and
  `silenceStatus: "alive, no stream for 397s"` — fields it never read.

Phases are ephemeral. At closeout: promote agent law into `Bootstrap` /
`TeachingSnippet`, contract help, and `AGENTS.md` routing; code remains SSOT
for fields; archive this packet.

**Code SSOT (today):** `RunService.swift` (write lock + FIFO ticket),
`RunWriteLockRegistry`, `ExecutionLaneRegistry`, `RelayCoordinator` (`laneBlocked`),
`ProcessOwnershipSurface` (`alln ps`), `AsyncTeamService.status` (`progressStale`,
`silenceStatus`), `RunActivity`, `OwnershipSilencePresentation`,
`NotificationCandidateDetection`.

---

## The two rules (first principles)

### Rule 1 — One mutator per repo

```text
On a given repo root, at most ONE mutating run executes at a time.
Every other mutating run queues behind it — FIFO — until the holder finishes
or is stopped.
```

### Rule 2 — Running is not advancing

```text
status: running means the run has not finished.
It does NOT mean the worker is making progress.

Process alive (identityAlive) means the OS process still exists.
It does NOT mean the worker stream is moving.

To know if work is advancing, read progressStale (or silenceStatus).
When progressStale is true, treat the run as STALLED until proven otherwise.
```

These are orthogonal axes. A run can be **running + alive + stalled** — and
block every other mutating run on the repo while doing nothing useful.

| Field | What it actually means |
| --- | --- |
| `status: running` | Lifecycle: not terminal yet |
| `identityAlive: yes` | PID still exists (may be wedged, auth-prompt, zombie child) |
| `heartbeatAgeSeconds` / `HB_AGE` | Seconds since **last stream activity** (`lastProgressAt`) — not a health OK |
| `progressStale: true` | No stream activity for >60s (default budget) while owner alive |
| `silenceStatus` | Human line: `alive, no stream for Ns` (+ stall diagnosis when known) |

Pilot status already has `streamSilenceWarning` for this. Team/run status has
the facts but not the scream.

This is not a Cursor bug, a Codex bug, or a driver bug. It is the project
invariant: **exactly one mutating worker per canonical repo root**
(`RunService.swift`, `RunWriteLockRegistry`, architecture policy).

| Run kind | Competes for write lock? |
| --- | --- |
| Mutating team run / build-class turn | **Yes** — one at a time per root |
| Read-only research / judgment team | **No** — parallel is fine |
| Relay dev turn / harness proof | **Yes** — same lane as mutating runs |

**Corollary agents must internalize:** You cannot run "two parallel mutating
chains" on the same repo. The architecture forbids it. Planning around that
assumption will always fail quietly.

---

## What actually happened (corrected)

1. **Grok (CAP-S07) held the write lock** — correctly, as the active mutating
   run on that repo root.
2. **Every other mutating dispatch queued behind it** — including Codex and
   Cursor runs. That is correct behavior, not a serialization bug.
3. **The dispatching agent received no queue signal** — three runs were accepted
   and looked "started" from the caller's perspective while they sat in FIFO.
4. **The Cursor zombie was a red herring** for the queue story. Killing a
   12-hour-idle process was still the right hygiene; it did not explain why
   queued runs stayed queued while Grok remained holder.
5. **Lower-priority queued work steals the slot** — cancelling slice S05 (and
   any other queued mutating run not on the critical path) prevents a later
   FIFO entrant from jumping ahead of work that matters.

### Liveness incident (same session)

6. **Grok (holder) was stalled, not advancing** — `progressStale: true`,
   `silenceStatus: "alive, no stream for 397s"`. Process existed; stream did not.
7. **Agent polled the wrong signals** — `status: running` and `HB_AGE` looked
   fine. Those fields do not answer "is it stuck?"
8. **Stall truth was buried** — `progressStale` and `silenceStatus` are in JSON;
   `silenceStatus` prints on a second line under `alln ps` human output. Easy to
   miss. `nextAction` still said `waitForStatus` while stalled.
9. **Queue behind a stalled holder** — FIFO runs cannot start until the holder
   finishes or is killed. A stalled holder is a **floor-wide outage** for mutating
   work, not a local Grok problem.

---

## Why agents get surprised

Allnighter already records FIFO facts on blocked runs (`blocker.holderId`,
`ticketPosition`, `holderAcquiredAt` via `RunService.recordBlockerTicket`) and
surfaces `laneBlocked` on relay/pilot status. Relay agents are told to poll for
it. **Mutating `alln run` dispatch does not close the loop:**

| Gap | Effect on agents |
| --- | --- |
| Dispatch ack looks like "running" | Agent assumes work started; moves on |
| Queue entry does not notify | `NotificationCandidateDetection` ignores `.queued` transitions |
| Ticket not in bootstrap / teaching | Agent never learns to check `blocker` or `alln ps` |
| `--no-wait` / detached handoff | Caller exits before `reportWaits` prints `blockedNotice` |
| No single "floor status" command | Agent must know run vs relay vs pending surfaces |

The defect is **honesty at dispatch time**, not the lock itself.

### Why agents think stalled runs are fine

| Gap | Effect on agents |
| --- | --- |
| `running` reads as healthy | Agent keeps polling; assumes work continues |
| `HB_AGE` sounds like heartbeat | Agent thinks low age = fine; it is stream-silence age |
| `progressStale` is optional JSON | Agents never fetch it; no top-level warning |
| `silenceStatus` is a sub-line in `alln ps` | Buried under the row; not in status summary |
| `nextAction: waitForStatus` while stale | Harness tells agent to keep waiting |
| No `streamSilenceWarning` on team status | Pilot has it; `alln team status` does not |
| Stall diagnosis exists but is optional | `alln ps` may append it — if agent reads line 2 |

The defect is **one-glance status honesty**, not missing telemetry.

---

## Recommendations (simple list)

Ordered by leverage. Each item is one sentence of product law.

### P0 — Dispatch must tell the truth

1. **Never return bare success when a mutating run is only queued.** Every accept
   path (`alln run`, team start, relay dev turn) must include queue state in the
   response: `status: queued`, `laneBlocked` or `blocker` ticket, holder id,
   position, `heldSinceSeconds`.

2. **Print the ticket immediately on stderr** when blocked — same text as
   `RunService.blockedNotice` today, but mandatory for all dispatch surfaces,
   including `--no-wait` and detached handoff ack JSON.

3. **Teach the invariant in `alln bootstrap`.** One paragraph: one mutating run
   per repo; check `alln ps` before spawning another; read `blocker.ticketPosition`
   on status; do not expect parallel mutating chains.

4. **Add `alln floor status --json`** (or extend `alln ps`) as the single agent
   preflight: who holds the write lock on this root, queue depth, ids of queued
   runs, oldest holder age.

### P1 — Agents can plan around the lock

5. **Preflight before mutating dispatch:** `alln floor status` returns
   `slotAvailable: false` + holder summary when busy; agents wait, kill holder,
   or route read-only work — not blind enqueue.

6. **Cancel queued runs you're not executing.** Queued mutating runs are real
   FIFO entries. Drop S05-style slices so they do not take the slot when the
   holder clears.

7. **Separate "research now" from "build now" in agent prompts.** Judgment /
   Spec Review teams (`mutating: false`) do not wait on the write lock. Use them
   for parallel investigation while one mutating run holds the lane.

8. **Surface ticket on run status JSON always** — not only after a long wait.
   `TeamRunJSON.blocker` should be populated on first queue, same as relay
   `laneBlocked`.

### P0 — Running must not look healthy when stalled

9. **Add `streamSilenceWarning` to `TeamStatusResponse`** — same semantics as
   pilot status: true when silence exceeds 6×`waitHintSeconds`. One bool agents
   can branch on.

10. **Derive `advancing: bool` on every status surface** — `advancing = running
    && !progressStale && !laneBlocked`. Agents read one field; humans read one
    column. False means investigate, not keep polling `running`.

11. **Rename `HB_AGE` → `STREAM_AGE` in `alln ps` human table** — stop implying
    process heartbeat. The number is seconds since `lastProgressAt`.

12. **Promote stall to the primary row** — `STALE yes/no` column on `alln ps`;
    when stale, prefix stderr summary on `alln team status --json` with the
    `silenceStatus` line (pilot already prints warnings on human status).

13. **Change `nextAction` when stalled** — not `waitForStatus`. Emit
    `inspectStall` with concrete steps: `alln ps --json`, read stall diagnosis,
    kill/reconcile holder, or escalate. Same pattern as pilot `nextActions`.

14. **Teach Rule 2 in bootstrap** — `running ≠ advancing`. Every status poll must
    check `progressStale` or `streamSilenceWarning`. `STREAM_AGE` rising while
    `running` is the stall smell test.

### P1 — Floor status ties queue + stall together

15. **`alln floor status` reports holder health** — not just who holds the lock,
    but `progressStale`, `silenceStatus`, and `advancing` on the holder. A stalled
    holder explains why the whole FIFO is frozen.

16. **Auto-populate `warnings[]` when `progressStale`** — e.g.
    `"holder stalled: alive, no stream for 397s — mutating queue blocked"`.

17. **Notify peer agents on stall, not only on terminal** — `alln serve`:
    "run X stalled 6min, holding write lock, N queued behind." Agents are the
    audience.

### P2 — Stuck holder hygiene (feeds both incidents)

18. **When holder is stale past threshold, fail holder honestly** — never fake
    progress. Frees the lock for the FIFO.

19. **Reconcile must clear the lane** — killing a holder via `alln ps` /
    `team reconcile` must release the write lock and wake the next queued run.

20. **Notify peer agents when a run enters the queue** — optional `alln serve`
    notification: "run X is #3 behind run Y (held 4h)."

### P3 — Policy agents can follow without archaeology

21. **Document the impossibility of parallel mutating chains** in agent teaching
    and error `agentAction` strings.

22. **Idempotency keys on `alln run`** — retries should not mint three queued runs
    for one intent.

23. **Queue + stall facts on terminal receipts** — `gateWaitMs`, `queueMs`,
    `ticketPosition`, max stall duration while holder.

---

## Agent playbook (today, before slices ship)

```text
BEFORE a mutating dispatch on a repo root:
  alln ps --json          # who holds the lane? any queued runs?
  # Read progressStale + silenceStatus on the holder — not just status:running.
  # If holder is stalled, kill/reconcile it BEFORE enqueueing more mutating work.

AFTER alln run / team start (especially --no-wait):
  alln team status <id> --json
  # Queued? read blocker.ticketPosition, holderId.
  # Running? read progressStale and silenceStatus — NOT status alone.
  # progressStale:true → run is STALLED. Inspect (alln ps), kill holder, or escalate.

EVERY poll while status is running:
  if progressStale == true OR silenceStatus contains "no stream for":
    # Do NOT assume fine. Do NOT only check HB_AGE.
    # Inspect stall diagnosis, kill wedged holder, or switch to read-only work.

WHILE waiting in FIFO:
  # Do not busy-loop. Harness owns the wait (EXECUTION_LANE_BUSY agentAction).
  # If the holder is stalled, you are waiting on a wedged lock — kill holder first.

WHEN deprioritizing work:
  alln run cancel <id>    # drop queued mutating runs not on the critical path
```

---

## Suggested slices

| Slice | Delivers |
| --- | --- |
| **AVQ-S00** | Dispatch ack JSON + stderr always include queue ticket when `status: queued` |
| **AVQ-S01** | `alln floor status --json` (write-lock holder + queue + holder `advancing`) |
| **AVQ-S02** | Bootstrap + `TeachingSnippet`: Rule 1 (one mutator) + Rule 2 (running≠advancing) |
| **AVQ-S03** | Reconcile/kill holder → release write lock → wake next FIFO entrant |
| **AVQ-S04** | Peer-agent notification on queue admission (serve scheduler) |
| **AVQ-S05** | `streamSilenceWarning` + `advancing` on `TeamStatusResponse`; stale changes `nextAction` |
| **AVQ-S06** | `alln ps` human table: `STREAM_AGE` + `STALE` column; stall on primary row |
| **AVQ-S07** | Peer-agent notification when holder goes `progressStale` while blocking queue |

Start at **AVQ-S00** and **AVQ-S05** in parallel — queue honesty and stall honesty
are the same product failure class.

---

## Non-goals

- **Raising the mutating concurrency limit** — violates project law.
- **Driver-specific queue UX** — `cursor_agent` serialization is a separate,
  process-wide spawn gate; this packet is about **per-repo write lock** only.
- **Human GUI polish** — agents are the customer; GUI may follow JSON truth.

---

## Success criteria

An agent operating on a busy root can answer, without human help:

1. How many mutating runs are queued vs actually advancing?
2. Who holds the lock, are they stalled, and for how long?
3. What to kill/cancel so critical path work can run?
4. Whether parallel mutating work was ever possible (no).
5. Whether `status: running` means work is moving (only when `advancing: true`).
