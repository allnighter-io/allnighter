# Design3 - Verdict, Remix Brief + the Build Flywheel

Status: **Build-ready after Design2.**
Owner: Founder + Shared Core + Mac
Created: 2026-06-14
Updated: 2026-06-14
Depends on: Design1 (board), Design2 (critique), RB3 (finalizer shape), RB4 (direct dispatch)

## Why this is the close (and the thing no single-shot tool can do)

For code, RB3's finalizer *reduces* — synthesis is the hero. For design, **taste is
the human's** and the hero move is **design-level synthesis**: composite the best of
each frame into something none of the seats produced, see it rendered, then ship its
code. This slice closes the loop: human verdict → Lead Designer tradeoff → **remix →
re-render → `DesignBrief` → build council**. It reuses RB3's finalizer shape and
RB4's dispatch, and it is what makes the design council a *flywheel* rather than a
prettier one-shot generator.

## Goal

The human picks (pairwise A/B for 4+). The optional Lead Designer names the tradeoff
*after* the look. The user composites regions/systems across frames into a
structured `DesignBrief` that **re-renders as a round-2 frame** (reusing the Design1
render harness), then becomes a build-council prompt via "Implement This" — carrying
the winning frame as a reference image. Every verdict is logged so a future
taste-memory seat can learn.

## Non-Goals

- No multi-round tournament beyond one remix round (named, deferred in Design0).
- No taste-memory `house_style` seat yet — Design3 only **logs** verdicts so the
  ledger accumulates.
- No Allnighter-owned git/worktree rules on the build handoff (RB4's boundary
  holds: Allnighter invokes the CLI; the repo owns git).
- Single-seat "more like this" is **in** (the iteration loop); full multi-board
  history is a stretch goal, not a gate.

## Design

### The verdict (human decides — Beam 3)

The board is the **first truth surface**; the verdict UI never shows an AI pick
first.

- **Pick directly** when ≤3 frames — click the winner (the amber treatment).
- **Pairwise A/B** when 4+ — "A or B?" rounds collapse to a winner with low cognitive
  load. The visual-diff slider (below) is the comparison surface.
