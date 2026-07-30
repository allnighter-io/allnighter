# Agent-Visible Queuing and Stall Truth

Status: **OPEN — incident-driven (2026-07-30)**  
Audience: **agents using `alln`**  
Revised: **v5 + S04 clarified (2026-07-30)** — `--read-only` is lock policy on `alln run`, not a team

## Core promise

For every mutating run, immediately after dispatch and on every status read, an agent can determine:

```text
Am I queued, unobserved, progressing, stalled, or terminal?
What is the one safe next action?
```

And for parallel feedback: `alln run --read-only --model …` — chat with a model **without** competing for the mutator lock. Not `--no-commit`. Not a team.

`status: running` is lifecycle only. It must never stand in for progress.

## Truth owner

The durable run journal, per-root write-lock ticket, and stream-progress clock own truth.

| Fact | Owner |
| --- | --- |
| One mutator and FIFO ticket per repo root | `RunService`, `RunWriteLockRegistry`, `ExecutionLaneRegistry` |
| Ticket persisted with the run | `RunService.recordBlockerTicket`, run journal |
| Stream progress and stale derivation | `RunActivity`, `StreamLiveness` |
| Write policy / whether this run takes the lock | `RunInvocationResolver` → `ResolvedRunInvocation.writePolicy` / `takesWriteLock` |
| Team-status projection | `AsyncTeamService`, `AsyncTeamStatusMapper`, `TeamStatusResponse` |
| Process/floor projection | `ProcessOwnershipSurface`, `OwnershipJSON` |
| Agent instruction | `TeachingSnippet`, `Bootstrap` |

CLI, GUI, and teaching project this truth. None may infer “healthy” from a live PID, lifecycle `running`, or an elapsed timer.

## Two laws

### 1. One mutator per repo root

At most one mutating run executes in a repo root. Other mutating runs wait FIFO. Research and judgment runs (`writePolicy: readOnly` / `mutating: false`) do not take this lock.

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

**Read-only (S04):** `alln run --read-only --model <id>` is the same one-model chat as bare `alln run --model <id>`, except `writePolicy: readOnly` and `takesWriteLock: false`. It never acquires the per-root write lock and never receives a FIFO ticket. Use for doc review, spec hardening, and report-only probes.

`--read-only` has **nothing to do with `--team`**. Teams are a separate axis (named panels/workflows). This slice does not add team resolution, team aliases, or silent catalog substitution.

Do **not** use `--no-commit` for parallel feedback — it only changes commit instruction; the run remains mutating and queues FIFO.

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

- **`alln run --read-only`** — write-policy flag so feedback never joins the mutator queue (S04; **ship first**).
- Honest queue facts in detached-mutating dispatch acknowledgement.
- Queue, liveness, and next-action truth in team status.
- Accurate `ps` labels and existing-row projection.
- Proof that killing or reconciling a terminal holder releases the next FIFO run.
- Bootstrap + help teaching for the two laws and `--read-only` vs `--no-commit`.

### Out of scope

- More than one mutator per root.
- Auto-killing a stalled owner.
- Notifications, retries, new daemon behavior, or a new status command.
- CPU sampling, vendor-specific liveness heuristics, or replacing stream progress.
- Queue analytics, throughput scoring, or GUI polish.
- Silent deduplication of intentionally separate runs.
- A filesystem sandbox, mirror, clone, or mechanical “blanket read-only layer” (architecture forbids it). `--read-only` is Allnighter write-policy + lock posture, not vendor FS isolation.
- New dry-run fields (`competesForWriteLock`, etc.). Project with existing `writePolicy` + `effects.repoWrite` + ticket absence.
- Team resolution under `--read-only` (no `--team` combo; teams are out of scope for this flag).

## Slices

**Ship order:** **AVQ-S04 first** (dogfood friction — agents must not queue for read-only feedback). S01–S03 follow. S04 unblocks parallel doc/spec work while mutating slices run on the floor.

### AVQ-S04 — `alln run --read-only` (no write-lock queue)

**Goal:** Chat with a model in parallel with the mutator — without FIFO behind the per-repo write lock.

