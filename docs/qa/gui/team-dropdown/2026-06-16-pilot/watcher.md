# Team dropdown — layout-watcher pilot

Surface: Team dropdown ("Your bench" popover)
Fixture: `team-open-mixed` (6 models, mixed health, dropdown deep-linked open)
Command: `bash scripts/gui_proof.sh team-open-mixed`
Render: `native.png`

## Before fix — VERDICT: FAIL

P1 — broken (blocks):
- Popover clipped at the TOP by the window edge; "Your bench" header and top rows
  sliced off (only a partial row fragment showed above "Sonnet 4.6").
- Popover floated detached from its Team anchor — opened up/clipped instead of
  hanging down.

Root cause: the panel was a sibling in `TeamControlView`'s `VStack` with
`.fixedSize(vertical:)`, and the title bar's centered `ZStack` made the tall open
panel overflow upward past the window's top edge.

## Fix

Moved the panel out of the title bar into a top-level `RootView` overlay below the
title bar (the proven `showDoctor` pattern). `TeamControlView` now renders only
the pill.

## After fix — VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- "Grok Build" / "Gemini (Antigravity)" issue-badge labels truncate ("Not sig…",
  "Probe f…") in the rows — contained, not clipped; ugly given available width.
  Follow-up polish, non-blocking.

The dropdown hangs correctly from top-right below the title bar, fully on-screen,
header/list/footer stacked properly, Repair links aligned to broken rows.
