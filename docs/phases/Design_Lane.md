# Design Lane — code mockups, host render, screenshot receipts

Status: **Draft law packet — founder-locked intent 2026-07-26; implementation
gap open.** This is what Allnighter means by **Design team** and **design
edits**. Not Midjourney.
Owner: AllnighterCore / AllnighterEngine (run path + board stage) + artifact /
Floor as readers
Updated: 2026-07-26
Companions:
- Artifact hero mockups: `docs/phases/Team_Run_Receipt.md` (Design tiles under
  the memo header; Evidence = full seat craft; chips jump to Evidence)
- Design system: `docs/design-system/production.md` + `tokens/*.css`
- Catalog families: `BuiltInTeams.swift` (`design_design` / Min / Max / Polish)
- Historical imageGen substrate (diffusion / engine paint): `DesignImageRunner`,
  `DesignCoordinator` — **not** the design-lane spine going forward
- Vocabulary: `docs/phases/Work_Order_Team_Model.md`

## Founder intent (locked)

Opus, Fable, Kimi K3 (and peers) are **insanely good at UI design** because they
**build interfaces in code** — HTML/CSS/Tailwind, SVG, clickable prototypes —
not because they diffuse photoreal JPEGs.

Allnighter’s Design lane must match that craft:

1. Seat **writes a bounded mockup** (renderable artifact — default: one HTML
   file in the run directory).
2. **Host renders** it (fixed viewport(s), sandboxed).
3. **Host captures a screenshot** → that PNG is the board option / artifact
   hero tile.
4. Humans judge **side-by-side screenshots**; deep read is the live HTML +
   Evidence prose.

**Diffusion / Midjourney-style text-to-image is optional and explicit** — a
different job (concept art, mood, illustration). It must never be the silent
default for “Design team.”

## The gap we hit (2026-07-26 dogfood)

- Catalog seats Design teams with an `image` capability gate aimed at
  **engine `imageGen`** (Grok / Gemini / ChatGPT paint a PNG).
- Opus / Fable / K3 **cannot** call that path — yet they are the models people
  mean when they say “great at design.”
- `DesignCoordinator` can assemble a `board` stage from painted PNGs, but the
  live **CLI / Mac team-run path does not invoke it** today. A Design team run
  often behaves like a **text/coding team**; the model may write HTML under
  `docs/gui/…` as a side effect, which is **not** a board option and does not
  feed the artifact hero automatically.

**Ruling:** that is a product gap. Fix the meaning of Design, then wire the
simple path — do not paper over it with Midjourney seats.

## Two jobs (do not conflate)

| Job | Noun | Output | When |
| --- | --- | --- | --- |
| **UI design / design edit** | Design team (default) | Code mockup → host screenshot | Screens, flows, polish of a product surface |
| **Concept image** | Explicit opt-in (name TBD — e.g. “Concept art” / `imageGen` seat) | Diffusion / engine paint PNG | Mood boards, illustration — **user asks for it** |

Same gallery chrome (option tiles) may show either; **birth path and seating
rules differ.**

## Simplicity law — stay usable

Complexity kills this feature. v1 is a **thin host pipeline**, not a design IDE.

### In v1 (do these only)

1. **One mockup file per design seat** — `mockup.html` (or `option_<workerId>.html`)
   under the run directory. No multi-page apps, no npm install, no external
   network fetch in the render sandbox.
2. **One desktop capture per seat** (e.g. 1280×800 or content-height capped).
   Optional second mobile capture is v1.1 — not required to ship the spine.
3. **Host owns render + capture** — WebKit (or equivalent) off-main-thread;
   fonts/CSS from the mockup file + allowed design-system snippet if we inject
   one later. Seat does not “return a PNG” unless it is the explicit concept-image
   path.
4. **Board stage unchanged as the contract surface** — `options[].imagePath`
   still points at the **screenshot**. Artifact / Floor already know how to
   show images; they keep doing that.
5. **Seat brief stays tiny** — `` ```seat { "summary": "…" } `` `` elevator line;
   craft body = short notes; mockup file is the product.
6. **Capability gate for UI design seats** = can produce a renderable mockup
   (reasoning + code), **not** `imageGen`. Retire using `image` as the silent
   synonym for “UI designer.”

### Out of v1 (explicit non-goals)

- Figma import/export, component libraries, multi-route SPAs.
- Live HMR, browser DevTools, user-driven resize while the team runs.
- Auto-diffing two HTML trees as a product feature.
- OCR / vision scoring of the screenshot as a gate.
- Replacing Floor or the artifact with an in-app design studio.
- Silent fallback from “HTML failed” → Midjourney paint.

### Complexity tripwires — stop and simplify if

- A seat needs a build step (`npm`, bundler, package download).
- Capture needs more than one host renderer or per-model special cases.
- Teaching copy needs a paragraph to explain “Design” vs “image.”
- Artifact hero needs a new field beyond existing board options + Evidence.

## Trusted workflow slice (target)

```text
alln run --lane design --team design_design_min "Redesign the artifact page"
  → each design seat writes runDir/option_<id>.html (+ seat summary)
  → host renders HTML (sandboxed) → writes option_<id>.png
  → board stage lists options with imagePath = screenshot
  → Lead Call compares options (plain English)
  → alln artifact show → Design hero tiles = screenshots; chip → Evidence
```

Works Test (when built): terminal Design Min run with a code-capable seat
(Opus or K3) produces a non-empty `board` stage whose `imagePath` files exist
on disk; `alln artifact show` embeds those images under the Design hero; no
`imageGen` required on that seat.

## Truth owners

| Concern | Owner |
| --- | --- |
| What Design means | This doc |
| Run + board stage write | `RunService` / design run coordinator (wire or replace `DesignCoordinator`) |
| HTML → PNG | New thin **host render-capture** (name TBD) — not the seat CLI |
| Artifact / Floor display | Existing projectors (`ArtifactProjector`, Floor) reading `board` |
| Concept-image path | Explicit seat/skill + existing `imageGen` manifests only when chosen |

## Seating (direction)

- **Default Design families** staff **code-mockup** seats (Opus / Fable / K3 /
  Composer / etc. by caliber + design reasoning — Law 3), not `imageGen`.
- **Polish** stays critique + optional single mockup edit — still code→capture
  when a visual is required.
- **Concept art** is a separate skill/team or an explicit seat tag — never the
  unnamed default.

Exact catalog edits are a follow-on slice after this law is accepted; do not
reshuffle `BuiltInTeams` in the same breath as inventing the renderer.

## Relation to Team Run Receipt

Artifact law already says: on `designBoard`, **mockups are the memo hero**
(not buried in Evidence). This packet defines **what those mockups are** —
screenshots of seat-built HTML — so Opus/K3 can appear in that hero without
pretending they are diffusion models.

## Open implementation questions (keep short)

1. Inject design-system CSS into the mockup sandbox, or require seats to inline
   tokens? (Lean: inject a **small frozen token snippet** so brand holds.)
2. Mobile capture in v1 or v1.1? (Lean: **desktop only in v1**.)
3. Rename catalog capability `image` → something honest (`mockup` /
   `designRender`) in one contract bump — or overload carefully with teaching.

Do not grow this list before the thin pipeline ships once.

## Kill criteria

- If host capture is flakier than reading the HTML in a browser for three
  consecutive dogfoods → ship “Open mockup HTML” as the hero and demote
  screenshots to optional.
- If seats cannot stay to one HTML file → the skill law failed; fix skills,
  don’t add a bundler.
