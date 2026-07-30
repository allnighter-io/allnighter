# Agent-Visible Queuing and Stall Truth

Status: **OPEN — incident-driven (2026-07-30)**  
Audience: **agents using `alln`**  
Revised: **v3 — smallest honest decision contract**

## Core promise

For every mutating run, immediately after dispatch and on every status read, an agent can determine:

```text
Am I queued, unobserved, progressing, stalled, or terminal?
What is the one safe next action?
```

`status: running` is lifecycle only. It must never stand in for progress.

## Truth owner

The durable run journal, per-root write-lock ticket, and stream-progress clock own truth.

| Fact | Owner |
| --- | --- |
| One mutator and FIFO ticket per repo root | `RunService`, `RunWriteLockRegistry`, `ExecutionLaneRegistry` |
| Ticket persisted with the run | `RunService.recordBlockerTicket`, run journal |
| Stream progress and stale derivation | `RunActivity`, `StreamLiveness` |
| Team-status projection | `AsyncTeamService`, `AsyncTeamStatusMapper`, `TeamStatusResponse` |
| Process/floor projection | `ProcessOwnershipSurface`, `OwnershipJSON` |
| Agent instruction | `TeachingSnippet`, `Bootstrap` |

CLI, GUI, and teaching project this truth. None may infer “healthy” from a live PID, lifecycle `running`, or an elapsed timer.

## Two laws

### 1. One mutator per repo root

At most one mutating run executes in a repo root. Other mutating runs wait FIFO. Research and judgment runs (`mutating: false`) do not take this lock.

There is no parallel mutating escape hatch. The legal parallel escape hatch is non-mutating work.

### 2. Running is not progress

A non-terminal run has one of these operational conditions:

| Condition | Required evidence | Agent action |
| --- | --- | --- |
| **Queued** | Write-lock ticket / blocker is present | Wait at the supplied cadence, cancel self if no longer needed, or inspect the holder. |
| **Unobserved** | Non-terminal, no ticket, no observed progress yet | Wait once at the supplied cadence; do not call it progressing. |
| **Progressing** | Non-terminal, no ticket, `lastProgressAt` exists, `progressStale: false` | Wait at the supplied cadence. |
| **Stalled** | Non-terminal, owner alive, `progressStale: true` | Inspect ownership, then kill/reconcile or escalate. Do not keep waiting. |
| **Terminal** | Lifecycle is terminal | Fetch the result or inspect the recorded failure. |

`progressStale: null` / absent means **unobserved**, not healthy and not stalled. Do not add an `advancing` boolean: it would collapse queued, unobserved, and observed-progress states into a misleading convenience flag.

## Contract

Use existing run/status contracts; do not create a floor manager, status service, or parallel JSON model.

### Dispatch

A mutating detached dispatch must not claim that work started before its lock outcome is known.

If the run is queued when its acknowledgement is emitted, JSON includes its existing queue ticket:

- FIFO position
- holder id and kind
- holder age
- the run’s queued/lifecycle state

A bare successful `dispatched` acknowledgement is allowed only before the run exists; it is not a completion of the mutating-dispatch contract. The caller must receive the run id and the status command that resolves the recorded lock outcome.

### Status

`alln team status <run-id> --json` is the per-run decision response. For a non-terminal run it must project:

- lifecycle `status`
- queue ticket/blocker when the run is behind the write lock
- `lastProgressAt`
- `progressStale`, preserving unknown before first progress
- `silenceStatus` when an owner is alive
- one `nextAction`
- `waitHintSeconds` only when waiting is safe

`nextAction` precedence is fixed:

```text
terminal             → fetchResult
queued               → waitForStatus or inspectBlocker
stalled              → inspectStall
unobserved/progressing → waitForStatus
```

A stalled response must never return `waitForStatus` as its primary next action. A queued response must never imply that the queued run holds the lock.

### Floor inspection

`alln ps --json` remains the cross-run recovery view. It must answer, from its existing process rows:

- who holds the root write lock;
- which runs have FIFO tickets and their positions;
- whether the holder is stale;
- how long since observed stream progress.

The human table must label elapsed stream activity accurately: `STREAM_AGE`, not `HB_AGE`, and visibly mark a stale owner. This is a projection correction, not a new command.

## Scope

### In scope

- Honest queue facts in detached-mutating dispatch acknowledgement.
- Queue, liveness, and next-action truth in team status.
- Accurate `ps` labels and existing-row projection.
- Proof that killing or reconciling a terminal holder releases the next FIFO run.
- One concise bootstrap instruction for the two laws.

### Out of scope

- More than one mutator per root.
- Auto-killing a stalled owner.
- Notifications, retries, new daemon behavior, or a new status command.
- CPU sampling, vendor-specific liveness heuristics, or replacing stream progress.
- Queue analytics, throughput scoring, or GUI polish.
- Silent deduplication of intentionally separate runs.

## Slices

### AVQ-S01 — One honest run decision

**Goal:** A mutating run’s acknowledgement and status response expose enough existing truth for an agent to choose wait, inspect, or recover.

**Truth owner:** Run journal ticket plus `RunActivity` progress clock.  
**Lie-prone layer:** Detached acknowledgement and `AsyncTeamStatusMapper.nextAction`.

**Touches:**

- `RunService` ticket-recording path
- `RunCLI` detached/no-wait acknowledgement
- detached dispatch envelope, if it owns the acknowledgement wire
- `AsyncTeamService.status`
- `AsyncTeamContracts.TeamStatusResponse`
- `AsyncTeamStatusMapper`
- contract schema/help and focused tests

**Acceptance:**

