# composer — layout-watcher verdict

Fixtures: compose-target-inline
Command: bash scripts/gui_proof.sh compose-target-inline

## VERDICT: PASS

Target popover renders cleanly with the (invisible) AppKit key catcher in place: top row
highlighted by default, hover moves it, ↑/↓/⏎/esc handled via a local NSEvent monitor
(doesn't steal search-field focus). Effort chip present, no duplicate effort in the chip.
The composer NSTextView is now a ComposerTextView subclass that routes Cmd+V/C/X/A/Z
itself (paste no longer depends on a main-menu Edit menu). No clipping/overlap.

P1 — broken (blocks): none
P2 — advisory: paste + key behavior are runtime — verify live.
