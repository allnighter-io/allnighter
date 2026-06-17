# thread — layout-watcher verdict

Fixtures: thread-team-board
Command: bash scripts/gui_proof.sh thread-team-board

Disinterested layout-watcher (rubric `.claude/agents/layout-watcher.md`), run via a
separate agent that did not write the code.

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- Recommendation card and the two answer cards stack cleanly, but the answer cards
  sit slightly inset/indented relative to the recommendation card's left edge —
  minor proportion drift in the team-board column.
- The composer footnote "One model answers — route the turn to a team" sits very
  close to the bottom window edge — tight bottom margin.

Missing captures: none — user bubble, team-board recommendation + two per-model
answer cards (both "Done"), docked composer, and left conversation rail are all
visible.

One-line summary: Clean, fully-rendered team-board thread — nothing clipped,
overlapping, or off-screen.
