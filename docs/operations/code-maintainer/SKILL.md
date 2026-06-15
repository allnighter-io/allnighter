---
name: code-maintainer
description: Behavior-preserving file/module/doc hygiene for Allnighter.
---

# Code Maintainer

Code Maintainer reduces future change cost without changing behavior. It is
whole-file/module hygiene, not closeout deslop and not bug fixing unless the
user explicitly asks for a bug fix.

No single scanner defines repo health. A silent signal advances the next lens;
it never proves global completion. The loop has batches and epochs, not an end.

## When To Use

- "run code maintainer";
- "clean this file/module";
- "find maintenance candidates";
- repeated agent confusion around a file/doc;
- large, mixed, high-churn, or proof-hostile files.

## Scope Modes

| Mode | Trigger | Output |
| --- | --- | --- |
| Scout | No path named | Readonly ranked candidates. |
| Maintain | Path named | Behavior-preserving cleanup in that scope. |
| Split plan | File is large/mixed/risky | Extraction map, no code movement. |
| Friction | Proof or commands keep failing nearby | Remove verification drag first. |
| Journal | After any run | Append `RUNLOG.md`. |

## Lens Model

| # | Lens | Question | Primary signal |
| --- | --- | --- | --- |
| 1 | Structure | Does this file do one job? Is it navigable? | File size, type count, mixed concerns (review until scanner ships) |
| 2 | Duplication | What logic exists in 2+ places? | Review + `rg` for repeated patterns |
| 3 | Dead weight | What is exported/kept but never used? | `swift build` warnings, unused symbol search |
| 4 | Doc truth | Do routed docs still tell the truth? | Contract vs code walk |
| 5 | Contract conformance | Is each contract law enforced by a test? | Contract-doc walk with file:line output |
| 6 | Proof debt | Are high-churn files untested? Are gates wired into `check.sh`? | Test coverage map vs hot files |
| 7 | Consistency deep-read | Which stale area has naming, error-shape, or pattern drift? | `LEDGER.md` |
| 8 | Friction | What keeps confusing agents or breaking proof commands? | Debug/RUNLOG proof failures |

## Lens Selection

- Every regular RUNLOG entry records `Lens: <name> (index k)` and the next
  regular batch runs index `(k + 1) % 8` by default.
- Lookback batches record `Lens: lookback` and do not advance the pointer.
- Missing detectors: run in review mode or skip with a RUNLOG note.
- Anti-starvation: an epoch closes only after every available lens has run at
  least once since the previous epoch boundary.

## Required Workflow

1. Read `AGENTS.md`, `Docs/operations/Contributing.md`, this doc, the last 3
   RUNLOG entries, open queue rows, and `DYNAMIC_RULES.json`.
2. Inspect `git status --short`; do not touch unrelated dirty files.
3. Determine the lens from the RUNLOG pointer, unless an override applies.
4. Establish scope.
5. Run or inspect the lens signal.
6. Find 1-2 local exemplars before editing.
7. Record baseline: lines, obvious jobs, lens signal, proof command.
8. Fix the top 1-3 behavior-preserving findings, or record an honest no-op.
9. Findings needing product decisions become `needs-founder` queue rows.
10. Append `RUNLOG.md` with lens name, pointer, proof, and next lens.

## Guardrails

- MUST preserve behavior unless explicitly fixing a bug.
- MUST NOT edit generated artifacts by hand.
- MUST NOT mix unrelated cleanup into product work.
- MUST NOT split a file without a proof path.
- MUST NOT hide missing proof behind confidence prose.

## Proof Contract

```text
Claim:
Protected invariant:
Truth owner:
Lie-prone layer:
Forbidden regression:
Required proof:
Exact command:
Missing proof:
Verdict: PROOF_READY | PROOF_DEBT | PLAN_ONLY
```

## Batch Completion Rule

Banned closing claims: "loop complete" and "repo clean". Correct closeout:

`Batch N (lens X) complete; queue has M open rows; next regular batch runs lens Y.`

## Report

```text
Scope:
Class:
Files touched:
Behavior guarantee:
Proof:
Before/after signal:
Skipped findings:
Lens:
Next lens:
Next maintenance pressure:
```
