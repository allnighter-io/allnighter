# setup — layout-watcher verdict (Track B state-driven dropdown)

Fixtures: team-open-mixed · doctor-open-mixed · readiness-mixed
Command: `bash scripts/gui_proof.sh <fixture>` (one per surface)
Renders: native-team-open-mixed.png · native-doctor-open-mixed.png · native-readiness-mixed.png

Change under review (Track B): the bench-dropdown footer is now state-driven —
primary "Set up tools" (opens the CLI setup page) when something needs setup,
a quiet ghost "Re-check tools" when all-ready; the agent-census "Find the rest"
button is removed from the dropdown. Sealed alongside the current readiness +
bench-health surfaces (integrated founder WIP).

## VERDICT: PASS

Disinterested layout-watcher (separate agent, protocol from
`.claude/agents/layout-watcher.md`) on all three current renders.

team (dropdown):
- P1: none
- P2: "Add models & build teams in settings." caption a touch tight against the
  popover edge but fully contained.

readiness (full CLI setup page):
- P1: none — header, 4 stat cards, grouped roster (READY / NEEDS A STEP / ADD A
  CLI), and the sticky right repair panel all aligned and on-screen.
- P2: right-panel "LAST PROOF" log clips at the window's bottom edge (expected
  scroll fold).

doctor (compact health popover):
- P1: none — anchored top-right, grouped rows stacked cleanly, "Open CLI setup"
  footer intact.
- P2: none.

One-line summary: All three clean and correctly stacked — the team footer shows
"Set up tools" + "Manage team" with no census/"Find the rest" button; nothing
clipped, overlapping, or detached.