1. With a mutating holder on root R, a second mutating `--no-wait --json` run can be resolved to a run id whose first status shows its FIFO ticket; no response calls it started merely because dispatch succeeded.
2. A queued team-status response includes the ticket or an equivalent existing blocker projection with holder id, position, and held duration.
3. A stale team-status response has `progressStale: true`, `silenceStatus`, and `nextAction.kind == inspectStall` (or the existing equivalent); it does not direct the agent to wait.
4. Before first progress, status preserves unknown progress rather than reporting progress or stale.
5. A non-mutating team never receives a write-lock ticket.
6. The stale threshold reuses `StreamLiveness` / `RunActivity`; this slice creates no second threshold.

**Works test:** Hold a fixture mutator, dispatch a second mutator, then assert queued ticket facts. Freeze the holder’s progress past the shared budget and assert stalled status plus a non-wait action.

**Depends on:** none.

---

### AVQ-S02 — Floor recovery is visible and real

**Goal:** The existing ownership view makes the blocked floor legible, and recovery releases FIFO without invented success.

**Truth owner:** `ProcessOwnershipSurface` plus write-lock settlement.  
**Lie-prone layer:** Human `ps` presentation and stale-holder cleanup.

**Touches:**

- `ProcessOwnershipSurface`
- `OwnershipJSON` only if an existing row lacks a needed ticket/holder fact
- `KillSettlement`, reconcile path, or lock registry only if the proof fails
- focused ownership and FIFO tests

**Acceptance:**

1. `alln ps --json` on a busy root identifies the holder, queued tickets, holder stream age, and holder stale state without another command.
2. The human table says `STREAM_AGE` and marks stale on the primary row.
3. Killing or reconciling a terminal/dead holder releases the root lock within one status read and wakes the next FIFO entrant.
4. A live stalled holder is never silently reaped or reported complete.

**Works test:** Start holder A, queue B, make A stale, inspect `ps`, explicitly kill or reconcile A, then prove B acquires the lane.

**Depends on:** AVQ-S01.

---

### AVQ-S03 — Teach the one reflex

**Goal:** A new agent learns the two laws before it starts issuing mutating work.

**Truth owner:** `TeachingSnippet`; field semantics remain code-owned.  
**Lie-prone layer:** Bootstrap prose that tells agents to poll lifecycle alone.

**Touches:**

- `TeachingSnippet`
- `Bootstrap` only if needed to expose the teaching body
- install/hash tests and contract help

**Acceptance:**

1. Bootstrap says: one mutator per root; `running` is not progress; inspect queue ticket and `progressStale`.
2. It tells agents to use non-mutating research for legal parallel work.
3. It contains no model roster, no new CLI verb, and no invented health claim.
4. Schema/hash installation behavior remains valid.

**Works test:** Parse the generated teaching body and assert the required queue, stall, and research-parallel instructions.

**Depends on:** AVQ-S01.

## Dependency order

```text
AVQ-S01 → AVQ-S02
     └──→ AVQ-S03
```

Do not begin notifications or analytics until this three-step decision path survives dogfood.

## Moat

This is defensible only if Allnighter owns the real cross-CLI execution boundary and turns it into a correct action.

ChatGPT brainstorming can recommend “check status,” but it does not own the repo-root lock, FIFO ticket, process identity, or stream-progress journal. A generic process watcher can see output silence, but not whether a different CLI is the write-lock holder. Native vendor tooling sees one vendor, not the shared root.

The product advantage is not a smarter queue. It is a trustworthy decision at the exact moment an agent would otherwise create duplicate mutators or wait behind a wedge.

## Closed loop to preserve now

```text
dispatch
  → observe queue/progress truth
  → wait, research in parallel, cancel, or recover
  → record terminal/settlement facts
  → teach the same reflex to the next agent session
```

The first three slices implement the action loop. They do not yet make the product learn from aggregate behavior.

Future measurement may close a second loop:

```text
queue and stall outcomes
  → identify recurring host/team failure patterns
  → improve default teaching, status wording, and recovery guidance
```

Do not add that instrumentation in this phase.

## Hidden assumptions

1. A stream-progress clock is the chosen liveness proxy; it may not prove useful computation.
2. A queued run can safely wait only if agents can see its ticket and inspect the holder when needed.
3. The repo root is the correct lock domain.
4. The dispatch path can persist enough state to report a meaningful acknowledgement.
5. An operator or agent, not automation, remains authorized to kill a live stalled process.
6. `progressStale: false` means recently observed stream activity, not successful work.

## Exit bar

A fixture triple-dispatch on one root must make all of the following impossible:

- treating FIFO-queued mutators as already executing;
- treating `running` as proof of progress;
- receiving a stalled run whose primary action is “wait”;
- requiring a human to discover who blocks the root;
- silently turning a killed or reconciled holder into success.

Evidence inspected:

- v2 packet, product vocabulary, execution playbook, and current status/ownership contracts.
- Existing ticket, liveness, status, and process-surface implementations.

Key claim:

- The smallest durable product is an honest wait-or-recover decision, not a new queue system or a health dashboard.

Confidence:

- High that the existing journal, lock ticket, and stream clock already contain the necessary facts; medium that every detached entry path can report the lock outcome without a small acknowledgement redesign.

What would falsify this:

- Evidence that a mutating run cannot know its ticket until long after dispatch, or that stream silence is routinely normal for longer than the shared stale budget.

What I reject and why:

- `advancing` as a new boolean, because it hides the important unobserved state.
- Notifications, analytics, auto-kill, and a new floor command, because none fixes the decision-point lie.
- Separate parallel mutating lanes, because they violate the root safety law rather than explain it.

Missing observation:

- No per-host evidence yet shows how often agents wait on stale runs, cancel queued work, or successfully recover a blocked floor.

Output:

- Three ordered slices: truthful decision contract, visible/recoverable floor, and bootstrap reflex.