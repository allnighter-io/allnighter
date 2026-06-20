# Handoff: CLI Setup & Dropdowns — Redesign (SwiftUI / macOS)

## Overview
Redesign of three related surfaces in Allnighter that all answer questions about **CLIs and the models they expose**:

1. **CLI setup** — the full settings page where you manage CLIs and choose which models are turned on.
2. **CLI health popover** — the title-bar glance ("is anything wrong?"), a mini snapshot of the setup list.
3. **Models dropdown** — the picker, a flat A→Z list of every model you've turned on.

The redesign removes "theater" chrome (a 4-card stat strip, `$0 marginal cost`, a `Code · Design · Copy` lanes box, and the repeated word **"Ready"**), and fixes a correctness bug: **the old dropdowns showed every model a CLI _could_ reach, not the models actually turned on.** The new rule below makes one list the single source of truth for every surface.

> **The core rule:** A model is *available* only when it is toggled **ON** on a CLI that is *ready*. The set of available models is the single source of truth — it drives the Models dropdown, the title-bar pill, and every model picker elsewhere in the app (e.g. team-worker selects). Setup is the one place a model gets turned on; everything else just reads the list.

---

## App Mapping & Review Notes (founder review, 2026-06-20)

We are simplifying **three currently-too-busy surfaces**. Here is exactly which app
component each one is, so the implementer doesn't have to guess:

| Founder's name | This doc's screen | App component (today) | What it shows today |
|---|---|---|---|
| **1. CLI Setup** | Screen 1 — CLI Setup | `TeamReadinessView` (embedded in Settings → CLIs via `TeamStudioView`), and first-run `SetupViews` | the readiness page |
| **2. The CLI dropdown** | Screen 2 — CLI Health Popover | title-bar `BenchHealthBadge` → its popover (the "● 5 ready" pill) | the CLI glance |
| **3. The Team dropdown** | Screen 3 — Models Dropdown | title-bar `TeamControlView` → `BenchDropdownPanel` (the "Team ●" pill, header "Your bench") | the model picker |

**Naming cutover (do this):** the title-bar "Team ●" dropdown becomes the **Models**
dropdown — drop the word "Team" from the pill and **"Your bench"** from the header (the
rest of the app says *models*). The pill reads the same readiness number as the badge.

**The real fix is the data, not the chrome.** Today the bench/dropdowns read
`AppModel.composeBench` / `benchDropdownRows` (enabled models) and a separate per-tool
readiness. Replace that with the **single derived `availableModels`** in the core rule
above (ON ∧ owning-CLI-ready, flattened A→Z). The title-bar number, the CLI-dropdown
summary, the Models dropdown, **and** the composer worker picker all read that one set.
One toggle in Setup updates everything. (This is the correctness bug the doc names.)

**Restraint / amber pass (align with the rest of the app).** We have been pulling amber
back so "color earns its place." Apply the same here — amber is allowed ONLY for:
the **one** primary CTA per surface (`Add CLI`), the **toggle ON** state, and the
**needs-attention** dot/copy. Everywhere else go neutral/muted:
- Drop the amber from the **`SETUP` eyebrow** (use `--text-faint`, or cut the eyebrow
  entirely — the 27pt title already says it).
- **`Add model`** and **`Re-check all`** are secondary/ghost, **not** amber.
- Status uses dots + position, not repeated "Ready" words (the doc already does this).
- The Ready/Dormant/Needs-attention **dots** keep their hues (green/grey/amber) — those
  are meaningful state, not decoration.

**Hard constraints (must hold):**
- **No API keys / BYOK, ever.** Setup, the detail panel, and every login/fix affordance
  use the CLI's own sign-in (`claude` `/login`, `codex` sign-in, `grok login`, etc.).
  Nothing may suggest pasting an API key. The redesign must not introduce one.
- **Dormant is not an error** (the doc is right) — render it quietly, never nag.
- **HTML is a reference only.** Recreate natively in SwiftUI with the existing tokens
  and components above; do not render or embed the HTML at runtime.

**Per-surface "cut more" checklist:**
- **CLI dropdown (health popover):** report-only is correct. Its footer is a single
  `Open CLI setup` row — no second button, no "Add models" caption.
- **Team → Models dropdown:** today's footer has *two* buttons (`Open CLI setup` +
  `Manage team`) plus a caption — collapse to **one** (`Manage in settings`) + the
  one-line caption, exactly as Screen 3 specifies.
