# First-Run Setup — "Assemble your team"

The first thing a new user sees. Today it's the worst thing they see: an empty
team with **0/1 healthy** and no idea why. This folder specs the replacement —
a first-run experience that finds the AI CLIs the user already has, gets them
authenticated, and assembles the Bench **for** them. It should feel like magic,
not configuration.

> The promise of Allnighter is "you already pay for the team — Allnighter makes
> it show up to work." Setup is where the team shows up. It is the first proof of
> that promise, so it has to land.

## Docs

- **[00_First_Run_Setup_Experience.md](00_First_Run_Setup_Experience.md)** —
  the WOW experience: the narrative, scene-by-scene screen specs, states, copy,
  and visual direction. **This is the doc the designers mock from.**
- **[01_CLI_Detection_Auth_And_Bench.md](01_CLI_Detection_Auth_And_Bench.md)** —
  the engineering contract: how detection actually works (the fix for the
  "works in my terminal but the app sees nothing" gap), the CLI registry, auth
  probing, auto-building the Bench/default Team, persistence, and the honesty
  rules.

## Ground rules (both docs obey these)

- **Dark mode only, amber on midnight** — built on `docs/design-system/` tokens
  and components. Build governance: `docs/gui/GUI_Workflow.md`.
- **Never fake state.** A CLI is shown ready only when its probe actually passed;
  missing/unauthed/broken are shown honestly with the real reason and the fix.
  (Reinforces the AGENTS.md "a failed worker is shown failed, never faked" law.)
- **Real detection, real auth, real versions.** No placeholder roster — the v1
  roster is **shipped drivers only** (no ghost cards for tools we can't drive yet).
- **Source vs model vs worker.** Detection is per **CLI/tool source**; the Bench
  is per **model**; the default Team is made of **workers** (`model + skill`).
  Tallies and the badge are source-level. See `01_…` §2.

## Prerequisite bug (found 2026-06-15)

Doctor confirmed the immediate cause of "0/1 healthy" is **not** PATH or auth — it's
a **packaging bug**: the `Resources/Drivers` manifests aren't shipped as a `Drivers/`
folder in the app bundle, so the driver registry loads empty and the legacy
default team falls back to one hardcoded worker. Detection never even runs. Details + fix
direction:
`01_CLI_Detection_Auth_And_Bench.md` §Cause 0.

**Phase 0 fix shipped (2026-06-15):** `AppConfig` loads manifests from the bundle
resource root (subdir-free), falls back to embedded `DefaultConfig` (not a fake
one-worker team), and `BuiltBundleConfigTests` gates the built `.app`. Doctor now
probes real CLIs — outcomes depend on what's installed/signed-in on the machine.

## Build order (no shortcuts, but sequenced)

Prove detection on a real machine before building the WOW UI (full detail in
`01_…` §11):

| Phase | Scope | Status |
| --- | --- | --- |
| **0** | Packaging fix + `DefaultConfig` safety net + built-bundle test → default models/team load, Doctor shows real reasons | **Done** (2026-06-15) |
| **1** | Detection engine — `CLIDetector` + hardened login-shell resolve + cached invocation + 5-state status. Prove headless with `alln doctor` first. | Not started |
| **2** | Wire Doctor + health badge to the detector → real "4/4 tools ready" | Not started |
| **3** | Setup UI (Experience Scenes 1–6); Doctor becomes the compact roster | **Blocked on designer mocks** (`00_…`) |
| **4** | Auto-build the Bench/default Team from ready sources/models | Not started |

**Next:** Phase 1 (engine, headless-first). Do not build Setup UI until designer
delivers mocks from `00_First_Run_Setup_Experience.md`.

Created 2026-06-15 · Phase 0 implemented 2026-06-15.
