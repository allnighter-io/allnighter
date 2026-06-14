# 14 — Combine and Remix

Status: Draft
Milestone: D (Parallel judgment)
Depends on: 11, 12
Owner: Mac + iOS
Created: 2026-06-13

## Goal

Let the user assemble a result from parts of several drafts ("Claude's layout +
Grok's animations"), and spawn variations from a winner. Combine creates a fresh
synthesis lane with full context; Remix spawns sibling drafts from a chosen
output.

## Non-Goals

- New transport/landing mechanics — reuses lanes (03), races (11), and
  picker-as-prompt (12).

## Approach (per source §11.5, §16.2)

- **Combine:** the user selects elements across drafts; Allnighter builds a
  **synthesis work order** describing the chosen elements + their source lanes;
  a fresh lane checks out from the base commit and a synthesis worker applies the
  selected ideas with full context; result returns as a new draft.
- **Remix:** spawn N variations from a selected output (same task, "more like
  this" seasoning from the preference seed).
- Selections feed the preference ledger (Phase 15).

## Ordered Slices

- [ ] P14-S01 — Multi-draft element selection UI (Mac grid + iOS).
- [ ] P14-S02 — Synthesis work-order assembler (elements + source lanes + context).
- [ ] P14-S03 — Fresh synthesis lane → combined draft.
- [ ] P14-S04 — Remix: spawn variations from a winner.

## Works Test

```text
Choose "A's layout, B's animation," tap Combine, and receive a synthesized lane
that contains both. Tap Remix on a winner and receive two sibling variations.
```

## Exit Gates

- [ ] Works Test passes; combined lane reflects both chosen sources.
- [ ] Reuses lane/race/picker plumbing (no duplicate orchestration).
- [ ] Code Audit CLEAN.

## Closeout

Milestone D complete (the wedge is fully expressed). Activate Phase 15.
