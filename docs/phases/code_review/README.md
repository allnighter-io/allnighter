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
