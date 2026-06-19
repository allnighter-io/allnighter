# teams-launcher — layout-watcher verdict

Fixtures: teams-launcher
Command: bash scripts/gui_proof.sh teams-launcher

## VERDICT: PASS

Surface: the `Inbox | Teams` top-bar toggle (Teams active) + the Send-to-team
launcher scaffold showing the real `TeamCard` roster (Code/Design/Copy/Signal),
each card = family · name · `returns <outputKind>` · worker count · posture.

P1 — broken (blocks): none

P2 — advisory:
- Bottom row of cards clipped by the window's lower edge — scroll-reveal (the grid
  is a `ScrollView`), not a break; cards below the fold are reachable by scrolling.
- The far-left moon/crescent is the pre-existing dark-mode appearance control, not
  the Inbox tab icon (Inbox uses SF Symbol `tray`).

Intentionally absent in this G-T0 scaffold (land in G-T1, not defects): deduped
model-logo lineups, bench strip, favorite stars, last-run footers, the bottom
action bar, and the Recent/Curated/Browse lens tabs.
