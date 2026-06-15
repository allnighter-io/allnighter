# Allnighter Design System — Production App Rules

**Status:** Canonical / Binding for the app UI
**Scope:** How the production app (`Apps/AllnighterMac/`, and the iOS companion)
consumes this design system. Brand, voice, color, type, and component specs live
in `readme.md` — read that first. This doc adds the rules that bind app code.

For *how to build* a surface (tiers, briefs, tests), see `docs/gui/GUI_Workflow.md`.
This doc is visual; that one is engineering governance.

## 1. Token Source Of Truth

The canonical design values live in this folder: `tokens/*.css` + `styles.css`
(and the generated `_ds_manifest.json`). The app mirrors them in **one** Swift
location — a single `Theme`/tokens source (asset-catalog colors + Swift
constants) — and views consume *named tokens*, never raw hex.

- Do not hard-code hex (`#FFA630`, `#0D101A`, …) in SwiftUI views. Reference the
  named token (`accent`, `bgBase`, `textPrimary`, …) that mirrors the CSS var.
- If a new value is needed, add it to the design-system tokens first, then to the
  Swift mirror, then document it here. The CSS tokens are the source; the Swift
  mirror is a consumer kept in sync.
- The generated bundle (`_ds_bundle.js`, `_ds_manifest.json`,
  `_adherence.oxlintrc.json`) is **derived** — regenerate it from the ikiro
  design tool; never hand-edit it. (It currently predates the `Select`, `Menu`,
  `Dialog`, and `Toast` components — regenerate before relying on it.)

## 2. Color & Surface Rules

- **Dark mode only.** Compose on the midnight ramp: `--bg-void` → `--bg-base` →
  `--bg-surface` → `--bg-raised` → `--bg-hover`/`--bg-active`. Never a light
  background, never a system-default window chrome that breaks the midnight field.
- **One warm signal — amber.** `--accent` (`#FFA630`) is reserved for: the single
  primary action on a surface, the live/"alive" state, the synthesizer/winner,
  and the mark. Everything else is ink + muted status. Do not introduce new
  accent colors or use amber for decoration.
- **Borders & elevation:** white-alpha hairlines (`--border-subtle`/`-default`/
  `-strong`), deep-black shadows, amber glow (`--glow-amber*`) only for "alive".

## 3. Status Color Mapping (bind, don't reinvent)

Run/worker status maps to fixed tokens — use these everywhere status appears:

| Status | Token |
| --- | --- |
| `queued` | `--status-queued` (muted ink) |
| `running` | `--status-running` (blue) + amber "alive" glow on the active worker |
| `done` | `--status-done` (green) |
| `failed` | `--status-failed` (red) |
| `timed_out` | `--status-timeout` (yellow) |

A failed worker renders failed; never recolor a failure as success.

## 4. Type & Density

- **Sans:** SF Pro natively (macOS) → Inter on web specimens. **Mono:** SF Mono →
  JetBrains Mono for model IDs, counts, run slugs, timestamps, and paths.
- **13px body density** (`--text-body`); use the type scale tokens (`--text-*`),
  not ad-hoc point sizes. Mono for any machine value.

## 5. Component Rules

- The components in `components/` are the **spec**. Map each to its SwiftUI
  control and keep names/behavior aligned: `Button` (primary/secondary/ghost/
  danger), `IconButton`, `Badge`, `Card`, `Input`/`Textarea`/`Switch`/`Select`,
  `Tabs`, `Menu`, `Dialog`, `Toast`, and the product pieces `StatusPill` +
  `WorkerChip`.
- Use the product components for their job: `StatusPill` for run/worker status,
  `WorkerChip` for a worker in the panel or live grid. Do not build one-off
  status chips that drift from the spec.
- Cards frame repeated items, answers, and modals — do not nest cards in cards.
- `Toast` is the calm "plan ready"/notification surface; keep it quiet.

## 6. Voice (UI copy)

Calm, plain-spoken, sentence case, verbs first. No emoji, no hype. Hide the
plumbing (panel / worker / council / plan — not worktree / subprocess).
Numbers are concrete and mono; a worker that failed is shown failed, never faked.
Full voice guidance: `readme.md`.
