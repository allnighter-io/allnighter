# Design2 - Design Lenses + Scorecard

Status: **Build-ready after Design1 is loved.**
Owner: Shared Core + Mac
Created: 2026-06-14
Updated: 2026-06-14
Depends on: Design1 (the board, frames, contract), RB2 (review board: lens fanout, verdict header, anti-echo, advisory-never-mutates)

## Why this reuses RB2 almost wholesale

RB2 is already a parallel adversarial-lens engine with per-lens verdicts that
**append, never mutate**. A design critique is structurally identical — swap the
lens prompts, point them at a rendered frame instead of `master_plan.md`, and the
plumbing holds. This is a **lens-profile + input swap**, not new machinery. The one
real addition is that RB2 reviews *one* artifact; the design board has *N* frames,
so the board gains a second axis: a **scorecard** (lenses × options) rendered as an
**overlay**, never the default. The board stays the hero; you do not lead a visual
decision with a spreadsheet.

## Goal

After the board exists (Design1), fan design lenses over each frame in parallel.
Each lens × frame lands a `design_review_<lensId>_<seatId>.md` (RB2 shape, with a
verdict header and **region anchors**). The structured roll-up is
`design_critique.json`. The board gains a **Critique overlay**: per-frame callouts +
an optional lenses × options scorecard. `contrast_a11y` is the one objective
blocker; every other lens is advisory.

## Non-Goals

- No human verdict synthesis or remix (Design3).
- No spatial-pin *authoring* (the user drawing pins). Lenses *emit* region anchors
  now; rendering them as pins ships here, authoring is Design3.
- No taste blockers. Only `contrast_a11y` can blocker; everything else is
  concern/ok. (Taste blockers recreate 0/10.)

## Design

### The lens-profile swap (RB0's `ui_ux` explodes)

One coarse `ui_ux` lens is too blunt when half of prompts are design. Explode it
into vision lenses (each an editable `PromptProfile`, RB2 anti-echo baked in):

