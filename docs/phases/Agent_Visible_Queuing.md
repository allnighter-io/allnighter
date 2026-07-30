# Agent-Visible Status

Status: **OPEN — incident-driven (2026-07-30)**  
Audience: **agents using `alln`** (humans are rare on this surface)  
Created: 2026-07-30  
Revised: 2026-07-30 (hardened for implementation — cut sprawl, one contract, PR-sized slices)  
Origin:
- **Queue:** An agent dispatched three mutating runs and never learned they were FIFO-queued. Work looked idle.
- **Liveness:** The same agent polled `status: running` and `HB_AGE` for hours while Grok was stalled. Truth was already present as `progressStale: true` and `silenceStatus: "alive, no stream for 397s"` — fields it never read.

Phases are ephemeral. At closeout: promote agent law into `TeachingSnippet` / `Bootstrap`, contract help, and `AGENTS.md` routing; **code remains SSOT for fields**; archive this packet.

**Code SSOT (today):**
| Concern | Owner |
| --- | --- |
| One mutator + FIFO ticket | `RunService.swift`, `RunWriteLockRegistry`, `ExecutionLaneRegistry` |
| Blocker journal + wire | `RunService.recordBlockerTicket`, `TeamRunJSONMapper`, `TeamRunJSON.BlockerJSON` |
| Blocked human/agent notice | `RunService.blockedNotice`, `reportWaits` |
| Detached dispatch ack | `RunCLI.emitDispatchAck`, `DetachedDispatchJSON` |
| Live team status | `AsyncTeamService.status`, `AsyncTeamStatusMapper`, `TeamStatusResponse` |
| Floor list / process rows | `ProcessOwnershipSurface` (`alln ps`), `OwnershipJSON` |
| Stall derivation | `RunActivity.progressStale`, `OwnershipSilencePresentation`, `StreamLiveness` |
| Pilot parity (already has scream) | `PilotCLI` (`streamSilenceWarning`) |
| Agent teaching | `TeachingSnippet`, `Bootstrap` |
| Notifications (optional later) | `NotificationCandidateDetection`, `NotificationScheduler` |

---

## Core promise

```text
An agent can answer, from one status read after dispatch:

  Is my mutating work advancing, queued, or stalled —
  and what do I do next?
```

That is the whole product. Not more surfaces. Not a smarter queue. **Honest status at the moment the agent decides.**

**Truth owner:** the run journal + write-lock ticket + stream progress clock. CLI/GUI only project; they never invent “healthy.”

---

## Product law (two rules — orthogonal axes)

### Rule 1 — One mutator per repo root

```text
On a given repo root, at most ONE mutating run executes at a time.
Every other mutating run queues FIFO until the holder finishes or is stopped.
Research / judgment teams (mutating: false) never take the lock.
```

| Run kind | Competes for write lock? |
| --- | --- |
| Mutating team run / build-class turn | **Yes** |
| Relay / pilot dev turn / harness proof | **Yes** (same lane) |
| Read-only research / judgment team | **No** — parallel OK |

**Corollary:** There are no “two parallel mutating chains” on one root. Planning around that always fails quietly today — the fix is honesty, not concurrency.

### Rule 2 — Running is not advancing

```text
status: running  → lifecycle: not terminal
identityAlive    → OS process still exists
heartbeatAgeSeconds / HB_AGE → seconds since lastProgressAt (stream silence age), NOT health OK
progressStale    → no stream activity past budget while owner alive → STALLED
silenceStatus    → human line: "alive, no stream for Ns"
```

A run can be **running + alive + stalled** and block the entire mutating floor while doing nothing useful.

| Field agents must use | Meaning |
| --- | --- |
| `status` | Lifecycle only |
| `progressStale` / `silenceStatus` | Stall truth (already derived) |
| `blocker` / `laneBlocked` | Queue truth (already recorded) |
| **`advancing`** (this packet) | One bool: work is moving now |
| **`nextAction`** | What to do — must not say `waitForStatus` while stalled or purely queued without ticket |

---

## What actually happened (facts only)

1. Grok held the write lock correctly.
2. Codex/Cursor mutating dispatches queued FIFO correctly.
3. Dispatch returned “accepted / dispatched” without queue state → agent assumed work started.
4. Cursor zombie was hygiene, not the queue root cause.
5. Queued lower-priority slices still occupy FIFO — cancel work you will not run.
6. Holder was **stalled** (`progressStale`, long silence), not advancing.
7. Agent polled `running` + `HB_AGE`; never branched on `progressStale`.
8. `nextAction` stayed `waitForStatus` while stalled.
9. Stalled holder = floor-wide mutating outage until kill/finish.

