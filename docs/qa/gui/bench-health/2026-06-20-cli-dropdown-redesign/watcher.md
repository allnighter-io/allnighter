# bench-health — layout-watcher verdict

Fixtures: doctor-open-mixed
Command: bash scripts/gui_proof.sh doctor-open-mixed

## VERDICT: PASS

P1 — broken (blocks): none
P2 — advisory: panel near the window right edge (tight, not clipped); a row partially
cut at the scroll boundary above the footer is normal scrolling.

CLI dropdown (CLI-setup redesign §2): shield + "CLIs" header, "N needs attention · M
ready · K models on" summary (attention amber), grouped NON-interactive CLI rows
(Needs attention → Ready → Dormant) sharing CLIStatusRow (glyph · name · reason/chips ·
status dot), footer = "Open CLI setup" BUTTON (matches the Models dropdown's button).
