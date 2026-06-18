# studio — layout-watcher verdict

Fixtures: studio-teams-build
Command: bash scripts/gui_proof.sh studio-teams-build

Disinterested layout-watcher (rubric `.claude/agents/layout-watcher.md`), run via a
separate agent that did not write the code. Confirms the pinned, locked Team Lead
section renders above the crew.

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- TEAM LEAD accent label + "reports back · required" sit close to the section
  baseline; minor spacing tightness — right pane.

Missing captures: none

One-line summary: The TEAM LEAD section is distinct and above WORKERS; the Lead row
has no × (workers all do); nothing clipped or overlapping. Footer reads
"5 workers + 1 lead".
