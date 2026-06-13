# 15 — Preference Ledger and Taste Memory

Status: Draft
Milestone: E (Intelligence layer)
Depends on: 11, 12, 13
Owner: Shared Core + Mac + iOS
Created: 2026-06-13

## Goal

Capture the highest-signal data the product produces — every pick, rejection,
split, remix, "more like this," and revert — as a durable **preference ledger**,
then periodically synthesize it into **project memory** that seasons future work
orders. v1 is a ledger + LLM synthesis, not a custom ML model (source §17).

## Non-Goals

- Pairwise ranking / agent routing optimization (routing lives in Phase 16) and
  speculative ranking (Phase 22) — those consume this data later.

## Approach (per source §17, `00` §10)

- **Inputs:** picks, rejections, split verdicts, remixes, "more like this,"
  reverts, manual ratings, notes on selections, repeated post-landing edits,
  agent win/loss outcomes — all as `PreferenceEvent`s (`00` §7).
- **Derived memory:** periodically summarize events into per-project memory (e.g.
  "prefers dense operational screens, restrained motion, small reversible
  changes"). This synthesis is a natural **local-worker** task (Phase 19) for
  privacy.
- **Injection points:** prompt seasoning, council judge weighting, race
  participant selection, route planning, speculative ranking, risk classification,
  first-draft attempts.
- **User control** (`00` §10): inspect, edit, delete, export memory; disable
  preference learning per project.
- **Forward-compatibility (cheap hook, do not skip).** `PreferenceEvent.event_type`
  is an **extensible enum**. v1 emits founder-taste events
  (`picked_winner`, `rejected`, `split`, `remixed`, `more_like_this`, `reverted`,
  `implemented`). Design it so future *market-outcome* events can be added without
  migration: `founder_pick`, `market_win`, `market_loss`, `guardrail_failure`,
  `experiment_inconclusive`, `promoted_winner`. This keeps the door open for the
  later A/B-testing extension (see `docs/strategy/Allnighter-Agent-AB-Testing-Extension.md`)
  without building any of it now.

## Ordered Slices

- [ ] P15-S01 — Persist all `PreferenceEvent` types from picks/rejections/reverts/remixes.
- [ ] P15-S02 — Preference history view (Mac + iOS).
- [ ] P15-S03 — Memory synthesis job (summarize events → project memory).
- [ ] P15-S04 — Inject project memory into work-order construction.
- [ ] P15-S05 — User controls: inspect / edit / delete / export / disable per project.

## Works Test

```text
After several picks and one revert, the project memory updates with user-approved
preferences, and a new work order visibly includes that memory. The user can
edit, delete, and export the memory, and disable learning for a project.
```

## Exit Gates

- [ ] Works Test passes; memory demonstrably affects a new work order.
- [ ] MAC-15 satisfied; preference data exportable + deletable (`00` §10).
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 16 (routing consumes scorecards + this memory).