Today bare `alln run --model <id>` is mutating and queues. `--no-commit` still takes the lock. Agents need one flag that says “answer only, don’t compete for the mutator.”

**Truth owner:** `ResolvedRunInvocation.writePolicy` / `takesWriteLock`; `RunService` must not acquire the lock when read-only.  
**Lie-prone layer:** Default mutating `alln run`; `--no-commit` name; doc/help that mentions teams in the same breath as `--read-only`.

**Product law:**

```text
alln run --model <id>                    →  mutating, takes write lock, queues FIFO
alln run --read-only --model <id>        →  same chat, writePolicy: readOnly, no lock, no queue
alln run --no-commit --model <id>        →  still mutating, still takes lock (commit instruction only)
```

`--read-only` is **lock policy on `alln run`**. It is not a team name, not a team alias, not a sandbox, not Spec Review.

**Default path (the whole slice):**

```bash
alln run --read-only --model model_grok --json "Review this doc."
alln run --read-only --model model_gpt_terra --dry-run --json "…"
alln run --read-only --model model_grok --no-wait --json "…"   # detach; still no lock
```

Requires `--model`. No `--team`. No catalog ids to memorize.

**Implementation (keep it thin):**

1. Parse `--read-only` in `RunCLI`.
2. Set `writePolicy: .readOnly` / `takesWriteLock: false` in resolution (`ResolvedRunInvocation` / `RunInvocationResolver`).
3. Skip write-lock acquire and FIFO ticket for this run (`RunService` path already does this when `writePolicy` is read-only — verify, don’t reinvent).
4. Refuse mutator-only flags and `--team` when `--read-only` is set (fail closed, name the conflict).
5. Help + contract + one teaching line so agents find the flag.

No team resolution theater. No mapping to `code_spec_review_min` or any built-in team.

**What this guarantees:** the run does **not** compete for the Allnighter write lock.  
**What this does not guarantee:** the vendor CLI cannot touch files. That is a different problem; this slice does not promise FS isolation.

**Invalid combos (fail closed):**

| Combo | Verdict |
| --- | --- |
| `--read-only` without `--model` | Fail: `--model` required |
| `--read-only` + `--team` | Fail: `--read-only` is not a team path; use `--model` only |
| `--read-only` + `--no-commit` | Fail: mutator-only; confusing |
| `--read-only` + `--commit-message` / `--try-fix` / `--proof` | Fail: mutator-only |
| `--read-only` + `--dry-run` / `--no-wait` / `--json` | Allow (existing output rules) |
| Mutator holds root write lock | **Must not** block start for `--read-only` |

Auth, doctor, and driver capacity gates still apply. Only the write lock is skipped.

**Dry-run / ack (existing fields only):**

- `writePolicy: "readOnly"`
- `effects.repoWrite: false`
- No write-lock ticket / blocker for this run
- `writeLockHeld` may report the root is held by someone else (observation only); must not queue this run or block start

**Help surface:**

| Item | Requirement |
| --- | --- |
| `HelpTopicRegistry` / `alln run` topic | One sentence: parallel feedback → `--read-only --model …`; build → default mutating `alln run`; `--no-commit` does not skip the queue. |
| `help search` | Hits from: `read-only`, `readonly`, `no commit`, `write lock`, `queue`, `parallel`, `feedback`. |
| `ContractRegistry` | `FlagSpec("read-only", …)`; mutual exclusivity with mutator-only flags and `--team`; `alln dev export-contracts --check`. |
| `TeachingSnippet` | One reflex line (full prose in S03). |

**Touches:**

- `RunCLI.swift` — parse flag; refuse `--team` and mutator-only combos
- `ResolvedRunInvocation.swift` / `RunInvocationResolver` — force `writePolicy: .readOnly`, `takesWriteLock: false`; skip lock probe for `canStart`
- `RunService.swift` — confirm non-mutating path never acquires (no second lock path)
- `SandboxHandoffSpool.swift` / `SandboxHandoffRunner.swift` — preserve read-only posture on sandbox handoff
- `ContractRegistry+Milestone1.swift`, `HelpTopicRegistry.swift`, `TeachingSnippet.swift`
- Tests: dry-run fields; live parallel start with holder present; invalid combos; help search; contracts check

