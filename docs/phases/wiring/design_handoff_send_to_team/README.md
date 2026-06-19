# Handoff: Send to Team — Launcher + Composer Picker

## Overview
This package covers two connected surfaces of Allnighter's **Send to team** feature — the
product's core differentiator (your own paid AI models show up as a coordinated *team*,
run in parallel, and return one synthesized answer).

1. **Teams launcher** (`designs/send-to-team-launcher.html`) — the "showroom." A full-pane
   view that shows the user's whole roster of teams. New users land here; it communicates the
   raw power of the product. Reached via the `Teams` toggle.
2. **Composer + team picker** (`designs/composer-picker.html`) — the in-flow view. A normal
   chat thread whose composer can route a turn to **Chat / Send to team / Execute**. In
   *Send to team* mode, a popover picker lets the user choose a team fast (Recent / Favorites /
   Search). Reached via the `Inbox` toggle.

The two are **two faces of one workspace**, joined by a persistent `Inbox | Teams` segmented
toggle in the top bar (⌘1 / ⌘2). Selecting a team in the launcher drops the user into the
composer with that team loaded; a finished team run returns to the **Inbox** as an unread item.

> **Not in this package (intentionally):** the "factory floor" / results view (the synthesized
> Insight + parallel-run visualization). That surface is still being refined and will be handed
> off separately. Do not implement it from memory.

## About the Design Files
The files in `designs/` are **design references created in HTML/CSS/vanilla JS** — prototypes
showing intended look and behavior, **not production code to copy directly**. The task is to
**recreate these designs in the target codebase's existing environment** (React/Vue/SwiftUI/
native, etc.) using its established components, state patterns, and icon system. If no
environment exists yet, choose the most appropriate framework for the project and implement
there.

Icons in the prototype use [Lucide](https://lucide.dev) (loaded from a CDN). Map each
`data-lucide="…"` name to the equivalent in the codebase's icon set. Model "logos" (Grok,
Claude, OpenAI, Gemini) are **monochrome placeholder SVGs** defined inline in the prototype —
replace them with the real brand favicons/marks, kept monochrome and muted per the design.

### Previewing the prototypes locally
Both HTML files link the design system at `../styles.css` and brand SVGs at `../assets/…`.
In this bundle those live at `tokens/` and `assets/`. To preview a file as-is, either serve it
from the original project (where `../styles.css` resolves) or update the two `<link>`/`<img>`
paths to point at this bundle's `tokens/` and `assets/`. The token files needed are included in
`tokens/`.

## Fidelity
**High-fidelity (hifi).** Final colors, typography, spacing, radii, shadows, and interaction
states are all specified via the Allnighter design tokens (see `tokens/`). Recreate the UI
pixel-faithfully using the codebase's libraries, pulling exact values from the tokens rather
than hardcoding hex where a token exists.

---

## Global shell (both screens)

- **Window**: max 1360 × 884 px, `border-radius: 14px`, `background: var(--bg-base)`,
  `1px solid var(--border-default)`, `box-shadow: var(--shadow-xl)`. In-app this is the main
  workspace region, not a literal window — the rounded card + traffic-lights are prototype
  chrome for a macOS app.
- **Top bar** (`.topbar`, height 52px, `background: var(--bg-subtle)`, bottom hairline
  `var(--border-subtle)`): traffic lights → Allnighter glyph → **mode switch** → spacer →
  project slug (`Allnighter / main`, mono, `--text-faint`) → user avatar chip.
- **Mode switch** (`.modeswitch`): segmented control, `background: var(--bg-surface)`,
  `1px solid var(--border-subtle)`, `border-radius: 10px`, 3px padding. Two buttons:
  - `Inbox` — icon `inbox`, shows an unread count badge (`--accent-surface` bg, `--accent-text`),
    shortcut `⌘1`.
  - `Teams` — icon `users-round`, shortcut `⌘2`.
  - Active button: `background: var(--bg-active)`, text `var(--ink-50)`,
    `box-shadow: inset 0 0 0 1px var(--border-subtle)`.
  - Inactive: text `var(--text-muted)`; hover → `var(--text-secondary)`.
- **Default landing**: new users → `Teams`; returning users → `Inbox` (remember last mode).

---

## Screen 1 — Teams launcher (`send-to-team-launcher.html`)

### Purpose
Browse and pick a team from the user's roster. Communicates product value to new users.

### Layout
Single column under the top bar. `.main` is a 4-row grid: **header → lens bar → scrolling
content → bottom action bar**.

