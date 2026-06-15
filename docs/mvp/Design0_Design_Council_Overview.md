# Design0 - Design Council Overview (Charter)

Status: **Finalized — build-ready. Activate Design1 after the Design Activation Gate passes.**
Owner: Founder + Shared Core + Mac
Created: 2026-06-14
Updated: 2026-06-14
Depends on: 06 (council foundation), RB1 (presets + stage primitives), RB2 (review board), RB3 (final spec)

> Lane 1 (RB0–RB6) gave the vibe coder a **bench of brilliant AI developers** who
> disagree productively and hand back an executable spec they own. Lane 2 — the
> design council — gives them a **bench of brilliant designers with deliberately
> incompatible taste** who hand back *comparable, production-grade frames + the
> source*, so the decision is visual, the verdict is theirs, and the next step
> (build) costs almost nothing.
>
> **One prompt (+ optionally an image) in. A wall of real, genuinely different
> designs out — rendered from real messy data, decided by your eyes, handed back
> as code you own.**

This is the **second spine**, not a feature. It is the same council
(Prompt → Panel → Dispatch → Judge/Review → Final), with two fundamentals swapped
and everything else reused.

## Who This Is For (the other half of every prompt)

The vibe coder asks the council two kinds of questions. Lane 1 nailed the
**technical** kind — "add per-user rate limiting" — where the artifact is prose you
can reason about objectively and the win is consensus + an executable spec.

The second kind is **design**: *"give me 3–4 mockups for this screen,"* *"redesign
this onboarding,"* *"make this not look like AI slop."* At least half of real
prompts are this shape, and today we score **0/10** on them — not by accident.

## Why Design Prompts Get 0/10 (wrong unit, wrong axis)

The technical chain assumes the artifact is **prose you can pressure-test**: its
stages are `JudgeAnalysis` (consensus / contradictions) and `final_spec`
(`executable ✓`) — **correctness** checks. A button radius has no "contradiction"
and nothing to "execute," so a design prompt runs the machinery and produces
*confident nonsense*: prose about pixels, merged on an axis that does not apply to
taste.

The fix is not a bolt-on lens. Design swaps two fundamentals:

| | Technical council | Design council |
| --- | --- | --- |
| **Unit each worker emits** | a Markdown answer | a **rendered frame** (self-contained HTML → screenshot) + its source |
| **Judging axis** | objective merge / consensus | **taste + ranking — the human decides**; AI advises |

Everything else in the spine is reusable.

## The Decision: Keep the Spine, Reshape the Middle

No forked app. No second mode with a parallel codebase. A run **knows it is a
design run** and three stages reshape how they represent themselves:

| Council stage (today) | Design council | New machinery? |
| --- | --- | --- |
| Seats with personas (First principles / Skeptic) | Seats with **design personas** (structural cages, below) | reuses per-seat dropdown |
| Dispatch → text answers | Dispatch → **rendered frames** at a fixed render contract | render harness (the one real new beam) |
| `analysis.md` (consensus) | **The board** — a live gallery of frames at identical scale | new view, same stage shape |
| Review board · lenses | **Design lenses** (hierarchy, contrast/a11y, brand, density, distinctiveness) | RB2 lens-profile swap |
| `final_spec.md` · `executable ✓` | **Chosen direction + remix brief** → build council | RB3 finalizer reshaped |

~90% of RB1–RB3 is reused; the board re-points the same fanout-of-lenses engine
from a code-trust layer to a design-decision layer.

## The Four Load-Bearing Beams (what is genuinely new)

Everything magical rests on four beams. The first three are the gate; the fourth
is the flywheel.

### Beam 1 — Comparable rendering (the gate)

For text, workers ramble different lengths and it is fine. For design, two things
kill comparability and **both** must be pinned before fan-out, or the board is
garbage:

