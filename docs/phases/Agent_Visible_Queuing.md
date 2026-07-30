# Agent-Visible Queuing

Status: **OPEN — incident-driven (2026-07-30)**
Audience: **agents using `alln`** (humans are rare on this surface)
Created: 2026-07-30
Origin: An agent dispatched three mutating runs (Cursor, Codex, and others) and
had no idea they were queued. Work appeared to "do nothing." A 12-hour-idle
Cursor process looked like the cause; it was not.

Phases are ephemeral. At closeout: promote agent law into `Bootstrap` /
`TeachingSnippet`, contract help, and `AGENTS.md` routing; code remains SSOT
for fields; archive this packet.

**Code SSOT (today):** `RunService.swift` (write lock + FIFO ticket),
`RunWriteLockRegistry`, `ExecutionLaneRegistry`, `RelayCoordinator` (`laneBlocked`),
`ProcessOwnershipSurface` (`alln ps`), `NotificationCandidateDetection`.

---

## The one rule (first principles)

```text
On a given repo root, at most ONE mutating run executes at a time.
Every other mutating run queues behind it — FIFO — until the holder finishes
or is stopped.
```

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

### P2 — Stuck holder hygiene (orthogonal to queue visibility)

9. **When holder stream is stale past threshold, fail holder honestly** — never
   fake progress. Frees the lock for the FIFO. (Stream liveness + ownership
   reconcile already exist; wire them to write-lock release.)

10. **Reconcile must clear the lane** — killing a holder via `alln ps` /
    `team reconcile` must release the write lock and wake the next queued run.
    Process death and lock state must stay coupled.

11. **Notify peer agents when a run enters the queue** — optional `alln serve`
    notification: "run X is #3 behind run Y (held 4h)." Agents are the primary
    consumer; cold-start suppression stays.

### P3 — Policy agents can follow without archaeology

12. **Document the impossibility of parallel mutating chains** in agent teaching
    and error `agentAction` strings — not buried in architecture policy alone.

13. **Idempotency keys on `alln run`** — agents that retry dispatch should not
    mint three separate queued runs for one intent.

14. **Queue depth in run receipts** — terminal receipt notes `gateWaitMs` /
    `queueMs` and `ticketPosition` at start so postmortems do not need journals.

---

## Agent playbook (today, before slices ship)

```text
BEFORE a mutating dispatch on a repo root:
  alln ps --json          # who holds the lane? any queued runs?
  # If a holder exists and you are not willing to wait or stop it — do not enqueue another mutating run.

AFTER alln run / team start (especially --no-wait):
  alln run status <id> --json   # or team status — read blocker.ticketPosition, holderId
  # If status is queued and ticketPosition > 1, you are waiting in FIFO. Poll; do not spawn duplicates.

WHILE waiting:
  # Do not busy-loop. Harness owns the wait (EXECUTION_LANE_BUSY agentAction).
  # Parallelize with read-only teams only.

WHEN deprioritizing work:
  alln run cancel <id>    # drop queued mutating runs not on the critical path
```

---

## Suggested slices

| Slice | Delivers |
| --- | --- |
| **AVQ-S00** | Dispatch ack JSON + stderr always include queue ticket when `status: queued` |
| **AVQ-S01** | `alln floor status --json` (write-lock holder + queue on current root) |
| **AVQ-S02** | Bootstrap + `TeachingSnippet` paragraph on one-mutating-run-per-root |
| **AVQ-S03** | Reconcile/kill holder → release write lock → wake next FIFO entrant |
| **AVQ-S04** | Peer-agent notification on queue admission (serve scheduler) |

Start at **AVQ-S00**. It fixes the incident class without new concepts.

---

## Non-goals

- **Raising the mutating concurrency limit** — violates project law.
- **Driver-specific queue UX** — `cursor_agent` serialization is a separate,
  process-wide spawn gate; this packet is about **per-repo write lock** only.
- **Human GUI polish** — agents are the customer; GUI may follow JSON truth.

---

## Success criteria

An agent that dispatches three mutating runs on a busy root can answer, without
human help:

1. How many are queued vs running?
2. Who holds the lock and for how long?
3. What to cancel so critical path work runs first?
4. Whether parallel mutating work was ever possible (no).
