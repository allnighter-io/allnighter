# 11 — Draft Race and Comparison

Status: Draft — **the wedge / launch story**
Milestone: D (Parallel judgment)
Depends on: 03, 04, 06, 09
Owner: Mac + iOS
Created: 2026-06-13

## Goal

Dispatch one task to 2–3 lanes from the **same pinned base commit**, run a
different worker in each, capture each preview/screenshot, and present them for
comparison — a **swipeable card stack on iPhone** and a **comparison grid on
Mac**. Then pick a winner. This is the "three options, pick one" wedge and the
heart of the North-Star demo.

## Non-Goals

- "Implement This" handoff (Phase 12), combine/remix (Phase 14), council (Phase
  13). Picking here records the winner; implementing is Phase 12.

## Approach (per `00` §9.4, Loop B)

- **Base-commit pinning:** resolve the target branch tip to one SHA at race
  creation; every race lane branches from it (deterministic comparison).
- **`POST /tasks/:id/race`** creates a `Race` + N lanes; the router assigns one
  worker per lane (distinct workers preferred). Each builds independently; each
  boots its preview (Phase 06) on its own port; artifacts captured per lane.
- **Mac comparison grid:** large-screen grid of drafts with synchronized previews,
  screenshots, summary, test status, and keyboard shortcuts (1/2/3 select, C
  combine, I implement, L land, R remix, Space open preview).
- **iOS race review:** swipeable cards, screenshot-first, live-preview button,
  one-paragraph summary, test/QA status, action buttons.
- **Pick:** `POST /races/:id/pick` sets the winner and emits a `preference.*`
  event seed (full ledger in Phase 15).

## Ordered Slices

- [ ] P11-S01 — `Race` creation: pin base commit, spawn N lanes, assign workers.
- [ ] P11-S02 — Per-lane preview + artifact collection for the race.
- [ ] P11-S03 — Per-draft summary generation (short, artifact-led).
- [ ] P11-S04 — Mac comparison grid + keyboard shortcuts.
- [ ] P11-S05 — iOS swipeable race-review cards.
- [ ] P11-S06 — Pick winner (`/races/:id/pick`) + preference-event seed.

## Works Test

```text
Ask for "three different dashboard directions." Allnighter creates three lanes
from one base commit, runs three workers, boots three previews on three ports,
captures three screenshots, and shows three comparable drafts as a Mac grid and
iPhone card stack. Picking one records the winner and rejected lanes.
```

## Exit Gates

- [ ] Works Test passes (this is the PRD §12.3 / §13.3 Works Test).
- [ ] All race lanes share one base commit; no cross-lane interference.
- [ ] MAC-10, IOS-5 satisfied.
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 12 — turn the pick into execution.
