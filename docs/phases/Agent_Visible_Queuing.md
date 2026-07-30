# Agent-Visible Queuing and Stall Truth

Status: **OPEN — incident-driven (2026-07-30)**  
Audience: **agents using `alln`**  
Revised: **v4 + S04 hardened (2026-07-30)** — write-policy flag first; honest queue/stall decision second

## Core promise

For every mutating run, immediately after dispatch and on every status read, an agent can determine:

```text
Am I queued, unobserved, progressing, stalled, or terminal?
What is the one safe next action?
```

And for feedback that must not mutate: an agent can dispatch **without entering the write-lock queue** via an explicit write-policy flag — not by guessing team ids or misusing commit flags.

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

**Read-only (S04):** `alln run --read-only …` resolves with `writePolicy: readOnly` and `takesWriteLock: false`. It never acquires the per-root write lock and never receives a FIFO ticket. Use for doc review, spec hardening, and report-only probes.

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
- Multi-seat Spec Review seating under this flag (use `--team code_spec_review*` for panels).

## Slices

**Ship order:** **AVQ-S04 first** (dogfood friction — agents must not queue for read-only feedback). S01–S03 follow. S04 unblocks parallel doc/spec work while mutating slices run on the floor.

### AVQ-S04 — `alln run --read-only` (no write-lock queue)

**Goal:** One flag so an agent can get model feedback (doc review, spec hardening, report-only probe) **without** knowing judgment-team catalog ids and **without** FIFO behind the per-repo mutator. Today bare `alln run --model <id>` is mutating `default_chat`; `--no-commit` still takes the lock — a product lie agents hit daily.

**Truth owner:** `RunInvocationResolver` / `ResolvedRunInvocation` (`writePolicy`, `takesWriteLock`); `RunService` acquire path (must not acquire when read-only).  
**Lie-prone layer:** Default mutating `alln run`; `--no-commit` name; missing help; any implication that “read-only” is a vendor FS sandbox.

**Product law:**

```text
--read-only   →  writePolicy: readOnly, takesWriteLock: false, no FIFO ticket
--no-commit   →  mutating runs only: skip git commit instruction; STILL takes write lock
```

`--read-only` is a **write-policy selector**, not a team name and not a sandbox. Seat selection stays ordinary:

| Invocation | Resolution |
| --- | --- |
| `--read-only --model <id>` | Default/single-seat path with named model; force `writePolicy: readOnly`. |
| `--read-only --team <id>` | Team must already be non-mutating (`writePolicy: readOnly`); run that team. Optional `--model` / `--seat` per existing judgment rules. |
| `--read-only` alone | Fail closed: name the missing seat (`--model` or a non-mutating `--team`). |

Do **not** expand `--read-only --model X` into `code_spec_review_min` or any multi-seat panel. Panels stay explicit `--team`.

**Not guaranteed:** worker process cannot touch files. Observational teams still run in the real repo; unexpected git change is a post-hoc observation path (`researchGitObservation` where applicable), never a silent reset. The guarantee is: **this run does not compete for the Allnighter write lock.**

**CLI surface:**

```bash
alln run --read-only --model model_grok --json "Harden the named phase packet."
alln run --read-only --model model_gpt_terra --dry-run --json "…"
alln run --read-only --team code_spec_review --json "…"   # multi-seat: team explicit
alln run --read-only --model model_grok --no-wait --json "…"  # detach; still no lock
```

**Flag matrix (fail closed / allow):**

| Combo | Verdict |
| --- | --- |
| `--read-only` + `--model` | Allow |
| `--read-only` + non-mutating `--team` | Allow |
| `--read-only` + mutating `--team` (e.g. `default_chat`, `build_slice`) | Fail: use `--model` without that team, or pick a judgment/research team |
| `--read-only` without `--model` and without `--team` | Fail: name required seat |
| `--read-only` + `--no-commit` | Fail: `--no-commit` is mutator-only; redundant/confusing |
| `--read-only` + `--commit-message` | Fail |
| `--read-only` + `--try-fix` / `--executor` | Fail |
| `--read-only` + `--proof` | Fail (proof is post-mutator) |
| `--read-only` + `--dry-run` | Allow; project `writePolicy: readOnly`, `effects.repoWrite: false`; no ticket for this run |
| `--read-only` + `--no-wait` | Allow; detach path must not wait on / claim write lock |
| `--read-only` + `--stream` / `--json` | Allow per existing mutual-exclusion rules among output modes |
| Root write lock held by another mutator | **Must not** block `canStart` for a read-only resolution. Driver/auth/governor gates still apply. |

**Gates vs lock (do not confuse):**

| Gate | Applies to `--read-only`? |
| --- | --- |
| Per-root write lock / FIFO | **No** — never acquire, never ticket |
| Model ready / source auth / doctor | **Yes** |
| Team governor / driver capacity | **Yes** (same as other non-mutating runs) |
| Execution mixed-source gate | N/A for single-seat / judgment teams as today |

**Dry-run / ack projection (existing fields only):**

- `writePolicy: "readOnly"`
- `effects.repoWrite: false`
- No write-lock ticket / blocker for this run
- `writeLockHeld` may still report the **root** is held by someone else (observation); that must not set this run to queued or block start

