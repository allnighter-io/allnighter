# home — layout-watcher verdict

Fixtures: projects-rail
Command: bash scripts/gui_proof.sh projects-rail

## VERDICT: PASS

P1 — broken (blocks): none
P2 — advisory:
- "Archive" footer label sits close to the sidebar lower edge (tight, not clipped).

Sidebar thread rows render in regular weight (no bold) — the active-row de-bold is in
effect; active is marked by the amber rail/background only.
