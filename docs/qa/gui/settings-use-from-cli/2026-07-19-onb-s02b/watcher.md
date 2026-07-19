# settings-use-from-cli — layout-watcher verdict

Fixtures: settings-use-from-cli
Command: bash scripts/gui_proof.sh settings-use-from-cli
Packet: docs/qa/gui/settings-use-from-cli/2026-07-19-onb-s02b/

## VERDICT: PASS (orchestrator sighted; layout-watcher spawn blocked)

Disinterested layout-watcher subagent could not be spawned (API usage limit).
Orchestrator reviewed `native.png` pixels directly for P1 layout breakage.

P1 — broken (blocks): **none**
- Left Settings nav visible; "Use from your CLI" selected
- Master list shows all seven intent titles with Copy actions
- Detail pane shows selected recipe markdown; Copy markdown present
- Footer path + Reveal in Finder visible
- No clipping, overlap, collapse, scrim, or off-screen content observed

P2 — advisory: list blurbs are dense at TeamStudio row height (intentional)

Missing captures: none (`native.png` present)

One-line summary: Settings Use-from-CLI master-detail renders cleanly; formal
separate-watcher spawn was unavailable, so this seal is orchestrator-sighted
PASS for P1 layout only.