| Design lens | Job | Verdict behavior |
| --- | --- | --- |
| `visual_hierarchy` | Does the eye land where it should? Is the primary action obvious? | concern/ok |
| `contrast_a11y` | WCAG contrast, color-blind safety, ≥44px hit targets, focus order | **may blocker** (objective) |
| `brand_fit` | Adheres to the bound `BrandTokens` / reference | concern/ok |
| `layout_density` | Spacing rhythm, alignment, responsive behavior, **holds under the messy fixture** | concern/ok |
| `content_design` | Microcopy, labels, tone (this is `writer_editor`, relabeled) | concern/ok |
| `distinctiveness` | Generic AI slop or actually considered? (confirms Design1's heuristic badge) | concern/ok |

Mapping is clean: `proof_qa → contrast_a11y` (the objective gate), `ui_ux →
visual_hierarchy + layout_density`, `writer_editor → content_design`. Lens profile
swap, not new machinery.

### Vision routing (`requiresVision` — RB2's `preferFastWorker` sibling)

A design lens consumes a **rendered frame** (the PNG + the HTML source), so its
binding must filter to **vision-capable** workers. Add `StageBinding.requiresVision`
beside RB2's `preferFastWorker`. The `CallPlan` says honestly when a blind worker
cannot take a visual lens and routes only vision-capable seats; if none are healthy,
the lens is skipped with an explicit note (partial beats blocked).

### Region anchors (say yes to pins — but cheaply)

Vision models already return bounding boxes. Each lens finding carries an optional
`{ seatId, region: {x,y,w,h} | elementHint }` anchor in the review header, in the
frame's Design1 coordinate system. In Design2 these render as **prose chips that
highlight the region on hover** (cheap, ships now); Design3 promotes them to drawn
pins. Because Design1 already stores the coordinate system, this retrofits with no
re-render.

```text
---
lens: visual_hierarchy
seat: bold_expressive
verdict: concerns
anchors:
  - region: {x: 0.62, y: 0.88, w: 0.3, h: 0.08}
    note: "primary CTA competes with the back button; both are amber"
---
<the full advisory critique in Markdown>
```

Header degrades safely (RB2 law): bad header → treat as advisory prose; `lensId` +
`seatId` are known structurally from the binding, never the header.

### The verdict axis bends but does not break (RB2's strip survives)

For code, blockers are common. For design, **almost nothing is a hard blocker except
accessibility** — contrast < 4.5:1 genuinely is. So `contrast_a11y` keeps the gate
honest while every other lens lands concern/ok. RB2's "3 lenses · 1 blocker" strip
renders verbatim — for design it almost always means "the a11y lens flagged
something on a frame."

### One artifact → many: the scorecard (overlay, never the hero)

`design_critique.json` = the lenses × options matrix; each cell is one lens's read
of one frame `{ verdict, anchors, oneLineWhy }`. The board gains a **Critique
toggle**:

- **Default (off):** the Design1 board — pure frames. The board is the hero.
- **Critique on:** per-frame callouts (anchored chips) draw on each frame; a
  **column** tells you "which option wins on hierarchy," a **row** tells you "where
  option B falls down." The full lenses × options grid is a secondary tab for deep
  comparison, never the landing surface.
- **Token strips:** each frame surfaces its extracted palette + type scale + spacing
  so the user compares *systems*, not just frames ("I love A's layout but B's
  colors" becomes actionable — and feeds Design3's remix).

### Reuse

Lenses consume the Design1 frames as **reused** inputs (no re-render, no re-fan-out)
— RB2's exact discipline. Re-running one lens appends a superseding review for that
`lensId × seatId`; changing a frame (Design1 reroll) invalidates that frame's
reviews only.

## Inputs

```text
the board (frame_<seatId>.png + frame_<seatId>.html, reused)
the RenderContract + BrandTokens (for brand_fit)
the ContentFixture (so layout_density judges behavior under real data)
design-lens PromptProfiles
```

## Ordered Slices

- [ ] D2-S01 — Design-lens `PromptProfile`s (the six above) with anti-echo +
  region-anchor instructions; fixtures + round-trip.
- [ ] D2-S02 — `StageBinding.requiresVision`; vision-capable worker routing via
  Doctor; honest skip + `CallPlan` note when no vision worker is healthy.
- [ ] D2-S03 — Design-lens fanout (RB2 coordinator) over the reused board; one lens ×
  one frame → `design_review_<lensId>_<seatId>.md` with the anchored header.
- [ ] D2-S04 — `design_critique.json` roll-up (lenses × options) from the review
  stage outputs; header degrades safely.
- [ ] D2-S05 — `contrast_a11y` as the single blocker-capable lens; RB2 verdict strip
  ("N lenses · 1 blocker") rendered for the board.
- [ ] D2-S06 — Board Critique overlay: anchored callouts on hover, per-column/row
  read, the secondary full-matrix tab, token strips.
- [ ] D2-S07 — `design_review` preset (board + lenses); `CallPlan` shows vision
  routing + lens × option count; reuse leaves frames untouched.

## Works Test

```text
On a board of 4 frames, run the design_review preset.
-> only vision-capable seats take the lenses; a blind worker is shown skipped with a
   CallPlan note, not silently dropped.
-> each frame gets per-lens critique; the bold frame's contrast_a11y returns a
   blocker (amber-on-amber CTA, 2.9:1); the strip shows "6 lenses · 1 blocker".
-> toggle Critique on: a red anchored chip highlights the failing CTA region on the
   bold frame on hover. The hierarchy column shows the minimalist frame winning.
-> the full matrix tab shows lenses × 4 options; token strips reveal frame A and B
   share a palette but differ in type scale.
-> disable distinctiveness and re-run: CallPlan drops one lens, frames are reused
   (no re-render), critique updates.
Default view (Critique off) is still just the four frames — the board stays the hero.
```

## Exit Gates

- [ ] Design lenses consume reused frames; they never re-render or re-fan-out.
- [ ] Critique appends; it never mutates a frame's HTML (advisory-never-mutates).
- [ ] Only `contrast_a11y` can throw a blocker; all other lenses are concern/ok.
- [ ] Vision routing is honest: non-vision workers are not bound to visual lenses;
  no healthy vision worker → explicit skip, not a blocked run.
- [ ] Region anchors render on hover and reuse Design1's coordinate system.
- [ ] The board stays the hero; the scorecard is an overlay/secondary tab, never the
  default surface.
- [ ] `swift test` + app suite green.

## Closeout

Activate Design3. The critique is advisory input to the human verdict — it informs
the pick and seeds the remix; it never casts the vote.
