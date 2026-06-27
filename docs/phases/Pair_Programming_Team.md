# Pair Programming Team — Autonomous Overnight Build Queue

Status: **Spec — implementation-ready (PPT-1 buildable today)**
Owner: AllnighterCore + CLI + Mac GUI
Updated: 2026-06-26

> Vocabulary note: this doc follows the locked language cutover — **Chat / Delegate /
> Execute**, **Team**, **worker**, one `team.run` primitive. "Supervisor" and "hammer"
> below are *role names within a pair*, not new craft types.

---

## 1. The promise (read this first)

Allnighter's whole reason to exist — the pun in the name — is **work produced while you
sleep**. The pair-programming feature is only valuable if it delivers exactly that:

> A queue the supervisor fills once, that the hammer grinds through **unattended,
> overnight**, gated by proofs, so you **wake up to proof-green, merge-ready work** —
> and a short list of the few slices that need a human.

**If it requires you to copy-paste a slice, watch it, and paste the next one, there is
nothing here.** Manual copy-paste was the *learning harness*, not the product. Every
design decision below is judged against one question: **does this run the queue forward
without a human in the loop?** If a feature needs babysitting, it is not done.

The economic inversion that makes this possible: **hammer compute is free and unlimited**
(OpenCode + GLM-5.2 on Featherless), while the **supervisor is the scarce resource**
(large-context, frontier-quality, expensive, *and your attention*). So we spend the
supervisor sparingly — author a batch, walk away — and let the hammer burn freely.

---

## 2. What we proved (empirical findings from the manual sprint)

These are **measured**, not theorized. They were learned running OC-S01a…d + a
deliberate judgment-test slice (`TextUtil.stripReasoningBlocks`) through Cursor → GLM by
hand. They are load-bearing — the architecture exists to honor them.

### F1 — Reasoning is FREE against the context window; **reads** are what choke it
GLM reasoned for **10+ minutes on a single slice while token usage stayed pinned at
11.1K**. Thinking does not accumulate in the window. The window is consumed by **inputs
(file reads, grep output, tool results)** and **outputs (the edits being written)** —
never by thought. The slice that failed (OC-S01d) did not fail from "too much reasoning";
it failed from **reading 4 source files + 3 greps** before it ever wrote a byte.

> **Design law:** size slices by *read surface*, not by difficulty. The ideal slice is
> **hard-to-reason, tiny-to-read, bounded-to-write.** Give GLM problems that need deep
> thinking over a small amount of text. (`stripReasoningBlocks`: 1-file read, unlimited
> think, ~50-line write — the platonic shape.)

### F2 — Compaction is RECOVERY, not a crash
When the hammer approaches the wall it **auto-compacts** (summarizes its own context) and
**keeps going to completion**. The terminal "Goal / Constraints / Progress / Compaction"
print that *looks* like the model melting down is the opposite — it is the model saving
itself. We repeatedly mistook it for a crash and killed runs that were about to succeed.

> **Design law:** the coordinator must recognize compaction and **never treat it as a
> stall**. This is the single most dangerous false-positive in the loop: the naive
> stall heuristics (timeout / empty-stdout → kill) would murder workers mid-recovery.

### F3 — The proof IS the product
GLM **silently conforms to whatever the proof asserts.** In the judgment test it
discovered a genuine contradiction between the prose spec and a test assertion, and
instead of stopping to flag it, it **inferred an unstated rule and wrote code to satisfy
the assertion**, narrating "the test is the contract." A *correct* proof yielded
genuinely correct, non-obvious code (a depth-counted state machine, not a naive regex). A
*wrong* proof would have yielded confident, green, **wrong** code — with no warning.

> **Design law:** proof correctness is the entire remaining intelligence and the entire
> remaining risk. Proofs are **supervisor-authored, behavioral, and red-first** (see §7).
> "Build stays green" is **not a proof** — it tests compilation, not behavior.

### F4 — Window = reads + writes. Budget it; pre-resolve to kill greps
The window filled when GLM had to *find* things (`grep` for a symbol signature, read a
big neighbor file). Every symbol the supervisor leaves unresolved becomes a read the
hammer pays for. The slices that landed pre-resolved their symbols inline and said "do
not grep."

