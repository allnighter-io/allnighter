# Handoff: First-Run Setup — "Assemble your council"

> Target platform: **native macOS app, SwiftUI.** This bundle is the designer's
> deliverable for **Phase 3 (Setup UI)** of the first-run experience. It pairs
> with the engineering contract already written by the team (see
> `spec/01_CLI_Detection_Auth_And_Panel.md`). Build detection (Phases 1–2)
> **before** wiring this UI to live data — this screen is a *thin skin over
> detection that already works*, never a beautiful wrapper around flaky probes.

---

## Overview

This is the full-window, first-launch flow a new user sees when they open
Allnighter. Allnighter coordinates the AI coding CLIs the user already pays for
(Claude Code, Codex, Grok, Antigravity…). Setup **scans the machine, finds those
CLIs, gets them authenticated, and assembles the council for the user.** The
emotional bar: "it found my whole team and it's ready" — recognition, not
configuration.

The specific screen in this handoff is the **roster in its partial state**: the
common real-world case where *some* CLIs are detected and ready but others need a
quick step (sign-in, a path fix, or an install). This is the screen that has to
turn a frustrating "0/1 healthy" cold-open into a calm, guided, one-screen fix.

This handoff documents:
1. **The Setup window** — the live partial-state roster (the primary screen).
2. **A per-state spec sheet** — every individual `WorkerSetupStatus` card
   rendered in isolation, so you can implement and verify each state precisely.
3. **The compact Council-health popover** (Doctor) — the in-app re-check surface
   opened from the title-bar health badge, reusing the exact same roster + cards.

---

## About the design files

The files in `design/` are **design references built in HTML/React** — a
prototype showing the intended look, copy, and behavior. **They are not
production code to copy.** Your task is to **recreate this design in the macOS
app in SwiftUI**, using the app's existing patterns (the `AppModel`,
`WorkerHealthChecker`/`CLIDetector`, the design-system tokens, etc.).

- `design/setup.html` — open this in a browser to see the screen exactly as
  designed. It renders the React prototype.
- `design/doctor.html` — the compact Council-health popover (Screen C), reusing
  the same `SetupCard` roster from a different container.
- `design/setup.jsx` — the prototype source: all card states, copy, layout, and
  the CSS (in a `<style>` injected at the top). **This is the most precise
  reference for measurements, colors, and copy.**
- `design/_preview.jsx`, `design/shell.jsx` — the design-system component runtime
  the prototype reuses (`StatusPill`, `Badge`, `Button`, the live mark, icons).
- `design/styles.css` + `design/tokens/*.css` — the full design-token source of
  truth (colors, type, spacing, radii, motion). All hex values below come from
  here.
- `design/assets/*.svg` — the brand mark ("live mark").
- `spec/00_…md`, `spec/01_…md` — the experience narrative and the engineering
  contract (entity model, detection strategy, status model, persistence). **Read
  `01_` §2 and §5 before building — the tool-vs-seat distinction and the
  `WorkerSetupStatus` enum are load-bearing.**

If anything in this README conflicts with the prototype, **the prototype wins for
visuals**; `spec/01_` wins for behavior/data contracts.

---

## Fidelity

