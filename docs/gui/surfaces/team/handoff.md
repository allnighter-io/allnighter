# Handoff: Council command center — **native SwiftUI (macOS)**

> **Legacy visual reference.** The visual direction may still be useful, but the
> vocabulary is superseded by `docs/phases/Work_Order_Team_Model.md` and
> `docs/phases/Team_First_Vocabulary_Cleanup.md`. Do not copy public labels such
> as Council, panel, synthesizer, member answer, or plan into new UI.

## Overview
The **Council** is the Allnighter MVP's primary screen. One prompt fans out to a
panel of subscription coding-CLIs in parallel; every answer streams back; then
**Opus 4.8 synthesizes one plan**. Text-only, local, zero marginal cost.
This pack documents that single window — its tokens, layout, states, and copy —
for implementation as a **native SwiftUI macOS app**.

## About the design files
The files under `reference/` are **design references created in HTML/React** —
a click-through prototype showing the intended look and behavior. They are **not
production code to port line-for-line**. Your task is to **recreate this design
natively in SwiftUI** using the token mapping and per-state specs below. Treat
the HTML/CSS as the visual ground truth (exact colors, spacing, copy) and the
two Swift files in this folder as your starting scaffolding.

> Target stack confirmed by the founder: **native SwiftUI, macOS 14+**. Do not
> ship the HTML or wrap it in a WebView. Build real `View`s. Where this doc says
> "web/React did X," it's describing intent — implement the SwiftUI-idiomatic
> equivalent.

## Fidelity
**High-fidelity.** Colors, typography, spacing, radii, and copy are final.
Reproduce them exactly via the token enums in `AllnighterTokens.swift`. The
brand is **dark-mode only** ("amber phosphor on midnight") — there is no light
theme; do not add one.

## What's in this pack
- **`AllnighterTokens.swift`** — the complete token→SwiftUI mapping (`ALColor`,
  `ALFont`, `ALSpace`, `ALRadius`, `ALControl`, `ALMotion`, shadow/glow view
  modifiers, and a `Color(hex:)` helper). **This is the source of truth for all
  values** — the tables below reference it.
- **`CouncilState.swift`** — the `@Observable` view model, the `Worker`/`RunStatus`
  domain types, the six-worker panel data, and the full state-transition table.
- **`reference/`** — the HTML/React prototype (`index.html`, `chrome.jsx`,
  `screens.jsx`, `data.jsx`) and the design-system `styles.css` + `tokens/`.

---

## Window anatomy (all states share this shell)

A single resizable window, min ~**1180×720**, `ALRadius.window` (12pt) corners,
1px `borderDefault` hairline, `ALColor.base` canvas. Three bands:

```
┌────────────────────────────────────────────────────────────┐
│  TITLE BAR  44pt · ALColor.surface · 1px borderSubtle base  │
│  ◉◉◉      ☾ allnighter · council        [5/5 healthy] ⟲ ⚙  │
├───────────────┬────────────────────────────────────────────┤
│  SIDEBAR      │  MAIN  (ALColor.base, scrolls)              │
│  264pt        │                                             │
│  ALColor      │  ← state-specific content (compose/run/plan)│
│  .subtle      │                                             │
│  1px border   │                                             │
│  right        │                                             │
└───────────────┴────────────────────────────────────────────┘
```

On macOS use a real title bar (`.windowStyle(.hiddenTitleBar)` + a custom
toolbar, or an `HSplitView`/`NavigationSplitView` for the sidebar). The traffic
lights are the system's; the centered title and right-side controls go in the
toolbar.

### Title bar
- **Left:** system traffic lights (don't redraw them; the mock's colored dots
  `#FF5F57 / #FEBC2E / #28C840` are placeholders for the real ones).
- **Center:** the **live mark** (16pt) + `allnighter` in `ALFont.label`
  `textSecondary` + `· council` in `ALFont.monoSm` `textFaint`.
- **Right:** a `Badge` (tone positive, dot) reading `5/5 healthy` (Doctor health),
  then two ghost `IconButton`s — `history`, `settings-2` (SF Symbols
  `clock.arrow.circlepath`, `gearshape`).

