# Pair Programming Team — the Control Plane, proven with a free executor

Status: **In progress — PPT-1 + PPT-2 implemented (CLI + queue loop)**
Owner: AllnighterCore + CLI + Mac GUI
Updated: 2026-06-26

> Vocabulary follows the locked cutover — **Chat / Delegate / Execute**, **Team**,
> **worker**, one `team.run` primitive. "Supervisor" and "hammer" are *role names within
> a pair*, not new craft types.

---

## 0. What this actually is

Pair Programming is **not a new product.** It is the sharpest possible **demonstration of
what makes Allnighter unique**: that the control plane can seat *any* model in the
executor chair — including a free, small-context one — and drive it to finish real work,
**on a schedule, across CLIs, with zero conflict, while you sleep.**

If Allnighter can take the *cheapest, weakest, free* executor (GLM-5.2 on Featherless,
32K window) and still produce built, checked work overnight with no human in the loop,
then it can seat *anything* — and the control plane is proven. The GLM half already works
(see §3). This doc is about the half that is uniquely Allnighter's: **scheduling and
safely running that work across models.**

### The vision, in one sentence

> You author the spec. You send it to one of your **Allnighter teams**. It gets built **on
> a schedule, across CLIs, with zero conflict, while you sleep** — and you wake up to the
> work done and the checks run.

---

## 1. The three pillars this is built on

Allnighter is the **neutral control plane for agentic coding work.** Everything below
serves exactly three things — and *only* these three:

| Pillar | What Allnighter does | Why nobody else does it |
| --- | --- | --- |
| **1. Schedule** | turn a pile of work into a queue that runs over time, unattended, with retry / stall handling / budget + time ceilings | the labs want you live in *their* single-model loop; workflow tools (n8n/Zapier) don't understand agentic coding |
| **2. Across any model + provider** | dispatch each unit to any CLI agent — Cursor, Claude Code, Codex, OpenCode/GLM — on the user's **own subscription logins**, under one team / handoff model | API routers (OpenRouter) route stateless tokens, not stateful CLI agents that hold locks and mutate repos; the labs won't seat a competitor's model |
| **3. Safely at volume** | the write-lock / lane / **one-mutating-worker** substrate that lets many agents run without colliding on the same repo | this is the quiet hard part — two mutating agents on one branch is catastrophe; almost no one has built the lock/lane discipline |

Pillar 3 is the one that's easy to undercount. The moment you "schedule a lot of work
across models," the failure mode isn't quality — it's **conflict**. The lock/lane
substrate is what turns *a lot of agents* from chaos into a queue. That is concurrency
control for mutating agents, and it is uniquely Allnighter's.

---

## 2. The boundary — what is Allnighter, and what is NOT

Allnighter does **not** own correctness, and does not pretend to. Trust is unsolvable as a
promise — even expert developers ship bugs that surface years later; nobody clears the
unknown-unknowns bar. So Allnighter promises what it can actually deliver: **the work ran,
safely, across CLIs, unattended — and here is what each worker returned, including whatever
check the repo defined.** Correctness is the repo's claim, surfaced honestly, never
Allnighter's guarantee.

| Concern | Owner | Notes |
| --- | --- | --- |
| The **code** | the model / CLI | the executor writes it |
| The **spec** | you (+ ChatGPT / Composer) | authored outside Allnighter |
| Decomposition into **slices** | the planner (Composer / a large-context worker) | the supervisor role |
| **git** (commit / branch / worktree / revert) | the **repo + CLI** | Allnighter has nothing to do with git |
| The **proof / check** (tests, GUI fixtures, SSOT) | the **repo** | a command/fixture defined in the repo, invoked by the order's prompt |
| **Scheduling, dispatch, lane safety, stall handling, retry/escalate, surfacing returns** | **Allnighter** | the three pillars — this is the whole job |

The proof being repo-owned is the **same boundary already drawn for git, taken to its
conclusion**: Allnighter sends orders; the repo owns everything about *how* the work is
done and *how* it is checked. Allnighter merely runs the repo's declared check to get a
pass/fail signal for the queue, and surfaces the result. It never authors, owns, or
vouches for the check.

---

## 3. What we proved seating GLM in the executor chair

