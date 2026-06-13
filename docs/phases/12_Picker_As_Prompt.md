# 12 — Picker-as-Prompt

Status: Draft — **the killer handoff**
Milestone: D (Parallel judgment)
Depends on: 01, 05, 11
Owner: Shared Core + Mac + iOS
Created: 2026-06-13

## Goal

Make a **selection become a work order**. When the user taps "Implement This" on a
strategy, plan, mockup, or running draft (optionally adding a voice/text note),
Allnighter creates or continues a lane and starts implementation — no copy/paste,
no re-explaining. Tap-to-dispatch in **under 5 seconds** (UI shows "preparing"
immediately if agent startup is slow).

## Non-Goals

- Council (Phase 13), combine/remix (Phase 14). This phase is the single-output
  "Implement This" handoff for races and (later) council verdicts.

## Approach (per source §11.4, §16.3, §16.4)

- **Selection event** + **implement-this command** (`POST /outputs/:id/implement`)
  defined in Core. Output types and whether each can be implemented per source
  §16.1 (strategy/plan/mockup → new work order; running code draft → continue/land).
- **Context attachment:** the implement work order attaches original prompt,
  selected output, useful rejected outputs, user note, project memory (Phase 15),
  acceptance criteria, lane context if already built, source artifacts, standing
  orders, protected paths. The user never re-types the chosen answer.
- **Latency:** create the lane record and show "preparing" instantly; the worker
  starts within 5 s.
- Records a `preference.*` "implemented" event.

## Ordered Slices

- [ ] P12-S01 — Selection event + `OutputType` implementability rules in Core.
- [ ] P12-S02 — `/outputs/:id/implement` command (new lane vs continue existing).
- [ ] P12-S03 — Context-attachment assembler (prompt + selection + note + memory + standing orders).
- [ ] P12-S04 — Append user voice/text note to the work order.
- [ ] P12-S05 — Instant lane record + "preparing" state; worker start < 5 s.
- [ ] P12-S06 — Record implemented preference event.

## Works Test

```text
Pick a race draft (or a strategy), say "but make the header sticky," and tap
"Implement This." A lane begins within 5 seconds with the selection + note as its
work order, runs, and returns a landing card. No manual re-prompting occurred.
```

## Exit Gates

- [ ] Works Test passes; tap-to-dispatch < 5 s (or instant "preparing").
- [ ] Context attachment includes selection, note, standing orders, protected paths.
- [ ] MAC-11, IOS-6, IOS-7 satisfied.
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 13 (Council). The thinking→deciding→doing bridge is complete.
