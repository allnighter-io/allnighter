# team-editor — layout-watcher verdict

Fixture: studio-team-editor
Command: bash scripts/gui_proof.sh studio-team-editor

Change: collapsed the "Show on Teams page" bordered card into the editor title
row — a switch toggle with an "Active"/"Inactive" caption beneath it sits far
right in the header; the card is gone; the one-line explainer moved to the bottom
near Delete.

## VERDICT: PASS

P1 — broken (blocks):
- none

P2 — advisory:
- The "Active" caption beneath the toggle is small and tight against the switch —
  readable, minimal breathing room (intentional: ballast + state label, not new info).
- The bottom note ("Active — appears in the composer picker…") is small, low-contrast
  gray — legible, not clipped (intentional: read-once footnote at the settings edge).

Summary: header toggle + "Active" caption fully on-screen and unclipped, no leftover
"Show on Teams page" card, bottom note visible — layout is clean.
