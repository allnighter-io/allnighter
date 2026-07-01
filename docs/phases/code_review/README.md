# GLM Code Review Queue

Status: **active — advisory only, sequential-first**
Owner: Pair-programming control plane + Core hot paths
Updated: 2026-06-27

## What this is

A **read-bounded advisory hardening pass** for seating GLM (OpenCode / Featherless, ~32K window)
on load-bearing slices of Allnighter — without asking it to explore the repo.

**Primary output:** structured findings that surface invariant gaps, security footguns,
and hardening options for the sprint queue. Volume of findings is a feature, not noise.

**Eternal playbook:** [`docs/operations/GLM_Worker_Best_Practices.md`](../../operations/GLM_Worker_Best_Practices.md)

**Follow-up log:** [`follow-up-recommendations.md`](follow-up-recommendations.md)

This is **not** implementation. GLM does not ship fixes here. It produces **structured
findings** that a planner (Composer / you) triages into real sprint slices, perf work,
or rejects.

The pair-programming loop already proved the executor chair works (see
[`Pair_Programming_Team.md`](../Pair_Programming_Team.md) §3). This program applies
the same F1/F4 discipline to **review**:

| Lesson | Review adaptation |
| --- | --- |
| **F1** — reads choke the window | Pre-inline the target file (or line range) in the task; forbid greps |
| **F2** — compaction ≠ stall | Review tasks that touch stall/classification get explicit false-positive lenses |
| **F3** — executor conforms to order | Narrow review questions; required output schema |
| **F4** — pre-resolve symbols | Task author inlines signatures + `file:line` for cross-refs |
| **F5** — serial hardening breadth | Queue many bounded reviews; triage findings into sprint slices |

## How this differs from sprint work orders

| | `docs/phases/sprint/` | `docs/phases/code_review/` |
| --- | --- | --- |
| Goal | Ship a bounded code change | Surface risks + improvement options |
| GLM writes code? | Yes (allowlisted paths) | **No** — one findings markdown file only |
| Proof | Repo test / fixture | Findings file passes section check |
| Output owner | Merged commit | Composer triage → maybe a new sprint doc |

## PM rules (non-negotiable)

### Sequential by default — patience over speed

GLM reasons slowly on hard invariants. That is fine: review is **cheap compute** and
the product is the **findings file**, not a green slice JSON. Default posture:

1. **One review at a time** — `PAIR_CR_PARALLEL=0` (the batch script default).
2. **Long timeouts** — `stallTimeoutSeconds: 3600` on review packets (1 hour); GLM
   may think for a long time before writing via tools.
3. **Success = findings + check** — triage when `findings/CR-NN.md` exists and the
   packet check passes, even if pair status says `stalled`/`failed` (see dogfood).
4. **Serial hardening pass is the happy path** — hard invariant chunks × patient timeout
   is fine; false urgency (parallel + short caps) produced worse outcomes.

Parallel fan-out is **opt-in only** after OpenCode serve/streaming is proven healthy
(see [`OC-S02`](../sprint/opencode/OC-S02-serve-lifecycle-hardening.md)). When enabled,
`scripts/cr_parallel_plan.py` and `CodeReviewParallelSafety` still require disjoint
`findings/` touch paths — but that gate is **necessary, not sufficient** (single
`:4096` serve and `maxConcurrentSpawns: 1` still serialize GLM work).

Advisory reviews **skip `RunWriteLock`** (`RunRequest.advisoryReview`) so serial
findings writes do not queue behind mutating runs.

### Verify pass (default on)

After each review:

```bash
python3 scripts/expand_cr_packet.py --verify . docs/phases/code_review/packets/CR-01.expanded.json
alln pair slice docs/phases/code_review/packets/CR-01.verify.expanded.json ...
```

Verify worker defaults P0 claims to **Reject** unless upheld in inlined source.
**Promote only P0s that survive verify** (`findings/CR-NN-verified.md`).

Disable verify: `PAIR_CR_VERIFY=0` (reasonable for review-only hardening pass; verify
when triaging). Opt into parallel: `PAIR_CR_PARALLEL=1` (not recommended until OC-S02).

### Terminal success (tool-only completions)

OpenCode streaming treats **tool-only completions** as worker success when tools
ran and `session.idle` was observed — even with no closing assistant text. See
`OpenCodeServeClient.streamRun` and `OpenCodeServeClientTests.testStreamRunToolOnlyCompletionIsDone`.
`SliceTerminalClassifier` uses the normal path: worker `.done` + check pass ⇒ slice pass.
No review-mode special casing.

### Symbol stubs

`expand_cr_packet.py` **auto-generates** `resolvedSymbols` from inlined Swift.
Do not hand-author symbols in packet JSON — phantom symbols produce phantom P0s.

## Pipeline (target)

