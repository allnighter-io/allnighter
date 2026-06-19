# compose-target — layout-watcher verdict

Fixtures: compose-target-send-to-team
Command: bash scripts/gui_proof.sh compose-target-send-to-team

## VERDICT: PASS

Change: `ComposeLane` gained a 4th case `.signal`, so the composer's send-to-team
target popover now shows four lane tabs (Code · Design · Copy · Signal) — Signal is
a first-class team craft and routable from the composer.

All four lane tabs render on a single row without clipping/wrapping; the popover is
solid (no bleed-through), properly anchored above the composer, nothing off-screen.

P1 — broken (blocks): none
P2 — advisory:
- Lane-tab row padding is slightly tight; "Signal" has minimal clearance to the
  popover's right edge (not clipped). Worth watching if labels grow.