1. **The render contract** — viewport, color scheme, platform (§ Render Contract).
2. **The content fixture** — *the actual strings and data every seat must render.*
   If seat A invents a 3-item nav and seat B a 6-item nav, you are comparing
   content, not design. The fixture is **one shared, deliberately messy dataset**
   (long names, missing avatars, an empty list, an overflowing row) so the board
   reveals which design holds up under real data — killing the lorem-ipsum lie
   that makes AI mockups look great empty and break on launch. (§ Render Contract.)

Allnighter **owns headless rendering** (Fork 1 resolved): workers emit *only*
self-contained HTML; Allnighter renders every frame at the contract. The
deliverable the user keeps is the **source**, not the PNG — the frame is the
*judging surface*; the artifact is *code you can ship*. This is continuity with
`executable ✓` and the moat: **the design council outputs running code**, so
remix → build is nearly free (you never left code).

### Beam 2 — Divergence enforcement (range is the product)

The #1 failure of AI design is **convergence**: every seat defaults to the same
centered-hero/gradient/rounded-card SaaS look. A philosophical persona
("restraint, material honesty") produces a slightly-more-minimal version of the
*same* generic layout. So personas are **structural cages, not vibes** — each seat
gets a binding layout/type/color mandate it may not leave, plus one **wildcard**
that breaks the genre (§ Personas). And divergence is **measured, not hoped**:
after render, Allnighter computes perceptual distance (local pHash, $0) between
frames; if two are too similar, it **rerolls the offending seat once** with a
stronger divergence push. **"Comparable or nothing" gets a sibling: "divergent or
reroll."** The reroll is bounded (max 1/seat) and shown in the `CallPlan`.

### Beam 3 — The human casts the verdict; the Lead Designer speaks *second*

