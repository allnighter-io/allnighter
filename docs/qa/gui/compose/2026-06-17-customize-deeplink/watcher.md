# compose — layout-watcher verdict

Fixtures: compose-target-fanout, studio-teams-build
Command: bash scripts/gui_proof.sh compose-target-fanout
         bash scripts/gui_proof.sh studio-teams-build

Disinterested layout-watcher (rubric `.claude/agents/layout-watcher.md`), run via a
separate agent that did not write the code.

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- compose-target-fanout: "Customize…" footer row sits tight against the team row
  above and the EFFORT divider below — cramped but fully visible, not overlapping.
- studio-teams-build: right-pane footer buttons (Revert / Save as my team) float
  low with a large empty gap above — proportion drift, not breakage.

Missing captures: none

One-line summary: Both clean — the composer's "Customize…" footer (now wired,
copy "Tune this team's workers + skills.") and the effort row are fully visible in
the Send-to-team popover, and the Team Studio three-column editable detail pane is
intact.
