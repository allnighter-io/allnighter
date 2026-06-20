# thread — layout-watcher verdict

Fixtures: thread-streaming-build
Command: bash scripts/gui_proof.sh thread-streaming-build

## VERDICT: PASS (re-render of the proven streaming layout + a thinking card)

P1 — broken (blocks): none
P2 — advisory: thinking card + streaming text sit close (tight, not clipped).

A running worker turn now shows TWO live surfaces: a muted "🧠 Thinking" card (the
model's streamed reasoning) above the streamed partial answer + "streaming…" affordance.
Both update live; the answer renders plain while running and via Markdown when settled.
