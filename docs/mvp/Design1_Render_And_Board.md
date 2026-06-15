# Design1 - Render Contract + The Board

Status: **Build-ready — gated on the Design Activation Gate (Design0) + render-engine pick.**
Owner: Shared Core + Mac
Created: 2026-06-14
Updated: 2026-06-14
Depends on: 06 (`PanelSeat`, `StageOutput`), RB1 (`WorkflowPreset`, `WorkflowStage`, `CallPlan`, reuse)

## Why this is the gate (the whole 10x lives or dies here)

Design0's thesis is that design swaps the **unit** (a rendered frame, not prose).
Design1 builds that unit and proves it is **comparable** and **divergent** — the two
properties without which a "design council" is four pretty pictures you can't
decide between, i.e. the 0/10 in a nicer costume. Everything after Design1
(lenses, scorecard, verdict, remix) reuses RB machinery. **This slice is the only
genuinely new engineering**, and it stops at "present correctly" — *no judging at
all*. Presenting four comparable, genuinely different frames, rendered from real
messy data, already feels like a private design team. That feeling is the gate.

## Goal

One design prompt (+ optional reference image) → a resolved render contract + one
shared messy content fixture → 4 caged divergent seats each emit self-contained
HTML → Allnighter renders them headlessly into comparable frames → a **progressive
live board** the user navigates and picks a direction from. Divergence is measured
and a converged seat rerolls once.

## Non-Goals

- No design lenses, scorecard, verdict synthesis, or remix (Design2/Design3).
- No real-DB scraping, no URL ingestion, no live dataset swap on the board.
- No distinct designed states (empty/loading/error as separate worker outputs) —
  the *one* shared fixture is deliberately messy; that is the realism in v1.
- No spatial-pin authoring UI (but frames store a coordinate system for it).
- No mixed-prompt auto-detection; the user picks the Design chip.

## Design

### Stage shape (reuses RB1 primitives)

```text
[optional] clarify_reduce   -> resolve underspecified contract dimensions (1 cheap reduce)
render_contract (resolve)   -> render_contract.json + content_fixture.json   (truth)
design_fanout (fanout)      -> frame_<seatId>.html per caged seat
render (local, non-model)   -> frame_<seatId>.png at the contract
divergence_check (local)    -> pHash distances; reroll ≤1 converged seat (re-enters design_fanout for that seat)
board (view)                -> board.json (ordered gallery + persona + divergence)
```

`design_fanout` is RB1's fanout primitive with a new binding: one **caged persona**
→ one worker, output is HTML not Markdown. `render` and `divergence_check` are
**local, zero-model** stage steps (new `StagePurpose` cases `render`, `board`).

### Render contract resolution (image → infer → clarify)

`RenderContract = { viewport, colorScheme, platform, htmlConstraint,
contentFixtureId, brandBindingId?, referenceImageId?, referenceMode }`. Resolved in
priority order (Design0 § Render Contract), surfaced as the **Render Brief pill** —
always visible, one-tap editable, never a settings panel:

- **Reference image present** → `redesign-this`: derive viewport/density from the
  image; OCR copy out of it to seed the fixture. Or `style-reference`: extract
  aesthetic DNA into a temporary `inspired_by_<name>` persona; layout free.
- **No image** → infer from prompt + repo (framework from the file tree, platform
  from prompt). Propose the pill; default viewport = desktop 1440×900, scheme =
  prefers-light, unless inferred otherwise.
- **Low confidence on a key dimension AND no image** → `clarify_reduce`: 1–3 visual
  quick-choices (platform / scheme / content), at most one about content, never
  open text. One cheap reduce that saves a wasted 4-seat fan-out.

**Brand binding:** scan the working dir for `tailwind.config.*`, `theme.css`, or
`:root{--…}` CSS vars → `BrandTokens { colors, type scale, radius, spacing }`. Feeds
the `on_brand` seat now and `brand_fit` (Design2) later. None found → brand comes
from the prompt/reference.

### The content fixture (the other half of the gate)

`ContentFixture` is **one shared dataset every seat must render** — pinned in the
contract so seats compete on design, not on invented content. It is **deliberately
messy** by construction: a too-long name, a missing avatar, an empty collection, an
overflowing row, a realistic-not-lorem tone. Sources, in order:

1. OCR'd copy from a `redesign-this` reference image (the user's real words).
2. Synthesized by one cheap reduce call from the prompt ("a user profile page" →
   a believable user record + 5 messy rows). Zero marginal cost (subscription CLI).
3. A built-in messy seed for the inferred screen archetype if synthesis is skipped.