### The live mark (brand heartbeat) — build once, reuse everywhere
The amber crescent with a cursor block where **only the block blinks**. The moon
is static. Implement as a `Canvas`/`Shape` or a bundled SVG-derived `Path`:
- Crescent = a filled circle (r≈32 at cx47,cy50 on a 100×100 box) minus a circle
  (r≈28 at cx62,cy41), filled with the amber gradient `#FFD79E → #FFA630 → #F0901C`.
- Cursor block = rounded rect at x60,y43,w10.5,h17,r2.6, fill `#FFE9C6`.
- **Idle:** block solid. **Running/planning:** block blinks via
  `ALMotion.blink` (hard on/off, 1.05s). **Done:** block turns `ALColor.statusDone`.
  The block doubles as the activity light — never animate the whole mark.

### Sidebar (264pt) — present in compose & run (selection disabled during run)
Three sections, vertical:
1. **Panel** — header row: `Panel` (`ALFont.caption` 700, uppercase,
   tracking `ALTracking.caps`, `textFaint`) + count `N of 6` (mono, `textFaint`,
   right). Below: the six **WorkerChip** rows (see component spec), each
   selectable with a checkbox affordance. At least one must stay selected.
2. **PlanWriter** — label `PlanWriter`, then one `raised` row (radius `md`):
   Opus glyph + `Opus 4.8` (`ALFont.body` 600) + `master` tag (mono, `accentText`)
   + a chevron. Tapping opens a picker (Opus / Sonnet).
3. **Recent** — pinned to the bottom (`Spacer()` above). Label `Recent`, then
   history rows: a status dot (green/yellow), title (`ALFont.label`,
   `textSecondary`, truncates), and mono meta (`03:12 · 6 done`).

---

## State 1 — **Compose**
**Purpose:** pick the panel, write one prompt, launch the run.

**Layout:** sidebar + a main area that **centers a 680pt column** vertically and
horizontally (`ALControl.readingMax`), padding 28×32pt.

- **Eyebrow:** `NEW COUNCIL RUN` — `ALFont.caption` 700, uppercase,
  tracking `ALTracking.caps`, `accentText`. 14pt below it the prompt card.
- **Prompt card:** `raised` fill, 1px `borderDefault`, radius `xl` (14pt),
  `alShadowSm()`. Focus → border becomes `accentBorder`.
  - `TextEditor` inside: transparent, 18pt `ALFont.sans`, line-height 1.5,
    padding 22/22/12, placeholder `Ask the panel one thing…` in `textFaint`.
  - Bottom bar (1px `borderSubtle` top, 12×14 padding): left meta
    `6 workers · local · $0 marginal` (`ALFont.monoSm`, `textFaint`); right a
    **primary Button** `Run council` with a `play` icon. Disabled until the
    prompt is non-empty and ≥1 worker selected.
- **Example chips** (16pt below): pill buttons (`surface` fill, 1px
  `borderSubtle`, radius `pill`, `ALFont.label`, `textMuted`) — tapping fills the
  prompt. Copy: `3 directions for a premium dashboard` · `rewrite our API error
  copy` · `plan a migration to Swift 6`.

---

## State 2 — **Run** (live) + synthesizer sub-states
**Purpose:** watch every selected worker answer in parallel, then watch Opus
synthesize. Sidebar selection is **disabled** here.

**Layout:** main padding 28×32pt.
- **Run header:** title `Council run` (`ALFont.h2` 700, tracking heading) with
  the prompt beneath it (`ALFont.body`, `textMuted`, max 560pt). Right: the
  `elapsed` clock (`ALFont.monoSm`, 13pt, `textFaint`) + a small secondary
  **Button** `Stop` with a `square` icon.
- **Worker grid:** 2 columns, 10pt gap (`LazyVGrid`, 2×`.flexible`). Each cell is
  a **WorkerChip** in *status* mode showing the live `RunStatus`:
  - `queued` — `statusQueued` dot, calm.
  - `running` — `statusRunning` (blue) dot **pulsing** (`ALMotion.pulse`),
    label "Running".
  - `done` — `statusDone` (green) pill + mono meta `2,140 · 00:04`.
  - `failed` — `statusFailed` (red) pill + meta `auth expired`. **Always shown,
    never hidden.** (Grok Build fails in the sample data.)