- **`chosen_frame.json`** records `{ seatId, persona, rationale?, rejected:
  [{seatId, why?}], timestamp }` — a real decision artifact (visibly adopted *and*
  rejected, RB3's honesty contract), and **the signal taste memory will learn from.**

### Visual-diff slider (the dopamine, for redesigns)

When the run has a `redesign-this` reference image, the winner view offers a
**split-screen slider**: drag a vertical handle — old (their current UI) on the left,
the council's winner on the right. Validates the tool's value in one motion and is
the most shareable moment. Reuses the reference image already on the run; for
greenfield runs the slider compares two chosen frames instead.

### The Lead Designer speaks *second* (anti-anchoring)

Optional design synthesizer. **Sequencing is the law**, not a nicety:

1. Board first, in silence; the human forms a reaction and/or picks.
2. **Then** the Lead Designer **names the tradeoff** — never a verdict: *"B wins
   hierarchy and a11y, but A's empty-state is the only one a first-run user won't
   bounce on. Power users → B; activation → A."* It draws on `design_critique.json`
   (Design2) so the tradeoff is grounded, not vibes.
3. Optionally it speaks *after* the click as pushback: *"you picked B — here's the
   one thing I'd steal from A before you ship."* That pushback is a ready-made remix
   suggestion.

A Lead Designer that merely ratifies the pick is wasted quota (anti-echo applies).

### Remix = design-level synthesis (Beam 4 — the flywheel)

The user composites across frames. The **Remix composer**:

- Select a region/element on a frame (Design2's coordinate system + anchors) — "take
  this nav from A" — or a **system** from a token strip — "B's palette", "C's empty-
  state".
- Each pick becomes a structured override in `DesignBrief`:

```text
DesignBrief {
  base: seatId                         # the layout you start from
  overrides: [
    { from: seatId, take: "nav" | region{...} | "palette" | "empty-state", note? }
  ]
  contract: RenderContract             # carried forward (viewport, fixture, brand)
  rationale: string                    # why this composite
  referenceFrames: [pngPath]           # winning + source frames, as reference images
}
```

- **Re-render round 2:** the `DesignBrief` is dispatched as **one** design seat
  (reusing Design1's HTML contract + render harness) → a new comparable frame lands
  on the board. The user *sees their Frankenstein design exist* before committing.
  Diverge → pick/mix → **converge (rendered merge)** → verdict. This is the
  tournament arc, bounded to one remix round in v1.
- The remix brief degrades to **prose** (`remix_brief.md`) when the user just wants
  text — but the structured form is what enables re-render and the build handoff.

### Single-seat "more like this" (the iteration loop)

Real design is 2–3 rounds. From any frame: **"Explore more like this"** re-dispatches
**one** seat with a tightened cage ("same persona family; push bolder" or "depart
less"). Reuses RB1 `reuseKey` — the other seats are untouched, no re-render. This is
the second flywheel that keeps the user *in* Allnighter for round two instead of
exporting a PNG to v0/Figma. (Multi-board history with back-navigation is a stretch
goal.)

### The build handoff (RB3 → RB4, design-shaped)

"Implement This" on a chosen/remixed frame produces an `ImplementationBrief` (RB4)
whose source is the `DesignBrief` + the **winning frame's HTML as the ship surface**
+ the **winning PNG as a reference image** for the build council. The build council
then runs the *technical* spine on it ("implement this component into the codebase
using the existing design system"). Zero copy/paste; the deliverable is code; you
never left Allnighter — the moat line made literal.

The winner also **exports tokens** (CSS vars / Tailwind config) alongside the
component, so the user keeps a system, not just a screen — maximally "code you own."

## Inputs

```text
the board + design_critique.json (reused)
the chosen frame(s) / pairwise picks
optional reference image (for the visual-diff slider)
the RenderContract (carried into remix re-render + build handoff)
```

## Ordered Slices

- [ ] D3-S01 — `chosen_frame.json` verdict model (adopted + rejected + rationale +
  timestamp); pairwise A/B reducer for 4+ frames; pick-directly for ≤3.
- [ ] D3-S02 — Visual-diff slider (old reference vs winner; or two frames for
  greenfield).
- [ ] D3-S03 — Lead Designer `PromptProfile` (names the tradeoff, never the verdict;
  consumes `design_critique.json`) + the strict **board-first, speak-second**
  sequencing in the UI; optional post-click pushback.
- [ ] D3-S04 — `DesignBrief` model (base + overrides + carried contract + reference
  frames) + the Remix composer UI (region/system picks via Design2 anchors).
- [ ] D3-S05 — Remix re-render: dispatch the `DesignBrief` as one design seat through
  Design1's harness → a round-2 frame on the board.
- [ ] D3-S06 — Single-seat "more like this" rerun (tightened cage, RB1 reuse, no
  re-render of other seats).
- [ ] D3-S07 — Build handoff: `DesignBrief` → RB4 `ImplementationBrief` with the
  winning HTML as ship surface + PNG as reference image; token export
  (CSS vars / Tailwind).
- [ ] D3-S08 — Verdict logging: append every `chosen_frame.json` to a local ledger
  (the seed `15_Preference_Ledger` consumes later); `design_full` preset; `bundle.md`
  includes verdict + remix.

## Works Test

```text
On a reviewed board (Design2), the human looks first — no AI pick is shown.
-> with 4 frames, pairwise A/B collapses to the minimalist winner in 3 clicks.
-> drag the visual-diff slider: the old cluttered profile page on the left wipes to
   the clean winner on the right.
-> NOW the Lead Designer speaks: "minimalist wins hierarchy and a11y, but the bold
   frame's empty-state is the only one a new user won't bounce on."
-> Remix: keep the minimalist layout, take the bold frame's empty-state, take frame
   A's palette. The DesignBrief re-renders as a round-2 frame that lands on the board
   — the composite the user just invented, rendered, comparable.
-> click "Explore more like this" on it: one seat reruns tighter; the other frames
   are untouched (no re-render).
-> "Implement This": the build council receives the round-2 HTML as the ship surface
   + its PNG as a reference image + exported Tailwind tokens, and runs the technical
   spine to wire it into the repo. No copy/paste anywhere.
chosen_frame.json is written for every pick and appended to the local taste ledger.
```

## Exit Gates

- [ ] No AI verdict precedes the human's look; the human casts the deciding vote.
- [ ] The Lead Designer names a tradeoff (never a winner); it is sequenced strictly
  after the board, and is optional per preset.
- [ ] `DesignBrief` re-renders through Design1's harness into a comparable round-2
  frame before any build handoff.
- [ ] "More like this" reruns one seat via `reuseKey`; other frames are untouched.
- [ ] The build handoff carries HTML (ship surface) + PNG (reference) + exported
  tokens into RB4; Allnighter invokes the CLI, the repo owns git (RB4 boundary).
- [ ] Every verdict is logged to the local ledger for future taste memory.
- [ ] `run.json` is truth; all artifacts derived; reuse discipline holds.
- [ ] `swift test` + app suite green.

## Closeout

The design council is now a flywheel: range → pick → mix → rendered merge → build,
zero paste, code you own. The next compounding step is **taste memory** (parked
`15_Preference_Ledger_And_Taste_Memory`): the logged verdicts train a `house_style`
seat that joins the bench and makes one of the four frames pre-tuned to *you* — the
moat that sharpens every night you use it.