```text
expand (inline + auto symbols)
    → review (GLM)     serial, patient timeout
    → verify (GLM)     optional second pass; same serial discipline
    → triage upheld P0s only → sprint docs
```

## GLM findings promoted so far (from triage)

| Source | Upheld insight | Sprint / backlog |
| --- | --- | --- |
| CR-01 | Owner-token `release`; symlink canonical key | [RUNLOCK-S01/S02](../sprint/runlock/) |
| CR-02 | `contains("compaction")` brittle; empty-output-before-check stalls file writers | backlog classifier |
| CR-03 | Allowlist content not validated | backlog SliceGate |
| CR-04 | Full env → `/bin/sh -c` check = secret exfiltration; skipped check `exitCode: 0` footgun | [CHECK-S01](../sprint/checkrunner/CHECK-S01-minimal-subprocess-env.md) |
| CR-05 | `spawnedPID` never cleared on child exit; undrained pipes; health trusts any :4096 2xx | [OC-S02](../sprint/opencode/OC-S02-serve-lifecycle-hardening.md) |

## Workflow

```text
  You / Composer                GLM (executor)              You / Composer
  ─────────────                 ──────────────              ──────────────
  Pick CR-0N task    ────────▶  Read inlined chunk only
  (or batch queue)              Answer review lenses
                                Write findings/CR-0N.md  ──▶ Triage P0–P2
                                                              Promote → sprint slice
                                                              or archive as noise
```

### Dispatch options

**0 — Expand packet (required for F4 compliance)**

```bash
python3 scripts/expand_cr_packet.py . docs/phases/code_review/packets/CR-01.json
# → writes CR-01.expanded.json with mode=review + inlinedSources
```

Or run the Phase 1 serial hardening pass (default):

```bash
scripts/run_cr_phase1.sh Allnighter
# subset: PAIR_CR_PARALLEL=0 scripts/run_cr_phase1.sh Allnighter 06 07 08
```

**A — MCP `pair_slice` (preferred when pair plumbing is up)**

Dispatch the **expanded** packet (inlined sources — executor must not tool-read):

```bash
alln pair slice --project <token> \
  docs/phases/code_review/packets/CR-01.expanded.json \
  --executor default_chat
```

**B — Direct OpenCode / hand prompt**

Copy the **Copy-paste prompt** block from the task doc into OpenCode with GLM seated.
Paste GLM's reply into `findings/CR-0N.md` manually if not using MCP.

### Triage rules (planner)

1. **P0** — invariant violation, data loss, or pair-loop false-kill → open sprint slice this week.
2. **P1** — real perf/maintainability win with clear allowlist → backlog sprint doc.
3. **P2** — style/nit/opinion → log in findings; do not spawn work.
4. **Noise** — GLM grepped anyway or answered off-scope → discard; tighten task prompt.

GLM is **faithful, not wise** (F3). Treat its output as a cheap second pair of eyes on
invariants, not as architecture authority.

## Task selection principles

Good CR targets:

- **Load-bearing invariants** — write lock, slice gate, terminal classifier
- **Small enough to inline** — ideally &lt;300 lines, one file (or one function chunk)
- **Clear review lenses** — not "make it better"
- **Proof nearby** — existing tests the finding can reference

Bad CR targets:

- 800+ line god files (split into multiple CR tasks with line ranges first)
- GUI-only polish without a stated invariant
- Areas with no tests and no stated contract (review becomes astrology)

## Output contract (every findings file)

```markdown
# CR-0N — <title>

## Summary
(one paragraph)

## Findings

### P0 — …
- **Invariant:** …
- **Evidence:** file:line
- **Suggested fix:** …
- **Suggested slice:** (optional one-line sprint title)

### P1 — …
…

## False alarms ruled out
(what you checked and decided is fine)

## Greps avoided
(confirm you did not explore outside the inlined chunk)
```

## Folder layout

```text
docs/phases/code_review/
  README.md
  queue.md                      ← status board
  follow-up-recommendations.md  ← master log (promote / backlog / reject)
  phase1-runlog.md
  phase2-runlog.md
  phase2-hardening-queue.md
  tasks/CR-0N-*.md
  packets/CR-0N.json
  triage/CR-0N-findings.md
  findings/                     ← gitignored GLM output
```

Add `docs/phases/code_review/findings/` to `.gitignore` if you want raw GLM output
local-only; or commit triaged findings for history.

## Related docs

- Pair loop law: [`Pair_Programming_Team.md`](../Pair_Programming_Team.md)
- Implementation slices: [`sprint/README.md`](../sprint/README.md)
- Perf hot paths: [`Team_Run_Load_Performance.md`](../Team_Run_Load_Performance.md)
- Maintainer lenses: [`docs/operations/code-maintainer/SKILL.md`](../../operations/code-maintainer/SKILL.md)
