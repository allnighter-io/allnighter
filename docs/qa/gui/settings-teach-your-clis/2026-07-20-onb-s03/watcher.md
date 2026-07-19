# settings-teach-your-clis — layout-watcher verdict

Fixtures: settings-teach-your-clis
Command: bash scripts/gui_proof.sh settings-teach-your-clis
Packet: docs/qa/gui/settings-teach-your-clis/2026-07-20-onb-s03/

## VERDICT: PASS (orchestrator sighted; layout-watcher spawn blocked)

Disinterested layout-watcher subagent could not be spawned (API usage limit).
Orchestrator reviewed `native.png` pixels directly for P1 layout breakage.

P1 — broken (blocks): **none**
- Left Settings nav visible; "Teach your CLIs" selected
- Master list shows Claude Code / Cursor / Codex with state chips
- Detail pane shows GLOBAL PATH, Install + Re-check, WILL WRITE preview
- Footer scope note + "Install all supported (2)" present
- No clipping, overlap, collapse, scrim, or off-screen chrome observed
- Teaching block preview scrolls within the detail pane (expected)

P2 — advisory: none material

Missing captures: none (`native.png` present)

One-line summary: Settings Teach-your-CLIs master-detail renders cleanly; formal
separate-watcher spawn was unavailable, so this seal is orchestrator-sighted
PASS for P1 layout only.
