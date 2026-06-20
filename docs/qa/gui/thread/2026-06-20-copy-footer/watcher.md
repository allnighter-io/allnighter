# thread — layout-watcher verdict

Fixtures: thread-copy-footer
Command: bash scripts/gui_proof.sh thread-copy-footer

## VERDICT: PASS

Copy icon is at the bottom-right of the assistant message body (below the last line of
the reply), right-aligned. No copy icon in the header row next to "Opus 4.8 · time".

P1 — broken (blocks):
- none

P2 — advisory:
- Small vertical gap between the final text line and the icon row — slightly loose
  spacing, not broken.
- Button is hover-revealed in production; forced visible here via the copy-footer fixture.
