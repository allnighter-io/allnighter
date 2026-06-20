# composer — layout-watcher verdict

Fixtures: compose-file-reference
Command: bash scripts/gui_proof.sh compose-file-reference

## VERDICT: PASS

Floating @ autocomplete above the composer renders identically after the perf rewrite:
compact list, top row selected (chevron), matched chars highlighted, root-relative paths,
scope count. The corpus is now scanned ONCE off the main thread and ranked in-memory per
keystroke (no git/stat on the main thread → no freeze). No clipping/overlap.

P1 — broken (blocks): none
P2 — advisory: none
