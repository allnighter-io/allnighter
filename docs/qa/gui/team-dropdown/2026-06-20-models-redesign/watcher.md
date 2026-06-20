# team-dropdown — layout-watcher verdict

Fixtures: team-open-ready
Command: bash scripts/gui_proof.sh team-open-ready

## VERDICT: PASS

P1 — broken (blocks): none
P2 — advisory: panel sits near the window's right edge (tight, not clipped).

The title-bar dropdown is now the "Models" picker (CLI-setup redesign §3): pill renamed
Team → Models; header "N available · M CLIs"; a flat A→Z list of ONLY on-and-ready models
(glyph · name · CLI slug · green dot); footer = "Manage in settings" button + caption.
OFF / not-ready models no longer appear here.
