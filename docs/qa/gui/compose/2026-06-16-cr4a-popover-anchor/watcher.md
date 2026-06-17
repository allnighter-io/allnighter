# compose — layout-watcher verdict

Fixtures: compose-mode-menu compose-target-chat compose-target-fanout
Command: bash scripts/gui_proof.sh compose-mode-menu

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- Click-outside dismiss is composer-local (not full-window scrim) — acceptable for v1.

Mode menu and target popovers now anchor left-aligned, 9px above their trigger pills (hm-popwrap), matching Cursor-style placement.
