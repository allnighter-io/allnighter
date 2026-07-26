# Design Lane — build a real surface, screenshot the receipt

Status: **Locked law + DL-S01–S03 shipped 2026-07-26.** Product camera =
HTML→WebKit; seat picks what to build from the repo. Diffusion Design default
ripped. Capture wiring lives in `DesignBoardCapture` + CatalogRunCoordinator.
Owner: AllnighterCore / AllnighterEngine (run path + board stage) + artifact /
Floor as readers
Updated: 2026-07-26 (DL-S01–S03 landed)
Companions:
- Sprint: `docs/phases/sprint/design-lane/` (S01 rip, S02 WebKit board, S03 brief)
- Artifact hero mockups: `docs/phases/Team_Run_Receipt.md` (Design tiles under
  the memo header; Evidence = full seat craft; chips jump to Evidence)
- Sibling proof habit for **this** app’s GUI: `GUI_Visual_Proof_Gate.md` +
  `docs/gui/GUI_Workflow.md` (SwiftUI fixture → screenshot → layout-watcher) —
  Allnighter-on-Allnighter special case, **not** the product default camera
- Design system: `docs/design-system/production.md` + `tokens/*.css`
- Catalog families: `BuiltInTeams.swift` (`design_design` / Min / Max / Polish)
- Chat/concept `imageGen` (WorkerImageCapture/Invoker) stays for **explicit**
  concept art only — not Design default
- Vocabulary: `docs/phases/Work_Order_Team_Model.md` (Design example must staff
  builder seats, not “Grok Imagine”)

## Founder intent (locked)

Opus, Fable, Kimi K3 (and peers) are **insanely good at UI design** because they
**build interfaces** — SwiftUI fixtures, HTML/CSS prototypes, SVG — not because
they diffuse photoreal JPEGs.

Allnighter’s Design lane must match that craft:

1. Seat **builds a bounded, renderable surface** (the cheapest honest medium for
   the job — see §Path selection).
2. **Host capture step** (see Truth owners) screenshots that surface.
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

**Self-determination (locked):** the seat picks what to **build** from the
prompt + the user’s repo. Vibe-coder projects are unpredictable — do not
overfit Design to Allnighter’s SwiftUI harness. The host’s job is a boring
universal camera for whatever captureable artifact the seat leaves behind.

What the agent must **not** self-determine: silently substituting diffusion for
a UI mockup, or claiming a design without a screenshot (or an explicit
waiver). Freedom is the medium; the obligation is a photographable receipt.

**Path declaration (v1 requirement):** each design seat emits one
machine-readable line (board meta or Evidence) naming
`native | html | concept` and the artifact path it produced. Enough for debug
and honesty; not a second product surface.

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
  mean when they say “great at design.” (They still qualify for `.design`
  reasoning seats; it is the **mockup-producing** seats that are `.image`-gated.)
- Live **CLI / Mac team-run path** does not yet normalize “built surface →
  board screenshot.” Models may write files under `docs/gui/…` as a side
  effect without producing a `board` stage the artifact can hero.
- **Blocking catalog retag (first slice):** mockup seats
  (`visual_system_designer`, `minimal_direction`, `bold_direction`,
  `editorial_direction`) must drop the `.image` gate; concept seats keep it.
  Until retagged, staffing still selects paint engines.
- Orphaned diffusion path (`DesignCoordinator` / `DesignImageRunner`) was never
  wired into `RunService` — **rip it**; zero customers, no migration.

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
2. **Product camera first = HTML file → WebKit** — universal for arbitrary
   repos. Seat leaves a bounded HTML (or SVG) the host can snap. Do not wait
   on Allnighter’s GUI proof wrapper to unlock Design for customers.
3. **Allnighter-native capture** = special case when the design target is
   **this** Mac app (GUI proof family). Not the product default.
4. **Bounded artifact** — one screen / one fixture / one HTML file. No npm,
   no multi-route SPA, no network in the HTML sandbox.