These are **measured** lessons from running real slices (OC-S01a…d + a deliberate
judgment test, `TextUtil.stripReasoningBlocks`, committed at `a4e88754`) through Cursor →
GLM by hand. They are lessons about **how the control plane must drive a small, cheap,
free executor** — not claims that proof is the product.

- **F1 — Reasoning is FREE against the window; READS choke it.** GLM reasoned 10+ minutes
  on one slice at a pinned 11.1K tokens. The window holds *inputs (reads/greps/tool
  output) + outputs (edits)*, never thought. → **The control plane must feed small, read-
  bounded slices.** Size by read surface, not difficulty. Ideal: hard-to-reason,
  tiny-to-read, bounded-to-write.
- **F2 — Compaction is RECOVERY, not a crash.** Near the wall the executor auto-compacts
  and finishes. The terminal "Compaction" print that looks like a meltdown is the model
  saving itself. → **The control plane's stall detection must never kill a compacting
  worker.** This is the single most dangerous false-positive in the loop.
- **F3 — The executor conforms to its order.** GLM silently does whatever the order
  implies — it even repaired a contradiction in a hand-authored test rather than flag it.
  → **The order (including whatever check the repo defines) is what the control plane
  dispatches; Allnighter surfaces the result, it does not judge correctness.** A free
  executor is faithful, not wise; faithfulness is enough *because* the check and the spec
  live upstream of it.
- **F4 — Pre-resolve to kill greps.** Every unresolved symbol becomes a read the executor
  pays for. The planner inlines signatures + `file:line` so the executor never greps.
  (Planner/supervisor concern, upstream of Allnighter.)
- **F5 — Slow, but free and unattended → value is parallel breadth, not speed.** A slice
  GLM takes ~10 min on, a frontier model writes in ~1. Per slice that's a loss; it wins
  only because the 10 min is *the executor's time, not yours.* → **Optimize the control
  plane for unattended overnight throughput, never single-slice latency.**

The real primitive GLM gives the executor chair: **infinite reasoning depth per narrow
slice at zero marginal cost** (Featherless doesn't count reasoning against window or
bill). The control plane's job is to keep the executor in the regime where that's a
superpower — small reads, one mutating worker, run it while you sleep.

---

## 4. Architecture — the loop, as control plane

A **coordinator daemon** runs a durable queue forward with zero human input until the
queue is empty, a budget/time ceiling hits, or a unit escalates.

```text
                     ┌─────────────────────────────────────────────┐
  Planner   ────────▶│  SliceQueue (durable, on-disk)              │
  (Composer /        │  [ pending | running | passed | failed |    │
   answer worker)    │    escalated ]                              │
   fills batch       └───────────────┬─────────────────────────────┘
   + re-engages                      │ pop next pending
   on escalation                     ▼
                          ┌──────────────────────────┐
                          │   PairCoordinator.loop    │   ← Allnighter
                          │  ONE RunWriteLock holder  │     (pillars 1+3)
                          └───────────┬──────────────┘
        ensure serve  ◀───────────────┤  per unit:
        (OpenCodeServeCoordinator)     │  1. ensureRunning()
        SliceGate (allowlist+danger) ◀─┤  2. gate (danger / scope)
        RunService.run (1 worker) ◀────┤  3. dispatch executor (any CLI) ← pillar 2
        run repo-declared check ◀──────┤  4. run the order's check → exit code
        terminal classifier ◀──────────┤  5. classify: pass | fail | stall
                                       ▼
              pass  → mark passed, link runs, advance
              stall (NOT compaction) → nudge, same unit, max N
              fail  → mark escalated, hand back to the planner
```

Note step 4: Allnighter **runs the check the order declares and reads its exit code** to
drive the queue. It does not define the check — that's repo-owned (§2). "Pass" means *the
repo's own check returned 0*, surfaced honestly; it is not a correctness guarantee.

### 4.1 Reuse map (real on `feat/design-chain`)

