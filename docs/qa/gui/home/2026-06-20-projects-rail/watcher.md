# home — layout-watcher verdict

Fixtures: projects-rail
Command: bash scripts/gui_proof.sh projects-rail

## VERDICT: PASS

The "1 more" expander now renders NEUTRAL/muted gray (was amber) — old chats don't
scream. Draft rows show the quiet dashed dot + muted non-bold text; the one unread
row keeps its earned amber dot + bold. No clipping/overlap.

P1 — broken (blocks): none
P2 — advisory: group-header aggregate unread dot stays amber (earned — unread).
