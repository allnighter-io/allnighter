# Design1 - The Image Council

Status: **Build-ready — gated on the Design Activation Gate (Design0).**
Owner: Shared Core + Mac
Created: 2026-06-15
Updated: 2026-06-15
Depends on: 06 (`PanelSeat`, `StageOutput`), RB1 (`WorkflowPreset`, `CallPlan`, reuse), 05 (`Doctor`)

> **Dead and not coming back:** OCR and the HTML render pipeline. See Design0 §
> "What is DEAD." The unit is a **generated image**, not rendered HTML. There is no
> WKWebView, no content fixture, no pHash, no render contract.

## Why this is small

The council shape already exists (RB): fan out one prompt to a panel, capture each
worker's output, show it. Design1 changes exactly one thing — **the workers emit
images instead of text, and the board shows images.** Everything else (panel
selection, parallel fan-out, per-worker timeout/status, reuse, the `CallPlan`) is
reused. The only genuinely new engineering is **capturing an image output from a CLI**
and a **gallery board**.

## Goal

Design chip + an attached screenshot ("improve this") → fan out to image-capable
workers × design personas → each returns a finished design image → a board of options
side by side → the user picks → "more like this" iterates a seat.

## Non-Goals

- No HTML, no rendering, no OCR, no content fixture, no divergence/reroll engine.
- No build/implement step (Design2).
- No required vision critique (advisory only, Design2).

## Design

### Panel: image-capable workers × personas

- **Capability gate (`canGenerateImages`).** Doctor learns, per worker, whether its
  CLI can generate an image headlessly at $0 (e.g. `grok` → Grok Imagine, `gemini` →
  Nano Banana Pro). A design seat binds only to an image-capable worker; the
  `CallPlan` shows the routing and honestly omits workers that can't.
- **Personas** are short editable style directions (Design0): `minimal`, `bold`,
  `editorial`, `on_brand`. A design panel is **seats = (image worker × persona)**,
  spread for range. Default 3–4 seats. A worker may fill several seats (different
  personas) — self-fusion, exactly like RB.
- **Range** comes from engines × personas. No automated divergence measurement; if
  options look too alike, the user hits **"more / re-roll."**

### Driver capability: capture an image output (the one new primitive)

Today drivers capture **stdout text** or an **output file** (`02_Worker_Drivers`).
Design adds an additive manifest capability: an **image-generation invocation** whose
output is one or more **image files** landing in the run folder. The driver manifest
declares how to ask its CLI for an image and where the image lands; the engine
captures `option_<seatId>.png` instead of parsing text. This is the only new contract
in the module — keep it thin and per-driver.

### The design prompt (kept dumb)