**High-fidelity (hifi).** Final colors, typography, spacing, copy, and component
structure. Recreate pixel-accurately with SwiftUI using the design tokens below.
The only thing deliberately *not* built is interactivity — the prototype is
static (buttons don't act). The behavior you must implement is described in
**Interactions & Behavior** and in `spec/01_`.

---

## Core concept: tool vs. seat (read this first)

This is the single most important rule (`spec/01_` §2):

- **Tool / driver** = one CLI (`claude`, `codex`, `grok`, `agy`). **Detection,
  auth, the roster card, the tally, and the health badge are per-tool.**
- **Worker / seat** = a model running on a tool (Opus *and* Sonnet are two seats
  on the one `claude_code` tool).

So: **one card per tool.** A *ready* tool expands to show its **seats**
underneath. The tally is tool-level — "**1 of 4 tools ready**", never "1 of 6".

**v1 roster = shipped drivers only:** `claude_code`, `codex`, `grok`,
`antigravity`. **No ghost cards** for tools without a manifest (Cursor / Aider /
Gemini-CLI are phase-2).

---

## Screens / Views

### Screen A — Setup window (partial roster)

**Purpose:** Show the user which of their CLIs are ready and let them fix the rest
inline, then continue into the app with whoever is ready (≥1 required).

**Window:** Full-window first-launch flow in the same window the Council runs in.
Min size **1100×720**; prototype is drawn at **1120 wide**. The app is a menu-bar
app (`LSUIElement`) — on first launch it must **auto-open this window at full
size** (never hide setup behind the menu-bar icon). See `spec/01_` §7.

**Top-level layout (vertical stack, fills the window):**

| Region | Height | Notes |
| --- | --- | --- |
| **Title bar** | 44px | Traffic lights · centered mark + `allnighter · setup` · right: health badge + settings. `bg-surface`, 1px `border-subtle` bottom. |
| **Stage** (scrolls) | flex | Centered column, `max-width 720`, top padding 44px. Hero block, then the roster. `bg-base`. |
| **Footer bar** | auto | "What gets scanned?" + reassurance on the left; hint + **Continue** on the right. `bg-surface`, 1px `border-subtle` top, 14px/22px padding. |

#### Title bar
- **Left:** three 12px traffic-light dots, 8px gap — `#FF5F57`, `#FEBC2E`,
  `#28C840`. (Use the real macOS title bar in the app; these are the prototype's
  stand-in.)
- **Center:** the **live mark** at 16px + `allnighter` (`text-label` 12px / 600 /
  `text-secondary`) + a faint mono `· setup` (`text-mono-sm` 11px / `text-faint`).
- **Right:** a **health badge** — pill, `warning` tone, leading dot, mono text
  `1/4 ready`; then a `settings-2` (gear) ghost icon button. This badge is the
  same title-bar health badge used elsewhere; it must reflect **real** probe
  state from the shared store.

#### Hero (centered, max-width 720, text-align center)
1. **Live mark**, 46px, **steady** (idle — solid crescent, *no* blinking cursor
   block). A soft amber drop-shadow glow sits behind it
   (`drop-shadow(0 0 22px rgba(255,166,48,.20))`). Margin-bottom 20px.
   - The mark is the protagonist of the whole flow. During the *scan* (an earlier
     scene, not this screen) the cursor block **blinks**; on this settled roster
     it is **steady**. Animate the block only, never the whole mark.
2. **Headline** — `Your council is taking shape` · display font, **30px / 800 /
   line-height 1.08 / letter-spacing −0.022em** / `text-primary`.
3. **Tally** (15px top) — row, `nowrap`: bold `text-primary` "**1** of **4** tools
   ready" (the numerals `1` and `4` in **mono**), then a faint mono `· 2 seats`
   (`text-faint`). The bold/numbers must be computed from real counts.
4. **Segment bar** (17px top) — four cells, 5px gap, each **52×5px, radius 3px**:
   - cell 1 = `green-500` (ready), cells 2–3 = `yellow-400` (needs a step),
     cell 4 = `bg-active` grey (not installed / unstarted).
   - One cell per tool, colored by that tool's state. This is an honest
     at-a-glance summary, not a progress %; order matches the tally groups.
5. **Subline** (17px top) — `text-muted` 13.5px / line-height 1.58 / max-width
   540 / `text-wrap: pretty`:
   *"Claude Code is ready. Two tools need a quick step and one isn't installed
   yet — fix them here and they go green in place. No restart, no typing."*
   (This copy is illustrative for this state; generate it from the real tallies,
   keeping the calm, sentence-case, verbs-first voice.)

#### Roster (centered, max-width 720, vertical stack, 9px gap, 32px top margin)
Cards are **sorted into three groups**, each with a group label:

| Group label | Tools in this prototype | Sort rule |
| --- | --- | --- |
| `READY` ·1 | Claude Code | `ready` tools first |
| `NEEDS A STEP` ·2 | Codex, Antigravity | `installedNotSignedIn`, `shimmedNeedsConfirm`, `probeFailed` |
| `AVAILABLE TO ADD` ·1 | Grok | `notInstalled` last |

**Group label** style: 15px top / 3px bottom padding; row with 10px gap:
uppercase text (10.5px / 700 / letter-spacing 0.11em / `text-faint`), then a mono
count (`ct`, same color), then a 1px `border-subtle` rule filling the remaining
width.

See **Components → SetupCard** for the card spec.

#### Footer bar
- **Left column** (flex 1, 5px gap):
  - **"What gets scanned?"** — a button styled as quiet text (12.5px / 500 /
    `text-secondary`, hover → `text-primary`) with a leading 14px `shield` icon.
    Opens a popover explaining: *we only look for known CLI tools, locally,
    read-only.*
  - **Reassurance line** — mono 10.5px `text-faint`:
    `scanned locally · read-only · only known CLI tools`.
- **Right column** (14px gap, nowrap):
  - **Hint** — 12px `text-muted`, right-aligned, max-width ~208:
    *"Continue with 1 ready, or fix the rest first."*
  - **Continue** — **primary** button (amber), trailing 16px `arrow-right` icon.
    Enabled because ≥1 tool is ready. **Never enable a path to a 0-ready council
    on first launch** (`spec/01_` §7) — if zero tools are ready, this is the
    *none-found* empty state instead (out of scope for this screen; noted in
    `spec/00_` §4).

---

### Screen B — Per-state spec sheet ("Every card state")

Below the window in `setup.html` is a documentation grid showing **one card per
`WorkerSetupStatus`** so you can build and QA each state in isolation. It is *not*
a second app screen — it's a reference. Implement the `SetupCard` to render each
of these states; the grid just lays them out 2-up.

**Section header:** title "Every card state" (18px / 700) + a caption explaining
that state is the single canonical `WorkerSetupStatus` that Doctor, Setup, and the
health badge all read, and that a card only flips to **Ready** when its smoke
probe actually passed.

**The nine states, with the enum they map to:**

| Label in grid | `WorkerSetupStatus` | What the card shows |
| --- | --- | --- |
| `ready` | `.ready(version)` | Header green pill + version + "signed in"; body = expanded **seats** (each with a green dot, name, mono model id; the synthesizer-eligible seat carries an amber `synthesizer` chip). |
| `installedNotSignedIn` | `.installedNotSignedIn(loginFlow)` | Amber "Needs sign-in" pill; fix-it body (see below). |
| `installedNotSignedIn · polling` | same, while re-probing | The post-action variant: a blue blinking "Waiting for sign-in…" pill in the body + "re-checking every few seconds" + a `loader`-icon note. |
| `notInstalled` | `.notInstalled` | Muted/dashed card, glyph dimmed; "Not installed" pill; install-hint body. |
| `shimmedNeedsConfirm` | `.shimmedNeedsConfirm(resolved)` | Amber "Needs a path" pill; alias/shim fix-it body. |
| `probeFailed` | `.probeFailed(reason)` | Red-tinted card; "Probe failed" pill; the real error in a red mono row. |
| `queued / ghost` | (pre-detection) | Dim/dashed slot, glyph monochrome, "Queued" muted pill, no body. The roll-call starts here. |
| `detecting` | (in-flight) | Monochrome glyph, blue blinking "Detecting…" pill, mono `resolving → version → smoke`, no body. |
| `re-probing` | (cheap re-check on launch/wake) | Normal card, blue blinking "Re-checking…" pill. |

---

### Screen C — Council health (compact Doctor) · `design/doctor.html`

**Purpose:** The quick "are my CLIs still good?" surface **inside the running
app** — opened *after* first-run setup is complete by clicking the **title-bar
health badge** ("4/4 ready"). This is the recheck home for what used to be the
Doctor sheet (`spec/00_` §6, `spec/01_` §10). It is **not** the first-launch flow
and **not** full-window.

**Form factor:** a **popover** anchored to (and dropping from) the health badge,
**404pt wide** (360–420 is fine), `bg-raised` fill, 1px `border-default`,
**radius-xl (14px)**, a deep shadow (`0 24px 60px rgba(0,0,0,.66)`), and a small
**caret** (13×13, rotated square, same fill + top/left border) pointing up at the
badge. In SwiftUI use `.popover`/`NSPopover` anchored to the badge. It scrolls
internally when the content is taller than the available height (the prototype
shows the whole thing expanded so every state is visible in one screenshot —
**in the app it scrolls**).

**It deliberately drops the cinematic furniture of Screen A:** no hero / live-mark
protagonist block, no segment bar, no footer **Continue** bar. Same design system,
tokens, `SetupCard`, `StatusPill`, `Cmd`, buttons, glyphs, copy voice, and honesty
rule — just compact and utilitarian.

**Structure (vertical):**

1. **Header** (13px padding, 1px `border-subtle` bottom):
   - Top row: a 26×26 `bg-active` tile with an amber-tinted `shield` icon · title
     **"Council health"** (14px / 700) · a **"Re-check"** button (ghost, sm,
     leading `rotate-cw`/`arrow.clockwise`) that re-runs detection · a **close**
     ghost icon button (`x`).
   - Sub row (`nowrap`, 11px top): the tool-level **tally** — bold "**1** of **4**
     tools ready" (numerals mono) + faint mono `· 2 seats` — and, pushed right, a
     mono "checked 2s ago" with a 12px `clock` icon. Recompute from real state.
2. **Roster** (4px/13px padding, 8px gap): the **exact same** grouped roster as
   Screen A — `READY` / `NEEDS A STEP` / `AVAILABLE TO ADD` group labels, each a
   `SetupCard`. **One difference:** in this compact surface, **ready cards are
   collapsed** — the seat list does *not* expand (the meta still reads
   `… · 2 seats · signed in`). Seat detail is confirm-only and lives in full
   Setup (Scene 5). Pass a `compact` flag to the card to suppress the seats body.
   Every other state renders its **full fix-it**, identical to Screen A —
   including the `installedNotSignedIn` → **"Open Terminal & sign in"** flow and
   its **waiting → green-flip polling** (shown live on Codex in the prototype),
   `shimmedNeedsConfirm` (Use it anyway / Locate the binary…), `notInstalled`
   (install hint + Re-scan), and `probeFailed` (Re-try probe / View log). **A
   signed-out tool here offers the same one-click fix as in first-run** — there is
   one fix-it implementation, reused.
3. **Footer** (9px/13px padding, 1px `border-subtle` top, `bg-surface`, centered):
   a single subtle **"Open full setup"** text button (leading `maximize` /
   `arrow.up.left.and.arrow.down.right` icon, `text-muted` → `text-primary` on
   hover) for the rare case the user wants the whole cinematic flow again
   (re-runs Setup, Scene 1–6).

**Same source of truth:** the badge, this popover, and full Setup all read the one
`CLIDetector` output + persisted store. Re-check here updates the badge and any
open Setup window identically — never a forked truth (`spec/01_` §5, §9).

> Implementation note: the Swift app builds **one** `SetupCard` view (from the
> Screen-A spec) and reuses it verbatim in both surfaces; Doctor is just a
> different container (popover + compact header/footer, ready cards collapsed)
> around the same cards and the same fix-it actions.

---

## Components

### SetupCard (the heart of the screen)

A rounded card, one per tool. Structure: a **head row** (always shown) + an
optional **body** (the fix-it / seats, shown for states that have one).

**Container:** `bg-raised` fill, 1px `border-subtle`, **radius-lg (10px)**,
`shadow-sm`, `overflow: hidden`. State-dependent variants:

| Variant | Trigger states | Override |
| --- | --- | --- |
| `ready` | `.ready` | border `rgba(63,185,109,.26)` (faint green); subtle top gradient `linear-gradient(180deg, rgba(63,185,109,.045), transparent 46%)` over `bg-raised`. |
| `step` | `installedNotSignedIn`, `shimmedNeedsConfirm`, `waiting`, `re-probing` | border `border-default` (10% white). |
| `muted` | `notInstalled`, `queued`, `detecting` | fill `bg-surface`, **dashed** `border-default`, no shadow. |
| `fail` | `probeFailed` | border `rgba(240,90,90,.28)` (faint red). |

**Head row** — flex, align center, 13px gap, **13px/15px padding**:
- **Glyph tile** — 40×40, **radius 10px**, `bg-active` fill, centered, clips. The
  brand glyph is **23px**. When the tool is `notInstalled`/`queued`/`detecting`,
  the tile is dimmed (opacity 0.5) and the glyph is rendered monochrome/muted.
  - Glyph sources (see **Assets**): Claude Code → Anthropic mark tinted amber
    `#FFA630`; Antigravity → Google Gemini mark tinted `#E1E5F0`; Grok → X mark
    tinted `#E1E5F0` (muted grey `#6B7180` when not installed). **Codex has no
    brand glyph** — use a neutral **terminal** SF Symbol/icon at 21px in
    `text-secondary` (Simple Icons removed the OpenAI mark for trademark reasons;
    do not fabricate one).
- **Identity column** (flex 1, 4px gap):
  - **Name** — 14.5px / 700 / letter-spacing −0.01em / `text-primary`
    (`text-muted` when muted).
  - **Meta** — mono 11px / `text-faint`, items separated by a faded `·` (sep at
    opacity 0.45), `flex-wrap` allowed but **each item is `nowrap`**. Items vary
    by state — examples:
    - ready: `via claude-code` · `claude 1.2.4` · `2 seats` · `signed in`
      (last in `green-400`).
    - needs-login: `via codex` · `codex 0.9.1` · `found, not signed in`.
    - needs-path: `via antigravity` · `agy` · `shell function`.
    - not-installed: `no binary on PATH or known paths`.
    - probe-failed: `via codex` · `codex 0.9.1` · `smoke failed`.
    - detecting: `via claude-code` · `resolving → version → smoke`.
    - re-probing: `via antigravity` · `agy` · `cheap re-check…`.
    - queued: `queued`.
- **Trailing:** the **status pill** (see below).

**Body** — shown only for states with one; 14px/15px/15px padding, 1px
`border-subtle` top:

- **Ready → Seats list.** Vertical, 1px gap. Each seat row: 8px/9px padding,
  radius-sm, 10px gap: a 7px green dot, name (13px / 600 / `text-primary`), mono
  model id (11px / `text-faint`), and — for the synthesizer-eligible seat — a
  right-aligned **`synthesizer` chip**: pill, `accent-surface` bg,
  `accent-border`, `accent-text`, 10.5px / 600, leading 11px `sparkles` icon.
  Synthesizer eligibility comes from `Worker.canSynthesize` (`spec/01_` §2) — do
  **not** put it on the tool/registry.
- **installedNotSignedIn → guided sign-in.**
  - Fix line (13px / `text-secondary`): *"Codex is installed but not signed in. It
    prompts for sign-in on first run."*
  - **Command box** (`Cmd`, see below): `$ codex`.
  - **Actions:** primary **"Open Terminal & sign in"** (leading `terminal` icon)
    + ghost **"Copy steps"** (leading `copy` icon).
  - **Note** (11.5px / `text-faint`, leading `info` icon): *"Sign in in Terminal —
    we'll detect when you're done."*
- **installedNotSignedIn (polling) → the waiting variant.** Same fix line + command
  box, but the actions are replaced by a **blue blinking "Waiting for sign-in…"
  pill** + mono "re-checking every few seconds", and the note uses a `loader` icon:
  *"Flips to ready the moment the probe passes — no restart, no app focus needed."*
- **shimmedNeedsConfirm → alias / non-PATH binary.**
  - Fix line: *"We found `agy` as a shell function, not a plain command."* (the
    `agy` inline-coded — see inline code style).
  - Command box with an `ƒ` prompt glyph:
    `ƒ  agy () { /Applications/Antigravity.app/Contents/MacOS/agy $@ }`.
  - **Actions:** secondary **"Use it anyway"** + ghost **"Locate the binary…"**
    (leading `folder` icon).
  - Note (`info`): *"Use-anyway runs it through your login shell — exactly as your
    terminal does."*
- **notInstalled → install hint.**
  - Fix line: *"You don't have Grok yet. Install it, then re-scan."*
  - Command box: `$ brew install grok` *(placeholder — substitute the real install
    one-liner from the driver manifest's `setup.installHint`).*
  - **Actions:** secondary **"Open install page"** (leading `external-link` icon)
    + ghost **"Re-scan"** (leading `rotate-cw` icon).
- **probeFailed → real reason.**
  - Fix line: *"Detected `codex 0.9.1`, but the smoke run failed."*
  - **Error command box** (red variant, `!` prompt): `error: unknown flag --model
    (exit 2)` — prompt and text in `red-400`.
  - **Actions:** secondary **"Re-try probe"** (`rotate-cw`) + ghost **"View log"**
    (`file-text`).
  - Note with a red `alert-triangle` icon: *"Detect passed, smoke didn't — this is
    not a sign-in problem."* This distinction (`installedNotSignedIn` vs
    `probeFailed`) is required by `spec/01_` §5 — users treat "sign in" and
    "unknown flag" very differently.

### StatusPill

Pill, height 23px, padding `0 10px 0 8px`, **radius-pill**, 11.5px / 600, leading
7px dot, 6px gap. Tones (all background tints already exist as tokens):

| Pill | Label | bg | text | dot |
| --- | --- | --- | --- | --- |
| ready | `Ready` | `success-surface` | `green-400` | `green-500` |
| step | `Needs sign-in` / `Needs a path` | `warning-surface` | `yellow-400` | `yellow-400` |
| muted | `Not installed` / `Queued` | `bg-active` | `text-faint` | `text-faint` |
| fail | `Probe failed` | `danger-surface` | `red-400` | `red-400` |
| check | `Detecting…` / `Re-checking…` / `Waiting for sign-in…` | `info-surface` | `blue-400` | `blue-400` (dot **blinks**) |

The `check` dot blinks: opacity 1 → 0.3 → 1 over 1.1s, ease-in-out, infinite
(matches the design system's running-status animation). Respect
`prefers-reduced-motion` / Reduce Motion — when set, the dot is solid.

### Cmd (copyable command box)

Row: `bg-void` fill, 1px `border-subtle`, **radius-md (8px)**, padding
`8px 8px 8px 12px`, 9px gap. A mono prompt glyph (`$` / `ƒ` / `!`, `text-faint`,
or `red-400` in the error variant), then mono command text (12.5px / `text-primary`,
ellipsis on overflow, flex 1), then a trailing ghost **copy** icon button (14px
`copy` icon) that copies the command to the clipboard.

### Buttons

Reuse the design-system `Button` (heights: sm 24, md 30, lg 36; radius-sm 6px;
600 weight). Variants used here:
- **primary** — amber fill `#FFA630`, ink text `#1A1203`; hover lightens to
  `#FFC169` + amber glow; press `#F08D1C` + `scale(.97)`.
- **secondary** — `bg-surface` fill, `text-primary`, 1px `border-default`.
- **ghost** — transparent, `text-secondary`, hover `bg-hover` + `text-primary`.
Icon buttons: 24/30/36 square, ghost by default.

### Live mark

`design/assets/allnighter-glyph-live.svg` is the mark. It is an **amber crescent**
on transparent; the "live" version adds a **cursor block** beside it. **Animate
the block only**:
- **Idle / steady** (this settled roster, and "ready"): solid amber, block static
  (or omitted, as in the hero here).
- **Running / scanning**: block blinks (0% solid → 53% hidden, `steps(1)`, 1.05s).
- **Done**: a single green glow-pulse (used on the final launch scene, not here).

In SwiftUI, build it as a `Shape`/`Canvas` or ship the SVG as a vector asset;
drive the block's opacity with an animation gated on Reduce Motion.

---

## Interactions & Behavior

All of the following is **static in the prototype** — implement it for real per
`spec/01_`:

1. **Continue** → dismisses Setup and proceeds to the panel/compose surface with
   the assembled council (Scene 5/6 in `spec/00_`). Enabled only when ≥1 tool is
   `ready`. Persist `SetupStore.setupCompletedAt` (`spec/01_` §7).
2. **Open Terminal & sign in** → launches Terminal to the tool's `loginFlow`
   `interactiveCommand`. The card then shows the **polling** variant and
   **re-probes** (cheap re-check, then one smoke). The moment the probe passes,
   the card animates to **Ready** in place — **no app restart, no manual refresh,
   no app focus required** (`spec/01_` §5, §13). This green-flip is the core
   reward loop.
3. **Copy steps / copy command** → copy the mono command(s) to the clipboard;
   show a brief "copied" affordance.
4. **Use it anyway** → accept the resolved alias/function; persist a
   `loginShell` `Invocation` for that tool and re-probe. **Locate the binary…** →
   open an `NSOpenPanel` file picker; persist the chosen path as a `direct`/`shim`
   invocation. (`spec/01_` §4.2–4.3.)
5. **Open install page** → open the tool's docs URL in the default browser.
   **Re-scan / Re-try probe** → re-run detection for that tool (or all) and update
   the card + tally + health badge.
6. **What gets scanned?** → popover: *we only look for known CLI tools, locally,
   read-only.*
7. **Honesty rule (non-negotiable):** a card flips to **Ready** **only** when its
   smoke probe actually returned the token. Never infer ready from presence; show
   missing/unauthed/broken honestly with the real reason and the fix
   (`spec/01_` §5; AGENTS.md "a failed worker is shown failed, never faked").
8. **Tally + segment bar + health badge** recompute from real per-tool state and
   stay in sync — they read from the **one** shared persistence store, never a
   forked truth.

### Motion
- Card "ignite" on detect: glyph goes from monochrome → full brand color; state
  pills cross-fade. Calm easing (`ease-out`), 140–200ms.
- Roll-call stagger (the scan scene): cards resolve ~120–160ms apart. **Cosmetic
  only** — probe order is fastest-first.
- Blinking dots: 1.1s ease-in-out opacity pulse. The lamp "breathes," never a
  spinner-y bounce.
- **Respect Reduce Motion** everywhere: no stagger, no blink — states just set.

### Edge / never-spin
A probe over ~8s shows "still checking (unusual for this tool)" + a manual skip —
never an infinite spinner (`spec/01_` §4.1).

---

## State management

Model per `spec/01_` §2 and §5. Suggested SwiftUI shape:

```swift
// One canonical status — Doctor, Setup, and the health badge all read this.
enum WorkerSetupStatus {
    case notInstalled                          // no bin resolved anywhere
    case shimmedNeedsConfirm(Resolved)         // ambiguous alias/function
    case installedNotSignedIn(LoginFlow)       // detect ok, smoke = auth error
    case probeFailed(reason: String)           // detect ok, smoke failed otherwise
    case ready(version: String)                // detect ok AND smoke token returned
    // transient UI-only states layered on top while probing:
    case queued, detecting, reProbing
}

struct ToolCard: Identifiable {        // one per CLI/tool
    let id: String                     // driverId: "claude_code", "codex", …
    let displayName: String            // "Claude Code"
    let brandSlug: String?             // "anthropic" / "googlegemini" / "x" / nil(Codex)
    let route: String                  // "via claude-code"
    var version: String?               // "claude 1.2.4"
    var status: WorkerSetupStatus
    var seats: [Seat]                  // only meaningful when .ready
}

struct Seat: Identifiable {            // one per model on a ready tool
    let id: String
    let name: String                   // "Opus 4.8"
    let modelId: String                // "opus-4.8"
    let canSynthesize: Bool            // amber "synthesizer" chip
}
```

- **Derived view state:** `readyCount`, `totalCount`, `seatCount` for the tally;
  grouped + sorted arrays for the three roster sections; segment-bar cells.
- **Triggers:** Open-Terminal → poll loop (`detecting`/`reProbing` → `.ready` or
  back to `installedNotSignedIn`); Re-scan/Re-try → re-probe; Use-it-anyway/Locate
  → persist `Invocation` then re-probe.
- **Persistence:** per tool `{ invocation, status, version, lastProbeAt }` under
  `AllnighterPaths.config`; fast re-validate from cache on launch/wake, then a
  background smoke (`spec/01_` §9). `SetupStore.setupCompletedAt` gates first run
  (`spec/01_` §7).
- **Single source of truth:** Setup, Doctor, and the title-bar badge all consume
  the same `CLIDetector` output + persisted store. No second classification path.

---

## Design tokens (exact values)

All from `design/tokens/`. Dark-mode only. Map these into the app's existing
token layer (Asset Catalog colors / a `Color` extension / SwiftUI environment).

**Backgrounds**
| Token | Hex | Use |
| --- | --- | --- |
| `bg-void` | `#05060C` | page behind the window / command boxes |
| `bg-base` | `#090B13` | stage / window body |
| `bg-subtle` | `#0D101A` | sunken |
| `bg-surface` | `#111420` | title bar, footer, secondary buttons, muted cards |
| `bg-raised` | `#151822` | cards, popovers |
| `bg-hover` | `#1A1E2A` | row/control hover |
| `bg-active` | `#1F2331` | glyph tile, pressed/selected, muted pill |
| `bg-input` | `#13161F` | form fields |

**Text**
| Token | Hex |
| --- | --- |
| `text-primary` | `#E1E5F0` |
| `text-secondary` | `#AEB5C9` |
| `text-muted` | `#7E869E` |
| `text-faint` | `#555C74` |
| `text-on-amber` | `#1A1203` |

**Borders** (white-alpha): `border-subtle` `rgba(255,255,255,.06)` ·
`border-default` `.10` · `border-strong` `.16`.

**Amber (accent)** — the one warm signal, reserved for the primary action, the
mark, the live state, and the synthesizer chip:
| Token | Hex |
| --- | --- |
| `amber-500 / accent` | `#FFA630` |
| `accent-hover` (amber-400) | `#FFC169` |
| `accent-press` (amber-600) | `#F08D1C` |
| `accent-text` (amber-400) | `#FFC169`–`#FFD79E` range → use `#FFC169` |
| `accent-surface` | `rgba(255,166,48,.12)` |
| `accent-border` | `rgba(255,166,48,.32)` |

**Status hues** (muted, calm) + their 12%-alpha surfaces:
| Role | Solid | Surface |
| --- | --- | --- |
| green (ready/done) | `green-500 #3FD18B`, `green-400 #5BDBA0` | `rgba(63,209,139,.12)` |
| blue (detecting/running) | `blue-500 #5B9DFF`, `blue-400 #7DB2FF` | `rgba(91,157,255,.12)` |
| yellow (needs a step) | `yellow-500 #F5C84B`, `yellow-400 #FCD66A` | `rgba(245,200,75,.12)` |
| red (probe failed) | `red-500 #F76B6B`, `red-400 #FF8585` | `rgba(247,107,107,.12)` |

(The "needs a step" pills use the **yellow/amber** status hue — distinct from the
brand `accent` amber, which stays reserved for the Continue button, the mark, and
the synthesizer chip.)

**Focus ring:** `0 0 0 3px rgba(255,166,48,.40)` — always visible, never removed.

**Typography** (native SF Pro Text/Display + SF Mono; the app gets these free):
| Role | Size | Weight | Tracking / leading |
| --- | --- | --- | --- |
| Hero headline (display) | 30px | 800 | −0.022em / 1.08 |
| Card name | 14.5px | 700 | −0.01em |
| Seat name | 13px | 600 | — |
| Body / fix line | 13–13.5px | 400 | 1.5–1.58 |
| Tally | 14–15px | 700 (bold part) | — |
| Group label (eyebrow) | 10.5px | 700 | 0.11em, UPPERCASE |
| Pill / chip | 11.5px / 10.5px | 600 | — |
| Note | 11.5px | 400 | 1.45 |
| Mono (versions, commands, model ids, counts) | 11–12.5px | 400–500 | SF Mono |

Set numerals, versions, model ids, routes, counts, paths, and commands in the
**mono** face — always.

**Spacing / radii** (4px grid): glyph tile radius **10px**; card radius **lg
10px**; command box radius **md 8px**; pills/chips **pill**; window corner
**12px**. Control heights 24 / 30 / 36. Reading column **720px** max. Common gaps
seen here: 4, 7, 9, 10, 13, 14px.

**Shadows:** cards use `shadow-sm` (deep black, low opacity, generous blur) +
hairline border — never a heavy drop shadow. Window uses `shadow-xl`.

---

## Assets

- **Live mark** — `design/assets/allnighter-glyph-live.svg` (crescent + cursor
  block) and `allnighter-glyph.svg` (crescent only). Amber, animate the block
  only. Ship as a vector asset or redraw as a SwiftUI `Shape`. **Never recolor the
  amber.**
- **App icon** — `design/assets/allnighter-icon.svg` (midnight squircle + amber
  crescent + glow).
- **Brand glyphs for tools** — in the web prototype these come from Simple Icons
  (`anthropic`, `googlegemini`, `x`). In the macOS app, use the brand's own
  asset or a bundled monochrome glyph, tinted per the SetupCard spec. **Codex /
  ChatGPT has no Simple Icons glyph (OpenAI was removed for trademark)** — use a
  neutral **terminal** SF Symbol (`terminal`) instead. Do not fabricate an OpenAI
  mark.
- **UI icons** — the prototype uses Lucide-equivalents (`terminal`, `copy`,
  `folder`, `rotate-cw`, `external-link`, `info`, `alert-triangle`, `loader`,
  `sparkles`, `shield`, `arrow-right`, `settings-2`, `chevron-*`). Map each to the
  nearest **SF Symbol** in the app (e.g. `terminal`, `doc.on.doc`, `folder`,
  `arrow.clockwise`, `arrow.up.right.square`, `info.circle`,
  `exclamationmark.triangle`, `sparkles`, `lock.shield`, `arrow.right`, `gearshape`).

---

## Files in this bundle

```
design_handoff_first_run_setup/
├── README.md                      ← this file (self-sufficient)
├── design/
│   ├── setup.html                 ← open in a browser to view the screen
│   ├── setup.jsx                  ← prototype source: states, copy, CSS (most precise visual ref)
│   ├── doctor.html                ← Screen C: compact Council-health popover (open in a browser)
│   ├── doctor.jsx                 ← Doctor source — reuses SetupCard from setup.jsx
│   ├── _preview.jsx               ← DS component runtime (Button, Badge, StatusPill, …)
│   ├── shell.jsx                  ← DS primitives + icons + the live mark
│   ├── styles.css                 ← token entry point
│   ├── tokens/                    ← colors / typography / spacing / elevation / motion / fonts / base
│   └── assets/                    ← live mark, glyph, app icon (SVG)
└── spec/
    ├── 00_First_Run_Setup_Experience.md   ← the experience narrative (scenes, states, voice)
    └── 01_CLI_Detection_Auth_And_Panel.md ← the engineering contract (READ §2, §5, §7 first)
```

**Suggested build order:** (1) tokens → SwiftUI color/type layer · (2) `StatusPill`,
`Cmd`, `Button`, the live mark · (3) `SetupCard` with all `WorkerSetupStatus`
branches (verify each against Screen B) · (4) the window: title bar + hero + tally
+ roster groups + footer · (5) wire to `CLIDetector` and the poll/green-flip loop ·
(6) the first-run gate + persistence. Do **not** wire UI to live data until
detection is proven headless (`spec/01_` §11, Phases 1–2).