**Defect class:** honesty at decision points (dispatch + every status poll), not missing telemetry and not the lock itself.

---

## Minimum honest contract (agent-facing)

One mental model. Three states for a mutating intent:

| State | How the agent knows | Correct next move |
| --- | --- | --- |
| **Advancing** | `status` non-terminal, `advancing: true` | Wait with `waitHintSeconds` |
| **Queued** | `status: queued` **or** blocker/ticket present; not holder | Wait, cancel self, or kill holder if stuck — do not spawn more mutators |
| **Stalled** | `progressStale: true` or `streamSilenceWarning: true` | Inspect (`alln ps --json`), kill/reconcile holder, escalate — **do not** keep waiting on `running` |

Non-mutating research can always run in parallel; teach that as the escape hatch, not a second write lane.

---

## Gaps (only the ones that bite)

| Gap | Why agents fail |
| --- | --- |
| `--no-wait` / detached ack says `dispatched` with no ticket | Caller exits before `reportWaits` / `blockedNotice` |
| Blocking path has `blockedNotice`; not all accept paths do | Inconsistent truth by entry surface |
| `TeamStatusResponse` has `progressStale` but no pilot-style scream | Agents branch on `status` only |
| `nextAction` ignores stall | Harness tells agent to wait on a wedged lock |
| `HB_AGE` name implies heartbeat health | Agents treat rising age as OK or misread it |
| Teaching never states Rule 1 + Rule 2 | Every new host agent rediscovers the lie |

**Already true (do not rebuild):**
- FIFO ticket on journal (`recordBlockerTicket`)
- `TeamRunJSON.blocker` projection
- `progressStale` / `silenceStatus` derivation
- `alln ps --json` rows with stall fields
- Pilot `streamSilenceWarning`
- `--idempotency-key` (opt-in; not silent collapse)
- Reconcile-on-read for dead owners (CLP) — verify lock release in AVQ-S03 only if still broken

---

## Recommendations (collapsed product law — implement as slices below)

Ordered by leverage. Each line is law, not a wishlist.

### Must ship (P0)

1. **Dispatch never looks like “started” when only queued.** Every accept path — blocking `alln run`, team start, `--no-wait` ack, relay/pilot mutating turn — returns machine-readable queue state: `status: queued` (or explicit `laneBlocked` / `blocker`), holder id, ticket position, `heldSinceSeconds`. Stderr prints `blockedNotice` when a TTY/human path exists; JSON always carries the ticket.

2. **Status never looks healthy when stalled.** Every live status surface agents poll (`team status`, `alln ps`, pilot/relay if not already) exposes:
   - `advancing: bool` = non-terminal ∧ ¬queued-behind-lock ∧ ¬progressStale  
   - `streamSilenceWarning: bool` (same semantics as pilot / `StreamLiveness`)  
   - `nextAction` that is **not** `waitForStatus` when stalled → `inspectStall` (point at `alln ps --json` + kill/reconcile)

3. **Teach both rules once** in `TeachingSnippet` (bootstrap paste). Agents re-learn every session from live menu + teaching — not from archaeology.

### Should ship (P1)

4. **One floor preflight on existing `alln ps --json`** (no new noun unless `ps` cannot carry it): root write-lock holder, queue depth / ticket positions, holder `advancing` / `progressStale` / `silenceStatus`. Prefer extend `ProcessOwnershipSurface` over inventing `alln floor status`.

5. **Human table honesty:** rename `HB_AGE` → `STREAM_AGE`; add `STALE` column so the primary row screams.

### Later / optional (P2 — not in critical path)

6. Peer notification when a run enters queue or holder goes stale while blocking others (`NotificationCandidateDetection` + serve). Agents-first; only after P0 is proven.
7. Terminal receipt fields: `queueMs`, max stall while holder (observability, not decision path).
8. Auto-fail stalled holders past a threshold — **out of scope** unless founder authorizes; project law is fail honestly when we kill, never fake progress. Default remains agent/operator kill.

### Explicit non-goals

- Raising mutating concurrency (architecture law).
- Driver-specific spawn gates (e.g. Cursor process-wide) — separate from per-repo write lock.
- Human GUI polish — follows JSON truth later.
- Silent idempotent collapse of intentional duplicate runs — keep `--idempotency-key` opt-in.
- New status microservices or “floor manager” product surface.

---

## Agent playbook (valid today; slices only make it louder)

