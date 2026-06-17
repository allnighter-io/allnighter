# studio — layout-watcher verdict

Fixtures: studio-clis
Command: bash scripts/gui_proof.sh studio-clis

Disinterested layout-watcher (rubric `.claude/agents/layout-watcher.md`), run via a
separate agent that did not write the code.

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- "Locate the binary…" action row in the repair panel sits close to the "Last
  proof" block; divider abuts the text — minor spacing drift. (Inside the embedded
  `TeamReadinessView`, not the Studio shell.)
- Bottom CLI source card ("Grok Build CLI") partially under the scroll viewport
  edge — reads as normal scroll affordance, not container clipping.

Missing captures: scrolled-to-bottom CLI list; DESIGN/COPY sub-item selected states
(shell nav present and correct at the fold).

One-line summary: Clean and correctly stacked — left nav (Done / CLIs / lane groups)
on the left, CLI-setup header + 4 stat cards + source list + sticky repair panel on
the right, everything aligned and readable.
