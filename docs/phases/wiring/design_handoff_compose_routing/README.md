# Handoff: Composer Routing + Team Selector

## Overview
This handoff covers two connected changes to the **Allnighter macOS home workspace** (the conversation/work-order window):

1. **Team selector (top-right).** The old `6 ready` status pill is replaced by an avatar-stack **Team** control that clearly reads as "who's on the bench → manage your team." It opens a dropdown listing bench models with readiness, plus a **Manage team** door into settings.
2. **Composer refactor.** The three coequal mode buttons (Chat / Fan out / Execute) collapse into one **mode pill** with a `⌘1 / ⌘2 / ⌘3` shortcut affordance, and the routing target becomes an adaptive **chip** that carries *who*. Fan out additionally exposes an explicit **Build / Design / Copy** lane choice — the app never infers the lane from prose.

The goal of the redesign: make team assembly intuitive (it was previously only reachable by clicking the `6/6 ready` status badge), and make the composer read as a sentence — **`[verb]` → `[who]`**.

## About the Design Files
The files in this bundle are **design references created in HTML/React (via in-browser Babel)** — a clickable prototype showing the intended look and behavior. They are **not production code to copy directly.**

The macOS app is the target. **Recreate these designs in the app's existing environment** (SwiftUI / AppKit, or whatever the GUI is built in) using its established components, tokens, and patterns. Treat the HTML/JSX as the source of truth for layout, copy, measurements, states, and interaction logic — then rebuild natively.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, radii, copy, and interaction behavior. Recreate the UI faithfully using the codebase's native primitives. Exact token values are listed under **Design Tokens**.

---

## Concept & Vocabulary (read first)
This product turns the AI models a user already pays for into a **team**. The mental model the design enforces:

- **Bench** — the available models (Opus, Sonnet, Grok, Gemini, ChatGPT/Codex, Composer). A *model at rest*.
- **Worker** — a `skill + model` assignment in a run. A *model at work*.
- **Team** — a saved lineup of workers for a lane. Built/edited in **settings**, never in compose.
- **Lane** — the *kind of work*: **Build** (specs/implementation), **Design** (visual mockups), **Copy** (copywriting). A team belongs to exactly one lane.
- **Reasoning effort** — optional provider/model reasoning-depth config. It is not the primary composer control and never changes team lineup.

Design principle enforced by this UI: **Compose is the touchline; settings is the locker room.** In compose you only *select* a pre-built team. You never configure skills or team membership there — that lives in settings behind a `Customize…` link.

---

## Screens / Views

There is one screen affected: **Home — conversation workspace** (1180×760 window). Two regions change.

### 1. Top bar — Team selector
- **Position:** top-right of the window title bar (`height: 44px`), in the right-hand control cluster, before the History and Settings icon buttons.
- **Replaces:** the previous `Badge` reading `6 ready`.
- **Closed state — a pill button:**
  - Layout: `inline-flex`, `gap: 8px`, `height: 28px`, padding `0 9px 0 7px`, `border-radius: 999px (--radius-pill)`, `1px solid --border-default`, background `--bg-raised`. Hover: border `--border-strong`, background `--bg-hover`.
  - Contents, left→right:
    1. **Avatar stack** — first 4 bench model glyphs, each `18×18`, `border-radius: 5px`, `1.5px solid --bg-surface` ring, overlapping with `margin-left: -6px` (first child `0`). Brand glyphs render via Simple Icons (`https://cdn.simpleicons.org/<slug>/<hexcolor>`); non-brand models use a Lucide `terminal`/`square` glyph at 11px in `--text-secondary`.
    2. **Label** "Team" — `12px / 600 / --text-secondary`.
    3. **Ready dot** — `7×7` circle, `--green-500`.
    4. **Chevron** — Lucide `chevron-down` 13px, `--text-faint`.
- **Open state — dropdown panel** (anchored below the pill, right-aligned):
  - Panel: width `306px`, background `--bg-surface`, `1px solid --border-default`, `border-radius: 10px (--radius-lg)`, `box-shadow: --shadow-xl`, opens *downward* (`top: calc(100% + 9px)`).
  - **Header:** title "Your bench" (`12.5px / 700 / --text-primary`) + sub "4 of 6 models ready" (mono, `10.5px`, `--text-faint`).
  - **List:** one non-interactive row per bench model (`padding: 8px 9px`, `gap: 10px`):
    - `27×27` glyph tile (`border-radius: 7px`, bg `--bg-active`), then name (`13px / 600`) + mono sub (`10px / --text-faint`, e.g. `Anthropic · Opus 4.8`), then a trailing **green dot** if ready or a **warning Badge** ("Not signed in" / "Not detected") if not.
  - **Footer:** a secondary **Manage team** button (Lucide `settings-2` icon) + note "Add models & build teams in settings." (`10.5px / --text-faint`). This is the navigation into settings/Bench management.
- **Click-outside:** a full-viewport invisible backdrop (`position: fixed; inset: 0`) closes the dropdown.

