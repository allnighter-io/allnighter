# thread — layout-watcher verdict

Fixtures: thread-streaming
Command: bash scripts/gui_proof.sh thread-streaming

## VERDICT: PASS

P1 — broken (blocks): none
P2 — advisory:
- spinner + "streaming…" sit close to the last partial line (tight, not clipped).

A running worker_chat turn renders its live partial text as plain paragraph text
(cuts off mid-word, intentional) with a small spinner + "streaming…" affordance — the
live render the founder asked for, vs. the bare "Working…" placeholder.
