# pending — layout-watcher verdict

Fixtures: pending-queue
Command: bash scripts/gui_proof.sh pending-queue

## VERDICT: PASS

P1 — broken (blocks):
- none

P2 — advisory:
- The count on the "Unassigned 3" group header uses plain text rather than a distinct
  badge — minor inconsistency vs. the amber count pill on the "Queued work" header, but
  both are readable and not clipped. (Intentional: group counts are quiet; only the
  total-pending pill earns amber.)
- The close X sits flush against the window's right edge with tight padding — not clipped.

Missing captures (out of scope for this slice):
- Scroll state with > 3 rows (overflow behavior)
- Hover/focus state on the remove X
- The sidebar "Pending" triage section (separate slice: 4-state rows)

Summary: All three row cards, the header, the count pill, and the remove X buttons are
fully visible, correctly stacked, nothing clipped or overlapping — screen is clean.
