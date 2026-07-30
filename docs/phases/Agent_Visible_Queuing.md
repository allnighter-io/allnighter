# Agent-Visible Queuing and Stall Truth

Status: **OPEN — incident-driven (2026-07-30)**  
Audience: **agents using `alln`**  
Revised: **v3 + S04 (2026-07-30)** — smallest honest decision contract + `--read-only` dispatch

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

**Read-only (S04):** `alln run --read-only --model <id>` never acquires the
write lock. Use for doc review, spec hardening, report-only probes. Do not use
`--no-commit` for this — it is mutating and queues FIFO.

**Mutating:** A mutating detached dispatch must not claim that work started before its lock outcome is known.

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

- **`alln run --read-only`** — doc feedback / judgment without write-lock queue (S04; **ship first**).
- Honest queue facts in detached-mutating dispatch acknowledgement.
- Queue, liveness, and next-action truth in team status.
- Accurate `ps` labels and existing-row projection.
- Proof that killing or reconciling a terminal holder releases the next FIFO run.
- Bootstrap + help teaching for the two laws and `--read-only` vs mutating dispatch.

### Out of scope

- More than one mutator per root.
- Auto-killing a stalled owner.
- Notifications, retries, new daemon behavior, or a new status command.
- CPU sampling, vendor-specific liveness heuristics, or replacing stream progress.
- Queue analytics, throughput scoring, or GUI polish.
- Silent deduplication of intentionally separate runs.

## Slices

**Ship order:** **AVQ-S04 first** (dogfood friction — agents must not queue for read-only
feedback). S01–S03 follow. S04 unblocks parallel doc/spec work while mutating slices
run on the floor.

### AVQ-S04 — `alln run --read-only` (no write-lock queue)

**Goal:** Agents can get model feedback (doc review, spec hardening, report-only
probes) **without** knowing team catalog names and **without** competing for the
per-repo mutating write lock. Today `alln run --model <id>` defaults to mutating
`default_chat`; `--no-commit` still queues FIFO — a product lie agents hit daily.

**Truth owner:** `RunInvocationResolver` / team resolution (`mutating: false`);
`RunWriteLockRegistry` (must not acquire when read-only).  
**Lie-prone layer:** Default `alln run` path; `--no-commit` name; missing help.

**Product law:**

```text
--read-only  →  mutating: false, single --model seat, no write-lock ticket
--no-commit  →  mutating runs only: skip git commit; STILL takes write lock
```

`--read-only` resolves to a one-seat judgment posture (implementation: force
`code_spec_review_min`-equivalent resolution for the named `--model` — agents
must not need to spell the team id).

**CLI surface:**

```bash
alln run --read-only --model model_grok --json "<prompt or @file>"
alln run --read-only --model model_gpt_terra --json "..."
```

- Requires `--model` (or future `--seat` on a read-only team — out of scope for
  v1 slice).
- Mutually exclusive with mutating-only flags (`--commit-message`, `--try-fix`, …).
- Dry-run and dispatch ack JSON expose `writePolicy: readOnly` and
  `competesForWriteLock: false` (or equivalent existing `effects.repoWrite`).

**Help surface** (SSOT_Founder_Input_Workflow closeout — same slice as flag):

| Item | Requirement |
| --- | --- |
| `HelpTopicRegistry` | Update `alln run` topic (and `team run` if aliased): document `--read-only`, contrast with `--no-commit`, when to use each. |
| `help search` | Must hit from: `read-only`, `readonly`, `no commit`, `write lock`, `queue`, `parallel`, `spec review`, `feedback`, `report only`. |
| `ContractRegistry` | `FlagSpec("read-only", …)`; regenerate via `alln dev export-contracts --check`. |
| `TeachingSnippet` / `Bootstrap` | One reflex line: doc feedback → `--read-only`; build → default mutating `alln run`. |
| Recovery | Empty search → `hello --for run` / menu still valid; topic names only resolvable flags. |
| Examples | `ExampleRecipes` or contract examples: read-only Grok doc review one-liner. |

**Touches:**

- `RunCLI.swift` (flag parse, dry-run, dispatch)
- `RunInvocationResolver` / `ResolvedRunInvocation` (read-only resolution path)
- `ContractRegistry+Milestone1.swift` (`FlagSpec`, mutual exclusivity)
- `HelpTopicRegistry.swift` + generated help corpus
- `TeachingSnippet.swift` (minimal — full two-laws prose stays S03)
- Tests: dry-run contract, write-lock non-acquisition with holder present, help search fixture

**Acceptance:**

1. With a mutating holder on root R, `alln run --read-only --model model_grok --dry-run --json` shows `writePolicy: readOnly` / `repoWrite: false` and does **not** show a write-lock ticket.
2. Same scenario: live `--read-only` run starts without FIFO queue (parallel with holder).
3. `alln run --model model_grok --no-commit --dry-run` still shows mutating / `repoWrite: true` (unchanged); help text states `--no-commit` does **not** skip the queue.
4. `--read-only` without `--model` fails closed with actionable error (name the flag).
5. `help search "read-only"` and `help search "write lock"` return the updated `run` topic.
6. `alln dev export-contracts --check` green after contract bump.

**Works test:** Hold mutating fixture on R; dispatch `--read-only --model model_grok` with short prompt; assert run reaches `running` or `done` without `blocker.ticketPosition` on first status.

**Depends on:** none. **Do this slice before S01–S03.**

**Dogfood note (2026-07-30):** OUR spec hardening and AVQ doc review were blocked or
skipped because agents used mutating `default_chat` instead of read-only dispatch.
S04 fixes the product; S03 teaching reinforces it.

---

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
2. It tells agents to use **`alln run --read-only`** for doc/spec feedback and non-mutating research for parallel work; **not** `--no-commit` for that purpose.
3. It contains no model roster, no invented health claim.
4. Schema/hash installation behavior remains valid.

**Works test:** Parse the generated teaching body and assert the required queue, stall, `--read-only`, and research-parallel instructions.

**Depends on:** AVQ-S01 and AVQ-S04.

## Dependency order

```text
AVQ-S04  (read-only dispatch — ship first; unblocks dogfood)
    │
    ├──→ AVQ-S01 → AVQ-S02
    │         └──→ AVQ-S03 (teaching; needs S04 flag + S01 truth)
    └──→ parallel doc/spec reviews while S01–S02 execute
```

Do not begin notifications or analytics until S01–S03 survive dogfood.

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
- silently turning a killed or reconciled holder into success;
- **queuing read-only doc/spec feedback** because the agent used mutating `default_chat` or thought `--no-commit` was safe parallel.

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

- Four slices: **`--read-only` dispatch (S04, first)**, honest run decision (S01),
  visible/recoverable floor (S02), bootstrap + help reflex (S03).