- **CLI Setup:** the 4-card stat strip, the `Code · Design · Copy` lanes box, the
  `$0 marginal cost` line, and the per-CLI proof block (`smoke: passed`) are all gone —
  a single mono summary line replaces the cards.

## About the Design Files
The file in this bundle (`CLI Setup — Redesign.html`) is a **design reference created in HTML/CSS/JS** — a prototype that shows the intended look and interactive behavior. It is **not** production code to copy. The task is to **recreate these designs natively in the SwiftUI macOS app** using its existing components, view models, and the Allnighter design tokens (which already map to SF Pro / SF Mono and the color ramp below). The HTML is a faithful spec for layout, color, type, spacing, and interaction — translate it into idiomatic SwiftUI.

The prototype is **interactive**: open it in a browser, toggle a model on/off in the right panel of the setup page, and watch the CLI flip Ready⇄Dormant and the Models dropdown re-sort live. Use that to understand state behavior.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, radii, and interaction model. Recreate pixel-faithfully using the app's existing design-token layer. All hex values, type sizes, and spacing are exact and listed under **Design Tokens**.

---

## Data Model

One `CLI`, each exposing `Model`s. A CLI's status is **derived**, not stored:

```swift
enum CLIStatus { case ready, dormant, needsAttention }

struct Model: Identifiable {
    let id: String          // e.g. "gemini-3.5-flash" (shown as a mono sub-label)
    let name: String        // e.g. "Gemini 3.5 Flash"
    var isOn: Bool          // user toggled it onto the available set
}

struct CLI: Identifiable {
    let id: String
    let name: String        // "Antigravity", "Claude Code", "Codex", "Cursor Agent", "Grok Build CLI"
    let slug: String         // "antigravity", "claude-code", "codex", "cursor", "grok" — mono sub-label
    let route: String        // "1.0.10 · via antigravity" — version + route, mono
    let glyph: Glyph         // brand asset or SF Symbol (see Assets)
    var isInstalledAndSignedIn: Bool
    var failureReason: String?   // non-nil ⇒ needsAttention; e.g. "Installed but signed out — sign in to use its models."
    var models: [Model]
}

extension CLI {
    var onModels: [Model] { models.filter(\.isOn) }
    var status: CLIStatus {
        if failureReason != nil { return .needsAttention }
        return onModels.isEmpty ? .dormant : .ready
    }
}
```

**Derived collections:**
- `availableModels` = every `model` where `model.isOn` and `cli.status == .ready`, **flattened across all CLIs, sorted A→Z by `name`**. This is what the Models dropdown and title-bar render.
- Counts: `readyCount`, `attentionCount`, `dormantCount`, `modelsOnCount = availableModels.count`.

**Status semantics (important):**
- **Ready** (green) — installed, signed in, ≥1 model on.
- **Dormant** (grey) — installed but 0 models on, OR no active subscription. **This is NOT an error.** A user may simply not want a given CLI active right now. Render it quietly at the bottom; never nag.
- **Needs attention** (amber) — genuinely broken (not installed / signed out / failing probe). The **only** state that gets explanatory copy and a **Fix** affordance.

---

## Screens / Views

### 1. CLI Setup (full settings page)

**Purpose:** Manage CLIs and choose which models are available across the app.

**Layout:** A window/settings surface, content max-width ~1100pt. Vertical stack:
- **Header row** (padding 26/30/18/30 — top/right/bottom/left):
  - Left: eyebrow `SETUP` (amber, uppercase, 11pt, weight 700, tracking 0.12em) → title **`CLI setup`** (27pt, weight 800, tracking −0.02em, primary text) → subhead (13pt, muted, max-width ~560pt, line-height 1.55): *"Choose which models are available across Allnighter. A **CLI** is just how a model gets here — turn a model on and it shows up everywhere you pick one."* (the two bold words are `--text-secondary`).
  - Right: **Re-check all** (secondary button, leading SF Symbol `arrow.clockwise`) + **Add CLI** (primary amber button, leading `plus`).
- **Summary line** (replaces the old 4 stat cards): a single mono line, 12.5pt, muted — `● 5 CLIs · 7 models available`. Leading green dot (7×7pt, `--green-500`, 3pt green glow ring). Numbers in `--text-secondary` weight 600. Bottom hairline divider (`--border-subtle`).
- **Two-column body** (`grid 1fr / 372pt`, gap 26pt, padding 22/30/36/30, top-aligned):
  - **Left — CLI list** (vertical stack, gap 7pt). Grouped sections in this order, each with a group label (10.5pt, weight 700, uppercase, tracking 0.12em, `--text-faint`, a mono count, then a hairline that fills remaining width):
    1. **NEEDS ATTENTION** (only if any)
    2. **READY**
    3. **DORMANT** (only if any)
  - **Right — detail panel** (sticky, top 14pt). Inspector for the selected CLI.

