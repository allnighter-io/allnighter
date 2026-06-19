# teams-launcher — layout-watcher verdict

Fixtures: teams-launcher
Command: bash scripts/gui_proof.sh teams-launcher

## VERDICT: PASS

Fix verified: the `Inbox | Teams` toggle no longer overlaps the macOS traffic-light
window controls. Added a 70px leading inset (`ALControl.trafficLightInset`); the dim
traffic-light dot cluster sits visibly to the left of the toggle with clear
horizontal separation, no overlap.

P1 — broken (blocks): none

P2 — advisory:
- Bottom row of cards clipped by the window edge — scroll-reveal (the grid is a
  `ScrollView`), not a break.
