# Handoff: Default Model & Substitutions (SwiftUI / macOS)

## Overview
A single settings surface — **Settings › Default** — that controls two things and one shared concept:

1. **The Default ("Auto")** — the model that answers any chat when the user hasn't picked a team or a specific model. Auto draws from a **tier**.
2. **Healthy substitutions** — if the chosen model is down, fall back to another ready model **on the same tier** (across any CLI). Never upgrades, never downgrades.
3. **Tiers** (Frontier / Balanced / Economy) — the shared concept under both. A tier is a **roster** (a membership list), not a property of a model. The **top model in a tier is that tier's Default** — what Auto resolves to and what substitutes lead with.

This pairs with the separate **CLI Setup** handoff: that surface decides *which models are turned on/available*; this surface decides *which of those available models are tiered, and which tier Auto uses.*

## About the Design Files
`Default & Substitutions — Redesign.html` is a **design reference built in HTML/CSS/JS** — a working prototype of the look and interaction. It is **not** production code to copy. Recreate it natively in the SwiftUI macOS app using existing components and the Allnighter design tokens (which already target SF Pro / SF Mono and the color ramp below).

The prototype is **interactive** — open it in a browser and:
- Click the **Pick the tier** segmented control → the Auto pill and the **Auto** badge on the rosters both move to the chosen tier.
- **Drag** model cards between the three tier columns and the **Unassigned** shelf; drag a card to the **top** of a tier to make it that tier's Default.
- Click the **＋** on any tier (or the empty-state button) → the **roster modal** opens; add from Unassigned (＋), remove (×), or drag between the two lists.
- Toggle **Allow healthy substitutions**.

## Fidelity
**High-fidelity.** Final colors, type, spacing, radii, copy, and interaction model. All hex values, sizes, and spacing are exact and listed under **Design Tokens**.

---

## Data Model

A flat list of **available** models (the on-models from CLI Setup). Each carries a **tier** membership; `nil` = Unassigned. **Order matters** — within a tier, index 0 is the Default.

```swift
enum Tier: String, CaseIterable { case frontier = "Frontier", balanced = "Balanced", economy = "Economy" }

struct DefaultModel: Identifiable {
    let id: String          // "opus-4.8"
    let name: String        // "Opus 4.8"
    let cliSlug: String     // "claude-code" — shown as mono sub-label
    let glyph: Glyph        // source CLI's brand mark
    var tier: Tier?         // nil = Unassigned
}

// Ordered list — array order within a tier defines the Default (first = Default).
var models: [DefaultModel]

// Global settings
var defaultTier: Tier = .flagship   // which tier Auto draws from
var substitutionsEnabled: Bool = true
```

**Derived:**
- `models(in: tier)` — models whose `tier == tier`, **in array order**. `models(in: tier).first` is that tier's **Default**.
- `unassigned` — models with `tier == nil`.
- `autoResolved = models(in: defaultTier).first` — the model Auto currently uses. If `nil`, **chats wait**.
- `substituteCount = models(in: defaultTier).count - 1`.

**Ordering rule:** keep the array grouped by tier (Frontier, Balanced, Economy, then Unassigned) using a **stable** sort, so intra-tier order (and therefore the Default) is preserved across moves. See **Move semantics**.

> **Most models start Unassigned.** Do NOT pre-sort every available model into a tier — there are too many. Ship a few sensible defaults tiered (e.g. Opus → Flagship) and leave the rest on the Unassigned shelf for the user to place.

---

## Screen: Settings › Default

A scrollable settings page, content max-width ~1080pt. Header + three stacked sections.

### Header
- Eyebrow `DEFAULT` (amber, 11pt/700, uppercase, tracking 0.12em).
- Title **`Default model`** (27pt/800, tracking −0.02em).
- Subhead (13pt, muted, max-width ~620pt): *"What answers when you don't pick a team or a model. Every chat starts here unless you say otherwise."*
- Bottom hairline (`--border-subtle`).