- **Synthesis bar** (appears once all workers terminate): full-width, radius `lg`,
  a subtle top-down amber tint over `raised`, 1px `accentBorder`, padding 14×16,
  12pt gap. Contains the **live mark** (26pt, blinking while planning) + a
  two-line status, and—when ready—a primary **Button**:
  - `planning`: title `Opus is planning the plan…`, meta
    `reading 5 answers · 1 failed`. Live mark blinks.
  - `ready`: title `Plan ready`, meta `5 answers · 00:42 · $0.00 marginal`,
    + Button `View plan` (`arrow-right`) → State 3.

**Timing (prototype values — replace with real CLI events):** workers start
staggered ~170ms apart; sample durations Opus 4.2s, ChatGPT 2.6s, Sonnet 3.1s,
Composer 2.2s, Gemini 1.5s, Grok 2.9s(fail). Synthesis begins ~450ms after the
slowest finishes and resolves ~2.7s later. The elapsed clock ticks every 100ms
and freezes when synthesis is ready.

---

## State 3 — **Plan**
**Purpose:** read the synthesized plan; inspect every raw member answer.

**Layout:** main padding 28×32pt.
- **Header row:** a **segmented `Tabs`** — `Plan` | `Member answers`
  (count 6) — on the left; on the right three buttons: ghost `Copy` (`copy`),
  secondary `Export Markdown` (`download`), primary `New run` (`plus` → reset to
  Compose).

### Tab A — Plan
- **Prompt recap card:** `accent` variant (amber-tinted surface), the prompt in
  quotes (`ALFont.body`, `textSecondary`) + an `Opus 4.8` mono `Badge`; meta line
  `synthesized from 5 answers · 00:42 · $0.00 marginal · local`.
- **Five sections**, each = an icon chip (24pt, radius `sm`, tinted surface +
  colored glyph) + a 15pt 600 title, over a `flush` Card:
  | Section | Icon | Icon tint | List style |
  |---|---|---|---|
  | Consensus | `check-check` | green / successSurface | dot rows |
  | Conflicts | `zap` | yellow / warningSurface | dot rows |
  | Gaps | `search` | blue / infoSurface | dot rows |
  | The plan | `arrow-right` | amber / accentSurface | **numbered** rows (amber number chip) |
  | Minority report | `users` | muted / active | a single italic quote + `— Gemini Flash` |
  - **Row spec:** 7pt vertical padding, `ALFont.body` `textSecondary`, line 1.5,
    1px `borderSubtle` divider between rows. Dot = 6pt circle `textFaint`.
    Numbered chip = 20pt circle, `accentSurface` bg, `accentText`, 11pt mono 600.
  - Exact copy for all five sections lives in `reference/data.jsx` (`AL_PLAN`).

### Tab B — Member answers
- A vertical stack (12pt gap) of `flush` Cards, one per worker:
  - Header: 26pt glyph chip (`active` bg, radius `md`) + name (600) + model
    (mono 11, `textFaint`, right) + a `StatusPill` (`done`/`failed`).
  - Body: the raw answer (`ALFont.body`, `textSecondary`, line 1.6). A failed
    worker shows, in `textFaint`: `No answer — CLI auth expired. Surfaced in
    Doctor, never faked.`
  - Exact answers live in `reference/data.jsx` (`AL_ANSWERS`).

---

## Components to build (native, reusable)
These appear across states — build them as SwiftUI views, styled from the tokens.

- **Button** — variants `primary` (amber fill, `textOnAmber`, `alGlowAmber()` on
  hover, darken→`accentPress` on press), `secondary` (`surface` fill, 1px
  `borderDefault`), `ghost` (transparent, hover→`hover`), `danger`. Heights
  `ALControl.height` (30) default / `heightSm` (24). Optional leading icon. Press
  = `scale(0.97)` via `ALMotion.fast`. Sentence-case labels.
- **IconButton** — square ghost/outline, sizes sm/md, SF Symbol inside, always
  an accessibility label.
