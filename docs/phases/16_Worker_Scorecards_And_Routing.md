# 16 — Worker Scorecards and Routing

Status: Draft
Milestone: E (Intelligence layer)
Depends on: 04, 05, 07, 15
Owner: Shared Core + Mac
Created: 2026-06-13

## Goal

Learn which worker wins for which kind of work, and use it. Capture outcome
metrics per agent and category, compute scorecards, show the worker roster, and
let the router and the user act on them (auto-route + pin worker).

## Non-Goals

- Quota-aware scheduling (Phase 17) — scorecards feed routing; quota is separate.

## Approach (per source §9.3)

- **Metrics captured** per `(agent, category)`: win rate, first-pass test pass
  rate, preview boot success, avg duration, avg human interventions, landing
  success rate, revert rate, user pick rate, quota cost where knowable.
- `WorkerScorecard` (`00` §7) persisted and updated on every lane/landing/pick.
- **Routing:** the router weights worker selection by scorecard for the task's
  category (combined with availability + health + preference memory from Phase 15).
- **Pin worker:** user override per task/project.

## Ordered Slices

- [ ] P16-S01 — Capture outcome metrics on lane/landing/pick events.
- [ ] P16-S02 — Compute per-category scorecards; persist + observe.
- [ ] P16-S03 — Worker roster UI (Mac) with scorecard + health.
- [ ] P16-S04 — Scorecard-weighted routing (with availability + preference memory).
- [ ] P16-S05 — Pin worker override.

## Works Test

```text
After recorded history, worker selection for a UI task shifts toward the agent
with the better UI scorecard; pinning a worker overrides routing; the roster shows
each worker's category scores, landing success, and revert rate.
```

## Exit Gates

- [ ] Works Test passes; routing demonstrably reflects scorecards.
- [ ] MAC-14 satisfied.
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 17 (quota harvester).
