# First-Run Setup — "Assemble your council"

The first thing a new user sees. Today it's the worst thing they see: an empty
panel with **0/1 healthy** and no idea why. This folder specs the replacement —
a first-run experience that finds the AI CLIs the user already has, gets them
authenticated, and assembles the council **for** them. It should feel like magic,
not configuration.

> The promise of Allnighter is "you already pay for the team — Allnighter makes
> it show up to work." Setup is where the team shows up. It is the first proof of
> that promise, so it has to land.

## Docs

- **[00_First_Run_Setup_Experience.md](00_First_Run_Setup_Experience.md)** —
  the WOW experience: the narrative, scene-by-scene screen specs, states, copy,
  and visual direction. **This is the doc the designers mock from.**
- **[01_CLI_Detection_Auth_And_Panel.md](01_CLI_Detection_Auth_And_Panel.md)** —
  the engineering contract: how detection actually works (the fix for the
  "works in my terminal but the app sees nothing" gap), the CLI registry, auth
  probing, auto-building the panel, persistence, and the honesty rules.

## Ground rules (both docs obey these)

- **Dark mode only, amber on midnight** — built on `docs/design-system/` tokens
  and components. Build governance: `docs/gui/GUI_Workflow.md`.
- **Never fake state.** A CLI is shown ready only when its probe actually passed;
  missing/unauthed/broken are shown honestly with the real reason and the fix.
  (Reinforces the AGENTS.md "a failed worker is shown failed, never faked" law.)
- **Real detection, real auth, real versions.** No placeholder roster — the v1
  roster is **shipped drivers only** (no ghost cards for tools we can't drive yet).
- **Tool vs seat.** Detection is per **tool/CLI**; the panel is per **model seat**
  (two seats — Opus, Sonnet — run on the one `claude_code` tool). Tallies and the
  badge are tool-level. See `01_…` §2.

## Prerequisite bug (found 2026-06-15)

Doctor confirmed the immediate cause of "0/1 healthy" is **not** PATH or auth — it's
a **packaging bug**: the `Resources/Drivers` manifests aren't shipped as a `Drivers/`
folder in the app bundle, so the driver registry loads empty and the panel falls
back to one hardcoded worker. Detection never even runs. Details + fix direction:
`01_CLI_Detection_Auth_And_Panel.md` §Cause 0. Fix that first; the Setup experience
layers on top.

## Build order (no shortcuts, but sequenced)

Prove detection on a real machine before building the WOW UI (full detail in
`01_…` §11):

0. **Packaging fix** + embedded `DefaultConfig` safety net + built-bundle test →
   6 workers appear, Doctor shows real reasons (today's blocker).
1. **Detection engine** — `CLIDetector` + hardened login-shell resolve + cached
   invocation + 5-state status. Prove headless (`allnighter detect`) first.
2. **Wire Doctor + health badge** to the detector → real "4/4 tools ready".
3. **Setup UI** (Experience Scenes 1–6); Doctor becomes the compact roster.
4. **Auto-build the panel** from ready tools.

Status: **Specs finalized (mentor review folded in). No code yet** — Phase 0
(packaging) is the agreed first step when build starts. Created 2026-06-15.
