# Allnighter — Design System

> **You already pay for the team. Allnighter makes it show up to work.**

This project is the **Allnighter** design system: brand foundations, design
tokens, the logo/icon, and foundation specimen cards. It is **dark-mode only**
and built for a **native macOS app** (with an iPhone companion to follow). An
automated compiler indexes the tokens and (later) bundles components into
`_ds_bundle.js` — do not edit the generated `_ds_*` files.

**Scope of this pass (per the brief):** colors, brand, type, logo, and icon —
the visual foundations only. **No product mockups or UI kits yet** — those come
once the foundation is approved. See *Next steps* at the bottom.

---

## 1. Product context

**Allnighter turns the user's Mac into an overnight agent factory and their
iPhone into the floor manager for it.** It coordinates the AI coding tools the
user already pays for — Claude Code, Codex CLI, Grok, Gemini CLI, Aider, Cursor,
local models — and spends that prepaid, expiring capacity on reviewable
progress. It is *not* a model provider, IDE, chat aggregator, or cloud coding
service. It is an **asynchronous project manager, scheduler, option factory, and
landing line** for solo builders who use AI as their primary dev workforce.

### What's being built (two horizons)
1. **The MVP — "The Council"** (active build, `uploads/README-b6a6d478.md`).
   One prompt → fan out, unchanged, to a panel of subscription CLIs in parallel
   → **Opus 4.8 synthesizes one master plan**. Text-only, local, private,
   **zero marginal cost** (subscription CLIs only — no API keys). The promise:
   *"One prompt in. One master plan out. The bench answers in parallel. You
   never touch the clipboard."* This is the surface the brand must serve first.
2. **The full roadmap** (parked, `uploads/README.md`). The worktree "factory":
   hidden lanes, parallel **races**, **picker-as-prompt** ("Implement This"),
   previews, landing/merge, quota harvesting, preference/taste, iOS floor
   manager. Same Swift substrate; the MVP grows into it without a rewrite.

### Sources provided
- `uploads/README.md` — the full Allnighter build-phases roadmap (the long game).
- `uploads/README-b6a6d478.md` — the MVP "Council" execution plan (what we ship now).
- No codebase, Figma, logo, or existing brand was provided. This is a
  **net-new identity** created from the concept, the product copy, and the
  positioning. The founder asked for: dark-mode only; Cursor and popular
  dark-mode dev tools/themes as inspiration; Inter-like type but, since it's a
  macOS app, SF Pro / Apple system faces. Everything here follows that brief.

---

## 2. Content fundamentals — how Allnighter writes

**Voice:** calm, technical, confident, plain-spoken. A capable operator that
respects you and never wastes your attention. Never hypey, never breathless.
The hidden engineering is impressive; the copy stays quiet about it.