- **Header** (`.head`, padding 20/28/16, faint amber radial wash top-left):
  - Eyebrow (mono caps, `--accent-text`): `TEAMS · YOUR ROSTER`.
  - Title row: `Send to team` (`--ink-50`, 23px/700) + subtitle "Pick the crew. **Your prompt
    comes next.**"
  - **Command/search bar** (`.cmd`, height 46, `--bg-input`, radius 11): search icon
    (`--accent-text`), input ("Search teams, outcomes, or starter prompts…"), `⌘K` kbd hint.
    Focus → `border-color: var(--accent-border); box-shadow: var(--focus-ring)`.
  - **Under bar**: left, a paste hint ("Paste a link and *Signal* teams jump to the top —
    nothing else waits on a model."); right, the **bench strip** — "BENCH" label + model dots
    (green = ready w/ `--glow-green`; yellow = down, e.g. "Gemini · auth") + "4 ready".
- **Lens bar** (`.lensbar`): a segmented control with three lenses — **Recent & favorites**
  (default, icon `history`), **Curated** (`sparkles`), **Browse all** (`layout-grid`); right
  side shows a live count.
- **Content** (`.content`, scrolls): one `.panel` per lens (only one visible).
- **Action bar** (`.actionbar`, bottom, `--bg-subtle`, top hairline): selected-team summary +
  starter chips + primary **Continue to prompt →** button (this is the hand-off into Screen 2).

### Lens: Recent & favorites (default)
- **Recent** section (`seclab` "RECENT" + hint "⌘1–3 to send · last team is ready"): a
  **3-column grid** of tiles. First tile is pre-selected.
- **Favorites** section: a **4-column grid** of tiles.

### Lens: Curated
- A 3-column grid of ~6 opinionated starter teams (no recency, leads with the promise line).

### Lens: Browse all
- **Family filter chips**: `All (18)` · `Signal` · `Code` · `Design` · `Copy`. Active chip:
  `--accent-surface` bg, `--accent-border`, `--ink-50` text. Clicking filters the rows.
- **Rows list** (`.rows`): dense rows, each = family tag · name · outcome · lineup logos ·
  last-run. Mutating teams show an `Execute` lock gate (`--accent-text`).

### Team tile (`.tile`) — the key component
```
┌─────────────────────────────────────┐
│ [family tag]              [⌘n / star]│   top row
│ Team Name                            │   15px / 700 / --ink-50, with muted fav logo before it
│ ↳ returns <Outcome>                  │   12px / --text-muted, arrow --accent-text, <Outcome> bold --text-secondary
│                                      │   (spring / flex gap)
│ [logo][logo]  N workers              │   lineup: deduped model logos + worker count
├──────────────────────────────────────│   hairline
│ ⏱ ran 2h ago        [hover: edit] ★ │   footer: last-run + hover edit + favorite star
└─────────────────────────────────────┘
```
- Card: `min-height 138px`, `border-radius 12px`, `border 1px solid var(--border-subtle)`,
  `background: linear-gradient(180deg, rgba(255,255,255,.015), transparent), var(--bg-raised)`,
  `box-shadow: var(--edge-top)`.
- Hover: `border-color: var(--border-strong)`, `background: var(--bg-hover)`.
- **Selected** (`.sel`): `border-color: var(--accent-border)`, amber-tinted gradient bg,
  `box-shadow: var(--edge-top), var(--glow-amber-sm)`.
- **Family tag** (`.fam`): pill, `--text-muted`, mono 10.5px, with a family icon
  (Signal=`radio-tower`, Code=`hammer`, Design=`image`, Copy=`file-text`).
- **Favicon before the name** (`.fav`): the lineup's lead model logo, **muted**
  (`color: var(--text-faint)`), 15px — deliberately NOT amber/colorful.
- **Outcome line** (`.tout`): what the team returns — this is the most important payoff signal;
  keep it prominent, not in the footer.
- **Lineup** (`.lineup`): one monochrome chip per **distinct** model vendor (dedupe — a team
  that runs Grok twice shows one Grok logo), `+ N workers` count. Chip = 23×23, radius 7,
  `--bg-surface`, `1px solid --border-default`; logo 14px, `color: var(--text-muted)`.
- **Edit affordance** (`.edit`): a hover-revealed control (opacity 0 → 1 on tile hover) that
  opens the existing **Customize team** drawer. **Must be a `<span role="button">`, NOT a
  `<button>`** — it lives inside the tile button and nested buttons are invalid HTML (this
  caused a real layout collapse in development). 26×26, radius 7. **Not wired in the prototype.**
- **Favorite star** (`.star`): `--accent` when on, `--text-disabled` when off; toggles, stops
  propagation so it doesn't select the card.

### Browse row (`.row`)
Grid `120px 1fr auto auto`: family tag · name (with lead favicon) · outcome · meta (optional
`Execute` gate + lineup logos + last-run). Selected row: amber left-edge
`box-shadow: inset 2px 0 0 var(--accent)` + faint gradient.

---

## Screen 2 — Composer + team picker (`composer-picker.html`)

### Purpose
Compose a request inside a thread and route the turn to a single team, fast.

### Layout
`.body` is a **2-column grid: `288px` Inbox rail + `1fr` thread**.

#### Inbox rail (`.inbox`, `--bg-subtle`, right hairline)
- **+ New chat** button (`.newchat`): full width, 38px, `background: var(--ink-50)`, text
  `var(--bg-void)`, 700. Icon `plus`. (Replaces the old "New work order" label.)
- **Search conversations** field.
- **Filter tabs**: `All` (active) · `Design` · `Code` · `Running`.
- **List** (`.ilist`): grouped **UNREAD** then **RECENT** (mono caps group labels).
  - **Conversation row** (`.conv`): grid `30px 1fr auto` — icon chip · title + meta · unread dot.
    - Icon chip: model logo (for chats) or family icon (for team runs).
    - Title `--ink-50`/600; **unread** rows → `#fff`.
    - Meta (`--text-faint`, mono): a green `rdot` + "team replied · 14m ago" / "replied · 1d ago"
      / "ran · 1d ago".
    - **Unread dot** (`.udot`): 8px, `--accent`, `--glow-amber-sm`.
    - Selected row (`.on`): `--bg-active` + inset hairline.
  - **Auto-titles**: title team runs by team/prompt (e.g. "Post-to-Project Signal · X thread",
    "Bug Hunt · login race condition"), chats by their content. Do **not** use the literal string
    "New work order" anywhere.
  - **Unread model is unified**: a finished team run marks its thread unread (amber dot) exactly
    like a model chat reply. This consistency is what makes "Inbox" honest.

#### Thread (`.thread`, 3-row grid: header · stream · composer)
- **Thread header** (`.thd`): title ("New chat") + branch tag (`git-branch`, "Allnighter / main")
  + spacer + history & more icon-buttons.
- **Stream** (`.stream`, scrolls): message rows (`.msg`, grid `30px 1fr`, max-width 760).
  - **User message** (`.me`): avatar = initials chip; name "You" + mono timestamp; body
    `--text-secondary`.
  - **Model message**: avatar = model logo chip; name e.g. "ChatGPT 5.5" + mono "routed · Chat";
    body with bolded prompt to escalate.
  - **PM hint** (`.pm-hint`): centered dashed-amber-border callout (`sparkles` icon) nudging the
    user to switch the turn to Send to team. Use sparingly — it's a soft suggestion, never a gate.

#### Composer (`.composer`, relative — popovers anchor here)
- **Composer box** (`.cwrap`, radius 14, `--bg-raised`, `--edge-top`):
  - Placeholder text row ("Reply, or start a new request…").
  - **Tools row** (`.ctools`):
    - **Mode pill** (`.pillbtn#modebtn`): leading icon `users-round` (`--accent-text`) +
      "Send to team" + chevron. Opens the **mode popover**.
    - **Team pill** (`.pillbtn.team#teambtn`): muted lead model favicon + team name (700) +
      lineup logo chips + chevron. Opens the **team picker popover**.
    - Spacer, then **attach** + **image** icon-buttons, then the **send** button (`.send`,
      40×40, radius 11, `background: var(--accent)`, ink `--text-on-amber`,
      `box-shadow: var(--glow-amber-sm)`; hover → `--accent-hover` + `--glow-amber`).
  - **Helper line** (`.chelp`, mono `--text-faint`): "A team answers in parallel → one
    synthesized answer lands in your Inbox."

### Mode popover (`.modepop`) — anchored to the mode pill
Width 392, `background: var(--bg-raised)`, radius 14, `box-shadow: var(--shadow-xl)`, a rotated
`.tail` diamond pointing down. Three options, each grid `34px 1fr auto`:
- **Chat** — icon `message-square`, "One model answers — route the turn to anyone." `⌘1`.
- **Send to team** — icon `users-round`, "A team runs in parallel → one synthesized answer." `⌘2`.
  Selected: `--bg-active` + amber check.
- **Execute** — icon `hammer`, "An agent runs it in your repo and the result returns here." `⌘3`.
- Option hover → `--bg-hover`. Icon tile `--accent-text`.

### Team picker popover (`.teampop`) — THE key new component
Anchored to the team pill. Width 464, max-height 560, column flex:
`background: var(--bg-raised)`, radius 14, `box-shadow: var(--shadow-xl)`, down-pointing `.tail`.

> **Critical:** the popover background MUST be solid (`var(--bg-raised)`). It overlaps the
> message stream; a translucent background let thread text bleed through (a real bug found in
> review). Do not use a semi-transparent scrim/`backdrop-filter` for this surface.

Structure:
- **Header** (`.tphd`): title "Send to which team?", subtitle "Your teams — type to filter, or
  browse all.", then a **search field** (`.tpsearch`, autofocus, 40px, `--bg-input`; focus →
  `--accent-border` + `--focus-ring`; `esc` kbd hint).