### 2. Composer (bottom of the thread pane, and the centered "Start a work order" empty state)
The composer is a rounded box (`--bg-raised`, `1px solid --border-default`, `border-radius: 10px`; focus-within → `--accent-border` + focus ring) containing a textarea above a control **bar**. The bar (left→right):

**a) Mode pill** — single control replacing the old 3-button segmented group.
- `inline-flex`, `gap: 7px`, `height: 31px`, padding `0 11px`, `border-radius: 8px (--radius-md)`, `1px solid --border-default`, background `--bg-subtle`. Hover: `--bg-hover` / `--border-strong`. `white-space: nowrap`.
- Contents: a Lucide icon in `--accent-text` (Chat→`message-square`, Fan out→`layers`, Execute→`hammer`), the verb label (`12.5px / 600 / --text-primary`), and a `chevron-down` (12px, `--text-faint`).
- **Click opens the mode menu** (width `300px`, anchored above, same panel styling as all popovers):
  - Three rows, each: icon (16px, `--accent-text`, top-aligned) + a body with a name row and a description row.
    - Name row: label (`13px / 600`), a `check` icon (13px, `--accent-text`) when active, and a **kbd** tag pushed to the right (`⌘1` / `⌘2` / `⌘3`; mono 10px, `1px solid --border-subtle`, `--bg-subtle`, `border-radius: 5px`, padding `1px 5px`).
    - Description (`11px / --text-muted`):
      - Chat — "One model answers — route the turn to anyone."
      - Fan out — "A team answers in parallel → a board to compare and pick."
      - Execute — "An agent runs it in your repo and the result returns here."
  - Active row background `--bg-active`; hover `--bg-hover`.
  - **Selecting Fan out auto-opens the target chip's popover** (so the user immediately picks a lane/team). Selecting Execute, if the current target isn't a valid executor, resets it to Claude Code.

**b) "to" label** — mono `11px`, `--text-faint`. **Shown only for Chat and Execute** (a fan-out reads `Fan out · [lane] team`, so "to" is omitted).

**c) Target chip** — adaptive routing control carrying *who*.
- `inline-flex`, `gap: 7px`, `height: 31px`, padding `0 10px`, `border-radius: 8px`, `1px solid --border-default`, background `--bg-raised`, **mono** font, `white-space: nowrap`. Hover: `--bg-hover` / `--border-strong`.
- Face:
  - **Chat / Execute:** model glyph + model name + chevron.
  - **Fan out:** lane icon (in `--accent-text`; Build→`hammer`, Design→`image`, Copy→`file-text`) + selected team name + chevron.
- **Click opens the target popover** (anchored above):
  - **Chat** → header "Route to model" / "One model answers this turn". List = all 6 bench models. Not-ready models are `disabled` and show a warning Badge.
  - **Execute** → header "Hand to executor" / "An agent runs it in your repo". List = executor-capable models only (`claude`, `gpt`, `grok`, `composer`).
  - Provider reasoning-effort settings, if supported, belong in advanced model/worker configuration rather than this primary popover.
  - **Fan out** → header "Send to team" / "Pick the lane, then the lineup", followed by:
    - **Lane tabs** — segmented row of **Build / Design / Copy**, each a `height: 31px` button with lane icon + label; active tab `--bg-active` + `--border-default`, icon `--accent-text`. **Switching lane re-selects that lane's default team.**
    - **Team list** — saved teams for the selected lane. Each row: lane-icon tile + name (`13px / 600`); the default team shows a `default` tag (mono 9px, bordered); a mono sub line (e.g. "4 mockups", "3 workers · custom"); a trailing `check` when selected.
    - **Footer** — a ghost **Customize…** button (`settings-2` icon) + note "Build & edit teams in settings." This is the *only* path to team configuration from compose; it navigates to settings, it does not expand inline.
    - No generic Effort row. Different worker counts/depths are different Teams.

**d) Spacer**, then an **Attach image** ghost icon-button (`image-plus`), then the **Send** button (`34×34`, `border-radius: 6px`, background `--accent`, ink `--text-on-amber`, `arrow-right` 16px; hover `--accent-hover` + amber glow). The send button's `aria-label` reflects the armed verb (e.g. "Send — Execute").

**e) Hint line** under the box (`11px / --text-faint`, leading `corner-down-right` icon) showing the active mode's description.

---

## Interactions & Behavior
- **Single open popover at a time.** Mode menu, target popover, and team dropdown are mutually exclusive; opening one closes the others. Each has a full-viewport invisible backdrop that closes it on outside click.
- **Smart default verb (must re-seed on thread switch).** The armed mode is derived from the active thread's state: a thread in **`spec ready`** state arms **Execute**; everything else defaults to **Chat**. This MUST update when the user switches threads — in the prototype this is a `useEffect` keyed on the incoming default, not a one-time mount initializer. The verb is always *visible* (on the mode pill) and overridable in one click/shortcut — never silently fired.
- **Lane is never inferred.** Fan out requires an explicit Build/Design/Copy choice. Default lane = the active thread's lane when it is build/design/copy, otherwise Design.
- **Picking Fan out** auto-opens the target popover so the lane/team choice is immediate.
- **Switching a fan-out lane** auto-selects that lane's default team (so the picker is never in an empty/illegal state).
- **Team selections persist** across thread switches (only the *verb* re-seeds), so an in-progress routing choice isn't lost.
- **Not-ready models** are non-selectable in the routing list and surface why (Not signed in / Not detected).
- Keyboard shortcuts `⌘1 / ⌘2 / ⌘3` (Chat / Fan out / Execute) are surfaced in the menu as affordances — wire them to the real mode toggle in the native app.

