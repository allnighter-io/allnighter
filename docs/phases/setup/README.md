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
  (Reinforces the AGENTS.md law and [[allnighter-working-prefs]].)
- **Real detection, real auth, real versions.** No placeholder roster.

Status: **Spec / design-pending.** Created 2026-06-15.
