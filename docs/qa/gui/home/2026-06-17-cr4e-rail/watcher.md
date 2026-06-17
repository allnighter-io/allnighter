# home — layout-watcher verdict

Fixtures: home-rail
Command: bash scripts/gui_proof.sh home-rail

Disinterested layout-watcher (rubric `.claude/agents/layout-watcher.md`), run via a
separate agent that did not write the code.

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- The two title-bar pill clusters at top-right ("4 ready" and "Team") render with
  cramped/partially illegible glyph artifacts — this is pre-existing chrome, NOT
  the rail under test (top-right header).

Missing captures: none

One-line summary: The left rail renders cleanly — New work order button, search
field, All/Design/Build/Running chips, then PINNED (one row) and RECENT (four rows)
each with glyph, title, status pill and timestamp, all aligned and on-screen.