```text
BEFORE mutating dispatch on a repo root:
  alln ps --json
  # Read holder progressStale + silenceStatus, not status alone.
  # If holder stalled → kill/reconcile BEFORE enqueueing more mutators.

AFTER alln run / team start (especially --no-wait):
  alln team status <id> --json
  # Queued?  blocker.ticketPosition + holderId
  # Running? progressStale / silenceStatus  (never status alone)
  # progressStale:true → STALLED. Inspect, kill holder, or escalate.

EVERY poll while non-terminal:
  if progressStale OR silenceStatus contains "no stream for":
    DO NOT keep waiting as if healthy.

WHILE in FIFO:
  Harness owns the wait. Do not busy-loop. Do not spawn another mutator.
  If holder stalled, you are blocked on a wedge — free the holder first.

WHEN deprioritizing:
  cancel queued mutating runs not on the critical path (they still hold FIFO seats).

PARALLEL work that is always legal:
  judgment / research teams (mutating: false) while one mutator holds the root.
```

---

## Slices (dependency order — one PR each)

Start **AVQ-S00** and **AVQ-S01** first (queue honesty + stall honesty). Teaching can ship with either. Extend `ps` after the two fields exist. Notifications last.

### AVQ-S00 — Dispatch ack tells the truth when queued

**Delivers:** No accept path returns bare success/`dispatched` for a mutating run that is only waiting on the write lock without ticket facts.

**Touches:**
- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift` (`blockedNotice`, ticket recording path)
- `Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift` (`emitDispatchAck`, `runNoWait`)
- `DetachedDispatch` / `DetachedDispatchJSON` (ack envelope fields)
- Team start path that accepts async runs (same ticket projection)
- Relay/pilot mutating entry if it can ack before lane acquire (parity with `laneBlocked`)
- Tests: extend `BlockedRunIsAnnouncedTests`; add no-wait ack fixture when lock held

**Acceptance:**
1. With a holder on root R, `alln run --no-wait --json …` ack includes queue ticket (holder id, position, heldSinceSeconds) or `status: queued` + `blocker` — not only `status: "dispatched"`.
2. Blocking path still prints `blockedNotice` on stderr within first wait cycle.
3. Read-only / non-mutating team start does **not** get a write-lock ticket.
4. Contract schema / help mention the ack fields if wire shape changes.

**Depends on:** nothing  
**Works test:** hold lock with fixture run → second mutating `--no-wait --json` → assert ticket present.

---

### AVQ-S01 — Status scream: `advancing` + stall `nextAction`

**Delivers:** One bool and one honest next action on team status (pilot already has `streamSilenceWarning`).

**Touches:**
- `AsyncTeamContracts.swift` (`TeamStatusResponse` fields)
- `AsyncTeamStatusMapper.swift` (`nextAction` branches)
- `AsyncTeamService.status` (populate `progressStale` path → also `advancing`, `streamSilenceWarning`)
- `StreamLiveness.swift` (reuse; do not fork thresholds)
- `ContractSchema.swift` + generated help if required
- Tests: `AsyncTeamLifecycleTests`, status fixture with frozen `lastProgressAt`

**Acceptance:**
1. `advancing == true` only when non-terminal, not write-lock-queued, and not `progressStale`.
2. When `progressStale == true`, `streamSilenceWarning == true` under pilot-equivalent budget (document multiplier; prefer shared `StreamLiveness`).
3. Stalled → `nextAction.kind == inspectStall` (or equivalent), command points at `alln ps --json` / status inspect — **not** `waitForStatus`.
4. Queued-behind-lock → next action is wait-or-inspect holder, not “fetch result.”
5. Terminal runs: `advancing` false/absent; next action remains `fetchResult`.

**Depends on:** none (parallel with S00)  
**Works test:** fixture running + silence > budget → status JSON has `progressStale`, `advancing: false`, non-wait nextAction.

---

### AVQ-S02 — Teaching: Rule 1 + Rule 2 in the paste block

**Delivers:** Every bootstrap/teaching install states the two rules and the poll fields.

**Touches:**
- `TeachingSnippet.swift` (schemaVersion bump; reflex lines — keep protocol-only, no model catalogs)
- `Bootstrap.swift` if extra prose outside markers is needed (prefer inside teaching body)
- Tests for hash/install state (`TeachingSnippet` parse tests)

**Acceptance:**
1. Teaching body includes: one mutator per root; `running ≠ advancing`; read `progressStale` / ticket / (after S01) `advancing`.
2. Schema version + content hash update; doctor install states still work.
3. No new CLI verbs; no embedded team/model lists.

**Depends on:** can ship with S00 or S01; if S01 lands first, mention `advancing`.

---

### AVQ-S03 — `alln ps` primary-row honesty (+ floor preflight)

**Delivers:** Human table and JSON make queue + stall obvious without a second command.

**Touches:**
- `ProcessOwnershipSurface.swift` (header `HB_AGE` → `STREAM_AGE`; `STALE` column; silence already on line 2 — promote)
- `OwnershipJSON.swift` if aggregate floor summary fields needed
- Prefer **extend** `alln ps --json` with optional root summary (`writeLockHolder`, `queueDepth`, holder advancing) over new `alln floor status`
- Help: `ContractRegistry` / `HelpTopicRegistry` (“queued”, “stalled”, “write lock”)
- Tests: `ProcessOwnershipSurfaceTests`

**Acceptance:**
1. Human table shows stream age under non-heartbeat name; STALE visible on primary row when `progressStale`.
2. `alln ps --json` for a busy root answers: who holds, who is queued, is holder advancing — without reading a second tool.
3. Default `ps` filter law from CLP preserved (`--all` for museum).

**Depends on:** S01 fields ideal but can derive `progressStale` already present on rows.

---

### AVQ-S04 — Kill/reconcile frees the lane (proof, not redesign)

**Delivers:** Proof that killing the holder releases the write lock and wakes the next FIFO entrant. Fix only if broken.

**Touches (if fix needed):**
- `KillSettlement.swift`, `ProcessOwnershipSurface` reconcile path, `RunWriteLock` / `ExecutionLaneRegistry`
- Tests: kill holder → next queued run acquires

**Acceptance:**
1. Kill/reconcile terminal holder → lock free within one status poll.
2. Next FIFO ticket becomes holder (or runs) without manual second reconcile on happy path.
3. No fake “done” for stalled-but-alive without explicit kill (still operator/agent choice).

**Depends on:** S00 useful for observing queue; not blocked by S01.

---

### AVQ-S05 — (Deferred) Peer notify on queue admit / holder stall

**Delivers:** `alln serve` can notify when mutating queue depth > 0 or holder becomes stale while others wait.

**Touches:** `NotificationCandidateDetection.swift`, serve scheduler  
**Acceptance:** transition-edge only (not spam every poll); agents/founder are audience.  
**Depends on:** S00 + S01 field stability. **Do not start until P0 proven in dogfood.**

---

## Implementation order

```text
AVQ-S00 ─┐
         ├─→ AVQ-S02 (teaching) ─→ AVQ-S03 (ps row / floor summary)