| Need | Use existing | File |
| --- | --- | --- |
| Serve lifecycle | `OpenCodeServeCoordinator.ensureRunning()` `async throws` | `AllnighterEngine/OpenCodeServeCoordinator.swift` |
| Dispatch one worker (any CLI) | `RunService.run(_:origin:…) -> Result<TeamRun, RunServiceError>` | `AllnighterEngine/RunService.swift` |
| **Zero-conflict invariant (pillar 3)** | `RunWriteLockRegistry.shared` (`waitToAcquire`/`release`, FIFO, `RunWriteLock.key(repoRoot:)`) | `AllnighterEngine/RunWriteLock.swift` |
| Chain template (parent→gate→child→link) | `FollowUpCoordinator.runTryFix` + `Outcome` | `AllnighterEngine/FollowUpCoordinator.swift` |
| Gate shape ("danger blocks, doubt doesn't") | `TryFixGate.evaluate(packet:executor:) -> Decision` | `AllnighterCore/TryFixGate.swift` |
| Spawn + timing/outcome | `WorkerRunner.invoke` → `WorkerRunOutcome` (`status`, `errorKind`, `output`, `ttftMs`, `exitCode`, `reasoning`) | `AllnighterEngine/WorkerRunner.swift` |
| Executor driver (the free seat) | `opencode.json` (`id:"opencode"`, `maxConcurrentSpawns:1`, smoke contract, `timeoutSeconds:600`) | `Apps/AllnighterMac/Resources/Drivers/opencode.json` |
| Run persistence + parent/child links | `RunStore` (per-id folder, atomic `run.json`, `owner.pid` liveness) + `RunLink{kind, runId}` | `AllnighterEngine/RunStore.swift`, `AllnighterCore/TeamRun.swift` |
| Stall signals | `StalledWorkDetector.scan` + `StallRecoveryService` (`keepWaiting`/`dismiss`) | `AllnighterEngine/{StalledWorkDetector,StallRecoveryService}.swift` |
| CLI dispatch + JSON envelope | `AllnighterCLI` switch → `PairCLI` (stub exists); `RunCLI` as pattern; `AllnighterCLI.jsonString`/`emitFailure` | `AllnighterCLI/{AllnighterCLI,RunCLI,PairCLI}.swift` |

> Note: `ProjectVerificationService` / `ExecutionLaneRegistry` / `ProjectDispatchService`
> referenced in older notes are **not present on this branch** (verified 2026-06-26).
> Build on `RunService` + `RunWriteLockRegistry` above.

### 4.2 New components to build (small, well-bounded)

| New | Responsibility | Mirrors |
| --- | --- | --- |
| `WorkSlicePacket` + parser | typed order the planner authors (§6) | `FixPacket` / `FixPacketParser` |
| `SliceGate` | danger flags + `touchAllowlist` scope check | `TryFixGate` |
| `CheckRunner` | run the order's **repo-declared** check as a bounded `/bin/sh -c` subprocess; capture exit/stdout-tail → advance signal (NOT a verifier — see §2) | — |
| `SliceAttemptPrompt.assemble` | render packet → executor prompt (F1/F4 shape) | `FixAttemptPrompt` |
| `SliceTerminalClassifier` | `WorkerRunOutcome` + check exit + **compaction marker** → `{passed, failed, stalled}` | extends `StalledWorkDetector` |
| `SliceQueue` + `SliceQueueStore` | durable queue of packets with status | `RunStore` folder pattern |
| `PairCoordinator` | `runSlice` (one) and `runQueue` (the loop) | `FollowUpCoordinator` |

---

## 5. Zero-conflict at volume (pillar 3 — the load-bearing safety)

This is what makes "a lot of work across CLIs while you sleep" safe instead of catastrophic.

- **One mutating worker** for the entire queue run, held under `RunWriteLockRegistry` keyed
  on repo root. The loop is **sequential by construction** — never two executors mutating
  one branch. (The pending-execute-lane invariant is INVIOLABLE.)
- **`touchAllowlist` enforced** by `SliceGate`: a unit touching outside its declared files
  is danger → blocked, not dispatched.
- **Danger flags hard-stop:** credentials, distribution/signing, destructive git,
  sandbox/TCC. Never auto-dispatched.
- **Bounded retries:** max `maxRetries` nudges per unit, then escalate — never an infinite
  loop.
- **Budget + time ceiling:** `--until` and `--max-tokens` are hard caps; the loop stops and
  reports, it does not run past dawn.
