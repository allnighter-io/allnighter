# thread — layout-watcher verdict

Fixtures: thread-mutating-run
Command: bash scripts/gui_proof.sh thread-mutating-run

## VERDICT: PASS

P1 — broken (blocks): none
P2 — advisory:
- Worker reply text sits close to the top of the content area (snug), nothing clipped.

Worker reply renders as plain markdown (no box, no "Ran" badge). Active sidebar row
marked by amber left rail + subtle background, NOT bold.