> **Design law:** the supervisor pre-resolves every symbol the slice references
> (signature + `file:line`), and the packet declares a **small** `readPaths[]`. A
> sizing gate refuses/splits slices whose read surface won't leave room to write.

### F5 — GLM is wall-clock SLOW but free and unattended → value is parallel breadth, not per-slice speed
A slice that a frontier model writes in ~1 minute took GLM **~10 minutes**. Per slice,
that is a wall-clock *loss*. It is only a win because the 10 minutes is **the hammer's
time, not yours** — you queue N slices and walk away. Throughput is **N-slices-per-night**
(bounded by lane safety + Featherless rate limits), not slice latency.

> **Design law:** optimize for queue throughput and unattended reliability, never for
> single-slice speed. A loop that needs a human between slices throws away the only win.

### F6 — The feeding pattern that works (proven packet shape)
Every slice that landed shared this shape. The packet schema (§6) formalizes it.
```text
<SLICE-ID> ONLY.
Read ONLY: <small list, with line anchors: file (symbol ~line-range)>
Touch ONLY: <1–2 files>
Do NOT grep. Do NOT read <the big neighbors>.
<Resolved symbols inline: signatures + the exact enum cases / API to call>
<Intent as behavior, or an inline skeleton — NOT a literal patch>
Proof: <exact command>. <If compaction screen appears, that is normal — keep going.>
WRITE NOW.
```
Note what is **not** here: no "literal old→new for every line." A fully spoon-fed patch
means the supervisor already did the work and the hammer is pure overhead (leverage → 1).
The packet is a **spec the hammer implements**, not a diff it transcribes.

---

## 3. The economic model — when this wins, when it loses

| | Wins | Loses |
| --- | --- | --- |
| **Resource spent** | supervisor authors a batch once, then sleeps | supervisor babysits each slice |
| **Slice shape** | hard-to-reason, small-to-read, behavioral proof | broad context, taste-based, "build green" proof |
| **Throughput** | N slices grind in the lane overnight | 1 slice at a time, human-paced |
| **Failure** | escalates to a short morning list | silently merges confident-wrong code |

**Leverage ratio** = (lines of correct hammer output) ÷ (lines of supervisor packet).
Track it per slice. `< ~2` → just let the supervisor do it. `> ~5` → printing money.
A literal-patch packet is `~1` and always loses; a `"same pattern in the other file"`
line is `~15`.

**The real primitive is not "infinite output." It is infinite *reasoning depth per
narrow slice, at zero marginal cost*** (F1 + F5). A frontier model charges for every
reasoning token; GLM-on-Featherless thinks for 10 minutes on a hard local problem for
free. We sell that — bounded by read-surface and wall-clock, guarded by proof quality.

---

## 4. Architecture — the autonomous loop

The heart is a **coordinator daemon** that runs a durable queue forward with zero human
input until the queue is empty, a budget/time ceiling is hit, or a slice escalates.

```text
                     ┌─────────────────────────────────────────────┐
  Supervisor  ──────▶│  SliceQueue (durable, on-disk)              │
  (Cursor /          │  [ pending | running | passed | failed |    │
   answer worker)    │    escalated ]                              │
   fills batch       └───────────────┬─────────────────────────────┘
   + re-engages                      │ pop next pending
   on escalation                     ▼
                          ┌──────────────────────────┐
                          │   PairCoordinator.loop    │
                          │  one RunWriteLock holder  │
                          └───────────┬──────────────┘
        ensure serve  ◀───────────────┤
        (OpenCodeServeCoordinator)     │ per slice:
        SliceGate (allowlist+danger) ◀─┤  1. ensureRunning()
        RunService.run (1 worker) ◀────┤  2. gate (danger/allowlist)
        ProofRunner (bounded sh) ◀─────┤  3. dispatch hammer (mutating)
        terminal classifier ◀──────────┤  4. run proof
                                       │  5. classify: pass | fail | stall
                                       ▼
              pass → mark passed, link runs, advance
              stall (NOT compaction) → nudge, same slice, max N
              fail (proof red) → mark escalated, emit supervisor task
```

### 4.1 Reuse map (what's real on `feat/design-chain`)

