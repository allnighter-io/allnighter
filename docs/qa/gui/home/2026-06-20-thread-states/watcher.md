# home — layout-watcher verdict

Fixtures: home-thread-states
Command: bash scripts/gui_proof.sh home-thread-states

## VERDICT: PASS

Verified on a 2x zoom of the three rows (the full-res downscale made the small dots
ambiguous; the zoom is authoritative):

- Row 1 "Rate-limit the public API" — blue filled dot + regular text (running). MATCH.
- Row 2 "Unread worker reply" — amber filled dot + bold text (replied/unread). MATCH.
- Row 3 "Testing this out" — dotted outlined ring (no fill) + muted regular text (draft). MATCH.

P1 — broken (blocks):
- none

P2 — advisory:
- Draft ring is small/subtle (intentional — a draft should be quiet).

Summary: All three row states match dot color, dot shape, and text weight exactly. Color
is earned — amber only for the replied row, blue only for the running row, draft is a
quiet ring with no bold and no amber.