**Acceptance:**

1. With a mutating holder on root R, `alln run --read-only --model model_grok --dry-run --json` shows `writePolicy: "readOnly"`, `effects.repoWrite: false`, no ticket; live run reaches `running` or terminal without `blocker.ticketPosition`.
2. `alln run --model model_grok --no-commit --dry-run --json` unchanged (mutating / `repoWrite: true`). Help says `--no-commit` does not skip the queue.
3. `--read-only` without `--model`, or `--read-only` + `--team`, or `--read-only` + mutator-only flags → fail with error naming the conflict.
4. `help search "read-only"` hits the `run` topic; `alln dev export-contracts --check` green.

**Works test:** Hold mutating fixture on R; `alln run --read-only --model model_grok --json` short prompt; first status has no write-lock ticket.

**Depends on:** none. **Ship before S01–S03.**

**Dogfood note (2026-07-30):** Doc review was blocked because agents used mutating `alln run --model …` (or thought `--no-commit` was parallel-safe). S04 adds the flag; S03 teaches it.

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
5. A non-mutating / `--read-only` run never receives a write-lock ticket.
6. The stale threshold reuses `StreamLiveness` / `RunActivity`; this slice creates no second threshold.

**Works test:** Hold a fixture mutator, dispatch a second mutator, then assert queued ticket facts. Freeze the holder’s progress past the shared budget and assert stalled status plus a non-wait action.

**Depends on:** none (ship after S04 for dogfood, not a code dependency).

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

**Goal:** A new agent learns the two laws and the read-only escape hatch before it starts issuing mutating work.

**Truth owner:** `TeachingSnippet`; field semantics remain code-owned.  
**Lie-prone layer:** Bootstrap prose that tells agents to poll lifecycle alone or to use `--no-commit` for parallel feedback.

**Touches:**

- `TeachingSnippet`
- `Bootstrap` only if needed to expose the teaching body
- install/hash tests and contract help

**Acceptance:**

1. Bootstrap says: one mutator per root; `running` is not progress; inspect queue ticket and `progressStale`.
2. It tells agents: doc/spec feedback → **`alln run --read-only --model …`**; build → default mutating `alln run`. **Not** `--no-commit` for parallel feedback.
3. It contains no model roster, no invented health claim, no claim of FS sandbox.
4. Schema/hash installation behavior remains valid.

**Works test:** Parse the generated teaching body and assert the required queue, stall, `--read-only`, and research-parallel instructions.

**Depends on:** AVQ-S01 (status vocabulary) and AVQ-S04 (flag exists to teach).

## Dependency order

```text
AVQ-S04  (read-only write-policy — ship first; unblocks dogfood)
    │
    ├──→ AVQ-S01 → AVQ-S02
    │         └──→ AVQ-S03 (teaching; needs S04 flag + S01 truth)
    └──→ parallel doc/spec reviews while S01–S02 execute
```

Do not begin notifications or analytics until S01–S03 survive dogfood.

## Moat

This is defensible only if Allnighter owns the real **cross-CLI execution boundary** and turns lock + progress truth into a correct action.

| Substitute | What it cannot own |
| --- | --- |
| ChatGPT brainstorming | No repo-root write lock, no FIFO ticket, no shared journal across CLIs |
| Generic process / log watchers | See silence or a PID; not “who holds the Allnighter mutator lock” vs “who is only answering” |
| Vendor-native tooling | One vendor’s session; not the shared root across Cursor, Claude, Codex, Grok, etc. |

The product advantage is not a smarter queue UI. It is:

1. **Correct isolation of feedback** — `--read-only --model …` so chat never wedges the mutator (S04).
2. **Trustworthy wait-or-recover** at the moment an agent would otherwise spawn a duplicate mutator or wait forever (S01–S02).
3. **The same reflex taught next session** (S03).

Without the closed loop below, this collapses to “another status JSON.”

