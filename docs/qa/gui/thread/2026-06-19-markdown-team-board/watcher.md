# thread — markdown-team-board — layout-watcher verdict

Fixture: thread-team-board
Command: bash scripts/gui_proof.sh thread-team-board

## VERDICT: PASS

Completes the inbox markdown rollout: the Team board (CR4c) RECOMMENDATION
synthesis block and each model's answer card now render through AllnighterMarkdown
(block-level — bold, italic, headings, lists, quotes) instead of inline-only
`Text(.init(...))`. Bold lead-ins ("Token bucket.", "Sliding-window counter.")
render with no raw `**`/`##` markers; consistent with the chat-turn renderer.

P1 — broken (blocks): none

P2 — advisory (all pre-existing styling, not regressions from this change):
- RECOMMENDATION label sits tight to the body / amber accent bar — minor hierarchy.
- The two answer cards share vertical rhythm with no divider — distinguishable by
  the model-name line; advisory only.
- Composer placeholder + "One model answers…" hint are low-contrast but fully
  visible, not clipped.