### Section 1 — The Auto card
A single `--bg-raised` card, 1pt `--border-default`, radius 14pt, padding 20/22pt, `HStack` gap 18pt, vertically centered:
- **∞ glyph tile** (left): 52×52pt, radius 14pt, `--accent-surface` fill, 1pt `--accent-border`, amber infinity icon ~26pt.
- **Main** (fills): 
  - Row: **`Auto`** (18pt/800) + a small **`Default`** pill (mono 11pt/600, `--accent-text`, `--accent-surface` fill, 1pt `--accent-border`, radius 999pt, padding 2/9pt, uppercase, tracking 0.06em).
  - Below (13pt muted), one line: *"Your go-to model used in chat by default."* followed inline by the **resolved-model pill** (see below).
- **Tier control** (right, `flex: none`): a small label **`Pick the tier`** (11pt/600 muted) above a **segmented control** (Frontier / Balanced / Economy). Use a native macOS segmented control or `Picker(.segmented)`. Active segment = amber fill (`--accent`) with `--text-on-amber` label; inactive = muted, hover brightens. Changing it sets `defaultTier` and updates the resolved pill + the **Auto** badge on the rosters.

**Resolved-model pill** (the inline pill — styled like the model chips on CLI cards):
- `--bg-active` fill, 1pt `--border-subtle`, radius 999pt, padding 4/13pt, 13pt/600.
- Text: model name in `--text-secondary`, then the tier name in `--text-faint`/500 with ~7pt leading gap, e.g. `Opus 4.8  Flagship`.
- **Empty/wait state**: if `autoResolved == nil`, the pill text turns `--amber-400` and reads `No model on <Tier> — waits`.

> Note: this card has **no** "Add or remove substitutes" link and **no** multi-line status copy — substitutes are managed per-tier in Section 3 / the modal.

### Section 2 — Substitutions
- Section label `SUBSTITUTIONS` (10.5pt/700, uppercase, tracking 0.12em, faint) with a trailing hairline.
- One row card (`--bg-raised`, 1pt `--border-subtle`, radius 12pt, padding 16/20pt, `HStack` gap 16pt):
  - Left: **`Allow healthy substitutions`** (14.5pt/700) + sub (12.5pt muted): *"If your model is down, fall back to another ready model **on the same tier** — across any CLI. Never upgrades, never downgrades."* (bold span = `--text-secondary`).
  - Right: a **toggle**, 42×24pt track / 18pt knob. On = `--accent` track + white knob (knob +18pt); off = `--ink-600` track + `--ink-200` knob. `Toggle(...).labelsHidden().tint(Color("accent"))`.

### Section 3 — Default model per tier (the rosters)
- Section label `DEFAULT MODEL PER TIER` + hairline.
- **Three tier columns** (`HStack`/grid, 3 equal columns, gap 16pt). Each column is a `--bg-surface` card, 1pt `--border-subtle`, radius 14pt, min-height ~200pt:
  - **Header** (padding 15/16/12, bottom hairline): optional **★** (amber) for Frontier; tier **name** (15pt/800); an **Auto** badge if this tier == `defaultTier` (9.5pt/700 uppercase, amber, `--accent-surface` fill, 1pt `--accent-border`, radius 999pt); a mono **count** pushed right (`--text-faint`); a small **＋** add button (24×24pt, `--bg-active`, neutral). Below: a one-line **caption** (12pt muted) — Frontier: *"Smartest. Slow and pricey."* · Balanced: *"Everyday workhorses."* · Economy: *"Quick and cheap."*
  - **List** (padding 12pt, vertical gap 8pt): **model cards** (see below), or an **empty state** (centered, amber clock icon, *"Empty — work waits"*, *"Nothing can stand in here."*, and an **Add a model** button).
- **Unassigned shelf** (below the columns, full width): a **dashed** 1pt `--border-default` container, radius 12pt, padding 13/15pt. Header `UNASSIGNED` + count + a muted caption *"pickable by hand · Auto never uses these · they never substitute."* Body = model cards in a wrapping row (each ~248pt wide), or empty text *"Every model is on a tier. Drag one here to bench it from Auto & substitution."*
- **Legend** (mono 11.5pt faint): *"The top model in each tier is its **default** — what Auto picks and what substitutes lead with. Drag to reorder; drag across tiers to move."*