| Need | Use existing | File |
| --- | --- | --- |
| Serve lifecycle | `OpenCodeServeCoordinator.ensureRunning()` `async throws` | `AllnighterEngine/OpenCodeServeCoordinator.swift` |
| Dispatch one worker (mutating) | `RunService.run(_:origin:…) -> Result<TeamRun, RunServiceError>` | `AllnighterEngine/RunService.swift` |
| One-writer-per-repo invariant | `RunWriteLockRegistry.shared` (`waitToAcquire`/`release`, FIFO, `RunWriteLock.key(repoRoot:)`) | `AllnighterEngine/RunWriteLock.swift` |
| Chain template (parent→gate→child→link) | `FollowUpCoordinator.runTryFix` + `Outcome` | `AllnighterEngine/FollowUpCoordinator.swift` |
| Gate shape ("danger blocks, doubt doesn't") | `TryFixGate.evaluate(packet:executor:) -> Decision` | `AllnighterCore/TryFixGate.swift` |
| Spawn + timing/outcome | `WorkerRunner.invoke` → `WorkerRunOutcome` (`status`, `errorKind`, `output`, `ttftMs`, `exitCode`, `reasoning`) | `AllnighterEngine/WorkerRunner.swift` |
| Hammer driver | `opencode.json` (`id:"opencode"`, `maxConcurrentSpawns:1`, smoke contract, `timeoutSeconds:600`) | `Apps/AllnighterMac/Resources/Drivers/opencode.json` |
| Run persistence + parent/child links | `RunStore` (per-id folder, atomic `run.json`, `owner.pid` liveness) + `RunLink{kind, runId}` | `AllnighterEngine/RunStore.swift`, `AllnighterCore/TeamRun.swift` |
| Stall signals | `StalledWorkDetector.scan` + `StallRecoveryService` (`keepWaiting`/`dismiss`) | `AllnighterEngine/{StalledWorkDetector,StallRecoveryService}.swift` |
| CLI dispatch + JSON envelope | `AllnighterCLI` switch → `PairCLI` (stub exists) ; `RunCLI` as pattern; `AllnighterCLI.jsonString`/`emitFailure` | `AllnighterCLI/AllnighterCLI.swift`, `RunCLI.swift`, `PairCLI.swift` |

### 4.2 New components to build (small, well-bounded)

| New | Responsibility | Mirrors |
| --- | --- | --- |
| `WorkSlicePacket` + parser | typed handoff (§6) | `FixPacket` / `FixPacketParser` |
| `SliceGate` | danger flags + `touchAllowlist` scope check | `TryFixGate` |
| `ProofRunner` | run a declared command as a **bounded** `/bin/sh -c` subprocess; capture exit/stdout/timeout → `ProofResult` | — (no shared proof runner exists today; **verify** no `ProjectVerificationService` landed before building) |
| `SliceAttemptPrompt.assemble` | render packet → hammer prompt (the F6 shape) | `FixAttemptPrompt` |
| `SliceTerminalClassifier` | `WorkerRunOutcome` + proof + **compaction marker** → `{passed, failed, stalled}` | extends `StalledWorkDetector` |
| `SliceQueue` + `SliceQueueStore` | durable queue of packets with status | `RunStore` folder pattern |
| `PairCoordinator` | `runSlice` (one) and `runQueue` (the loop) | `FollowUpCoordinator` |

---

## 5. The compaction-vs-stall law (F2 — get this right or the loop kills itself)

The classifier must distinguish three terminal-ish states. Only one is a real stall.

| Observed | Meaning | Action |
| --- | --- | --- |
| Process alive, **context size flat**, compaction marker emitted, still producing | **Compaction in progress** | **WAIT** — extend the deadline by one compaction grace window. Never nudge/kill. |
| Process alive, no output, no compaction, age > `stallTimeoutSeconds` | Genuine hang | nudge (same slice, max N) |
| Exit 0 but `output` empty after extraction | Empty result | nudge (same slice, max N) |
| Proof command exits non-zero | **Real failure** | escalate to supervisor (do **not** auto-retry the same code) |
| Featherless "model is busy" / 429 | Infra backoff | exponential backoff retry (not a nudge, not an escalation) |

