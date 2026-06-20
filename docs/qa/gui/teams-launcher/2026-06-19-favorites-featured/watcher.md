# teams-launcher — layout-watcher verdict

Fixtures: teams-launcher
Command: bash scripts/gui_proof.sh teams-launcher

## VERDICT: PASS

P1 — broken (blocks): none
P2 — advisory:
- Footer favorite star sits snug next to the "1 agent · mutating" text; not overlapping.
- Filter pills lack a strong active-state indicator at this zoom (advisory).

Default Team card featured first (top-left) with "1 agent · mutating" and a filled amber
star in the card FOOTER — no collision with the top-right "Writes" badge. "+ Add team"
amber button + search bar render unclipped.
