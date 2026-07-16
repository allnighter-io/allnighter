# thread — layout-watcher verdict

Fixtures: thread-relay-escalated
Command: bash scripts/gui_proof.sh thread-relay-escalated

## VERDICT: PASS

Title, model badges, reply bubbles, Raw/Copy controls all properly aligned
with no clipping or overlap. The amber escalation card (title, note text,
"Your answer…" field, "Answer & resume" button) and the docked composer
below it are both fully opaque and unclipped.

P1 — broken (blocks): none

P2 — advisory: none

One-line summary: the escalated relay thread renders cleanly — no layout
issues found.