Detection signals to combine: `WorkerRunOutcome` timing fields (`lastAnswerDeltaAt`,
`rawStdoutChunkCount`), the OpenCode compaction stdout marker, `RunStore` `owner.pid`
liveness, and `StalledWorkDetector` age thresholds. **Compaction grace** is a distinct,
larger timeout than `stallTimeoutSeconds`.

---

## 6. `WorkSlicePacket` (typed handoff — final schema)

Spec-shaped, not patch-shaped (F6). Carries the read-budget and the proof discipline.

```text
WorkSlicePacket
  schemaVersion        : Int
  sliceId              : String              // e.g. "OC-S02b"
  title                : String

  // --- read budget (F1, F4) — the supervisor keeps this SMALL ---
  readPaths            : [ReadAnchor]        // { path, symbol?, lineRange? } — anchored, minimal
  resolvedSymbols      : [ResolvedSymbol]    // { name, signature, definedAt:"file:line" } — kills greps
  estReadTokens        : Int?                // for the sizing gate (§8)

  // --- the work ---
  intent               : String             // behavior to achieve, in prose
  skeleton             : String?             // optional inline code skeleton (NOT a literal full patch)
  touchAllowlist       : [String]            // required for mutating slices; enforced by SliceGate

  // --- the proof (F3) — supervisor-authored, behavioral, red-first ---
  proof                : Proof
    .method            : .command | .guiFixture | .userObservation   // reuse FixPacket.ProofMethod
    .command           : String?             // exit 0 = pass; MUST fail before the work (red-first)
    .behavioralTest    : String?             // exact assertions the supervisor owns (the rail)
    .expectRedBefore   : Bool                // require proof to FAIL on baseline before dispatch

  // --- loop control ---
  maxRetries           : Int                 // default 2 (stall/nudge on same slice)
  stallTimeoutSeconds  : Int                 // default 300 (genuine-hang threshold)
  compactionGraceSeconds : Int               // default 180 (extra wait while compacting — F2)
  dangerFlags          : [String]            // credentials, distribution, destructive-git, sandbox/TCC…
```

Drop from earlier drafts: `copyPastePrompt` (now rendered by `SliceAttemptPrompt`) and
`literalEdits` (retracted — leverage → 1).

---

## 7. Proof discipline — the whole ballgame (F3)

Because the hammer conforms to the proof silently, the proof is where all correctness
lives. Three non-negotiable rules:

1. **Behavioral, not compilation.** The proof must assert *behavior* (a failing test that
   the change makes pass), never just "`swift build` succeeds." A green build on an
   add-a-guard change proves nothing.
2. **Supervisor owns the expected values.** The hammer may write production code *and*
   the test file, but the **assertions/expected values are authored by the supervisor**
   and pasted verbatim into the packet as the rail. The hammer cannot weaken what it
   doesn't get to choose.
3. **Red-first.** Before dispatch, `ProofRunner` runs the proof against the baseline and
   **requires it to FAIL** (`expectRedBefore`). A proof that is already green is a
   non-proof — it would let the hammer "pass" without doing anything. This is the direct
   countermeasure to F3's silent-conformance risk.

`ProofRunner` contract:
```text
ProofRunner.run(command, cwd, timeout) async -> ProofResult
  ProofResult { passed: Bool, exitCode: Int?, stdoutTail: String, timedOut: Bool }
  // bounded /bin/sh -c subprocess at repo root; capture only a tail (don't blow our own logs)
```
The coordinator feeds the hammer **only** `passed` + `stdoutTail`'s first failure line —
never the full test output (F1: that would be a giant read).

---

## 8. Slice-sizing gate (read-budget enforcement — F1, F4)

```text
SliceSizer.check(packet) -> .ok | .tooLarge(estReadTokens, suggestSplit)
  budget = readPaths byte-sum (→ tokens) + headroom for writes + compaction reserve
  refuse if budget > ~50% of the hammer context window (≈16K of 32K) → leave room to write + compact
  NEVER size on reasoning (F1: reasoning is free)
```
Failing the gate is **prevention**, not the §5 detection. OC-S01d would have been
*rejected and auto-split* into a/b/c/d before ever spawning — which is exactly what the
human did by hand. Prefer **one read-path per slice**; pre-resolve symbols so the hammer
never greps.

