# Ikiro — Design System

> Your bio link, upgraded into a website you own.

This project is the Ikiro design system: brand foundations, design tokens, reusable React components, and high-fidelity UI kits. An automated compiler indexes the tokens and bundles the components into `_ds_bundle.js` (do not edit the generated `_ds_*` files).

---

## 1. Product context

**Ikiro is the easiest way to create, upgrade, publish, edit, and own a simple web presence.** The wedge is sharper than a broad "AI website builder":

```
paste existing bio link
  → generate a beautiful, image-rich bio site
  → publish at https://{slug}.ikiro.pro
  → edit links instantly
  → measure clicks and improve the page
  → grow into a portable, Carrd-class website
  → export the Website.md project whenever desired
```

The one-liner lineage:

> Carrd made simple sites easy. Linktree made the bio link default. **Ikiro turns the bio link into a real website the user owns.**

**Positioning pillars:** speed · taste · **ownership** · portability · useful, bounded AI editing.

**Anti-positioning:** *not* "AI makes a website." That category is crowded and fragile. Never lead with the AI. Lead with the outcome — a beautiful site you own and can export.

### Products represented here
1. **Ikiro Studio editor** (`ui_kits/studio/`) — the canvas-first Link Hub editor. The wedge's primary surface: build, theme, and publish a bio page with direct manipulation, a registry-powered Add composer, a contextual inspector, and a docked AI copilot. (Replaces an earlier tabbed-sidebar playground the founder scored 1/10.)
2. **Published Link Hub** (`ui_kits/studio/public.html`) — the public page at `{slug}.ikiro.pro` that the editor produces: warm editorial backdrop, identity header, Platform Icon Strip, a Lead Media Link, and stacked pill links. The output users create and own.

### Product specs driving this (founder docs)
- **Phase 19 — Default Link Hub Template** (`uploads/19_Default_Link_Hub_Template_Launch.md`): the Linktree/lnk.bio-style page = identity + Platform Icon Strip + Lead Media Link + stacked links + curated Backdrop Layer; no-JS public render; exact URLs preserved. Reference set: `lnk.bio/msjennafischer`, `lnk.bio/RoyalCaribbean`, `lnk.bio/popmart`.
- **Phase 20 — Desktop Bio Setup & Edit UX** (`uploads/20_Bio_Setup_And_Edit_Product_UX.md`): "Forms are the hands, AI is the brain, operations are the truth." `Add` is block-general + capability-filtered; direct controls own all basic CRUD with no model call; role-dispatched contextual inspector; AI is a docked copilot, never required. This is the brief the Studio editor implements.

### Sources provided
- `uploads/Ikiro-Light.png` — the wordmark (ink on paper). Cropped/derived assets live in `assets/`.
- `uploads/ikiro-icon-light.svg` — supplied but **empty** (it references an unembedded raster); not usable. The mark in `assets/ikiro-icon*.png` was cropped from the wordmark PNG instead.
- Founder mockup screenshots of the target published page (Remi Solène) and the rejected editor — the published page is the quality bar the Studio canvas reproduces.
- No codebase or Figma file was provided. The brand visual foundations are an original, brand-faithful system derived from the logo, the product copy, the positioning, and the founder mockup. Treat them as the canonical starting point and refine with the team.

---

## 2. Content fundamentals — how Ikiro writes

**Voice:** calm, confident, plain-spoken. A capable tool that respects you. Never hypey, never breathless.

