# composer — layout-watcher verdict

Fixtures: compose-file-reference
Command: bash scripts/gui_proof.sh compose-file-reference

## VERDICT: PASS

@-file references are now a floating autocomplete ABOVE the composer (no search box):
compact list hugging its rows, top row selected (chevron + subtle bg), matched chars
highlighted amber, root-relative paths, "5 / 5" scope count top-right. ↑/↓ move, ⏎
inserts, Esc dismisses (keyboard wired in handleEditorCommand). Title bar is the shorter
36pt height. No clipping/overlap.

P1 — broken (blocks): none
P2 — advisory: none
