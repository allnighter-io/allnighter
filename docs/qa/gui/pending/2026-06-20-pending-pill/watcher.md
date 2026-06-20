# pending — layout-watcher verdict

Fixtures: pending-pill
Command: bash scripts/gui_proof.sh pending-pill

## VERDICT: PASS

P1 — broken (blocks):
- none

P2 — advisory:
- The amber "3 pending" pill and green "5 ready" badge sit very close together with
  minimal inter-element gap — not overlapping, but tighter than the gap between
  "5 ready" and "Models". Minor spacing drift only.

Summary: The amber pill renders cleanly in the title-bar cluster — visible, not clipped,
not overlapping the adjacent badge or "Models" control.