**CLI row** (the shared component — reused verbatim in the snapshot popover):
- Container: `--bg-raised` fill, 1pt `--border-subtle` border, radius 10pt (`--radius-lg`), padding 13/15pt, `HStack` gap 14pt, vertically centered.
- **Glyph tile**: 40×40pt, radius 10pt, `--bg-active` fill, brand/SF-Symbol mark centered at ~22pt.
- **Main** (fills): CLI name (14.5pt, weight 700, primary). Below it (margin-top ~8pt), one of:
  - Ready → **on-model chips**: `HStack` wrap, gap 6pt. Each chip: 12pt secondary text, `--bg-active` fill, 1pt `--border-subtle`, radius 999pt (pill), padding 3/10pt. **Only ON models appear as chips.**
  - Dormant → mono caption `No models on — dormant` (11.5pt, `--text-faint`).
  - Needs attention → the `failureReason` text (12pt, `--text-muted`).
- **Trailing**: status dot (see Tokens → Status dots).
- **Selected state** (left list only): replace border with a focus ring — `0 0 0 1pt --accent-border, 0 0 0 4pt --accent-surface` (an amber 1pt ring with a soft amber halo). In SwiftUI: `.overlay(RoundedRectangle(cornerRadius:10).stroke(accentBorder)).background(...accentSurface ring)` or an `.overlay` ring + outer glow.
- **Hover**: border brightens to `--border-default`.
- **Dormant variant**: transparent fill (no card), name dims to `--text-muted`, glyph opacity 0.55.

**Detail panel** (right, selected CLI):
- Container: `--bg-raised`, 1pt `--border-default`, radius 14pt (`--radius-xl`), clipped.
- **Header** (padding 16/16/14, bottom hairline): glyph tile (40pt) · id block (name 15pt/700; below it `route` in mono 11.5pt `--text-faint`) · trailing status dot.
- **Body** (padding 14/16/16):
  - Column header row: `MODELS ON THIS CLI` (left) / `ON` (right) — both 10pt, weight 700, uppercase, tracking 0.10em, `--text-faint`.
  - **Model rows** (one per model on this CLI, divided by hairlines): name (13.5pt, weight 600; dims to `--text-muted` when off) + mono id below (11pt `--text-faint`) on the left; a **toggle** on the right.
    - Toggle: 38×22pt track, knob 16pt. **On** = `--accent` (amber) track, white knob, knob translated +16pt. **Off** = `--ink-600` track, `--ink-200` knob. In SwiftUI use `Toggle(...).labelsHidden().tint(Color("accent"))`.
  - **Add model**: amber text button (13pt, weight 600, `--accent-text`), leading `plus`, margin-top 14pt.
  - **Footer** (mono 11.5pt, margin-top 16pt): for ready → `● N models on · available everywhere you pick a model.` (green dot). For dormant → grey dot + "Dormant — no models on. That's fine; turn one on to use this CLI." For attention → amber dot + the `failureReason`.

> Drop the old proof block ("This CLI is ready." / `smoke: passed`). Only show a status line when the state is **not** green.

---

### 2. CLI Health Popover (title-bar glance)

**Purpose:** A quick "is anything wrong?" glance from the title bar. It is a **mini snapshot of the setup list** — the same grouped rows, narrower, with no detail panel.

**Trigger:** the title-bar CLI pill / shield. Present as an `NSPopover`-style panel.

**Layout** (width ~470pt):
- Container: `--bg-surface` fill, 1pt `--border-default`, radius 16pt, `--shadow-xl`. (Note: body uses `--bg-surface` so the `--bg-raised` rows inside read with contrast.)
- **Header** (padding 15/18/0): shield SF Symbol (`checkmark.shield` or `shield`, amber, 18pt) · title **`CLIs`** (15pt/700) · trailing close `xmark` (16pt, `--text-faint`).
- **Summary** (padding 6/18/12, mono 12pt, bottom hairline): when healthy → `N CLIs ready · M models on`. When something's broken → `⟨N needs attention⟩ · R ready · M models on`, where the attention clause is amber (`--amber-400`, weight 600). Numbers in `--text-secondary`.
- **List** (padding 12/14/8, vertical gap 7pt, max-height ~460pt then scroll): the **same grouped CLI rows** as the setup left column (Needs attention → Ready → Dormant), but **non-interactive** (cursor default, no selection ring, hover does not brighten). Same glyphs, same on-chips, same dots.
- **Footer** (centered, 13pt/600 `--text-secondary`, top hairline, padding 13pt): SF Symbol `arrow.up.left.and.arrow.down.right` + **`Open CLI setup`**. Hover → `--bg-hover`. Opens screen 1.

