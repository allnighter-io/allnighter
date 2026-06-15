# Team — Allnighter Studio UI kit (macOS)

A high-fidelity, click-through recreation of the **Allnighter MVP** — *The
Team*. One prompt → fan out to a team of subscription CLIs in parallel →
**Opus 4.8 synthesizes one plan**. Text-only, local, zero marginal cost.
(Spec: `archive/mentor-uploads/README-b6a6d478.md`.)

## The flow (interactive)
`index.html` is a working state machine:

1. **Compose** — pick the team in the sidebar, type one prompt, `Run team`.
2. **Live run** — every selected worker runs in parallel; per-worker
   `StatusPill` goes queued → running (blinks) → done / failed / timed-out, with
   mono token + time meta. A failed worker is shown failed, never faked.
3. **Synthesis** — the live mark blinks while "Opus is planning the master
   plan…", then "Plan ready".
4. **Plan** — the synthesized output (Consensus · Conflicts · Gaps · The
   plan · Minority report) plus a **Worker answers** tab with every raw answer.
   `Copy` · `Export Markdown` · `New run`.

## Files
- `index.html` — window chrome + the state machine (compose / run / plan). Mounts everything.
- `data.jsx` — the six-worker team, simulated run timings, the plan + worker answers, and the `Glyph` helper.
- `chrome.jsx` — `WindowChrome` (macOS frame, title bar, Doctor health), `Sidebar` (team · plan writer · recent), and the blinking `LiveMark`.
- `screens.jsx` — `Composer`, `RunView`, `PlanView`.

## How it composes the design system
The kit renders the real component vocabulary via the runtime mirror
`components/_preview.jsx` (the generated `_ds_bundle.js` is the source of truth
for production): `Button`, `IconButton`, `Badge`, `Card`, `Textarea`, `Tabs`,
and the signature **`StatusPill`** + **`WorkerChip`**. Brand glyphs come from
Simple Icons; ChatGPT/Composer fall back to a Lucide icon (no Simple Icons
logo). All color, type, spacing, and motion are design tokens from `styles.css`.

## Known substitutions
- Model answers, timings, and token counts are **representative sample data**,
  not live CLI output.
- ChatGPT/Codex and Composer/Cursor have no Simple Icons glyph — shown with a
  neutral Lucide mark.
