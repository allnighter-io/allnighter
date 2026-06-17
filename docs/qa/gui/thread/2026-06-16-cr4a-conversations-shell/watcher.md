# thread — layout-watcher verdict

Fixtures: thread-empty home-with-threads thread-with-turns
Command: bash scripts/gui_proof.sh thread-empty (also home-with-threads, thread-with-turns)

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- Rail filter/search pills are present but not wired (deferred to CR4e per slice scope).
- Relative timestamps on fixture threads use real `Date()` — acceptable for proof captures.
- Title-bar bench shows "4 ready" while home empty state says "6 ready" — fixture seeds all-ready bench vs title-bar live probe count; not a layout break.

Compared against `docs/phases/wiring/compose-routing/allnighter-compose-routing-new-work-order.png` and `…-base.png`:
- Left rail lists conversations with glyph + title + time.
- Empty thread shows centered "Start a work order" + bench-ready line + big routing composer.
- Thread with turns shows header, user bubble, docked composer bar.