## Closed loop to preserve now

```text
choose posture (--read-only vs mutating)
  → dispatch
  → observe queue / progress truth (or free parallel feedback)
  → wait, research in parallel, cancel, or recover
  → record terminal / settlement facts
  → teach the same reflex to the next agent session
```

S04 implements the posture choice. S01–S02 implement the mutating decision loop. S03 compounds the reflex.

**Not in this phase (flag the missing feedback path):**

```text
queue / stall / mistaken-mutating outcomes
  → per-host or per-niche patterns
  → improve default teaching, status wording, recovery guidance
```

No instrumentation, analytics, or preference compounding from stall histograms here. Without that later loop, the product stays one-shot honesty per run rather than getting smarter per bench.

## Hidden assumptions

1. A stream-progress clock is the chosen liveness proxy; it may not prove useful computation.
2. A queued run can safely wait only if agents can see its ticket and inspect the holder when needed.
3. The repo root is the correct lock domain.
4. The dispatch path can persist enough state to report a meaningful acknowledgement.
5. An operator or agent, not automation, remains authorized to kill a live stalled process.
6. `progressStale: false` means recently observed stream activity, not successful work.
7. Agents will use an explicit flag when taught; naming alone does not stop misuse of `--no-commit` until help + bootstrap land (S04 help + S03).
8. `--read-only` honesty is lock/write-policy honesty, not a claim that every vendor CLI is FS-immutable.

## Exit bar

A fixture triple-dispatch on one root must make all of the following impossible:

- treating FIFO-queued mutators as already executing;
- treating `running` as proof of progress;
- receiving a stalled run whose primary action is “wait”;
- requiring a human to discover who blocks the root;
- silently turning a killed or reconciled holder into success;
- **queuing read-only doc/spec feedback** because the agent used mutating `alln run --model …` or thought `--no-commit` was safe parallel.

Evidence inspected:

- Phase packet v4 (S04 hardened), Product Vocabulary, architecture policy (no blanket read-only layer).
- `ResolvedRunInvocation` / `RunInvocationResolver` (`writePolicy`, `takesWriteLock`).
- `RunDryRunJSON` (`writePolicy`, `effects.repoWrite`), `RunService` write-lock acquire only on mutating path.
- `alln run` help contract: `--no-commit` is commit instruction only.

Key claim:

- The smallest durable product is (1) an explicit non-queue feedback flag and (2) an honest wait-or-recover decision — not a new queue system, health dashboard, or FS sandbox.

Confidence:

- High that existing journal, lock ticket, stream clock, and `writePolicy` already contain the facts; high that S04 is a thin resolver/CLI/help slice; medium that every detached entry path can report mutating lock outcome without a small acknowledgement redesign (S01).

What would falsify this:

- Evidence that a mutating run cannot know its ticket until long after dispatch, or that stream silence is routinely normal for longer than the shared stale budget.
- Evidence that agents still cannot discover `--read-only` after help/bootstrap, or that workers under `--read-only` so often rewrite the tree that lock-only honesty is dogfood-useless without stronger isolation (would demand a different phase, not silent sandboxing here).

What I reject and why:

- `advancing` as a new boolean — hides the unobserved state.
- Notifications, analytics, auto-kill, and a new floor command — none fix the decision-point lie.
- Separate parallel mutating lanes — violate the root safety law rather than explain it.
- Mapping `--read-only` to any built-in team or panel — scope creep; teams stay on `--team`.
- Team resolution theater under `--read-only` — the flag is lock policy on model chat, not a team alias.
- Inventing `competesForWriteLock` or a mechanical blanket read-only layer — duplicates existing policy fields / violates architecture.
- Treating `--no-commit` as “safe parallel” — product lie this phase exists to kill.

Missing observation:

- No per-host evidence yet shows how often agents wait on stale runs, cancel queued work, recover a blocked floor, or still choose mutating default for doc feedback after S04 ships.

Output:

- Four slices: **`--read-only` write-policy (S04, first)**, honest run decision (S01), visible/recoverable floor (S02), bootstrap + help reflex (S03).