**Model card** (in rosters + shelf):
- `--bg-raised` fill, 1pt `--border-subtle`, radius 10pt, padding 10/12pt, `HStack` gap 11pt. `cursor: grab`.
- 30×30pt glyph tile (`--bg-active`, radius 8pt) with the source-CLI brand mark.
- Name (13.5pt/700) + mono `cliSlug` sub (11pt faint).
- A **`Default`** tag (amber `mm-tag` style) only on the **first** card of a tier.
- A **grip** dots icon (right, `--text-disabled`) signalling draggability.

---

## The Roster Modal (shared)

Opened by any tier's **＋** (or empty-state "Add a model"). Scoped to one tier. This is the single surface for adding/removing a tier's models — i.e. choosing Auto's substitutes for that tier.

- Scrim `--bg-overlay`, centered card ~540pt wide, max-height 82vh, `--bg-raised`, 1pt `--border-default`, radius 18pt, `--shadow-xl`.
- **Header** (padding 18/20/15, bottom hairline): ★ (amber, Flagship only) · title **`Manage <Tier>`** (16pt/800) · subtitle *"Pick healthy substitutes for this tier."* (12.5pt muted) · close `×`.
- **Body** (scroll), two groups:
  - **`On <Tier> · N`** — a drop list of the tier's models in order. Each row: grip · glyph · name (+ **Default** tag on the first) · mono slug · a neutral **×** icon button (remove → Unassigned).
  - **`Unassigned · N`** — a drop list of `unassigned` models only. Each row: grip · glyph · name · slug · a neutral **＋** icon button (add → this tier).
  - **Add pulls from Unassigned only** — a model on another tier does NOT appear here; free it first (remove on its tier, or drag on the main screen).
- **Footer** (top hairline, space-between): mono hint *"Drag to the top to set the default · ＋ / × to add and remove · adds come from unassigned only."* + a neutral **Done** button (`--bg-active`, 1pt `--border-default`, primary text — **not** amber).
- **Icon buttons** are 28×28pt, radius 7pt, `--bg-active`, 1pt `--border-subtle`, muted glyph; hover brightens. No yellow fills.
- **Drag** works between the two lists and to reorder within `On <Tier>`; dropping at the top sets the Default.

---

## Interactions & Move semantics

All mutations go through one operation:

```
move(modelID, toTier: Tier?, before: modelID?)
  1. set model.tier = toTier        (nil = Unassigned)
  2. remove model from the array
  3. if `before` given: insert immediately before that model; else append
  4. stable-sort the array by tier order (Flagship, Balanced, Fast, Unassigned)
  5. re-render everything
```

Because the sort is **stable**, inserting directly before the drop-target preserves the intended intra-tier order — so **drag-to-top = set Default**, and there is no separate "Set default" button.

- **Drag computation** (`before`): within the destination list, the target is the first card whose vertical midpoint is below the cursor; if none, append (end).
- **Pick the tier** (segmented control): sets `defaultTier`; re-render the Auto pill **and** the rosters (the **Auto** badge moves to the new tier). ⚠️ Don't forget to refresh the rosters, not just the card.
- **Toggle substitutions**: sets `substitutionsEnabled`. (Affects runtime fallback behavior; the card copy no longer narrates it.)
- **＋ / Add a model**: opens the roster modal for that tier.
- **× / ＋ in modal**: `move(id, toTier: nil)` / `move(id, toTier: modalTier, before: nil)`.
- **Empty tier**: if `models(in: defaultTier)` is empty, the Auto pill shows the amber **"waits"** state. An empty tier is a real, allowed state — *work waits* until the user adds a model or repoints Auto. **Not** an error/alarm.

## State Management
- Single source of truth: the ordered `models` array + `defaultTier` + `substitutionsEnabled`. Everything else (`autoResolved`, counts, per-tier rosters, the Auto badge location) is **derived** — no duplicate "isDefault" flags; the array position IS the default.
- The same available-model set is shared with CLI Setup and every model picker (title bar, worker selects). Tiering here does not change availability there.

## Design Tokens

