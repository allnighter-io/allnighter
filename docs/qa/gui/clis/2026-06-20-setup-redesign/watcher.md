# clis — layout-watcher verdict

Fixtures: studio-clis
Command: bash scripts/gui_proof.sh studio-clis

## VERDICT: PASS

P1 — broken (blocks): none
P2 — advisory: detail-panel proof block + census row sit close to the column bottoms
(scroll overflow, not clipped).

CLI setup page (CLI-setup redesign §1): 4-card stat strip → a single "● N CLIs · M
models available" summary line; muted SETUP eyebrow + new "choose which models are
available" subhead; left list regrouped Needs attention → Ready → Dormant on the shared
CLIStatusRow (glyph · name · chips/reason · dot, amber focus ring). Detail panel keeps
the working toggle/repair UI.