---

## 9. Supervisor seat (the scarce resource)

- **Authors a batch** (`WorkSlicePlan` = ordered slice IDs or inline packets) from **one**
  read of the area, then disengages. Maximize **slices-per-supervisor-pass**.
- **Re-engages only on escalation** (proof-fail). The coordinator emits a supervisor task
  containing the failed slice + `stdoutTail`; the supervisor re-plans (split, fix the
  proof, add a resolved symbol) and pushes new pending slices.
- **V1: manual supervisor** (Cursor authors slices into `docs/phases/sprint/<topic>/`).
  **V2: in-app** large-context answer worker emits the plan as structured output.
- The supervisor never holds the write lock and never mutates the repo — it only writes
  packets. (Allnighter does no git; the hammer's CLI owns all git.)

---

## 10. Implementation phases

### PPT-1 — Single-slice handoff (CLI) — *buildable today*

| Slice | Deliverable | Mirrors / uses |
| --- | --- | --- |
| PPT-S01 | `WorkSlicePacket` + parser + tests (`AllnighterCore`) | `FixPacket`/`FixPacketParser` |
| PPT-S02 | `SliceGate.evaluate` (allowlist + danger) + tests | `TryFixGate` |
| PPT-S03 | `ProofRunner` (bounded `/bin/sh -c`, `ProofResult`) + **red-first** check + tests | new; verify no `ProjectVerificationService` |
| PPT-S04 | `SliceAttemptPrompt.assemble` (F6 shape) + tests | `FixAttemptPrompt` |
| PPT-S05 | `PairCoordinator.runSlice`: ensureRunning → SliceGate → red-first proof → `RunService.run` (mutating, lane lock) → proof → link via `RunLink` | `FollowUpCoordinator.runTryFix` |
| PPT-S06 | `alln pair slice <packet-path> --json` (extend existing `PairCLI`) | `RunCLI` |

### PPT-2 — The autonomous queue (THE product)

| Slice | Deliverable |
| --- | --- |
| PPT-S07 | `SliceQueue` + `SliceQueueStore` (durable; status pending/running/passed/failed/escalated; `RunStore` folder pattern) |
| PPT-S08 | `SliceTerminalClassifier` incl **compaction-not-stall** (§5); compaction marker detection + grace window |
| PPT-S09 | Nudge injection: `NudgePrompt` (template, not LLM), same slice, max `maxRetries` |
| PPT-S10 | `PairCoordinator.runQueue` loop: pop → runSlice → advance/nudge/escalate; single `RunWriteLock` holder for the whole run |
| PPT-S11 | Ceilings + hard stop: `--until <HH:MM>`, `--max-tokens N`, `--max-retries N`; `alln pair run --queue <dir> …` |
| PPT-S12 | Escalation: on proof-fail mark `escalated` + write supervisor task (failed slice + `stdoutTail`) |

### PPT-3 — Supervisor automation

| Slice | Deliverable |
| --- | --- |
| PPT-S13 | `WorkSlicePlan` authoring: large-context answer worker (or Cursor seat) emits structured plan |
| PPT-S14 | Auto re-engage supervisor on escalation (closes the overnight loop) |

### PPT-4 — Mac GUI (last, projection-only)

| Slice | Deliverable |
| --- | --- |
| PPT-S15 | Overnight queue rail: per-slice status, pass/fail, lane, leverage ratio; parent-run → slice-attempts → proof results |
| PPT-S16 | Pair-build team preset surfaced in composer |

### PPT-5 — Serve lifecycle hardening

| Slice | Deliverable |
| --- | --- |
| PPT-S17 | `OpenCodeServeCoordinator` owned by Mac background coordinator (start on app launch) |
| PPT-S18 | `opencode serve` health in Doctor / setup card |

---

## 11. Safety laws (carried from Try Fix, sharpened by the findings)

- **One mutating worker** under `RunWriteLockRegistry` for the entire queue run — the
  pending-execute-lane invariant is INVIOLABLE (concurrent Execute on one branch is
  catastrophic). The loop is sequential by construction.
- **`touchAllowlist` enforced** by `SliceGate`: a slice that touches outside its list is
  danger → blocked.
- **Danger flags hard-stop:** credentials, distribution/signing, destructive git, sandbox/
  TCC. Never auto-dispatched.
- **Proof red-first** (§7): no dispatch unless the proof currently fails.
- **Bounded retries:** max `maxRetries` nudges per slice, then escalate — never an
  infinite loop on red.
- **Budget + time ceiling:** `--until` and `--max-tokens` are hard caps; the loop stops
  and reports, it does not run past dawn.
- **Compaction ≠ stall** (§5): never kill a recovering worker.
- **Allnighter does no git.** The hammer's CLI owns commit/branch/worktree/revert. Safety
  is the write lock + bounded packet + proof + hard stops + the user's own undo, never
  Allnighter touching the repo's history.

---

## 12. Non-goals (V1)

- Parallel hammers (one write lock, one mutating worker — by safety law).
- Hammer reading the full repo / `AGENTS.md` / phase boards (violates F1/F4).
- Streaming the hammer's tokens to the UI (final-output posture; the value is *waking up
  to results*, not watching).
