# composer — layout-watcher verdict

Fixtures: compose-file-reference
Command: bash scripts/gui_proof.sh compose-file-reference

## VERDICT: PASS

All five rows render as single-line root-relative paths with amber match highlights on the
"Com" substring, one ungrouped list, header "Search Project files · Com". Ranking visible:
docs/Composer_Guide.md first (readable-doc tiebreak), vendor/lib-composer.js last (vendor
sink). No clipping/overlap.

P1 — broken (blocks):
- none

P2 — advisory:
- ↩ glyph appears only on row 1 — that's the keyboard-highlighted candidate
  (highlightedFileIndex = 0), correct.
- ~8px dead space below the last row — minor panel padding, not broken.
