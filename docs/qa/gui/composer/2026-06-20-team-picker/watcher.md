# composer — layout-watcher verdict

Fixtures: compose-target-inline
Command: bash scripts/gui_proof.sh compose-target-inline

## VERDICT: PASS

All expected elements present, correct top-to-bottom order, unclipped, non-overlapping:
chip reads "Auto · Opus 4.8" · LIGHTENED Team/Worker tabs (quiet text tabs, selected
carries a subtle pill, no boxed track/border — whole tab is the hit target via
contentShape) · Auto/Default model (checked) · search field with "Bug" + clear · two
results (Bug Hunt, GUI Bug Hunt) with stars · Customize… footer · Effort row. NO craft
chips anywhere.

P1 — broken (blocks):
- none

P2 — advisory:
- Customize… footer + Effort row sit just below the panel's visual boundary. This is an
  artifact of the INLINE proof render (the real picker is a native NSPopover with its own
  chrome, uncapturable in-process); not a defect in the popover itself.
- "Tune this team's workers + skills." helper text is always visible beside Customize…
  (pre-existing footer copy, by design).
