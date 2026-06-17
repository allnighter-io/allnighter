# home — layout-watcher verdict

Fixtures: home-rail-unr
Disinterested layout-watcher. Change: unread-light color → soft amber #FFD79E
(ALPalette.amber300) for normal unread; red retained for failed/blocking unread.

## VERDICT: PASS

P1 — broken (blocks): none
P2 — advisory:
- Trailing unread dot sits just inside the right padding (vertically centered,
  unclipped, never overlaps title/timestamp) — minor drift.

One-line summary: Rail groups + rows + trailing unread dots render aligned and
unclipped; thread + composer intact.