> The **Fix** action does NOT live here — the popover only reports. Tapping a broken row (or "Open CLI setup") takes the user to the full page to fix it.

---

### 3. Models Dropdown (the picker)

**Purpose:** Pick a model. A flat, alphabetical list of **only the models that are on**.

**Layout** (width ~440pt):
- Container: `--bg-raised`, 1pt `--border-default`, radius 16pt, `--shadow-xl`.
- **Header** (padding 18/20/14, bottom hairline): title **`Models`** (16pt/700, primary) + count `7 available · 5 CLIs` (mono 12.5pt, `--text-faint`). **Kill the old "Your bench" wording** — the rest of the app calls these "models", so this does too.
- **List** (padding 6/0): one row per available model, **sorted A→Z by model name**:
  - Row (padding 11/20, `HStack` gap 14pt, hover `--bg-hover`):
    - **CLI glyph** tile 36×36pt, radius 9pt, `--bg-active` (the model's *source CLI* icon — matches the team dropdown convention).
    - Main: model name (14.5pt/700) + CLI **slug** sub-label below (mono 12pt, `--text-faint`).
    - Trailing: green status dot.
- **Footer** (top hairline, padding 13/16): **Manage in settings** (secondary button, leading `slider.horizontal.3`) + caption "Only models you've turned on appear here." (12pt `--text-faint`).

> No capability chips. Dormant and broken CLIs **never** appear here. This list = `availableModels` (defined above), identical to what the title bar shows.

---

## Interactions & Behavior
- **Toggle a model** (setup detail panel): flips `model.isOn`. Recompute the owning CLI's derived `status` (a CLI moves Dormant⇄Ready as its on-count crosses zero; an attention CLI stays attention). Re-render: left list grouping, detail-panel footer, **and the Models dropdown / title bar** (they read the same derived set). Transition the toggle knob over ~160ms ease.
- **Select a CLI** (left list): focuses the detail panel; selected row gets the amber focus ring. Single selection.
- **Re-check all / Re-scan**: re-probes every CLI (async). Out of scope for visuals here — wire to existing probe.
- **Add CLI / Add model**: open existing add flows.
- **Health popover rows**: non-interactive display; the whole popover's job is the glance. Footer → open setup.
- **Focus ring / hover** timing: 150ms ease-out on border/shadow.

## State Management
- Source of truth: `[CLI]` with per-`Model` `isOn` and per-CLI install/sign-in/probe state. Everything else is **derived** (`status`, `availableModels`, all counts) — do not store duplicate "ready" flags. This is what fixes the original bug.
- Setup page: `selectedCLIID` (which CLI the detail panel shows).
- The title-bar pill, health popover, Models dropdown, and team-worker model pickers all read `availableModels` / counts from the same store. One write (a toggle) updates all of them.

## Design Tokens

**Colors (exact hex):**
| Token | Hex | Use |
|---|---|---|
| `--bg-void` | `#05060C` | behind the window / page canvas |
| `--bg-base` | `#090B13` | app/window background |
| `--bg-surface` | `#111420` | panels, toolbars, **health popover body** |
| `--bg-raised` | `#151822` | cards, rows, **Models dropdown**, detail panel |
| `--bg-hover` | `#1A1E2A` | row/control hover |
| `--bg-active` | `#1F2331` | glyph tiles, chips |
| `--ink-600` | `#252A39` | toggle OFF track |
| `--ink-450` | `#454C62` | dormant (grey) status dot |
| `--ink-200` | `#AEB5C9` | toggle OFF knob; secondary text |
| `--border-subtle` | `rgba(255,255,255,0.06)` | hairlines, card borders |
| `--border-default` | `rgba(255,255,255,0.10)` | panel/popover borders, hover border |
| `--text-primary` | `#E1E5F0` | titles, names |
| `--text-secondary` | `#AEB5C9` | emphasized inline / counts |
| `--text-muted` | `#7E869E` | subheads, off model names |
| `--text-faint` | `#555C74` | mono slugs, captions, group labels |
| `--text-on-amber` | `#1A1203` | label on amber primary button |
| `--accent` (amber-500) | `#FFA630` | primary button, toggle ON, focus ring source |
| `--accent-hover` (amber-400) | `#FFC169` | primary hover; amber-as-text |
| `--accent-text` (amber-400) | `#FFC169` | eyebrow, "Add model", amber copy |
| `--accent-surface` | `rgba(255,166,48,0.12)` | focus-ring halo |
| `--accent-border` | `rgba(255,166,48,0.32)` | focus-ring 1pt line |
| `--green-500` | `#3FD18B` | Ready status dot |
| `--green-400` | `#5BDBA0` | green-as-text |
| `--amber-500` | `#FFA630` | Needs-attention dot |

**Status dots:** 9×9pt circle. Ready = `--green-500` with `0 0 0 3pt rgba(63,209,139,0.15)` halo. Dormant = `--ink-450`, no halo. Needs attention = `--amber-500` with `0 0 0 3pt rgba(255,166,48,0.18)` halo. (Dropdown rows use the same green dot at this size; popover/setup share it.)

**Typography** (native SF Pro / SF Mono — these map directly to SwiftUI `Font`):
| Role | Size / Weight | Notes |
|---|---|---|
| Page title (`CLI setup`) | 27pt / 800, tracking −0.02em | `.font(.system(size:27, weight:.heavy))` |
| Eyebrow (`SETUP`) | 11pt / 700, uppercase, tracking 0.12em | amber |
| Subhead | 13pt / 400, line-height 1.55 | muted |
| Popover/dropdown title | 15–16pt / 700 | |
| CLI name | 14.5pt / 700 | |
| Model name (rows) | 13.5–14.5pt / 600–700 | |
| Chip | 12pt / 400 | |
| Group label | 10.5pt / 700, uppercase, tracking 0.12em | faint |
| Mono (slugs, ids, route, counts) | 11–12.5pt / 500 | SF Mono |
| Caption | 11–12pt / 400 | faint |

**Spacing:** 4pt base grid. Key values used: row padding 13/15, panel padding 14–16, section gaps 7, chip gaps 6, header padding 15–26. **Radii:** chips/dots = pill (999), buttons = 6–8 (`--radius-sm/md`), glyph tiles = 9–10, cards = 10 (`--radius-lg`), detail panel = 14 (`--radius-xl`), popovers/dropdowns = 16, window = 12.

**Shadows:** popovers/dropdowns use `--shadow-xl` = `0 32px 64px -12px rgba(0,0,0,0.70)` plus the 1pt border. Status-dot halos as above.

## Assets
- **Brand glyphs** — ship as vector assets (PDF/SVG) in the asset catalog; these are real product logos, not SF Symbols: **Anthropic** (Claude Code, render in amber `#FFA630`), **OpenAI**-style mark (Codex — see note), **X** (Grok), **Google Gemini** (Antigravity / Gemini CLI), **Ollama**. The prototype loaded these from simpleicons at runtime for the mock only — **do not** depend on a CDN; bundle the marks.
  - **Codex/OpenAI note:** the OpenAI brand mark is no longer freely distributed via simpleicons (trademark). The prototype substitutes a simple terminal-prompt glyph (`>_`). For the app, use the appropriate licensed OpenAI/Codex mark, or an SF Symbol `terminal` / `chevron.left.forwardslash.chevron.right` as a neutral stand-in.
- **Geometric marks (SF Symbols ok):** Antigravity = `sparkle`/`sparkles`; Cursor Agent = `hexagon.fill`. Both tinted `--text-secondary`.
- **UI SF Symbols:** Re-check `arrow.clockwise` · Add `plus` · Shield `checkmark.shield`/`shield` · Close `xmark` · Open setup `arrow.up.left.and.arrow.down.right` · Manage `slider.horizontal.3`.

## Files
- `CLI Setup — Redesign.html` — the interactive prototype (all three surfaces laid out side-by-side as labeled frames). Open in a browser; toggle models to see live state propagation.
- `colors.css` — the full Allnighter color-token source (the table above is derived from it; included for exact values and the semantic aliases).

The app already has Allnighter design tokens for SF Pro / SF Mono and this color ramp — prefer those over re-deriving values.
