# home — layout-watcher verdict

Fixtures: home-thread-states
Command: bash scripts/gui_proof.sh home-thread-states

## VERDICT: PASS

Draft row = dashed ring + muted non-bold text (subtle). Running = blue dot. Replied =
amber dot + bold. Color earned. (Selected-draft amber-rail removal is code-gated:
`selected && state != .draft`; the active background marks selection, never amber.)

P1 — broken (blocks): none
P2 — advisory: none