- **Person:** address the user as **you** ("a website you own", "edit links instantly"). Ikiro refers to itself as **Ikiro**, rarely "we".
- **Casing:** sentence case everywhere — UI labels, buttons, headings. Not Title Case. (`Add link`, `Publish changes`, `View site`.)
- **Verbs first, short:** buttons and actions are imperative and tight — `Publish`, `Add link`, `Upgrade`, `Export Website.md`.
- **Outcome over feature:** "Measure clicks and improve the page", not "Analytics dashboard with charts."
- **Ownership language:** *own, yours, export, portable, you keep it.* This is the differentiator — say it plainly.
- **Numbers are concrete and tabular:** `1,284 clicks`, `3 seats left`, `ikiro.pro/mara`. Use the mono face for slugs, counts and the `Website.md` filename.
- **No emoji** in product UI or marketing. The teal dot and Lucide icons carry the warmth.
- **Punctuation:** middle dot `·` separates metadata (`42 new prints · ikiro.pro/notes`). Em dashes for asides, sparingly.

**Examples**
- Hero: *"Your bio link, upgraded into a website you own."*
- Empty state: *"Add a link, header, or embed."*
- Publish toast: *"Published — live at ikiro.pro/mara."*
- Upsell: *"Custom domain & deep analytics."* (a fragment, not a sentence — calm, not salesy.)

---

## 3. Visual foundations

The system is built on three colors: **ink** `#030619`, **teal** `#12BDBC`, and **paper** `#FFFFFF`. One vivid accent against a navy-tinted neutral scale; lots of air.

- **Color** — Ink is the near-black navy of the wordmark; it tints every neutral (slate ramp `--ink-25 → --ink-950`) and every shadow. Teal is the only saturated brand color — reserve it for primary actions, the live/accent state, and the mark's dot. Status hues (green/amber/red/blue) are muted so they sit quietly beside teal. Teal `#12BDBC` fails text contrast on white, so `--accent-text` resolves to `--teal-700` for type. See `tokens/colors.css`.
- **Type** — **Geist** (a clean, modern geometric grotesk) for all product UI, **JetBrains Mono** for slugs, counts and `Website.md`, and **Newsreader** (`--font-serif`) as an editorial serif used *only* for expressive published-page identity (e.g. the Remi Solène name) — never in the product chrome. Display is extrabold (800) with tight tracking; body is 400/450 at 1.5–1.6 line-height. Headings balance-wrap, body pretty-wraps. See `tokens/typography.css`.
- **Spacing** — 4px base grid. Whitespace is a brand value: panels breathe, the published site centers in a calm ~560px column. See `tokens/spacing.css`.
- **Corners** — soft, never bubbly, echoing the arch of the mark. Controls 12px, cards 16px, panels/modals 22px, hero surfaces 28px, pills fully round. See `tokens/elevation.css`.
- **Shadows** — soft and navy-tinted (`rgba(3,6,25,…)`), low opacity, generous blur. Five steps (`xs → xl`). A dedicated teal glow (`--shadow-accent`) appears under primary buttons on hover and under "alive" elements. Cards are a **hairline border + small shadow**, not heavy drop shadows.
- **Backgrounds** — paper or app-grey, never gradient washes. Imagery is the color: real photography (warm, natural light) in covers, feature tiles and thumbnails. The only gradients used are (a) the cover→page scrim and (b) the subtle teal tint on `accent`/upsell surfaces.
- **Borders** — 1px hairlines in ink-tinted greys (`--border-subtle/-default/-strong`). On dark themes, borders become low-alpha white.
- **Motion** — quick and confident: 140–320ms, `--ease-out` for most things, a single restrained spring (`--ease-spring`) reserved for "alive" moments (publish toast, switch thumb, drag pickup). Things fade and glide; they rarely bounce. Respect `prefers-reduced-motion`.
- **Hover** — surfaces lighten to `--surface-hover`; interactive cards and tiles lift `translateY(-2px)` with a deeper shadow; primary buttons darken one step and gain the teal glow.
- **Press** — `scale(0.97)` plus a darker fill. Quick, tactile.
- **Focus** — a 4px teal ring at 22% (`--focus-ring`), offset on text. Always visible; never removed.
- **Transparency / blur** — used sparingly: the floating theme switch on the published site is a frosted pill (`backdrop-filter: blur`). Overlays use `--surface-overlay` (ink at 48%).
- **Imagery vibe** — warm, natural, editorial photography. Full-bleed covers and 16:9 feature tiles; square thumbnails. Let photos provide the saturation; keep the chrome neutral.