5. **Board stage stays the contract** — Artifact / Floor already show images.
6. **Seat brief stays tiny** — `` ```seat { "summary": "…" } `` ``; Evidence =
   short notes + pointer to the surface.
7. **Capability for UI design seats** = can reason and build UI (native or
   web), **not** `imageGen`.

### Out of v1

- Forcing HTML when the target is Allnighter SwiftUI (seat may choose native).
- Figma sync, bundlers, HMR, OCR gates, design studio shell.
- Silent HTML→Midjourney fallback.
- Keeping `DesignCoordinator` / `DesignImageRunner` as dead Design-default code.

### Complexity tripwires

- Teaching needs a long essay to pick SwiftUI vs HTML → simplify defaults
  (Allnighter repo → native; else HTML).
- Capture needs per-model special cases → fix the host, not the seat.
- Agent spends the run rebuilding Allnighter in Tailwind “for design” →
  skill/path law failed.

## Trusted workflow slices (target)

**A — Product default (HTML → WebKit) — first capture slice**

```text
alln run --lane design "Redesign this landing hero"
  → seat builds a bounded HTML/SVG (or other captureable file) in the run dir
  → host WebKit capture → option_<id>.png
  → board stage + Lead Call + artifact Design hero
```

**B — Allnighter-on-Allnighter (native) — special case**

```text
alln run --lane design "Redesign the Boost window header"
  → seat edits / uses a SwiftUI fixture or surface
  → host capture (GUI proof camera) → option_<id>.png
  → board stage + Lead Call + artifact Design hero
```

Works Test (first capture slice): a design run with **zero** `.image` seats
leaves captureable HTML; host WebKit writes `board.options[].imagePath`;
artifact Design hero shows them. Capture failure → seat shown failed; **no**
silent diffusion fallback.

## Truth owners

| Concern | Owner |
| --- | --- |
| What Design means | This doc |
| Path choice (native vs HTML vs concept) | Prompt + repo context + thin host policy |
| **Who writes the board** | **Host capture step inside the team-run pipeline** (new thin owner — **not** a revived `DesignCoordinator`) |
| Product camera (default) | Thin host **HTML/SVG → WebKit** render-capture |
| Native screenshot (Allnighter special case) | Existing GUI proof harness / fixtures |
| Board + artifact / Floor | Existing projectors reading `board` |
| Concept-image path | Explicit seat only |
| Human pick (v1.1) | `BoardPayload.chosen` / `ChosenOption` → `chosen_option.json` |

## Record the pick (v1.1 — after capture works)

The compounding loop needs the human’s choice on disk. Schema already exists:
`ChosenOption` on `BoardPayload.chosen`, persisted as `chosen_option.json`
(`DesignRun.swift`). Naming it here is the requirement; wiring a pick surface
is **not** a DL-S0 blocker — land it right after capture is honest.

## Seating (direction)

Staff **design reasoners / builders** (e.g. Opus, Fable, K3, Composer, Grok) by
caliber — not `imageGen`. Concept art remains an explicit add-on.

Polish team (`design_polish`) is **post-pick refinement**, out of v1 capture
scope.

## Supersession

This packet supersedes Design0’s “HTML rendering is DEAD / image engines
design” **for the Design default**. That charter killed the OCR/pHash render
*contract* and Midjourney-as-default — it did **not** ban rendering a built
surface for a screenshot receipt. Live leftovers that still state the old law
(e.g. `DesignRun.swift` header, stale Work Order examples) are corrected with
this packet / DL-S0; agents must not re-learn diffusion-default from those
lines.

## Relation to Team Run Receipt

On `designBoard`, **screenshots are the memo hero**. This packet defines them
as receipts of **built** surfaces (native or HTML), so strong design models can
appear without pretending they are diffusion engines. HTML mockups are **not**
a moat — any chatbot can one-shot them; the defensible part is the user’s own
multi-model bench, side by side, on the run record.

## Open questions (keep short)

1. How much teaching does the seat brief need so agents leave a **single
   captureable file** (not a half-edited React tree the host cannot snap)?
   Keep it one line if possible.

## Kill criteria

- If “Design” still means “write a parallel HTML Allnighter” for Mac-app
  prompts → the path law failed; fix teaching and defaults.
- If seats cannot produce a screenshot without diffusion for three dogfoods →
  the capture pipeline is the bug, not the models.
- If mockup seats still require `.image` after the catalog retag → staffing
  will keep selecting paint engines.
- If the product default camera stays Allnighter-GUI-only → we overfit for us
  and fail vibe-coder repos.