- **Body** (`.tpbody`, scrolls): grouped rows.
  - **Group labels** (`.tpgrp`): mono caps with icon — **RECENT** (`history`), **FAVORITES**
    (`star`) — each with a trailing hairline.
  - **Team row** (`.tprow`, grid `30px 1fr auto`):
    - Icon chip (family icon).
    - Name (`--ink-50`/600) + optional `⌘n` kbd; outcome line below
      (`↳ returns <Outcome>`, arrow `--accent-text`, outcome bold `--text-secondary`).
    - Right cluster: optional **Execute gate** (`lock` + "Execute", `--accent-text`) for mutating
      teams · **lineup** logo chips (20×20) · **favorite star** (`--accent`).
    - Hover → `--bg-hover`. **Selected** (`.sel`): amber left-edge
      `box-shadow: inset 2px 0 0 var(--accent)` + faint gradient.
  - **Signal teams appear as ordinary rows mixed into Recent/Favorites** — they are NOT a
    separate lane/tab here. The picker is organized by the user's behavior (recency, favorites,
    search), not by department. (Department lanes — Code/Design/Copy — and Signal-as-component
    live only in the separate "Manage Teams" surface, not in this picker.)
- **Footer** (`.tpfoot`): two buttons — **Browse all 18 teams** (`layout-grid`, opens the full
  launcher/library) and **Customize…** (`sliders-horizontal`, opens the Customize-team drawer).