**Help surface** (same slice as the flag — agents cannot discover what they cannot search):

| Item | Requirement |
| --- | --- |
| `HelpTopicRegistry` / `alln run` topic | Document `--read-only`; one-line contrast with `--no-commit`; state “not a FS sandbox.” |
| `help search` | Hits from: `read-only`, `readonly`, `no commit`, `write lock`, `queue`, `parallel`, `feedback`, `report only`, `spec review`. |
| `ContractRegistry` | `FlagSpec("read-only", …)`; mutual exclusivity with mutator-only flags; regenerate via `alln dev export-contracts --check`. |
| `TeachingSnippet` / `Bootstrap` | One reflex line only (full two-laws prose stays S03): doc/spec feedback → `--read-only --model …`; build → default mutating `alln run`. |
| Examples | One contract/example recipe: read-only single-model doc review. |

**Touches:**

- `RunCLI.swift` — parse flag; wire into request/normalized flags; refuse invalid combos early with actionable errors
- `ResolvedRunInvocation.swift` / `RunInvocationResolver` — `readOnly` on normalized flags; force `writePolicy: .readOnly` and `takesWriteLock: false`; skip write-lock probe for `canStart`; reject mutating `--team` under the flag
- `RunService.swift` — confirm non-mutating path never calls write-lock acquire (already true for `writePolicy: readOnly`; no second lock path)
- `SandboxHandoffSpool.swift` / `SandboxHandoffRunner.swift` — handoff request must preserve read-only posture so a sandbox-handed-off run keeps `takesWriteLock: false`
- `ContractRegistry+Milestone1.swift` — `FlagSpec`, exclusivity, effects profile unchanged
- `HelpTopicRegistry.swift` + generated help corpus
- `TeachingSnippet.swift` — minimal one-liner (S03 owns full teaching)
- Tests: dry-run field assertions; live non-acquisition with holder present; invalid combos; help search fixture; contracts check

**Optional same-slice nicety (cut if it grows):** when bare mutating dry-run already emits ADP-S02 `alternatives`, prefer teaching `alln run --read-only --model …` over only `--team code_plan`. Not required for Works Test.

**Acceptance (merged):**

1. **Policy + parallel:** With a mutating holder on root R, `alln run --read-only --model model_grok --dry-run --json` shows `writePolicy: "readOnly"`, `effects.repoWrite: false`, and no FIFO ticket for this run; a live short-prompt `--read-only` run reaches `running` or terminal **without** `blocker.ticketPosition` while the holder remains.
2. **Contrast:** `alln run --model model_grok --no-commit --dry-run --json` remains mutating / `effects.repoWrite: true` (unchanged). Help states `--no-commit` does not skip the queue.
3. **Fail closed:** Missing seat; `--read-only` + mutator-only flags; `--read-only` + mutating `--team` — each fails with an error that names the conflicting/missing flag.
4. **Discoverable:** `help search "read-only"` and `help search "write lock"` hit the `run` topic; `alln dev export-contracts --check` green.

**Works test:** Hold mutating fixture on R; dispatch `alln run --read-only --model model_grok --json` with a short prompt; first status has no write-lock ticket and lifecycle is non-queued (`running` or terminal).

**Depends on:** none. **Do this slice before S01–S03.**

**Dogfood note (2026-07-30):** Spec hardening and AVQ doc review were blocked or skipped because agents used mutating `default_chat` (or thought `--no-commit` was parallel-safe). S04 fixes the product surface; S03 teaching locks the reflex.

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
2. It tells agents to use **`alln run --read-only --model …`** for doc/spec feedback and non-mutating research for parallel work; **not** `--no-commit` for that purpose.
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

1. **Correct isolation of feedback** — `--read-only` so judgment never wedges the mutator (S04).
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
- **queuing read-only doc/spec feedback** because the agent used mutating `default_chat` or thought `--no-commit` was safe parallel.

Evidence inspected:

- Phase packet v3 (S04 draft), Product Vocabulary, architecture policy (no blanket read-only layer).
- `ResolvedRunInvocation` / `RunInvocationResolver` (`writePolicy`, `takesWriteLock`, ADP-S02 `code_plan` steer).
- `RunDryRunJSON` (`writePolicy`, `effects.repoWrite`), `RunService` write-lock acquire only on mutating path.
- `alln run` help contract: `--no-commit` is commit instruction; dry-run already projects write policy.
- Built-in teams: judgment/research non-mutating vs `default_chat` / `build_slice` mutating.

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
- Mapping `--read-only --model X` onto multi-seat Spec Review — scope creep; panels stay explicit `--team`.
- Inventing `competesForWriteLock` or a mechanical blanket read-only layer — duplicates existing policy fields / violates architecture.
- Treating `--no-commit` as “safe parallel” — product lie this phase exists to kill.

Missing observation:

- No per-host evidence yet shows how often agents wait on stale runs, cancel queued work, recover a blocked floor, or still choose mutating default for doc feedback after S04 ships.

Output:

- Four slices: **`--read-only` write-policy (S04, first)**, honest run decision (S01), visible/recoverable floor (S02), bootstrap + help reflex (S03).