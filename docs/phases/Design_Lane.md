# Design Lane — build a real surface, screenshot the receipt

Status: **Draft law packet — founder-locked intent 2026-07-26; corrected same
day (path is not HTML-only).** This is what Allnighter means by **Design team**
and **design edits**. Not Midjourney.
Owner: AllnighterCore / AllnighterEngine (run path + board stage) + artifact /
Floor as readers
Updated: 2026-07-26 (path flexibility: native vs HTML)
Companions:
- Artifact hero mockups: `docs/phases/Team_Run_Receipt.md` (Design tiles under
  the memo header; Evidence = full seat craft; chips jump to Evidence)
- Sibling proof habit for **this** app’s GUI: `GUI_Visual_Proof_Gate.md` +
  `docs/gui/GUI_Workflow.md` (SwiftUI fixture → screenshot → layout-watcher)
- Design system: `docs/design-system/production.md` + `tokens/*.css`
- Catalog families: `BuiltInTeams.swift` (`design_design` / Min / Max / Polish)
- Historical imageGen substrate (diffusion / engine paint): `DesignImageRunner`,
  `DesignCoordinator` — **not** the design-lane spine going forward
- Vocabulary: `docs/phases/Work_Order_Team_Model.md`

## Founder intent (locked)

Opus, Fable, Kimi K3 (and peers) are **insanely good at UI design** because they
**build interfaces** — SwiftUI fixtures, HTML/CSS prototypes, SVG — not because
they diffuse photoreal JPEGs.

Allnighter’s Design lane must match that craft:

1. Seat **builds a bounded, renderable surface** (the cheapest honest medium for
   the job — see §Path selection).
2. **Host (or existing GUI proof harness) captures a screenshot**.
3. That PNG is the board option / artifact **hero** tile.
4. Humans judge **side-by-side screenshots**; deep read is Evidence (+ open the
   live surface when useful).

**Diffusion / Midjourney-style text-to-image is optional and explicit** — a
different job (concept art, mood, illustration). It must never be the silent
default for “Design team.”

### Correction (2026-07-26) — do not force HTML

If the user asks the Design team to mock a feature **in the Allnighter Mac
app**, forcing an HTML rebuild is **10× the wrong work**. The right path is the
same family as GUI proof: edit / stand up a **SwiftUI surface or fixture**,
render it, screenshot it.

**Law:** the **receipt** is a screenshot of a built surface. The **path** is
chosen for the surface — not prescribed as HTML for every Design run.

## Path selection (keep this simple)

The seat (with host affordances) picks the **cheapest honest path** that yields
a real screenshot. It does **not** freestyle into Midjourney unless the user
asked for concept art.

| Situation | Prefer | Why |
| --- | --- | --- |
| Redesign / polish a screen **in this Allnighter repo** | SwiftUI + existing GUI render/screenshot path (`GUI_Visual_Proof_Gate`) | Same stack as production; no fake web twin |
| User’s product is **web / marketing / HTML-native** | One HTML (or similar) mockup → host WebKit capture | Fast design-to-code |
| Greenfield UI with no native harness yet | HTML mockup → capture **or** smallest fixture the repo already supports | Don’t invent a second app |
| User explicitly wants **concept art / photo / illustration** | Explicit `imageGen` / concept seat | Different job |

**Self-determination:** yes — within those allowed means. The agent chooses
SwiftUI vs HTML vs “open this existing fixture” based on the prompt and repo.
The host must make at least one capture path easy; v1 can ship **one** path
well and teach the other, not five.

What the agent must **not** self-determine: silently substituting diffusion for
a UI mockup, or claiming a design without a screenshot (or an explicit
waiver).

## Same camera, two jobs

| | GUI Visual Proof Gate | Design lane |
| --- | --- | --- |
| Spine | Render real surface → screenshot → eyes | Same |
| Job | **Verify** a change before “fixed” | **Propose** options for judgment |
| Typical Allnighter-app path | SwiftUI fixture / surface | Same when designing Allnighter itself |
| Typical external / web path | n/a | HTML → capture |

Design-on-Allnighter **is** using a lane like GUI proof — proposal mode, not
closeout mode. Do not build a parallel HTML universe for our native app.

## The gap we hit (2026-07-26 dogfood)

- Catalog seats Design teams with an `image` capability gate aimed at
  **engine `imageGen`** (Grok / Gemini / ChatGPT paint a PNG).
