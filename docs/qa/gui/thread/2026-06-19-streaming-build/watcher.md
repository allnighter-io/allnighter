# thread — layout-watcher verdict

Fixtures: thread-streaming-build
Command: bash scripts/gui_proof.sh thread-streaming-build

## VERDICT: PASS

P1 — broken (blocks): none
P2 — advisory:
- streaming text runs near the bubble's right edge (tight, not clipped); spinner sits
  close under the last line.

A running mutatingRun turn (the Auto/RunService path the default run actually takes)
now renders its live streamed partial text + a "streaming…" affordance, instead of the
bare "Working…" placeholder.