- Literal-patch packets (retracted — leverage → 1).
- Allnighter performing git.
- Replacing the supervisor with the hammer (the supervisor authors proofs; that is
  irreducibly frontier work).

---

## 13. Open questions

- Compaction marker: is there a stable, parseable OpenCode signal, or must we infer
  compaction from "context flat + process alive + no answer delta"? (Spike before S08.)
- Supervisor seat: always Cursor, or an in-app large-context answer worker? (S13 decides.)
- `WorkSlicePlan` storage: in the parent `TeamRun` JSON, or a dedicated `SliceQueueStore`?
  (Leaning dedicated store, mirroring `RunStore`.)
- Featherless rate-limit behavior under an overnight queue — does GLM throttle hard enough
  to make N-parallel-nightly small? (Measure during the first real overnight run.)

---

## 14. Works Test — the real acceptance is *unattended*

V1 manual (learning harness — already passing):
```text
opencode serve up; Featherless GLM configured.
Cursor authors a sprint slice + verbatim behavioral test (the rail).
Paste to OpenCode; on a genuine stall send NUDGE; ignore compaction screens.
Run the proof. Repeat. (This is the harness, NOT the product.)
```

V2 automated single slice (PPT-S06):
```bash
alln pair slice docs/phases/sprint/opencode/OC-S02b.md --json
# → { sliceId, status: passed, proof: { passed: true }, leverage: 6.2, childRunId, parentRunId }
```

**V3 — the product (PPT-S11+). The acceptance test for the entire feature:**
```bash
alln pair run --queue docs/phases/sprint/opencode/ --until 07:00 --max-retries 2 --json
```
Acceptance:
- Runs **with no human in the loop** until the queue is empty or 07:00.
- Each slice gated **red-first**; every proof is **behavioral**.
- The write lock is **never** held by two workers; lane invariant intact.
- Output: `{ passed: N, escalated: M, slices: [ … with proof + leverage ] }`.
- You **wake up** to N merge-ready slices and an M-item escalation list — and you touched
  nothing overnight.

If V3 needs you awake, the feature is not done.

---

## 15. Routing

| Work | Read |
| --- | --- |
| Build the proof runner / gate | `TryFixGate.swift`, `FixPacket.swift`, `FollowUpCoordinator.swift` |
| Dispatch a worker | `RunService.swift`, `RunWriteLock.swift`, `WorkerRunner.swift` |
| Serve lifecycle | `OpenCodeServeCoordinator.swift`, `opencode.json` |
| Stall / compaction | `StalledWorkDetector.swift`, `StallRecoveryService.swift` |
| Persist queue / link runs | `RunStore.swift`, `TeamRun.swift` (`RunLink`) |
| Add the CLI | `AllnighterCLI.swift`, `PairCLI.swift`, `RunCLI.swift` |
| Sprint packet format | `docs/phases/sprint/README.md` |
| First proven slice (reference) | `git show a4e88754` — `TextUtil.stripReasoningBlocks` + its 9-test rail |
