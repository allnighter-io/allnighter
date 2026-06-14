# 13 — Council

Status: Draft
Milestone: D (Parallel judgment)
Depends on: 04, 11, 12
Owner: Mac + Shared Core + iOS
Created: 2026-06-13

## Goal

Add **pre-execution judgment**: fan an ambiguous product/architecture/pricing/
feature question out to several workers, run a critique round where they red-team
each other, synthesize a **verdict + minority report + decision points**, and let
the user accept, pick the dissent, ask another round, or **Implement This**. The
council is not chat — it is parallel judgment that feeds execution.

## Non-Goals

- Custom judge ML — synthesis is prompt-driven. Combine/remix is Phase 14.

## Approach (per source §11.3, §16)

- **`POST /tasks/:id/council`** runs three rounds: (1) independent answers from N
  workers; (2) critique round (each red-teams the others); (3) synthesis round
  producing the `Council` verdict object (`00` §7): `recommendation`,
  `consensus` score, `minority_report`, decision points, implementation
  implication.
- The synthesis/summarizer role is a natural **local-worker** job later (Phase 19)
  for privacy; v1 may use any healthy worker.
- **iOS verdict card:** recommended answer, consensus, strongest dissent, decision
  cards, "Implement This," "Ask one more round." **Mac council view** shows the
  full reasoning.
- "Implement This" reuses Phase 12 (picker-as-prompt) — the verdict (or chosen
  dissent) becomes the work order.

## Ordered Slices

- [ ] P13-S01 — Council fan-out (N independent answers).
- [ ] P13-S02 — Critique round (cross red-team).
- [ ] P13-S03 — Synthesis round → `Council` verdict + minority report + decision points.
- [ ] P13-S04 — iOS verdict card.
- [ ] P13-S05 — Mac council view (full reasoning).
- [ ] P13-S06 — "Ask one more round" + "Implement This" (via Phase 12).

## Works Test

```text
Ask "Should we add team accounts before billing analytics?" The council returns a
recommended verdict, a consensus score, and a strongest-dissent minority report.
Tapping "Implement This" turns the chosen direction into a work order and starts a
lane.
```

## Exit Gates

- [ ] Works Test passes; verdict + dissent both present and distinct.
- [ ] "Implement This" reuses the Phase 12 handoff (no duplicate logic).
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 14 (Combine & Remix).
