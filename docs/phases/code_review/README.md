# GLM Code Review Queue

Status: **active — advisory only**
Owner: Pair-programming control plane + Core hot paths
Updated: 2026-06-27

## What this is

A **read-bounded advisory queue** for seating GLM (OpenCode / Featherless, ~32K window)
on the highest-leverage slices of Allnighter — without asking it to explore the repo.

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
| **F5** — parallel breadth | Run 10 reviews overnight; triage in the morning |

## How this differs from sprint work orders

| | `docs/phases/sprint/` | `docs/phases/code_review/` |
| --- | --- | --- |
| Goal | Ship a bounded code change | Surface risks + improvement options |
| GLM writes code? | Yes (allowlisted paths) | **No** — one findings markdown file only |
| Proof | Repo test / fixture | Findings file passes section check |
| Output owner | Merged commit | Composer triage → maybe a new sprint doc |

## PM rules (non-negotiable)

### Parallel fan-out — ONLY when safe

Parallel is **never** the default courage move. `scripts/cr_parallel_plan.py` and
`CodeReviewParallelSafety` enforce:

1. **Touch surfaces must be disjoint** — each packet writes only
   `docs/phases/code_review/findings/<sliceId>.md` (or `-verified.md`); no two
   concurrent packets may share a touch path.
2. **Touch must stay under `findings/`** — no Swift edits in parallel review.
3. **Max 4 concurrent** — matches Featherless Premium; set via `ALLNIGHTER_REVIEW_SPAWN_LIMIT`.
4. **Read overlap is OK** — multiple reviews may read the same source file (read-only).
5. **On any violation → serial fallback** — `run_cr_phase1.sh` refuses unsafe batches.

Advisory reviews **skip `RunWriteLock`** (`RunRequest.advisoryReview`) so disjoint
findings writes do not queue behind each other.

### Verify pass (default on)

After each review:

```bash
python3 scripts/expand_cr_packet.py --verify . docs/phases/code_review/packets/CR-01.expanded.json
alln pair slice docs/phases/code_review/packets/CR-01.verify.expanded.json ...
```

Verify worker defaults P0 claims to **Reject** unless upheld in inlined source.
**Promote only P0s that survive verify** (`findings/CR-NN-verified.md`).

Disable verify: `PAIR_CR_VERIFY=0`. Disable parallel: `PAIR_CR_PARALLEL=0`.

### Terminal success (review mode)

For `mode=review` or `reviewVerify`: **check pass ⇒ slice pass**, even when OpenCode
stream is empty (tool-write path). See `SliceTerminalClassifier` + dogfood CR-01.

### Symbol stubs

`expand_cr_packet.py` **auto-generates** `resolvedSymbols` from inlined Swift.
Do not hand-author symbols in packet JSON — phantom symbols produce phantom P0s.

## Pipeline (target)

```text
expand (inline + auto symbols)
    → review (GLM)     ─┐ parallel when safe (≤4)
    → verify (GLM)     ─┘ serial per slice after its review
    → triage upheld P0s only
```

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

Or batch Phase 1:

```bash
scripts/run_cr_phase1.sh Allnighter
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
  README.md           ← this file
  queue.md            ← status board
  tasks/CR-0N-*.md    ← one screen per review task
  packets/CR-0N.json          ← source stubs (readPaths only)
  packets/CR-0N.expanded.json ← generated: mode=review + inlinedSources (gitignored)
  findings/           ← GLM output lands here (gitignored until triaged)
```

Add `docs/phases/code_review/findings/` to `.gitignore` if you want raw GLM output
local-only; or commit triaged findings for history.

## Related docs

- Pair loop law: [`Pair_Programming_Team.md`](../Pair_Programming_Team.md)
- Implementation slices: [`sprint/README.md`](../sprint/README.md)
- Perf hot paths: [`Team_Run_Load_Performance.md`](../Team_Run_Load_Performance.md)
- Maintainer lenses: [`docs/operations/code-maintainer/SKILL.md`](../../operations/code-maintainer/SKILL.md)
