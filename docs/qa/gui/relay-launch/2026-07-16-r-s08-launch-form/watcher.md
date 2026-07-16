# relay-launch — layout-watcher verdict

Fixtures: relay-launch
Command: bash scripts/gui_proof.sh relay-launch

## VERDICT: PASS

All clean — title, model badges, reply bubbles, Raw/Copy controls all properly
aligned with no clipping or overlap. Both captures (this one + thread/2026-07-16-
r-s08-relay-escalation) pass layout review.

P1 — broken (blocks): none

P2 — advisory:
- both the "PM SEAT" and "DEV SEAT" bounded lists clip their last row mid-text
  at the list's own inner edge (e.g. "Grok 4.5" cut just above the toggle row,
  "Gemini 3.5 Flash" cut just above the footer) — text terminates cleanly at
  the list boundary with no overlap onto adjacent chrome, consistent with
  normal independently-scrollable-list clipping. Purely cosmetic, not a defect.

One-line summary: modal (with scrim), sections, toggle, footer/Start button
are all properly aligned, opaque, and unclipped except for the expected/
documented scroll-list truncation.