- **Person:** address the user as **you** ("your bench", "you never touch the
  clipboard"). The product is **Allnighter**, rarely "we".
- **Casing:** **sentence case** everywhere — buttons, labels, headings
  (`Run council`, `Choose the panel`, `Copy master plan`). Not Title Case.
- **Verbs first, tight:** actions are imperative — `Run council`, `Add worker`,
  `Synthesize`, `Copy`, `Export Markdown`, `Stop`.
- **Hide the plumbing.** Say **panel, worker, council run, member answer,
  synthesizer, master plan, lane, draft, landing, preview**. Never expose
  *worktree, rebase, detached HEAD, port collision, subprocess* in core UX.
- **Lead with the outcome, not the model.** "One master plan out", not "LLM
  orchestration." Never lead with "AI". The AI is a docked tool, never the hero.
- **Ownership & utilization language.** *You already pay for it · zero marginal
  cost · local · private · you own it · export.* This is the differentiator —
  say it plainly.
- **Honesty.** A worker that didn't answer is shown **failed**, never faked.
  Quota/limit hints are labeled **estimates**. Trust is the product.
- **Numbers are concrete and mono.** `6 workers · 0 failed`, `1,284 tokens`,
  `$0.00 marginal`, `00:00:42`, `opus-4.8 via claude-code`. Slugs, counts, model
  IDs, run timestamps, and file paths are always set in the mono face.
- **No emoji** in product UI or marketing. The amber dot and Lucide icons carry
  any warmth. Metadata is separated by the middle dot `·`.
- **Punctuation:** `·` separates metadata; em dashes for asides, sparingly.

**Examples**
- Hero: *"Put your Mac on the night shift."*
- One-liner: *"You already pay for the team. Allnighter makes it show up to work."*
- Empty state: *"Type one prompt. The bench answers in parallel."*
- Run status: *"6 done · 0 failed · synthesizing master plan…"*
- Done toast: *"Master plan ready — $0.00 marginal."* (calm, factual, not salesy.)

---

## 3. Visual foundations

The whole system is **"amber phosphor on midnight"**: deep, blue-tinted midnight
surfaces — the 3am sky, a dark room — lit by **one** warm signal, amber. The
amber is the light still on while everyone else sleeps; it nods to old amber-CRT
terminals and to "burning the midnight oil." The chrome is Cursor-grade:
precise, quiet, dense, dark. Lineage is Cursor · Linear · Raycast · Warp ·
Zed · VS Code Dark — but warm where they're cool.

- **Color** — Three roles: **midnight** (a blue-tinted near-black neutral ramp,
  `--ink-950 → --ink-50`), **amber** (`#FFA630`, the one saturated brand color),
  and **paper** (`--ink-50 #F2F4FA`, the lightest text — never pure white).
  Amber is reserved for the single primary action on a surface, the live/"alive"
  state, the synthesizer/winner, and the mark. Status hues (green/blue/red/
  yellow) are **muted** so they sit quietly beside amber. Backgrounds climb from
  `void → base → surface → raised` by getting *lighter*, never by stacking heavy
  shadows. See `tokens/colors.css`.
- **Type** — **SF Pro Text / SF Pro Display** for all product UI (it's a macOS
  app, so the system face is free, native, and on-brand), **SF Mono** for slugs,
  counts, model IDs, run timestamps and file paths. On the web (these specimens,
  marketing, prototypes) the system stack renders SF Pro natively on Macs and
  falls back to **Inter** (≈ SF Pro) and **JetBrains Mono** (≈ SF Mono),
  loaded from Google. macOS density → **13px body**; display is extrabold (800)
  with tight tracking. Headings balance-wrap; body pretty-wraps. See
  `tokens/typography.css`.
- **Spacing** — 4px base grid; tight and precise, a tool not a brochure.
  Whitespace is controlled, not lavish. macOS-native control heights (30px
  default). See `tokens/spacing.css`.
- **Corners** — tighter than consumer-soft: controls/inputs **6px**, cards
  **10px**, panels/popovers **14px**, modals **18px**, the app window **12px**,
  status pills fully round. Never bubbly. See `tokens/spacing.css`.
- **Borders** — **1px white-alpha hairlines** (`--border-subtle` 6%, `-default`
  10%, `-strong` 16%) so a line reads correctly over any surface. An opaque ink
  divider (`--border-solid`) exists for when alpha won't do.
- **Shadows** — dark-mode depth is **deep black, low opacity, generous blur**
  (`--shadow-xs → -xl`), paired with a top-lit inset edge (`--edge-top`) on
  raised surfaces. Cards are **hairline border + small shadow**, never a heavy
  drop shadow.
- **Glow** — the signature lighting move: a soft **amber glow**
  (`--glow-amber*`) appears under the primary button on hover, around the
  synthesizer, and on "alive" elements (a running worker, the live dot). Status
  glows (green/blue/red) exist for emphatic states. Glow is how the system says
  *this is working right now*.
- **Backgrounds** — solid midnight, **never gradient washes**. The only
  gradients permitted: (a) the subtle radial depth inside the app icon, (b) the
  amber glow halos, (c) a marketing hero's faint corner light. No purple/blue
  hero gradients.
- **Imagery** — this is a developer tool, so imagery is mostly **the work
  itself**: terminal output, code, diffs, master-plan Markdown, worker status
  grids, the menu-bar. Where atmosphere is wanted, lean on the midnight canvas +
  amber glow and a faint starfield/noise — not stock photography. Keep chrome
  neutral; let the amber be the only color event.
- **Motion** — quick and confident: **120–280ms**, `--ease-out` for almost
  everything. A single restrained spring (`--ease-spring`) is reserved for
  "alive" moments (a worker finishing, a toast, a switch thumb). The "working"
  state uses a slow opacity **pulse** (the lamp breathing), never a spinner-y
  bounce. Respect `prefers-reduced-motion`.
- **Hover** — surfaces **lighten** one step (`--bg-hover`); the primary button's
  amber **lightens** (dark-mode hover goes up, not down) and gains the glow;
  interactive cards lift `translateY(-2px)` with a deeper shadow.
- **Press** — `scale(0.97)` + a darker fill. Quick, tactile.
- **Focus** — a 3px amber ring at 40% (`--focus-ring`), always visible, never
  removed.
- **Transparency / blur** — used sparingly: popovers, menus, and the command bar
  may sit on a blurred midnight (`backdrop-filter: blur`) over the scrim
  (`--bg-overlay`, ink at 66%). Not a decorative glass everywhere.
- **Cards** — `--bg-raised` fill, 1px `--border-subtle`, `--radius-lg` (10px),
  `--shadow-sm`, optional `--edge-top`. Calm rectangles that hold real content.

Specimen cards for all of the above render in the **Design System** tab (groups:
Colors, Type, Spacing, Brand).

---

## 4. Iconography

- **UI icons — [Lucide](https://lucide.dev).** A ~2px stroke with rounded line
  caps matches the rounded, confident feel of the brand. Loaded from the Lucide
  CDN; recolor via `currentColor`. Common picks: `moon`, `play`, `layers`,
  `users`, `git-branch`, `zap`, `check-check`, `terminal`, `activity`, `clock`,
  `copy`, `settings-2`. *(Substitution: no house icon set was provided — swap if
  the team adopts one.)*
- **Worker / brand glyphs — [Simple Icons](https://simpleicons.org) via
  `cdn.simpleicons.org`.** Authentic monochrome logos for the panel of workers
  and service detection (Anthropic, Google Gemini, Grok/X, Ollama, …). Render as
  `<img src="https://cdn.simpleicons.org/<slug>/<hex>">`; recolor to `--ink-100`
  on the midnight chrome, or to brand hex for detection chips. **Note:** Simple
  Icons has **removed OpenAI** (trademark), so ChatGPT/Codex has no glyph there —
  use a neutral terminal chip or the team's own asset for those workers.
- **Brand mark as an icon:** `assets/allnighter-glyph.svg` (the amber crescent)
  and `assets/allnighter-glyph-mono.svg` (`currentColor`). Use for favicons, the
  menu-bar item, and a "Made with Allnighter" badge. The crescent is **static**
  in all icon/small-size contexts. Never recolor the amber to another hue.
- **The live mark** (`assets/allnighter-glyph-live.svg`) adds a cursor block to
  the crescent for web/active contexts — see Brand assets below.
- **No emoji, no Unicode-glyph icons.** Metadata uses the middle dot `·` only.

---

## 5. Brand assets

The mark is an **amber crescent moon** on a midnight squircle — the one warm
light still on while everyone else sleeps. It is deliberately **simple and
static**: no star (the star is the astrology tell, so it's gone), no extra
ornament. That simplicity is the point — it stays legible and calm at every size.

The identity is a **two-part system**:

1. **The mark — a static crescent.** Used everywhere it must be instantly
   legible and quiet: macOS app icon, favicon, menu-bar, and the wordmark
   lockup. It never animates.
2. **The live mark — crescent + a cursor block, where *only the block blinks*.**
   Used on the website, loading states, and "council running" moments. The moon
   stays rock-solid; the amber terminal-cursor block beside it is the single
   element that pulses — the brand's heartbeat. The block doubles as a **status
   light**: solid amber = idle, blinking amber = workers running, green
   (`--green-500`) = done. So the logo *is* the activity indicator.

Rule: animate the **block only**, never the whole mark. (The earlier beam-A and
crescent-with-star explorations are archived in
`guidelines/explorations/Allnighter Logo Exploration.html` and
`guidelines/explorations/Allnighter Moon Refinement.html`.)

**Live mark markup** (block-only blink):

```html
<svg class="al-live" viewBox="0 0 100 100" width="32">
  <defs>
    <linearGradient id="cg" x1="20" y1="24" x2="66" y2="80" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFD79E"/><stop offset=".5" stop-color="#FFA630"/><stop offset="1" stop-color="#F0901C"/>
    </linearGradient>
    <mask id="cm"><rect width="100" height="100" fill="black"/>
      <circle cx="47" cy="50" r="32" fill="white"/><circle cx="62" cy="41" r="28" fill="black"/></mask>
  </defs>
  <rect width="100" height="100" fill="url(#cg)" mask="url(#cm)"/>
  <rect class="cur" x="60" y="43" width="10.5" height="17" rx="2.6" fill="#FFE9C6"/>
</svg>
<style>
  @keyframes curblink{0%,52%{opacity:1}53%,100%{opacity:0}}
  .al-live .cur{animation:curblink 1.05s steps(1,end) infinite}  /* running */
</style>
```

| File | Use |
| --- | --- |
| `assets/allnighter-icon.svg` | macOS app icon — squircle, midnight + amber crescent + glow. Static. |
| `assets/allnighter-glyph.svg` | The crescent alone (gradient), transparent bg — inline, menu-bar, badges. |
| `assets/allnighter-glyph-mono.svg` | Single-color crescent (`currentColor`) for masking / recoloring. |
| `assets/allnighter-glyph-live.svg` | Live mark — crescent + cursor block (blink the block on the web). |
| `assets/allnighter-wordmark.svg` | Horizontal lockup: crescent + **allnighter** (lowercase, SF Pro Display, tight). |

Clear space ≈ the height of the crescent on all sides. Don't recolor the
amber, don't place the wordmark on busy imagery, don't add a drop shadow to the
flat glyph (the app icon already carries its own depth).

---

## 6. Index / manifest

**Root**
- `styles.css` — the single entry point consumers link (`@import`s only).
- `tokens/` — `fonts.css`, `colors.css`, `typography.css`, `spacing.css`,
  `elevation.css`, `motion.css`, `base.css`.
- `assets/` — `allnighter-icon.svg`, `allnighter-glyph.svg`,
  `allnighter-glyph-mono.svg`, `allnighter-glyph-live.svg`, `allnighter-wordmark.svg`.
- `components/` — reusable React primitives (see below); `_preview.jsx` is the
  runtime mirror used by specimen cards + the UI kit.
- `ui_kits/council/` — the **Council** macOS app (the MVP), built from the components.
- `guidelines/` — foundation specimen cards (Colors, Type, Spacing, Brand),
  shown in the Design System tab.
- `SKILL.md` — Agent-Skills wrapper so this system works inside Claude Code.
- `readme.md` — this guide.

**Components** (`window.<Namespace>.<Name>`)
- `components/core/` — `Button`, `IconButton`, `Badge`, `Card`
- `components/forms/` — `Input`, `Textarea`, `Switch`, `Select`
- `components/navigation/` — `Tabs` (segmented · underline)
- `components/overlay/` — `Menu` (contextual actions), `Dialog` (modal confirm)
- `components/feedback/` — `Toast` (calm notifications)
- `components/product/` — `StatusPill` (queued/running/done/failed/timed-out — running blinks),
  `WorkerChip` (a worker in the panel or live run grid)

**UI kits**
- `ui_kits/council/` — **Council**, the macOS MVP: window chrome, panel sidebar,
  prompt composer, live run grid, synthesis bar, master-plan + member-answers.
  `index.html` is an interactive state machine.
- `ui_kits/ios-floor-manager/` — the **iPhone floor manager** (parked roadmap):
  Morning Pull, Active Lanes, and the **Draft Race + picker-as-prompt** wedge.
- `ui_kits/judgment/` — the **judgment / Review Board** surfaces (macOS): workflow
  presets, stage primitives, and the return-review flow (see `docs/mvp/RB*`).
- `ui_kits/judgment-ios/` — the iPhone companion for the judgment flow.

**Tokens at a glance**
- Color: `--ink-50…950` (midnight ramp), `--amber-300…800` (signature),
  status hues; semantic aliases `--bg-*`, `--text-*`, `--border-*`, `--accent*`,
  `--status-*`, `--focus-ring`.
- Type: `--font-sans` / `--font-display` (SF Pro → Inter), `--font-mono`
  (SF Mono → JetBrains Mono); `--text-display…caption`, weights, leading,
  tracking; helper classes `.t-display`, `.t-h1`, `.t-body`, `.t-mono`, etc.
- Spacing/radius: `--space-*` (4px grid), `--radius-xs…2xl/pill`, control heights.
- Elevation/motion: `--shadow-*`, `--edge-*`, `--glow-amber*`, `--ease-*`,
  `--duration-*`.

---

## 7. Known substitutions (please confirm)
- **Fonts.** The intended native faces are **SF Pro** + **SF Mono** (Apple system
  fonts, not redistributable). The web specimens render them via the system
  stack and fall back to **Inter** + **JetBrains Mono** from Google. On a real
  Mac, SF Pro renders natively. If you want pixel-identical web rendering, we can
  self-host a licensed face — tell me.
- **Icons** are Lucide (UI) + Simple Icons (worker glyphs) via CDN — stand-ins
  until a house set exists. OpenAI/ChatGPT has no Simple Icons glyph.
- **The logo is net-new.** I designed the crescent mark, the live cursor-block
  lockup, wordmark, and app icon from the concept; there was no prior brand.
  They're SVG and easy to iterate. Earlier directions (beam-A, desk lamp, hanging
  bulb, crescent variants) live in
  `guidelines/explorations/Allnighter Logo Exploration.html` and
  `guidelines/explorations/Allnighter Moon Refinement.html`.
- **Amber hue** `#FFA630` is my pick for "phosphor amber." Easy to shift warmer
  (more gold) or hotter (toward orange) — say the word.

---

## Next steps
The foundations, 14 components, the Council MVP kit, and the iOS floor-manager
roadmap surface are built. Natural follow-ons:
1. **Marketing one-pager / landing** using these foundations.
2. **More roadmap surfaces** — the Mac comparison grid (race side-by-side), the
   landing queue / risk tiers, Local Bench, Quota Harvester.
3. **A few more primitives** as needed: Tooltip, Stat tiles, Segmented progress.
