# First-Run Setup — The Experience ("Find your team")

**Status:** BUILT (lean). Designers/agents follow this doc — it is the spec.
**Surface:** A full-window, first-launch page on macOS (the same window the team
runs in). Re-runnable later from the team dropdown / health badge.
**Owner:** Founder / GUI
**Created:** 2026-06-15 · **Lean rewrite:** 2026-06-16
**Visual SSOT:** `docs/design-system/` · **Build governance:** `docs/gui/GUI_Workflow.md`

---

## Direction change (2026-06-16) — the cinematic flow is cut

The original version of this doc specified a 6-scene cinematic flow: a breathing
hero, a staggered "roll-call" reveal where tools light up one by one, a
celebration glow-pulse, and separate "confirm your team" + "launch" scenes.
**That choreography is deleted.** Founder call: it is bloat — it adds build and
maintenance cost, more GUI-proof surface, and it *slows down* first run
(auto-advancing scenes = waiting) for zero functional gain.

**The wow was never motion.** It is **recognition** ("it found everything I
already have"), **speed** (scan → fix the reds → working, under a minute), and
**trust** (nothing is ever faked). A solo builder opened the app to *work* —
give them the team on the floor, not a show.

What replaces it is the lean onboarding below: a single honest **CLI setup page**
that shows what we support vs. what we found, fixes the gaps in place, and lets
the user into the app. It is built.

---

## 1. Why this exists (the moment to win)

A solo builder already pays for Claude Code, Codex, Grok, Gemini/Antigravity…
The thesis is **"you already pay for the team — Allnighter makes it show up to
work."** First-run is where the team shows up. It is the first proof of the
promise.

### The anti-spec (never ship this again)
- Cold open into an empty run surface with a 1-worker team.
- A `0/1 healthy` badge with no explanation and no path forward.
- The user has 4 CLIs installed; the app shows one, broken, with zero guidance.

The bar: launch → "my whole team is ready" with **one scan and zero typing** in
the common case.

> **Source vs model vs worker:** the roster is **one card per CLI/tool source**
> (Claude Code, Codex, Grok, Antigravity), not one per model. Detection is per
> source; ready sources populate the bench with models (Opus, Sonnet…). Tallies
> and the health badge are source-level. See `01_…` §2.

---

## 2. The feeling (values, not choreography)

Calm, honest, fast. Dark, amber-on-midnight. The values survive the cut:

- **Recognition over animation.** The reward is seeing your real tools found and
  ready — not a reveal sequence. No staggered ignite, no celebration pulse.
- **Honest always.** A card is `ready` only when its probe actually passed.
  Missing / unauthed / broken show the real reason and the fix. Never faked.
- **Speed is the wow.** Fewer steps, no gated scenes, no auto-advance. The fastest
  path from launch to a working team wins.

Voice: sentence case, verbs first, no hype, no emoji. Versions/paths/commands in
mono. "Found Claude Code 1.2.4." "Grok needs a login." Never "AI-powered."

The **one** motion worth keeping: **re-probe-in-place** — a card flips to green
the moment a fix passes. That is not engineered animation; it is honest state
catching up to reality, and it is the real reward loop.

---

## 3. The flow (lean — what's built)

One page, no scenes.

1. **First-run gate.** On launch, if setup was never completed
   (`AppModel.hasCompletedSetup == false`), the app opens the **CLI setup page**
   automatically. It is **process-quiet** (Launch Authority TCC hotfix): it
   renders cached/unknown state and spawns nothing until the user acts.
2. **The roster (`TeamReadinessView`).** All supported CLIs in three groups:
   - **Ready** — green, version shown; the models that source powers.
   - **Needs a step** — found but not signed in / alias-or-path ambiguous /
     probe-failed; each carries its exact fix.
   - **Add a CLI** — supported but not installed; install hint + docs.
   A header tally states it plainly: *we support N, found M*.
3. **Scan / re-check.** A single **"Re-check all"** runs the live probe
   (interactive `-lic` so the user's real PATH is seen; one-time TCC prompt is
   acceptable here — explicit intent). Detection also auto-resolves common
   install dirs + Spotlight, so most tools resolve with no further action.
4. **Fix in place.** The sticky repair panel (`BenchRepairPanel`) gives the
   contextual action per state — open sign-in in Terminal, locate the binary,
   use-anyway, re-try, open install page — and the card **re-probes and flips
   green in place** when it passes. No restart, no app refocus.
5. **Agent fallback (last resort, opt-in).** Only when a supported CLI is still
   not found AND a working agent exists: a framed "Search my machine" card runs
   a read-only agent census (~30–60s, honest about the time, verifies every path
   before trusting it). Onboarding only — never the dropdown.
6. **Into the app.** Closing the page marks setup seen (`markSetupCompleted`) and
   drops the user into the normal compose surface with the bench already seated
   from ready models. The team-confirm + plan-writer choices live in the normal
   compose UI, **not** a separate gated scene.

**Non-trapping (founder call, 2026-06-16):** the user can leave setup at any time,
even with 0 ready. We never wall a user out of their own app. If gaps remain, the
team dropdown shows an **"Open CLI setup"** entry to return, and the title-bar
health badge stays honest. We do **not** hard-gate the app behind "≥1 ready."

---

## 4. States to design (every card, every scene removed — states remain)

Each source card still needs all of:
`unknown/not-checked` · `detecting` · `ready (version)` · `needs-login` ·
`not-installed` · `alias/needs-path` · `probe-failed (reason)` · `re-probing`.

Page-level: `cold/unprobed (cache only)` · `partial (some ready)` · `all-ready` ·
`none-found` · `a CLI hung` ("taking a while…", never spin forever).

The **none-found** state matters: a machine with zero CLIs should still feel
hopeful — "here are the fastest to install," each a one-liner, plus the agent
"Search my machine" fallback.

---

## 5. Visual direction

- **Tokens/components:** `docs/design-system/` — midnight surfaces, amber as the
  single warm signal, `StatusPill`, model/worker chips, `Badge`, `Button`. Mono
  for versions, paths, commands.
- **Real brand glyphs** — `anthropic`, `googlegemini`, `x`; ChatGPT/Codex uses a
  neutral terminal chip (Simple Icons removed OpenAI). Shared via
  `DriverBrandGlyph`.
- **No roll-call motion, no glyph ignite, no celebration pulse.** The only state
  transition is a card re-probing to green in place. Respect reduced-motion.
- Density and chrome match the team-run window so setup feels like the same
  product, not an installer.

---

## 6. Re-entry & relationship to Doctor

Setup is re-runnable. The title-bar **health badge** opens a compact roster
(`BenchHealthPopover`) with the same groups + an **"Open CLI setup"** footer to
the full page. The team dropdown shows **"Open CLI setup"** only when something
is not ready. Setup, the popover, and the badge all read one source of truth
(`AppModel.toolStatuses`); see `01_…`.

---

## 7. Success criteria

- **One scan, zero typing** in the common case (CLIs installed + signed in) →
  team ready.
- **% of installed CLIs auto-detected approaches 100%** — including `.zshrc`-PATH,
  aliases, shims, and version-manager installs (interactive resolve + common
  dirs + Spotlight; agent census only for the genuine long tail).
- An unauthed CLI is fixed **without restarting the app** — sign-in completes in
  Terminal, the card re-probes and flips green in place.
- Time from launch → first team run under a minute.
- Emotional read: "it found my whole team," not "nice animation."

---

## 8. Design decisions (current)

1. **No cinematic scenes.** No hero cold-open, no roll-call, no celebration, no
   separate confirm/launch scenes. First-run = land on the CLI setup page.
2. **No auto-scan on the auto-opened page.** Process-quiet: render cache; the
   probe runs only on the explicit "Re-check all" click (one-time TCC prompt OK).
3. **Non-trapping.** Never block the app behind setup; always offer a way back in.
4. **"Add a tool you don't have"** lives inline on `not-installed` cards. No
   separate "browse tools" step.
5. **Agent census is onboarding-only**, gated on a real gap + a working agent,
   framed with its cost; never in the dropdown.
6. **Roster = shipped drivers only** (Claude Code, Codex, Grok, Antigravity). No
   ghost cards for tools without a manifest.

---

## 9. Built surfaces & proof

- `TeamReadinessView` (full CLI setup page), `BenchRepairPanel` (contextual fix),
  `BenchHealthPopover` / `BenchHealthBadge` (compact roster), `BenchDropdownPanel`
  (team dropdown footer state-driven to "Open CLI setup").
- First-run gating: `AppModel.hasCompletedSetup` / `markSetupCompleted`
  (persisted via `SetupStore`); launch opens the page when unset.
- Detection: `CLIDetector` interactive `-lic` at explicit setup, common-bin-dirs
  + Spotlight fallback, gap detector `AppModel.unresolvedSupported`. See `01_…`
  and `Launch_Authority_TCC_Hotfix.md` (rule 8).
- Dev review: the DEBUG **GUI routes** sheet has a **First-run onboarding** route
  plus CLI-setup page/popover and mixed-health scenarios.
- Visual proof packets under `docs/qa/gui/setup/` (layout-watcher PASS).