For code the finalizer reduces and synthesis is the hero. For design **taste is
yours.** The council ranks and critiques; **you pick** (the amber winner treatment
already exists; pairwise A/B for 4+ options). The optional **Lead Designer**
survives but is ruthlessly sequenced to avoid anchoring: **board first, in
silence → you form a reaction → then it names the *tradeoff*** ("B wins hierarchy
and a11y, but A's empty-state is the only one a first-run user won't bounce on"),
never a verdict — and may speak *after* you click as "here's where I'd push back."

### Beam 4 — Remix is design-level synthesis → the build flywheel

The remix brief is not a footnote; it is the thing no single-shot tool can do.
After the board, the user composites the best of each frame — "A's nav + B's
palette + C's empty-state" — into a **structured `DesignBrief`** that **re-renders
as a new comparable frame** (a round 2), then becomes the prompt for a build
council. Diverge (range) → pick/mix → converge (a rendered merge) → ship code.
(§ Design3.) Verdicts are logged from day one so a future **taste-memory
`house_style` seat** can learn the user's taste and become one of the four seats —
a moat that compounds (named, deferred; § Deferred).

## Render Contract (resolved before fan-out)

The contract is first-class run truth (`render_contract.json`). It is resolved
from three sources, in priority order — **no toggle-hell** (the design analog of
RB0's "cost is never silent"):

1. **Attached reference image (best).** The image *is* the map. Two modes
   (Fork 7 resolved):
   - **Redesign-this** — the screenshot is the thing to fix. It fixes viewport,
     density, and content region; Allnighter OCRs the real copy *out of it* so the
     redesign uses the user's actual words, and seeds the **content fixture**.
     Strict comparability.
   - **Style-reference** — "make my settings feel like this." Allnighter extracts
     its aesthetic DNA (palette, type scale, radius, spacing) into a **temporary
     persona** (`inspired_by_<name>`); layout is free to diverge.
2. **Inferred from prompt + repo.** "redesign this iOS settings screen" → mobile,
   iOS metrics; React/Tailwind detected in the file tree → that stack. The
   composer proposes the contract as an **always-visible, one-tap-editable Render
   Brief pill**, not a settings panel.
3. **Clarify before fan-out (only when needed).** Underspecified **and** no
   reference image → ask **1–3 visual quick-choices** (platform? scheme? what
   content?), at most one about content (the comparability killer), each with a
   thumbnail where possible. A cheap reduce that *saves* a wasted 4-seat fan-out.
   Never open text. (Honors "cost is never silent.")

`RenderContract = { viewport, colorScheme, platform, htmlConstraint,
contentFixtureId, brandBindingId?, referenceImageId?, referenceMode? }`.

**Brand binding** (Fork 5 resolved): per-run target, defaulting to **repo-scanned
tokens** — Allnighter parses `tailwind.config.*`, `theme.css`, or `:root` CSS vars
into a token set that feeds the `on_brand` seat and the `brand_fit` lens. If none
found, brand comes from the prompt/reference. Dogfood: bind Allnighter's own
amber-on-midnight tokens and design the board *using* the board.

## Personas (structural cages, user-extensible Skills)

Design seats wear **design personas** — editable `PromptProfile`s — spread to force
range. Each carries a **divergence mandate** (a structural constraint it may not
leave), not a personality description:

| Persona | Divergence mandate (the cage) |
| --- | --- |
| `ive_protege` | Restraint + material honesty; remove until it breaks; no decorative gradient or shadow. |
| `pure_minimalist` | Exactly two colors + white; type-driven hierarchy; no hero image above the headline. |
| `bold_expressive` | High-contrast, oversized type, opinionated color, motion-forward; the headline dominates. |
| `editorial_wild` (wildcard) | **Break the SaaS genre** — magazine/editorial or dense-information layout (e.g. left-edge vertical nav only, no top bar; or grid-dense). Must not look like a modern SaaS app. |
| `on_brand` (swap-in) | Adhere hard to the bound design system (repo tokens / reference). Range in *layout*, not brand. |

Default Design preset = **4 seats** (Fork 4 resolved): `ive_protege`,
`pure_minimalist`, `bold_expressive`, `editorial_wild`; `on_brand` swaps in via the
dropdown when a brand is bound. Users can fork a persona ("protégé of whoever did
Linear's site") exactly like a review lens. Dispatch surfaces the persona on each
frame (a subtle badge) so the user *reads the range at a glance*.

## The Measured Win (what 10/10 means, in user-visible signals)

| Signal | Today (design prompt via RB chain) | Design council target |
| --- | --- | --- |
| Time to first comparable frame | N/A (prose about pixels) | First frame ≤ ~30s; board fills **progressively** as seats finish |
| Clicks: prompt → pickable mockups | 0 useful | 1 (Design preset + commit) |
| Taste range on the board | Convergent slop | **Visibly distinct at thumbnail scale** (cages + pHash reroll + `distinctiveness`) |
| Realism | Lorem-ipsum theater | Rendered from **shared messy data**; stress/empty states visible |
| Decision confidence | "AI picked for me" / prose about pixels | **"I chose; the council showed the tradeoffs"** |
| Handoff to build | Copy a PNG / re-prompt | **Remix brief → build council, zero paste** |
| Marginal cost | — | **$0** (subscription CLIs + local render only) |
| Hidden product truth | None | None (render brief + `CallPlan` + reroll ceiling visible pre-commit) |

## Artifact Contract

All Markdown/JSON files are **derived from `run.json` stages**; `run.json` is the
only truth (same RB law). Design runs add:

```text
run_<id>/
  render_contract.json          # resolved before fan-out; viewport + scheme + brand + fixture ref
  content_fixture.json          # the one shared, deliberately-messy dataset all seats render
  frame_<seatId>.html           # worker output (self-contained HTML; the deliverable)
  frame_<seatId>.png            # rendered by Allnighter at the contract (the judging surface)
  board.json                    # ordered gallery metadata + per-frame persona + divergence scores
  design_review_<lensId>_<seatId>.md   # lens × option critique (Design2; carries region anchors)
  design_critique.json          # structured scorecard (lenses × options) (Design2)
  chosen_frame.json             # the human verdict + rationale (logged for taste memory) (Design3)
  remix_brief.md / design_brief.json   # design final → build handoff (Design3)
  bundle.md                     # composed view incl. the board
```

The structured truth between fan-out and the board is **`board.json`** (the design
analog of `JudgeAnalysis`); the structured critique is **`design_critique.json`**.

## Built-In Design Presets (and CallPlan honesty)

| Preset | Stages | Rough calls |
| --- | --- | --- |
| `design_board` | clarify? → render contract → 4 seats fan out → render → board | 4 fan-out + 4 local renders **(+ up to 4 rerolls)** |
| `design_review` | + design lenses (vision) + scorecard | + lenses × options (vision workers) |
| `design_full` | + Lead Designer tradeoff + remix round | + 1–2 reduce + 1 remix re-render |

Design runs are heavier and **variable** in a way RB never was: render calls (local,
$0, but show latency), vision-lens calls, and a **non-deterministic reroll ceiling.**
**Product law:** the `CallPlan` shows render + vision calls *and* the reroll ceiling
("up to +N if seats converge") before commit. Each seat's persona shows a one-line
stance in the `CallPlan` so the user knows they are buying **range**, not four
lottery tickets.

## Product Laws (design path — additions to RB0)

- **The human casts the deciding vote.** AI ranks and critiques; it never
  auto-picks the winner.
- **The board is the first truth surface.** No prose summary or AI verdict
  precedes the visual wall. Your eyes decide before any AI voice speaks.
- **Comparable or nothing.** No frame reaches the board unless rendered at the
  run's contract against the shared content fixture.
- **Divergent or reroll.** Measured convergence triggers a bounded reroll; range
  is enforced, not hoped.
- **The deliverable is code.** The board shows pixels; the winner hands back
  source (and exported tokens). No PNG-only dead-ends.
- **No silent mode switch.** Design mode is chosen (chip) or confirmed
  (result-side prompt), never auto-flipped.
- **Ask before you waste.** Underspecified + no reference image → clarify before
  fan-out, not four divergent guesses.
- **Accessibility is the one objective gate.** `contrast_a11y` may throw a real
  blocker; every other lens lands as concern/ok. Taste is never a blocker (that is
  how 0/10 returns).
- **Advisory never mutates.** Lenses append; they never overwrite a frame's source.
- **Cost is never silent.** Render + vision + reroll-ceiling are in the `CallPlan`
  before commit.
- **Reuse over re-run.** Editing one persona re-renders **one** seat; changing the
  render contract or content fixture invalidates **all** frames. Same `reuseKey`
  discipline as RB.

## Moat (why a single-shot tool structurally cannot match this)

| Tool | What you get | Structural gap |
| --- | --- | --- |
| v0 | One code generation per prompt | No range, no review, one shot |
| Galileo | AI Figma designs | Figma lock-in, no code |
| Figma AI | Redesign within Figma | Single output, no council, no code handoff |
| Claude Artifacts / claude.ai/design | One rendered component, amnesiac | No range, no persisted taste, nothing to diff |
| **Design council** | **N caged taste profiles in parallel, rendered from real messy data, design-lens reviewed, human picks, outputs code — in the same session as your build council** | — |

The last row is the moat: range + review + **you never left Allnighter** + a memory
that sharpens every night you use it. A single-shot chat can make one pretty thing;
it cannot guarantee range (no council), remember your taste (no ledger), diff/toggle
N candidates synchronously (no comparable frames), measure-and-fix convergence
(nothing to diff), or hand you code that flows into a build agent with zero paste.

## Vocabulary (additions to RB0)

| Term | Meaning |
| --- | --- |
| **Design run** | A council run whose unit is a rendered frame and whose verdict is human taste. A `WorkflowPreset` flavor, not a separate app. |
| **Render contract** | Resolved pre-fan-out target: viewport, color scheme, platform, HTML constraint, content-fixture + brand refs. Truth in `render_contract.json`. |
| **Content fixture** | The one shared, deliberately-messy dataset all seats must render — the other half of comparability. |
| **Reference image** | A user-attached image, in `redesign-this` (layout/content map) or `style-reference` (seeds a persona) mode. |
| **Design persona** | A named taste `PromptProfile` with a structural divergence mandate, bound to a seat. Replaces Neutral/Skeptic for design runs. |
| **The board** | The live gallery of comparable frames at identical scale — design analog of `analysis.md`; the hero view. |
| **Divergence score** | Local perceptual distance (pHash) between frames; drives the bounded reroll. |
| **Design lens** | A vision `PromptProfile` critiquing one frame on one visual axis; carries region anchors. (Design2.) |
| **Scorecard** | The lenses × options matrix; an overlay on the board, never the default. (Design2.) |
| **Lead Designer** | Optional design synthesizer that names the tradeoff *after* the human looks. Never the verdict. (Design3.) |
| **Remix brief / `DesignBrief`** | Design-level synthesis ("A's nav + B's palette") that re-renders, then hands to the build council. (Design3.) |

## Detection (deliberate first, smart later — never silent)

- **Prompt-side (v1):** a 4th composer chip beside Synthesis / Light / Full:
  **Design**. The user tells us; skip a fragile intent classifier.
- **Result-side (later):** a worker emitting `.html`/an image → a quiet *"These look
  like design results — view as a board?"* The user confirms. Better signal than
  prompt classification; v2 polish.
- **Mixed prompts** ("70% logic, 30% make the error state nice") are **out of scope
  in v1** — the user picks the chip; a future "split run" is named, not built.

## Slice Map

| Slice | Doc | Purpose | Status gate |
| --- | --- | --- | --- |
| **Design1** | `Design1_Render_And_Board.md` | The gate: render contract + content fixture + **headless render harness** + structural personas + **divergence reroll** + the **progressive live board** + pick a direction. **No lenses, no judging.** | Build only after the **Design Activation Gate** (below) passes. |
| **Design2** | `Design2_Design_Lenses_And_Scorecard.md` | Re-point RB2: design lens profiles, `requiresVision` routing, `contrast_a11y` blocker, scorecard overlay, **region-anchored** critique. | After Design1 is loved. |
| **Design3** | `Design3_Verdict_Remix_And_Flywheel.md` | Human verdict (pairwise), Lead Designer tradeoff, **remix → re-render → `DesignBrief` → build council**, visual-diff slider, single-seat "more like this", verdict logging for taste memory. | After Design2. |

**Founder lean made firm:** clarify-before-fan-out and structural-persona dispatch
are **Design1 requirements**, not polish — the gate fails on convergence without
them. Lenses can wait; divergence cannot.

## Design Activation Gate (mirrors RB0 — build nothing past Design1 until this passes)

You cannot eval taste. You **can** eval the objective floor that makes taste
possible. Before Design1 machinery is trusted (and again before Design2), run
**three real design prompts** manually through the dispatch + render path:

1. **Redesign with an attached screenshot** (contract from image).
2. **Greenfield screen, underspecified** (the clarify path).
3. **"Make this not look like AI slop"** on an existing UI.

Score each pass/fail; the path earns its machinery only on a **majority across the
three prompts**:

1. **Comparable** — all frames rendered at one contract, side by side at thumbnail
   scale (not phone-vs-desktop, not lorem-vs-paragraph).
2. **Divergent** — ≥3 of 4 frames *visibly* different in layout/taste at thumbnail
   scale, not palette swaps (after at most one reroll/seat).
3. **Accessible floor** — `contrast_a11y` (manual at gate time) catches a real WCAG
   failure you can verify by hand.
4. **Real content** — frames render the shared messy fixture, not single-word
   labels; at least one design visibly strains under it.
5. **Shippable** — the winner's HTML is a plausible ship surface, not a PNG
   dead-end.
6. **Non-designer can pick a favorite in < 60s on the board alone**, before any AI
   voice speaks.
7. **Worth the calls** — clearly beats asking one model once.

### Design Activation Gate Decision Log

| Date | Prompts (pass / fail) | Rubric (1–7) | Render engine chosen | Go / revise |
| --- | --- | --- | --- | --- |
| _pending_ | _redesign ✓, greenfield ✓, anti-slop ?_ | _filled at gate time_ | _WKWebView / Chromium_ | _pending_ |

If the floor fails — frames not comparable, or seats converge despite cages + one
reroll — **revise the render contract, the content-fixture synthesis, or the
persona cages and re-run.** Do not start Design1 slices on a board of four
near-identical frames; that is the 0/10 in a nicer costume.

## North-Star Acceptance Demo (the whole path)

```text
type ONE design prompt  (e.g. "make this profile page feel premium and clean")
  + optionally attach a screenshot to redesign (or a style reference)
-> pick the Design chip
-> Allnighter resolves the Render Brief pill (viewport, scheme, repo tokens) — one tap to correct
   (or, underspecified + no image, asks 1-3 visual quick-choices)
-> it synthesizes ONE shared, deliberately-messy content fixture (real-feeling names, a missing
   avatar, an empty list, an overflowing row) and OCRs copy out of the reference if present
-> 4 seats wear CAGED, divergent personas (Ive protégé / pure minimalist / bold / editorial wildcard),
   each constrained to the same contract + fixture
-> each seat emits ONE self-contained HTML file; Allnighter renders 4 comparable frames headlessly
-> THE BOARD fills progressively (placeholders at identical size -> frames swap in as they finish).
   pHash flags two that converged -> the offending seat rerolls once, harder. Four genuinely
   different interpretations now sit side by side at the same scale.
   << Design1 stops here — and it already feels like a private design team. >>
-> open one fullscreen: it is LIVE HTML, not a PNG (hover, scroll, real interaction)
-> (Design2) design lenses critique each frame; the scorecard overlay = lenses × options;
   contrast_a11y can blocker; critique pins anchor to regions of the frame
-> (Design3) you look first, in silence, and pick (pairwise A/B if 4+). THEN the Lead Designer
   names the tradeoff. You composite "A's nav + B's palette + C's empty-state" -> it RE-RENDERS as a
   round-2 frame -> becomes a DesignBrief -> "Implement This" hands it (with the winning frame as a
   reference image) to the build council.
No copy/paste. No silent mode switch. The deliverable is code, not a PNG.
```

## Deferred (named, not forgotten — magical ≠ complex)

- **Taste-memory `house_style` seat** (parked `15_Preference_Ledger_And_Taste_Memory`).
  Verdict logging starts in Design3 so the ledger accumulates; the learned persona
  becomes a seat post-launch. The compounding moat.
- **Real-data ingestion** — pull live rows from repo fixtures / dev DB into the
  content fixture (privilege surface). v1 synthesizes the messy fixture instead.
- **URL "vibe stealer"** — drop a `linear.app` URL → fetch + screenshot → style
  reference. v1 takes local images only (zero-cost, private).
- **Multi-round tournaments** beyond one remix round; **live dataset swap** on the
  board (requires a data-island HTML contract); **distinct designed states**
  (empty/loading/error as separate worker outputs).
- **Spatial-pin authoring** UI ships in Design3, but frames store a coordinate
  system from Design1 so pins retrofit without re-rendering.
- **Reverse flywheel** — a technical run flags "this needs a design pass" and hands
  a slice to the design council.

## Exit Gate (this charter)

This charter is finalized. Design1 is build-ready below. The only thing between
here and Design1 code is **running the Design Activation Gate on three real
prompts and recording the result** — and, in doing so, **choosing the render
engine** (the one decision Design1 cannot start without).