The fixture is handed to every seat in the dispatch prompt and **baked into each
frame's HTML**. (Live dataset swap = deferred; the one fixture is messy enough to
expose fragile designs.)

### The HTML dispatch contract (cross-worker comparability — the real risk)

Heterogeneous CLIs (Claude Code, Codex, Gemini…) emit wildly different scaffolding
unless pinned **hard**. The dispatch prompt for every design seat requires:

- **Exactly one self-contained HTML document.** No external files. Styles inline or
  via the pinned Tailwind Play CDN (one allowed `<script>` URL). No external
  assets except image URLs provided in the fixture.
- **Renders at the contract viewport** with no horizontal scroll at that width.
- **Uses the content fixture verbatim** — the given strings/data, no substitutions.
- **Respects a `.dark` class toggle** on `<html>` (so the board can flip theme
  locally without re-dispatch).
- **Honors the brand tokens** if bound (the `on_brand` seat) or the persona cage
  (every other seat).
- **Emits an `<!--artist-statement: …-->`** one-liner: the persona's own bet
  ("dropped card borders, leaned on spacing because your content is text-heavy").

A frame that violates "one self-contained renderable document" fails comparability;
the board shows it as a failed seat (gray tile, "seat failed"), never blocks the run
(RB2 law: partial beats blocked).

### Headless render harness (Allnighter owns it — Fork 1 resolved)

Workers emit HTML; **Allnighter renders.** Self-screenshotting CLIs can never be
viewport-consistent. Engine decision is the Design Activation Gate's deliverable:

- **Primary: offscreen `WKWebView`** (native macOS, zero bundled dependency, zero
  marginal cost). Load the HTML string, set the contract viewport, snapshot to PNG.
- **Fallback: bundled headless Chromium** *only if* WKWebView fails the gate's
  pixel-comparability test (font metrics / viewport fidelity). Heavier; chosen only
  if forced.

The render is local and free; the same WebView instance powers the **live**
fullscreen view (the deliverable is code — fullscreen is real HTML, not the PNG).
PNGs are the comparable gallery surface; HTML is the deliverable + the live surface.

### Divergence enforcement (measured, bounded — Beam 2)