- **Compaction ≠ stall** (F2): never kill a recovering worker.
- **Allnighter does no git.** The executor's CLI owns commit/branch/worktree/revert.

### Compaction-vs-stall classifier (get this right or the loop kills itself)

| Observed | Meaning | Action |
| --- | --- | --- |
| Alive, context flat, compaction marker, still producing | Compaction in progress | **WAIT** (compaction grace window). Never kill. |
| Alive, no output, no compaction, age > `stallTimeoutSeconds` | Genuine hang | nudge (same unit, max N) |
| Exit 0, empty extracted output | Empty result | nudge (same unit, max N) |
| Repo check exits non-zero | The repo's check failed | escalate to planner (no auto-retry of same code) |
| Featherless "busy" / 429 | Infra backoff | exponential backoff (not a nudge, not an escalation) |

---

## 6. `WorkSlicePacket` — the order the control plane dispatches

Authored by the planner (Composer / large-context worker), **outside** Allnighter.
Allnighter carries it, gates it, dispatches it, runs its check, and surfaces the result.

```text
WorkSlicePacket
  schemaVersion        : Int
  sliceId              : String              // e.g. "OC-S02b"
  title                : String

  // --- read budget (F1, F4) — planner keeps SMALL so the executor never chokes ---
  readPaths            : [ReadAnchor]        // { path, symbol?, lineRange? } — minimal, anchored
  resolvedSymbols      : [ResolvedSymbol]    // { name, signature, definedAt:"file:line" } — kills greps
  estReadTokens        : Int?                // for the read-budget gate

  // --- the work ---
  intent               : String             // behavior to achieve, in prose
  skeleton             : String?             // optional inline code skeleton (NOT a literal full patch)
  touchAllowlist       : [String]            // required for mutating units; enforced by SliceGate

  // --- the check (repo-owned; Allnighter only RUNS it for the advance signal) ---
  check                : Check
    .method            : .command | .guiFixture | .userObservation   // reuse FixPacket.ProofMethod
    .command           : String?             // exit 0 = advance; defined by the repo, not Allnighter
    .fixture           : String?             // repo fixture name (guiFixture)

  // --- loop control (Allnighter's) ---
  maxRetries           : Int                 // default 2 (nudge same unit)
  stallTimeoutSeconds  : Int                 // default 300
  compactionGraceSeconds : Int               // default 180 (extra wait while compacting — F2)
  dangerFlags          : [String]            // credentials, distribution, destructive-git, sandbox/TCC…
```

Dropped from earlier drafts: `literalEdits` (a fully spoon-fed patch means the planner
already did the work — leverage → 1) and any notion that Allnighter authors the check.

---

## 7. Implementation phases

### PPT-1 — Single-unit handoff (CLI) — *done*

| Slice | Deliverable | Status |
| --- | --- | --- |
| PPT-S01 | `WorkSlicePacket` + parser + tests (`AllnighterCore`) | **done** |
| PPT-S02 | `SliceGate.evaluate` (allowlist + danger) + tests | **done** |
| PPT-S03 | `CheckRunner` (bounded `/bin/sh -c`, exit + stdout-tail) + tests | **done** |
| PPT-S04 | `SliceAttemptPrompt.assemble` (F1/F4 shape) + tests | **done** |
| PPT-S05 | `PairCoordinator.runSlice` | **done** |
| PPT-S06 | `alln pair slice <packet-path> --json` | **done** |

### PPT-2 — The autonomous queue (the product surface) — *done*

| Slice | Deliverable | Status |
| --- | --- | --- |
| PPT-S07 | `SliceQueue` + `SliceQueueStore` | **done** |
| PPT-S08 | `SliceTerminalClassifier` incl compaction-not-stall | **done** |
| PPT-S09 | `NudgePrompt` template | **done** |
| PPT-S10 | `PairCoordinator.runQueue` loop | **done** |
| PPT-S11 | `--until`, `--max-retries`; `alln pair run --queue <dir>` | **done** |
| PPT-S12 | Escalation on check-fail → `escalated` status | **done** |

### PPT-3 — Planner automation (close the loop)

