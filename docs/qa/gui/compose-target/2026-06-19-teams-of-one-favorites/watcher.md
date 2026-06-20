# compose-target — layout-watcher verdict

Fixtures: compose-target-chat
Command: bash scripts/gui_proof.sh compose-target-chat

## VERDICT: PASS

P1 — broken (blocks): none
P2 — advisory:
- "Customize…" footer and the EFFORT section sit close together (minimal separation), nothing clipped/overlapping.
- The customize hint text floats over the Customize row region; low-contrast but not overlapping anything critical.

The route popover now shows a [Team | Worker] tab (one form at a time, height-bounded),
Default Team amber-pinned at top with star+checkmark, scrollable team list with stars,
and a visible EFFORT row — no more crammed/overflowing team+model stack.
