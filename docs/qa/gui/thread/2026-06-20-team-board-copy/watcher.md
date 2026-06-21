# thread — layout-watcher verdict
Fixtures: thread-team-board
Command: bash scripts/gui_proof.sh thread-team-board
## VERDICT: PASS
Terminal team board now renders the synthesis (RECOMMENDATION, with Copy) full, and each
worker answer as a COLLAPSED 2-line preview + chevron — only expanding a card renders its
full markdown (perf: first paint no longer lays out every answer). Copy button still
present on expand + synthesis. No clipping/overlap.
P1 — broken: none
P2 — advisory: collapsed preview shows raw markdown chars; acceptable for a preview.
