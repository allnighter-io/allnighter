# thread-chat — layout-watcher verdict

Fixtures: thread-chat
Command: bash scripts/gui_proof.sh thread-chat

## VERDICT: PASS

Change: the inbox agent reply (`.done` worker turn) now renders through our
AllnighterMarkdown engine (block-level), themed for dark mode — replacing
inline-only `Text(.init(...))`.

The Opus 4.8 reply renders cleanly: inline bold lead ("Token bucket.") with no raw
`**` markers, correct wrapping, left-aligned with the user message above, no
clipping/overlap.

P1 — broken (blocks): none
P2 — advisory:
- Agent text block reads a hair lighter than the canvas (barely perceptible) — the
  theme's `.text` background is `Color.clear`; verify no stray inline-code/bubble
  tint when richer content lands.