- Opus / Fable / K3 **cannot** call that path — yet they are the models people
  mean when they say “great at design.”
- Live **CLI / Mac team-run path** does not yet normalize “built surface →
  board screenshot.” Models may write files under `docs/gui/…` as a side
  effect without producing a `board` stage the artifact can hero.

**Ruling:** product gap. Fix the meaning of Design (screenshot of a built
surface), wire capture into the run, staff code/design reasoners — do not paper
over with Midjourney seats.

## Two jobs (do not conflate)

| Job | Noun | Output | When |
| --- | --- | --- | --- |
| **UI design / design edit** | Design team (default) | Built surface → screenshot | Screens, flows, polish |
| **Concept image** | Explicit opt-in | Diffusion / engine paint PNG | Mood / illustration — **user asks** |

## Simplicity law — stay usable

Complexity kills this feature. v1 is a **thin capture pipeline**, not a design
IDE and not “always HTML.”

### In v1 (do these only)

1. **Outcome per design seat:** one desktop screenshot on the board
   (`options[].imagePath`). How it was born is metadata, not a second gallery.
2. **At most two capture backends in v1** — (A) existing native GUI screenshot
   path for Allnighter surfaces, (B) sandboxed HTML file → WebKit capture for
   web/greenfield. Do not add a third before both work once.
3. **Bounded artifact** — one screen / one fixture / one HTML file. No npm,
   no multi-route SPA, no network in the HTML sandbox.
4. **Board stage stays the contract** — Artifact / Floor already show images.
5. **Seat brief stays tiny** — `` ```seat { "summary": "…" } `` ``; Evidence =
   short notes + pointer to the surface.
6. **Capability for UI design seats** = can reason and build UI (native or
   web), **not** `imageGen`.

### Out of v1

- Forcing HTML when the target is Allnighter SwiftUI.
- Figma sync, bundlers, HMR, OCR gates, design studio shell.
- Silent HTML→Midjourney fallback.

### Complexity tripwires

- Teaching needs a long essay to pick SwiftUI vs HTML → simplify defaults
  (Allnighter repo → native; else HTML).
- Capture needs per-model special cases → fix the host, not the seat.
- Agent spends the run rebuilding Allnighter in Tailwind “for design” →
  skill/path law failed.

## Trusted workflow slices (target)

**A — Design on Allnighter (native)**

```text
alln run --lane design "Redesign the Boost window header"
  → seat edits / uses a SwiftUI fixture or surface
  → GUI proof-style render → option_<id>.png
  → board stage + Lead Call + artifact Design hero
```

**B — Design for web / external HTML**

```text
alln run --lane design "Redesign this landing hero"
  → seat writes runDir/option_<id>.html
  → host WebKit capture → option_<id>.png
  → board stage + Lead Call + artifact Design hero
```

Works Test (when built): at least one path (prefer A if Allnighter-targeted)
produces a board screenshot without `imageGen`; artifact shows it in the Design
hero.

## Truth owners

| Concern | Owner |
| --- | --- |
| What Design means | This doc |
| Path choice (native vs HTML vs concept) | Prompt + repo context + thin host policy |
| Native screenshot | Existing GUI proof harness / fixtures |
| HTML → PNG | Thin host render-capture |
| Board + artifact / Floor | Existing projectors reading `board` |
| Concept-image path | Explicit seat only |

## Seating (direction)

Staff **design reasoners / builders** (Opus, Fable, K3, Composer, …) by caliber
— not `imageGen`. Concept art remains an explicit add-on.

## Relation to Team Run Receipt

On `designBoard`, **screenshots are the memo hero**. This packet defines them
as receipts of **built** surfaces (native or HTML), so strong design models can
appear without pretending they are diffusion engines.

## Open questions (keep short)

1. v1 ship order: native-Allnighter capture first, or HTML capture first?
   (Lean: **whichever unblocks the next founder dogfood** — if the ask is
   Allnighter UI, native first.)
2. How the seat declares which path it used (one line in Evidence / board
   meta) — enough for debug, not a second product surface.

## Kill criteria

- If “Design” still means “write a parallel HTML Allnighter” for Mac-app
  prompts → the path law failed; fix teaching and defaults.
- If seats cannot produce a screenshot without diffusion for three dogfoods →
  the capture pipeline is the bug, not the models.