AVQ-S01 ─┘                              │
                                        ↓
                                   AVQ-S04 (lane free proof)
                                        ↓
                                   AVQ-S05 (notify, optional)
```

Parallel: S00 ∥ S01. S02 can pair with either PR. S03 after at least S01. S05 last.

---

## Moat (why this is not ChatGPT brainstorming)

| Alternative | Why it loses here |
| --- | --- |
| Single-vendor IDE native queue | One CLI only; no cross-CLI write lock across Claude/Codex/Cursor/Grok |
| Generic “listen to process” tools | No ownership of Allnighter FIFO ticket or run journal |
| Chat brainstorming “just poll status” | Without field discipline, agents poll the lying fields forever |
| Adding more agent features | Amplifies silent queue + silent stall |

**Defensible loop this packet designs for (wire later OK):**

```text
dispatch → honest state (queued | advancing | stalled)
        → agent action (wait | cancel | kill | research-parallel)
        → throughput / fewer wedged floors
        → teaching + nextAction encode the lesson for the next session
```

**Missing feedback paths (flag, do not fake):**
- No per-host metric that “agent polled `running` for N minutes while `progressStale`” — product cannot yet auto-tune teaching per niche.
- No closed loop from queue wait histograms → bootstrap copy.
- P2 notifications are awareness only until an agent consumes them into action.

Ship the decision contract first; measurement hooks (`queueMs`, stall duration on receipt) are optional fuel for a later loop — not a substitute for honesty.

---

## Hidden assumptions (call out)

1. Agents will re-read status JSON fields if they are obvious and `nextAction` points correctly — teaching alone is insufficient; **nextAction is the harness lever**.
2. Stream silence is a good stall proxy (project already chose this; do not invent CPU sampling here).
3. One root = one lock domain (canonical repo root), not “project” abstraction drift.
4. `--no-wait` is the common agent path — blocking `reportWaits` is not enough.
5. Founder will not authorize auto-kill of stalled holders in this phase.

---

## Success criteria

An agent on a busy root can answer **without human help**:

1. How many mutating runs are queued vs actually advancing?
2. Who holds the lock, are they stalled, and for how long?
3. What to kill/cancel so critical-path work can run?
4. Whether parallel mutating work was ever possible (**no**).
5. Whether `status: running` means work is moving (**only if `advancing: true`**).

**Closeout bar:** after S00–S03, a triple-dispatch dogfood cannot silently sit behind a stalled holder while the agent believes all three are “running fine.”