Specimen cards for all of the above render in the **Design System** tab (groups: Colors, Type, Spacing, Brand).

---

## 4. Iconography

Two complementary systems:

- **UI icons — [Lucide](https://lucide.dev).** Rounded line caps and a ~2px stroke echo the rounded stroke of the Ikiro mark. Rendered as React SVGs via a tiny `<Icon name="…">` helper (`ui_kits/*/icons.jsx`) over the Lucide UMD CDN; `name` accepts kebab- or Pascal-case, default size 20 / stroke 2 / `currentColor`. A substitution (no proprietary UI set was provided) — swap if the team adopts a house set.
- **Platform / brand glyphs — [Simple Icons](https://simpleicons.org) via `cdn.simpleicons.org`.** Authentic, monochrome, recolorable logos for the Platform Icon Strip and the Add composer's service detection (YouTube, Instagram, TikTok, X, Spotify, Substack, Gumroad, Calendly, …). Rendered as `<BrandIcon slug color size>` (an `<img>`); pass `color="white"` for the frosted glass strip, the brand hex for detection chips. Backed conceptually by the `@ikiro/service-registry` the docs describe; `registry.jsx` is the design-system stand-in (`SERVICES` + `detectService(url)`).
- **Brand mark as an icon:** `assets/ikiro-icon*.png` (the doorway). Use it for app/site favicons and the "Made with Ikiro" footer badge — never recolor the teal dot.
- **No emoji**, no Unicode glyph icons. Metadata uses the middle dot `·` only.

---

## 5. Index / manifest

**Root**
- `styles.css` — the single entry point consumers link. `@import`s only.
- `tokens/` — `fonts.css`, `colors.css`, `typography.css`, `spacing.css`, `elevation.css`, `motion.css`, `base.css`.
- `assets/` — `ikiro-logo.png`, `ikiro-logo-on-dark.png`, `ikiro-icon.png`, `ikiro-icon-on-dark.png`, plus the original upload.
- `guidelines/` — foundation specimen cards (Colors, Type, Spacing, Brand) shown in the Design System tab.
- `SKILL.md` — Agent-Skills wrapper so this system works inside Claude Code.
- `_ds_bundle.js`, `_ds_manifest.json`, `_adherence.oxlintrc.json` — **generated**, do not edit.

**Components** (`window.IkiroDesignSystem_5d473b.<Name>`)
- `components/core/` — `Button`, `IconButton`, `Badge`, `Tag`, `Avatar`, `Card`
- `components/forms/` — `Input`, `Textarea`, `Switch`
- `components/navigation/` — `Tabs`
- `components/product/` — `LinkRow` (signature bio-link tile), `Stat` (analytics metric)

Each component directory has `<Name>.jsx`, `<Name>.d.ts`, `<Name>.prompt.md`, and a `*.card.html` specimen. Starting points: `Button`, `Input`, `LinkRow`.

**UI kits**
- `ui_kits/studio/` — **Ikiro Studio**, the canvas-first Link Hub editor (`index.html`) plus the published page it produces (`public.html`). See its README for the full thesis and file map.

---

## Known substitutions (please confirm)
- **Fonts** are served from Google Fonts (Geist, Newsreader, JetBrains Mono), not self-hosted binaries. If you have licensed brand fonts, drop the `.woff2` files in and replace the `@import` in `tokens/fonts.css` with local `@font-face` rules.
- **Icons** are Lucide (UI) + Simple Icons (brand glyphs), both via CDN — stand-ins for the real `@ikiro/service-registry`.
- The **mark** was reconstructed by cropping the wordmark PNG (the supplied SVG was empty). A clean vector `.svg` of the mark from the team would be ideal.
- **Newsreader** is my serif pick for expressive identity; confirm it matches the intended display face in the Remi Solène mockup, or send the real one.
