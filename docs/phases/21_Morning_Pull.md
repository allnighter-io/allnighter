# 21 — Morning Pull

Status: Draft
Milestone: F (Always-on and ship)
Depends on: 07, 09, 11, 13, 17
Owner: iOS + Mac
Created: 2026-06-13

## Goal

Make opening the app in the morning feel like **seeing what the team made**, not
clearing an error queue. A single rewarding digest of overnight work and the
decisions waiting for the user.

## Non-Goals

- Speculative-build generation (Phase 22) — Morning Pull *presents* speculative
  suggestions but a placeholder is fine until Phase 22.

## Approach (per source §11.6, Principle 3)

- **Digest generator** assembles: landed work summary; ready-to-land drafts; races
  needing a winner; council disagreements; failed lanes needing a decision;
  speculative suggestions (placeholder until Phase 22); quota harvested;
  agent-hours worked.
- **Prioritization + rewarding order:** lead with wins and finished work; pending
  decisions next; problems last — each with one-tap next actions.
- The summary is a natural **local-worker** job (Phase 19) for privacy.

## Ordered Slices

- [ ] P21-S01 — Daily digest generator (assemble overnight state).
- [ ] P21-S02 — Prioritization + rewarding card order.
- [ ] P21-S03 — Agent-hours + quota-harvested summary.
- [ ] P21-S04 — Pending-decision cards with one-tap actions.
- [ ] P21-S05 — Speculative-suggestion slot (placeholder → Phase 22).

## Works Test

```text
Opening the app in the morning shows one digest: finished/landed work first, then
races/councils awaiting a verdict, then failed lanes — each with a one-tap action
— plus agent-hours worked and quota harvested.
```

## Exit Gates

- [ ] Works Test passes; order leads with wins, not errors.
- [ ] IOS-12 satisfied.
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 22 (speculative builds).
