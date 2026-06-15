# GUI Workflow

**Status:** Canonical / Agent Router
**Scope:** Decides which GUI docs an agent must read before UI work on the
native macOS (and iOS companion) app.

## 1. Purpose

Route GUI work by risk. A tiny paint change should not require reading every GUI
doc; a new surface that renders run state, dispatch, or quota does.

**Folder split (no overlap):**

- `docs/design-system/` owns **visual design** — brand, voice, color, type,
  tokens, components, logo/icon, and the binding production rules
  (`production.md`). It is the visual SSOT.
- `docs/gui/` owns **GUI engineering governance** — this workflow, invariants,
  surface architecture, and surface briefs. It says *how to build* UI against
  the design system and the core contracts.
- `docs/mvp/` + `docs/phases/` own **what to build and when**.

Do not add visual-design content under `docs/gui/`, and do not add build
sequencing under `docs/design-system/`.

## 2. Tier Routing

| Tier | Work type | Required reads |
| --- | --- | --- |
| A | Tiny paint change, copy tweak, icon swap | `docs/design-system/production.md` + the target view |
| B | Component or layout change inside an existing surface | `docs/gui/0.GUI-Tech-Stack.md`, `docs/design-system/production.md` (+ `readme.md` for brand questions), `docs/gui/1.GUI-Invariants.md`, the surface brief if present |
| C | New or materially changed surface (window, panel, sheet, view) | Tier B + `docs/gui/2.GUI-Surface-Architecture.md` + a surface brief (`docs/gui/surfaces/`) |
| D | UI touching run/dispatch state, quota/billing, secrets/Keychain, or pairing | Tier C + `docs/workflows/SSOT_Feature_Workflow.md` + the owning `docs/mvp/` or `RB*` contract |

When unsure, choose the higher tier.

## 3. Escalation Triggers

Escalate to Tier D if the work touches:

- starting, killing, or routing agent runs / workers;
- quota harvesting, billing, or entitlement display;
- secrets, API keys, or Keychain;
- Tailscale pairing or device auth;
- master-plan / synthesis output presented as truth;
- anything that destroys a lane, worktree, or session.

## 4. Non-Negotiables

- **UI does not own domain truth.** Views bind to `AllnighterCore` models and
  live run state. Never fabricate GUI-only fields, statuses, worker names, or
  option lists; back them with the owning contract.
- **Dark mode only.** Build on the midnight surfaces
  (`--bg-base`/`-surface`/`-raised`); never a light background.
- **One warm signal.** Amber (`--accent`, `#FFA630`) is reserved for the single
  primary action, the live/"alive" state, the synthesizer/winner, and the mark.
  Status hues stay muted. Do not introduce new accent colors.
- **Never fake state.** A failed worker is shown failed; a timeout is shown
  timed out. Numbers are concrete and mono. No fabricated progress.
- **Hide the plumbing.** Speak panel / worker / council / master plan — never
  worktree / subprocess / branch in user-facing copy.
- **Every critical surface has loading, empty, error, running, and done states.**
- **Voice:** calm, plain-spoken, sentence case, verbs first, no emoji, no hype
  (see `docs/design-system/readme.md`).

## 5. Surface Brief Rule

A surface that handles nuanced run, dispatch, quota, secret, or pairing behavior
needs a `brief.md` before implementation. Use the template in
`docs/gui/surfaces/README.md`.

## 6. Testing Rule

Use the lightest test that protects the behavior:

- pure presenter/formatter logic → Swift unit tests;
- view state machines (queued → running → done/failed/timeout) → state-model
  unit tests, or snapshot/inspection tests where practical;
- run-state, dispatch, secrets, or quota rules → targeted behavioral tests.

Do not substitute screenshots for behavioral tests on run-state, dispatch,
secrets, or billing.

## 7. Related Docs

- Stack: `docs/gui/0.GUI-Tech-Stack.md`
- Invariants: `docs/gui/1.GUI-Invariants.md`
- Surface architecture: `docs/gui/2.GUI-Surface-Architecture.md`
- Surface briefs: `docs/gui/surfaces/README.md`
- Design system (brand, tokens, components): `docs/design-system/readme.md`
- Design system production rules: `docs/design-system/production.md`
- Feature workflow: `docs/workflows/SSOT_Feature_Workflow.md`