**Colors (exact hex / alias):**
| Token | Value | Use |
|---|---|---|
| `--bg-void` | `#05060C` | page canvas behind window |
| `--bg-base` | `#090B13` | window background |
| `--bg-surface` | `#111420` | tier columns |
| `--bg-raised` | `#151822` | cards, rows, modal, dropdown |
| `--bg-hover` | `#1A1E2A` | hover |
| `--bg-active` | `#1F2331` | glyph tiles, pills, icon buttons, Done button |
| `--bg-overlay` | `rgba(5,6,12,0.66)` | modal scrim |
| `--ink-600` | `#252A39` | toggle OFF track |
| `--ink-200` | `#AEB5C9` | toggle OFF knob |
| `--border-subtle` | `rgba(255,255,255,0.06)` | hairlines, card borders |
| `--border-default` | `rgba(255,255,255,0.10)` | panel/modal borders, dashed shelf, segmented control border |
| `--text-primary` | `#E1E5F0` | titles, names |
| `--text-secondary` | `#AEB5C9` | pill model name, emphasis |
| `--text-muted` | `#7E869E` | subheads, captions |
| `--text-faint` | `#555C74` | mono slugs/counts/legend, pill tier suffix |
| `--text-disabled` | `#454C62` | grip dots |
| `--text-on-amber` | `#1A1203` | label on amber controls |
| `--accent` (amber-500) | `#FFA630` | active segment, toggle ON, ∞ icon |
| `--accent-text`/`--accent-hover` (amber-400) | `#FFC169` | eyebrow, Default/Auto tags |
| `--accent-surface` | `rgba(255,166,48,0.12)` | ∞ tile, Default/Auto tag fills, drop highlight |
| `--accent-border` | `rgba(255,166,48,0.32)` | those tags' 1pt borders |
| `--green-500` | `#3FD18B` | (ready dots elsewhere) |
| `--amber-400` / `--amber-500` | `#FFC169` / `#FFA630` | empty-tier "waits" text / clock icon |

**Typography** (SF Pro / SF Mono — map to `Font.system`):
| Role | Size / Weight |
|---|---|
| Page title | 27 / 800, tracking −0.02em |
| Eyebrow, section labels | 10.5–11 / 700, uppercase, tracking 0.12em |
| `Auto` | 18 / 800 |
| Tier name | 15 / 800 |
| Model name (cards) | 13.5 / 700 |
| Card/modal body, captions | 12–13 / 400–600 |
| Pills, Default/Auto tags | 9.5–13 |
| Mono (slugs, counts, legend, hint) | 11–11.5 / 500, SF Mono |

**Spacing:** 4pt grid. Card padding 16–22; column header 15/16/12; list gap 8; section gap 26. **Radii:** pills/dots = 999; icon buttons/tiles = 7–8; model cards = 10; row cards = 12; tier columns / Auto card = 14; modal = 18; window = 12. **Shadows:** modal/dropdown `--shadow-xl` `0 32px 64px -12px rgba(0,0,0,0.70)` + 1pt border.

## Assets
- **Source-CLI brand glyphs** (bundle as vector assets — do NOT depend on a CDN; the prototype loads simpleicons at runtime for the mock only): **Anthropic** (render amber `#FFA630`), **X** (Grok), **Google Gemini**, plus geometric marks for **Cursor** (`hexagon.fill`) and **Codex** (terminal `>_` / SF Symbol `chevron.left.forwardslash.chevron.right` — the OpenAI mark is trademark-restricted; source a licensed asset or use the neutral stand-in).
- **UI SF Symbols:** ∞ infinity (custom path in the mock — use a bundled infinity glyph or SF Symbol `infinity`), add `plus`, remove `xmark`, grip (6-dot), clock `clock` (empty-tier), close `xmark`, star `star.fill` (Flagship).

## Files
- `Default & Substitutions — Redesign.html` — the interactive prototype (Auto card + substitutions + tier rosters + roster modal + a synced Models dropdown showing Auto pinned on top).
- `colors.css` — full Allnighter color-token source.

Prefer the app's existing token layer over re-deriving values.
