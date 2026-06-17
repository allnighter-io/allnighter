# home — layout-watcher verdict

Fixtures: home-with-threads, thread-empty
Command: bash scripts/gui_proof.sh home-with-threads ; bash scripts/gui_proof.sh thread-empty

Disinterested layout-watcher (rubric `.claude/agents/layout-watcher.md`), run via a
separate agent that did not write the code. Change under test: brand mark amber → white.

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- White crescent sits slightly left of the headline optical center (pre-existing
  centering, minor drift).

Note: the sidebar shows a "No matches" search-filter state in these captures — an
unrelated fixture/capture quirk (stray search text), not a layout defect or part of
this change.

One-line summary: White crescent brand mark reads clean in both the title bar and
main pane — nothing clipped, overlapping, collapsed, or off-screen.