## State Management
Per-composer state (one composer instance per thread pane + the empty state):
- `mode`: `'chat' | 'fanout' | 'exec'` — re-seeded from the thread's default on thread change.
- `to`: model id for chat/exec routing (e.g. `'claude'`).
- No generic composer `effort` state. Provider reasoning effort, if supported,
  belongs to advanced model/worker configuration.
- `lane`: `'build' | 'design' | 'copy'` (fan out) — seeded from the thread's lane.
- `team`: selected team id for the current lane (seeded to the lane's default).
- `pop`: which popover is open — `'mode' | 'target' | null`.

Inputs the native implementation needs from the app model:
- **Bench**: list of models with `{ id, displayName, brandSlug/icon, subLabel, ready, notReadyReason }`.
- **Executor capability** per model (which models can run as agents).
- **Teams** grouped by lane, each `{ id, name, summary, isDefault }` (these are the saved presets configured in settings).
- **Active thread** `{ lane, state }` to compute the default verb and default lane.

## Design Tokens (exact values, dark theme)
Colors (semantic → hex):
- `--accent` `#FFA630` · `--accent-hover` `#FFC169` · `--accent-text` `#FFC169` · `--accent-surface` `rgba(255,166,48,.12)` · `--accent-border` `rgba(255,166,48,.32)` · `--text-on-amber` `#1A1203`
- `--bg-base` `#090B13` · `--bg-subtle` `#0D101A` · `--bg-surface` `#111420` · `--bg-raised` `#151822` · `--bg-hover` `#1A1E2A` · `--bg-active` `#1F2331` · `--bg-input` `#13161F`
- `--border-subtle` `rgba(255,255,255,.06)` · `--border-default` `rgba(255,255,255,.10)` · `--border-strong` `rgba(255,255,255,.16)`
- `--text-primary` `#E1E5F0` · `--text-secondary` `#AEB5C9` · `--text-muted` `#7E869E` · `--text-faint` `#555C74`
- `--green-500` `#3FD18B` (ready/healthy) · `--green-400` `#5BDBA0` · `--yellow-500` `#F5C84B` (warning) + `--warning-surface` `rgba(245,200,75,.12)` · `--red-500` `#F76B6B` · `--blue-400` `#7DB2FF`
- Focus ring: `0 0 0 3px rgba(255,166,48,.40)`

Radii: `--radius-xs 4px` (kbd/tags) · `--radius-sm 6px` (send button) · `--radius-md 8px` (pill/chip/menu items) · `--radius-lg 10px` (composer box, popovers) · `--radius-pill 999px` (team control).

Control heights used: pill/chip/lane-tab `31px`, team control `28px`, send `34px`.

Typography: `--font-sans` for UI labels, `--font-mono` for the chip, sub-lines, and kbd tags. Sizes are called out inline per component above (range 9–13px for this dense control area).

Shadows: `--shadow-xl` (popovers/dropdowns), `--shadow-xs` (active segmented button). Amber glow on the send button hover (`--glow-amber-sm`).

Icons: **Lucide** line icons (`message-square`, `layers`, `hammer`, `image`, `file-text`, `settings-2`, `chevron-down`, `check`, `arrow-right`, `image-plus`, `corner-down-right`, `terminal`, `square`). Model brand glyphs: **Simple Icons** via `cdn.simpleicons.org` (`anthropic`, `x`, `googlegemini`) recolored, plus Lucide `terminal`/`square` for CLI/Composer.

## Assets
- Window/app icon: `assets/allnighter-icon.svg` (already in the project).
- Model glyphs are fetched at runtime from Simple Icons (brand) or drawn as Lucide marks; no static image assets are introduced by this change.

## Files
Reference sources included in this bundle (under `reference/`):
- `app.jsx` — prototype reference for the composer, the `TeamControl`, the routing data (`BENCH_ROWS`, `EXEC_IDS`, `FAN_LANES`, `FAN_TEAMS`, `MODE_INFO`), the threads data, and popover markup. Any `EFFORT_OPTS` / `EffortRow` code in the prototype is superseded by the simplified contract above.
- `home.jsx` — base composer/window CSS and the shared worker/lane/status helpers (`WK`, `WGly`, `LANE`, `Stt`). The composer-specific CSS lives in the `home-comp-css` style block inside `app.jsx`.

In the live project these render via `home/index.html`. A self-contained, clickable copy of the prototype is included as `Compose Routing Prototype.html` (open it in any browser to interact with all three popovers).