After all frames render, compute pairwise **pHash** distance between the PNGs
(local, deterministic, $0). If a pair is below the convergence threshold, the seat
with the more generic frame (lower distinctiveness heuristic — centered hero +
gradient + card stack) **rerolls once** with a stronger divergence push appended to
its cage ("you converged with seat X; depart structurally — change the layout
grammar, not the palette"). Bounded: **max 1 reroll/seat**; the `CallPlan` shows the
ceiling ("up to +N if seats converge"). Rerolls re-enter `design_fanout` for that
seat only (reuse leaves the others untouched). Persisted in `board.json` so the
board can honestly show "seat C was rerolled for convergence."

A cheap **slop badge** (the same centered-hero/gradient/card heuristic) tags each
thumbnail "considered / generic" at render time — instant anti-slop signal before
any lens runs.

### The board (the hero view)

`board.json` = ordered gallery metadata: per-frame `{ seatId, persona, pngPath,
htmlPath, artistStatement, slopBadge, divergenceScore, rerolled }`. The board is the
**first truth surface** — no prose, no AI verdict precedes it. Required behavior:

- **Progressive reveal.** Placeholder tiles at identical size appear immediately;
  each swaps to its rendered frame as the seat finishes (streaming, like RB panel
  answers). The grid never reflows — the final frame arriving feels like a reveal.
- **Identical scale, persona badge, artist-statement caption** on each tile.
- **Fullscreen** (←/→ to flip; the fullscreen view is **live HTML**, hover/scroll
  real) and **A/B** (two frames side by side).
- **Squint toggle** — a one-CSS-filter Gaussian blur over the whole board: reveals
  real hierarchy vs. decoration. Free, and it signals "designers built this."
- **Pick this direction** → records the chosen seat (the Design3 verdict reuses
  this; in Design1 it just selects the frame whose source you keep).
- **Failed seats** render as gray tiles with the failure reason; the board is usable
  with N−1 frames.

### Reuse / resume discipline (RB law, design-shaped)

- Editing **one persona** re-renders **one** seat. Changing the **render contract**
  or **content fixture** invalidates **all** frames (content-addressed `reuseKey`
  over `{contract, fixture, persona, prompt}`).
- A run stopped mid-fan-out keeps completed frames; re-running continues from the
  first incomplete seat.

## Inputs

```text
founder design prompt
optional reference image (redesign-this | style-reference)
resolved RenderContract + ContentFixture
per-seat caged design persona (PromptProfile)
bound BrandTokens (optional)
```

## Ordered Slices

- [ ] D1-S01 — `RenderContract` + `ContentFixture` + `BrandTokens` Core models
  (`AllnighterCore`), Codable round-trip + fixtures. Contract-first.
- [ ] D1-S02 — Render contract resolver: image-mode detection, prompt/repo
  inference, the **Render Brief pill** model, and `clarify_reduce` (visual
  quick-choices) gated on low confidence + no image.
- [ ] D1-S03 — Reference-image pipeline: attach (local file), `redesign-this` OCR →
  fixture seed, `style-reference` → temporary `inspired_by_<name>` persona.
- [ ] D1-S04 — Content-fixture synthesis (one cheap reduce) with the **deliberate
  messiness** contract (long string / missing avatar / empty list / overflow);
  built-in messy seeds per archetype as fallback.
- [ ] D1-S05 — Brand-token scanner (`tailwind.config.*` / `theme.css` / `:root`
  vars) → `BrandTokens`.
- [ ] D1-S06 — Caged design-persona `PromptProfile`s (the five in Design0, each with
  a structural **divergence mandate**) + the HTML dispatch contract builder
  (self-contained HTML, viewport, fixture-verbatim, `.dark`, artist-statement).
- [ ] D1-S07 — `design_fanout` stage (RB1 fanout; output `frame_<seatId>.html`) with
  per-seat persona binding and the `CallPlan` showing each seat's stance + the
  reroll ceiling.
- [ ] D1-S08 — **Headless render harness** (`render` stage): WKWebView offscreen →
  `frame_<seatId>.png` at the contract; fidelity self-test for the gate; Chromium
  fallback seam (not built unless the gate forces it).
- [ ] D1-S09 — `divergence_check` stage: pHash distances + slop heuristic →
  bounded single reroll of the converged seat; `board.json` records it.
- [ ] D1-S10 — The board UI: progressive reveal, identical-scale grid, persona
  badges, artist-statement captions, slop badges, fullscreen **live** + A/B, squint
  toggle, failed-seat tiles, "pick this direction".
- [ ] D1-S11 — `design_board` preset + reuse/resume (`reuseKey` over
  contract/fixture/persona) + `bundle.md` includes the board.

## Works Test

```text
Pick the Design chip. Prompt: "redesign this user profile page to feel premium"
and attach a screenshot of the current page.
-> the Render Brief pill shows: mobile 390x844 (from the image), light, React/Tailwind
   tokens scanned from the repo. One tap flips it to desktop; flip it back.
-> Allnighter OCRs the real name/email out of the screenshot and synthesizes a messy
   fixture (a 28-char display name, one missing avatar, an empty "teams" list).
-> 4 caged seats fan out (Ive protégé / minimalist / bold / editorial wildcard),
   each emitting one self-contained HTML file rendering THAT fixture at 390px.
-> the board fills progressively; all 4 frames are the same size, same data.
-> two frames come back near-identical; pHash flags them; the generic seat rerolls
   once and returns a structurally different layout. board.json shows rerolled: true.
-> open the bold frame fullscreen: it is live HTML — hover the button, it responds.
-> hit squint: the minimalist frame keeps a clear hierarchy; one decorative frame
   turns to mush. Pick the minimalist direction; its HTML is saved as the artifact.
Force one seat to emit broken multi-file output: it shows as a failed gray tile and
the other three frames remain fully usable.
```

## Exit Gates

- [ ] Every frame on the board rendered at the **same** contract viewport against
  the **same** content fixture (comparable or nothing).
- [ ] Reference-image runs derive the contract + seed the fixture from the image;
  no-image runs resolve via inference, asking ≤3 visual quick-choices only when
  confidence is low.
- [ ] Workers emit **only** self-contained HTML; Allnighter renders all PNGs; the
  fullscreen view is live HTML.
- [ ] Divergence is measured (pHash); a converged seat rerolls at most once; the
  reroll ceiling is shown in the `CallPlan` and the actual reroll in `board.json`.
- [ ] The board reveals progressively, shows persona + artist statement + slop badge,
  supports fullscreen/A-B/squint, and degrades gracefully on a failed seat.
- [ ] No design lens, scorecard, or AI verdict appears anywhere in Design1.
- [ ] `run.json` is truth; all artifacts derived; reuse re-renders one seat,
  contract/fixture change invalidates all.
- [ ] Render engine chosen and recorded in the Activation Gate log; pixel-
  comparability self-test passes.
- [ ] `swift test` + app suite green via `scripts/check.sh`.

## Closeout

Design1 must be lovable on its own — a board of comparable, divergent, real-data
frames you can pick from, with zero judging. Activate Design2 only after the
founder has run Design1 on real prompts and the board *feels* like a design team.