Each seat is dispatched the **attached screenshot** (as a file the model reads) +
**"improve this"** + the **persona direction** + the **target shape** (mobile/desktop,
inferred from the screenshot's dimensions, or asked once for greenfield). No fixture,
no structural cage — a short, honest prompt. Greenfield (no screenshot) just sends the
text prompt + persona + target shape.

### Target shape (light, not a contract)

- **Screenshot attached** → infer mobile/desktop from its pixel dimensions; show it as
  an editable chip the user can flip. No deep image analysis.
- **No screenshot** → default from the prompt archetype; if genuinely ambiguous, ask
  **one** quick choice (mobile / desktop). That's the whole "clarify" story.

### The board (the hero view)

`board.json` = ordered options `{ seatId, engine, persona, imagePath }`. The board is
the **first truth surface** — no AI verdict precedes it.

- **Progressive reveal:** placeholder tiles at identical size appear immediately; each
  swaps to its image as the seat finishes (like RB's streaming panel). The grid never
  reflows.
- **Identical scale, persona + engine badge** on each tile.
- **Fullscreen** (←/→ to flip) and **A/B** (two side by side).
- **Pick this** → records `chosen_option.json` (logged for future taste memory).
- **"More like this"** on any tile → re-dispatch **that seat** (same persona, "push
  this direction") via RB1 `reuseKey`; the other tiles are untouched.
- **Failed seat** (engine error / no image) → a gray tile with the reason; the board
  is usable with N−1 options (partial beats blocked, RB law).

### Reuse / resume

- **"More like this"** and persona edits re-run **one** seat. Changing the screenshot
  or the base prompt invalidates the board (content-addressed `reuseKey` over
  `{screenshot, prompt, persona, targetShape}`).
- A run stopped mid-fan-out keeps completed options; re-running continues from the
  first incomplete seat.

### Engine/spine wiring (contract-first)

Additive only — do **not** overload RB's text stages:

- New `StagePurpose` cases: `design_fanout` (fanout that captures images), `board`
  (local view stage).
- New `StagePayload.board(BoardPayload)`; new `Doctor` flag `canGenerateImages`.
- Design runs are a **parallel preset** with no Markdown member answers — the unit is
  the image, not `JudgeAnalysis`.

Land these in `AllnighterCore` with Codable round-trip + fixtures before any UI.

## Ordered Slices

- [ ] D1-S01 — Core models: `DesignRequest`, `BoardPayload`, `chosen_option.json`,
  `StagePurpose.design_fanout`/`.board`; Codable round-trip + fixtures.
- [ ] D1-S02 — Doctor `canGenerateImages` capability probe per worker; surfaced in
  Doctor UI + `CallPlan` routing.
- [ ] D1-S03 — Driver manifest image-generation capability (additive): invocation +
  image-output capture → `option_<seatId>.png`.
- [ ] D1-S04 — Persona style-direction `PromptProfile`s (the four in Design0;
  editable) + the dumb design-prompt builder (screenshot file + "improve this" +
  persona + target shape).
- [ ] D1-S05 — Screenshot attach in the composer (drag/drop + `NSOpenPanel`/
  `fileImporter`) + the target-shape chip (inferred from dimensions, one quick choice
  for greenfield).
- [ ] D1-S06 — `design_fanout` stage: parallel image fan-out over image-capable seats,
  per-seat timeout/status, image capture; `CallPlan` shows generation count + engines.
- [ ] D1-S07 — The board UI: progressive reveal, identical-scale grid, persona/engine
  badges, fullscreen + A/B, "pick this", "more like this", failed-seat tiles.
- [ ] D1-S08 — `design_board` preset + reuse/resume + `bundle.md` includes the board.

## Works Test

```text
Pick the Design chip. Attach a screenshot of a cluttered profile page; type
"make this feel premium and clean."
-> the target-shape chip reads "mobile" from the screenshot dimensions; one tap could
   flip it to desktop.
-> 3-4 seats fan out across image-capable engines × personas (minimal / bold /
   editorial / on_brand). The CallPlan showed "4 image generations · grok-imagine,
   gemini" before commit.
-> the board fills progressively; four finished design images sit side by side at the
   same scale, each badged with its engine + persona.
-> open the bold option fullscreen, flip ←/→ through the others, A/B the two you like.
-> click "more like this" on the minimal option: that one seat regenerates a tighter
   variant; the other three tiles are untouched.
-> pick the minimal variant; chosen_option.json is written.
Force one engine to error: its tile is gray with the reason; the other three remain
fully usable.
```

## Exit Gates

- [ ] Design seats bind only to `canGenerateImages` workers; routing is shown in the
  `CallPlan`; non-capable workers are omitted honestly.
- [ ] Workers emit **images**; the engine captures `option_<seatId>.png`. No HTML, no
  render step, no OCR anywhere.
- [ ] The board reveals progressively at identical scale, supports fullscreen/A-B,
  "pick this", and "more like this" (one-seat reuse), and degrades on a failed seat.
- [ ] No AI verdict precedes the board; `chosen_option.json` is written on pick.
- [ ] `run.json` is truth; artifacts derived; reuse re-runs one seat, screenshot/prompt
  change invalidates the board.
- [ ] Activation Gate passed and image-capable CLIs recorded.
- [ ] `swift test` + app suite green via `scripts/check.sh`.

## Closeout

Design1 is lovable alone: attach a screenshot, get a board of real design options,
pick the one you love. Activate Design2 to turn that pick into code.
