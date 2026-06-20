# composer — layout-watcher verdict

Fixtures: compose-target-inline
Command: bash scripts/gui_proof.sh compose-target-inline

## VERDICT: PASS

DECLUTTERED (2026-06-20): composer bar has two chips — target "Auto · Opus 4.8 ⌄" + a
standalone effort chip "Med ⌄". Picker tabs renamed Model | Team (lightened quiet text
tabs, whole tab hit-tested via contentShape). Team tab = search + team rows with stars
only. CONFIRMED ABSENT: FAVORITES label, Customize… footer, Effort Low/Med/High row, all
helper/explainer text, craft chips. Auto moved to the Model tab. Unclipped, non-overlapping.

P1 — broken (blocks):
- none

P2 — advisory:
- Customize… footer + Effort row sit just below the panel's visual boundary. This is an
  artifact of the INLINE proof render (the real picker is a native NSPopover with its own
  chrome, uncapturable in-process); not a defect in the popover itself.
- "Tune this team's workers + skills." helper text is always visible beside Customize…
  (pre-existing footer copy, by design).