| Slice | Deliverable | Status |
| --- | --- | --- |
| PPT-S13 | `WorkSlicePlan` authoring: large-context worker (or Composer seat) emits the batch as structured output | open |
| PPT-S14 | Auto re-engage planner on escalation — **three GLM attempts → planner takeover once → advance queue** | **done (MCP + CLI)** |

### PPT-4 — Mac GUI (last; "send to team", projection-only)

| Slice | Deliverable |
| --- | --- |
| PPT-S15 | **Send-to-team → schedule**: pick a queue, pick the seats (planner CLI + executor CLI), set `--until`; the overnight-queue rail shows per-unit status, pass/fail, lane, across-CLI |
| PPT-S16 | `pair_build` team preset surfaced in the composer (seat 1 planner, seat 2 free executor) |

### PPT-5 — Serve lifecycle hardening

| Slice | Deliverable |
| --- | --- |
| PPT-S17 | `OpenCodeServeCoordinator` owned by the Mac background coordinator (start on launch) |
| PPT-S18 | `opencode serve` health in Doctor / setup card |

---

## 8. Non-goals (V1)

- Parallel mutating executors (one write lock, one mutating worker — pillar 3).
- Executor reading the full repo / `AGENTS.md` / phase boards (violates F1/F4).
- Streaming the executor's tokens to the UI (the value is *waking up to results*, not
  watching).
- Allnighter authoring or owning the check / proof (repo's job — §2).
- Allnighter performing git.
- Allnighter promising correctness (unsolvable — §2). It promises *ran, safely,
  unattended, here's what came back.*
- Replacing the planner with the executor.

---

## 9. Open questions

- Compaction marker: a stable parseable OpenCode signal, or infer from "context flat +
  alive + no answer delta"? (Spike before S08.)
- Planner seat: Composer (manual today) or an in-app large-context worker? (S13.)
- Queue storage: in the parent `TeamRun` JSON, or a dedicated `SliceQueueStore`? (Leaning
  dedicated, mirroring `RunStore`.)
- Featherless rate limits under an overnight queue — how small does N-parallel get?
  (Measure on the first real overnight run.)

---

## 10. Works Test — the acceptance is *unattended, across CLIs, zero conflict*

V2 — single unit (PPT-S06):
```bash
alln pair slice docs/phases/sprint/pair/PPT-smoke.json --project . --json
# → { sliceId, status: passed, check: { exitCode: 0 }, childRunId, parentRunId }
```

**V3 — the product (PPT-S11+). The acceptance test for the whole feature:**
```bash
alln pair run --queue docs/phases/sprint/pair/ --project . --until 07:00 --max-retries 2 --json
```
Acceptance — this is the vision, made literal:
- Runs **with no human in the loop** until the queue is empty or 07:00.
- Each unit dispatched to its seat's CLI (planner + free executor) — **across models**.
- The write lock is **never** held by two workers — **zero conflict**.
- Each unit's **repo-declared check** is run and its result surfaced honestly (pass = the
  repo's check returned 0, not a correctness claim).
- Output: `{ passed: N, escalated: M, slices: [ … with check result + childRunId ] }`.
- You **wake up** to N built-and-checked units and an M-item escalation list — having
  touched nothing overnight.

If V3 needs you awake, the feature is not done.

---

## 11. Routing

| Work | Read |
| --- | --- |
| Dispatch / lane safety (pillars 2+3) | `RunService.swift`, `RunWriteLock.swift`, `WorkerRunner.swift` |
| Chain / gate template | `FollowUpCoordinator.swift`, `TryFixGate.swift`, `FixPacket.swift` |
| Serve lifecycle | `OpenCodeServeCoordinator.swift`, `opencode.json` |
| Stall / compaction | `StalledWorkDetector.swift`, `StallRecoveryService.swift` |
| Persist queue / link runs | `RunStore.swift`, `TeamRun.swift` (`RunLink`) |
| Add the CLI | `AllnighterCLI.swift`, `PairCLI.swift`, `RunCLI.swift` |
| MCP orchestration | `pair_slice`, `pair_run` MCP tools + `MCPPairHandlers.swift` |
| Slice packet format | `docs/phases/sprint/README.md` |
| First proven slice (reference executor run) | `git show a4e88754` — `TextUtil.stripReasoningBlocks` + its check |
```
