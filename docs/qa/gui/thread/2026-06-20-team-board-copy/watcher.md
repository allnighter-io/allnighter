# thread — layout-watcher verdict
Fixtures: thread-team-board
Command: bash scripts/gui_proof.sh thread-team-board

## VERDICT: PASS
Every team-board answer (RECOMMENDATION synthesis + each worker answer) now has an
always-visible "Copy" button at the bottom-right (was missing entirely; the others were
hover-only). Code-red: agent answers can be copied to the clipboard. No clipping/overlap.

P1 — broken: none
P2 — advisory: text selection in the markdown renderer is still unreliable — the Copy
button is the dependable path.