- **Badge** — pill, tones (positive/accent/neutral/warning/danger), optional
  leading dot. Tinted surface + matching text color from the status pairs.
- **StatusPill** — the signature run-status chip: dot + label, color per
  `RunStatus` (queued/running/done/failed/timedOut). The `running` dot pulses.
- **WorkerChip** — a worker row in two modes: **selectable** (sidebar: glyph +
  name + model + checkbox; selected → `active` bg + `accentBorder`) and **status**
  (run grid: glyph + name + model + `StatusPill` + meta).
- **Card** — base surface; variants `default` (`raised` + 1px `borderSubtle` +
  `alShadowSm`), `flush` (no shadow, for list sections), `accent` (amber-tinted).
  Radius `lg` (10).
- **Tabs** — segmented control (`surface` track, `raised` selected thumb), used
  in the plan header. Optional count badge per tab.

> SF Pro & SF Mono are the **system fonts** — `ALFont` already uses `.system(...)`,
> so type renders natively with correct optical sizing. Keep `.tracking()` from
> `ALTracking` on display/heading/eyebrow text.

---

## Iconography
- **UI icons** → **SF Symbols** (native). Mapping from the prototype's Lucide
  names: `play`→`play.fill`, `square`→`stop.fill`/`square`, `arrow-right`→
  `arrow.right`, `copy`→`doc.on.doc`, `download`→`square.and.arrow.down`,
  `plus`→`plus`, `check-check`→`checkmark.circle`, `zap`→`bolt.fill`,
  `search`→`magnifyingglass`, `users`→`person.2.fill`, `history`→
  `clock.arrow.circlepath`, `settings-2`→`gearshape`, `chevron-down`→`chevron.down`.
- **Worker/brand glyphs** → the prototype uses Simple Icons (Anthropic, Gemini,
  X/Grok). Bundle the monochrome SVGs (or PDFs) as assets and tint per worker
  (`glyphHex`). ChatGPT/Codex and Composer/Cursor have **no** Simple Icons glyph
  — fall back to an SF Symbol (`terminal`, `square`) in `textSecondary`, exactly
  as the prototype does.
- **No emoji.** Metadata is separated by the middle dot `·`.

---

## Voice & copy rules (match exactly)
Sentence case everywhere; verbs first (`Run council`, `Stop`, `New run`). Numbers
are concrete and mono (`5 answers · 00:42 · $0.00 marginal`). Never lead with
"AI." A failed worker is shown **failed with its real reason**, never faked —
this honesty is the product. No emoji; `·` separates metadata.

## Design tokens
All values are in **`AllnighterTokens.swift`** (`ALColor`, `ALFont`, `ALSpace`,
`ALRadius`, `ALControl`, `ALMotion`). The raw CSS originals are in
`reference/tokens/` if you need to diff. Key anchors: amber `#FFA630`, canvas
`#090B13`, sidebar `#0D101A`, surface `#111420`, card `#151822`, primary text
`#E1E5F0`. Dark-mode only.

## State management
See `CouncilState.swift` — `CouncilModel` (`@Observable`) holds `prompt`,
`selected`, `view`, `states`, `elapsed`, `synth`; the file ends with the full
transition table. Swap the simulated scheduling in `startRun()` for real CLI
subprocess tasks (one per selected worker), updating `states[id]` on start/exit
and advancing `synth` when all terminate.

## Assets
- App icon / live mark: `reference/` references `assets/allnighter-icon.svg`
  (in the design-system root). Ask for the vector if you don't have it; the live
  mark geometry is specified above for a native rebuild.
- Brand glyphs: bundle Simple Icons SVGs for anthropic, googlegemini, x.

## Files
- `AllnighterTokens.swift` — token→SwiftUI mapping (start here).
- `CouncilState.swift` — model + state machine.
- `reference/index.html` — the runnable prototype (open in a browser to click through all states).
- `reference/chrome.jsx` — window chrome + sidebar + live mark.
- `reference/screens.jsx` — Composer / RunView / PlanView layouts.
- `reference/data.jsx` — the six-worker panel, sample timings, plan + answers copy.
- `reference/styles.css` + `reference/tokens/` — the source design tokens.