> **Deliberately omitted:** there is **no Effort (Low/Med/High) control** in the picker. Team
> size / effort is part of a team's definition (edited in Customize), not a per-send user dial.
> Do not add one to the send path.

---

## Interactions & Behavior
- **Mode toggle (`Inbox | Teams`)**: swaps the whole main pane. ⌘1 / ⌘2. Preserve composer draft
  across swaps. Selecting a team in the launcher → switch to Inbox/composer with that team loaded
  (the launcher's "Continue to prompt →" *is* the swap-back; the launcher is never a dead end).
- **Lens switch (launcher)**: shows the matching `.panel`, updates the count label.
- **Family filter (Browse)**: show/hide rows by `data-fam`; `All` shows everything.
- **Open popovers**: clicking the mode pill or team pill toggles its popover; opening one closes
  the other; clicking outside closes both; clicks inside don't bubble. (Add `Esc` to close.)
- **Select a team (picker or tile/row)**: marks it selected and updates the composer team pill —
  name, lineup logos, and lead favicon (first lineup glyph). Then close the popover. In the
  launcher, selection updates the bottom action-bar summary + starter chips.
- **Favorite star**: toggles; stops propagation so it doesn't also select the card/row.
- **Edit (hover)**: opens the Customize-team drawer (existing surface). Not wired in prototype.
- **Paste-to-reorder (the only "smart" behavior)**: if the clipboard/input looks like a URL,
  Signal teams sort to the top. This is **deterministic pattern-matching only** — never an LLM
  intent-routing call, and it only re-orders, never gates. Everything else: the human picks.
- **Send**: dispatches the turn to the selected team; the resulting run returns to Inbox as an
  unread thread.

## State Management
- `mode`: `'inbox' | 'teams'` (top-bar toggle; persist last value).
- `composerMode`: `'chat' | 'send-to-team' | 'execute'`.
- `selectedTeam`: the team object bound to the composer (name, family, outcome, lineup, mutating).
- `launcherLens`: `'recent-favorites' | 'curated' | 'browse'`.
- `browseFamilyFilter`: `'all' | 'Signal' | 'Code' | 'Design' | 'Copy'`.
- `openPopover`: `null | 'mode' | 'team'` (mutually exclusive; close on outside-click / Esc).
- `pickerQuery`: search string filtering team rows.
- Conversation list: items with `{ id, title, icon, kind, lastActivity, unread }`; unread set by
  both chat replies and finished team runs.
- Teams data: `{ name, family, icon, outcome, lineup: vendor[], favorite, recentAt, mutating }`.
  Lineup is **deduped by vendor** for display, with a separate worker count.

## Design Tokens
All values come from the Allnighter design system. Files included in `tokens/`:
`colors.css`, `typography.css`, `elevation.css`. Highlights:

**Color**
- Backgrounds: `--bg-void #05060C` · `--bg-base #090B13` · `--bg-subtle #0D101A` ·
  `--bg-surface #111420` · `--bg-raised #151822` · `--bg-hover #1A1E2A` · `--bg-active #1F2331` ·
  `--bg-input #13161F`.
- Borders (white-alpha): `--border-subtle` .06 · `--border-default` .10 · `--border-strong` .16.
- Text: `--ink-50 #F2F4FA` (highest) · `--text-primary #E1E5F0` · `--text-secondary #AEB5C9` ·
  `--text-muted #7E869E` · `--text-faint #555C74` · `--text-disabled #454C62`.
- Accent (amber): `--accent #FFA630` · `--accent-hover #FFC169` · `--accent-text #FFC169`
  (amber as text) · `--accent-surface rgba(255,166,48,.12)` · `--accent-border rgba(255,166,48,.32)`
  · `--text-on-amber #1A1203` (ink on amber fills).
- Status: `--green-500 #3FD18B` (done/ready) · `--yellow-500 #F5C84B` (warn/down) ·
  `--blue-500 #5B9DFF` (running) · `--red-500 #F76B6B` (failed).

**Typography**
- `--font-sans`: `-apple-system, BlinkMacSystemFont, "Inter", system-ui, …` (SF Pro on Apple).
- `--font-mono`: `ui-monospace, "SF Mono", "JetBrains Mono", Menlo, …` — used for eyebrows,
  counts, timestamps, kbd, model IDs.
- Base body 13px. Tile name 15/700; launcher H1 23/700; popover title 14/700.
- Tracking: `--tracking-heading -0.014em`, `--tracking-normal -0.006em`, `--tracking-caps 0.08em`
  (uppercase mono eyebrows). Weights 400/500/600/700.

**Radius** (literal px used): cards/popovers 14 · tiles 12 · pills/controls 10 · chips/rows 7–9 ·
icon chips 6–8.

**Elevation**
- `--shadow-xl` (window, popovers) · `--shadow-md` · `--edge-top` (top-lit hairline on raised
  surfaces).
- **Amber glow** marks "alive"/primary: `--glow-amber-sm` (selected tile, send button, unread
  dot) · `--glow-amber` (send hover). `--glow-green` for ready model dots.
- `--focus-ring: 0 0 0 3px rgba(255,166,48,.40)` on focused inputs.

## Assets
- `assets/allnighter-glyph.svg`, `assets/allnighter-icon.svg` — brand marks used in the top bar /
  favicon. Other brand variants exist in the main project's `assets/`.
- **Model logos** (Grok / Claude / OpenAI / Gemini) in the prototype are **monochrome placeholder
  SVG symbols** defined inline (see the `<svg>…<symbol>` block near the top of
  `composer-picker.html`, and the equivalent in the launcher). Replace with the real, licensed
  brand favicons — keep them monochrome and muted (`--text-muted` / `--text-faint`), never full
  color, per the design decision.
- **Icons**: Lucide. Names used incl. `inbox, users-round, message-square, hammer, radio-tower,
  image, file-text, search, star, history, sparkles, layout-grid, sliders-horizontal, lock,
  corner-down-right, chevron-down, plus, paperclip, arrow-up, git-branch, folder-git-2,
  more-horizontal, check`.

## Files
- `designs/send-to-team-launcher.html` — Screen 1 (Teams launcher).
- `designs/composer-picker.html` — Screen 2 (Composer + team picker).
- `tokens/colors.css`, `tokens/typography.css`, `tokens/elevation.css` — design tokens.
- `assets/` — brand SVGs.

In the source project these live at `team/send-to-team-launcher.html` and
`team/composer-picker.html`, linking the full system at the project-root `styles.css`.
