# home — layout-watcher verdict

Fixtures: home-with-threads team-open-mixed compose-target-send-to-team compose-target-inline
Command: bash scripts/gui_proof.sh <fixture> (each; fresh renders post-rebuild)

## VERDICT: PASS

Watcher: layout-watcher subagent, 3-round pass (2026-07-19).

Round 1 (pre-fix):
- home-with-threads.png — PASS
- team-open-mixed.png — PASS (P2: team-card text flush against popover edge;
  P2 data note: readiness pill vs popover count mismatch — content, not layout)
- compose-target-send-to-team.png — FAIL, P1: model rows "ChatGPT 5.6 Sol"
  ellipsis-clipped their parenthetical driver tag ("(C…" / "(Curs…"), leaving
  adjacent rows visually near-identical.

Fix applied: RoutingComposer.rowLabel — driver parenthetical gets
`.layoutPriority(1)` so it survives tight widths intact; the long catalog
display-name truncates instead (the parenthetical is the only discriminator
between same-named models).

Final round (fresh renders):
- compose-target-send-to-team.png — PASS. Re-verified at 2x zoom: driver tags
  "(Codex / ChatGPT)" vs "(Cursor Agent)" fully intact for both rows; rows
  distinguishable; clear right-side padding. P2 advisory only: bold-name
  truncation is visually tight (intentional; nested parenthetical in the name
  string is catalog data, not layout).
- compose-target-inline.png — PASS. Panel closes with proper rounded
  corners/border above the window canvas (prior "clipped by window edge" call
  retracted — compressed-crop artifact). All six seeded team rows show full
  labels, worker counts, star affordances; no truncation/overlap.

P1 — broken (blocks): none
P2 — advisory:
- Bold model-name truncation tight but intentional (see above).
- compose-team fixture cannot capture ("native popover window not visible",
  persists across retries) — pre-existing fixture wiring issue, out of scope.
- Renamed teams "Spec Review"/"Code Plan"/"Build Slice"/"Design" are not in
  the inline fixture's seed data; row-fit for those exact labels remains
  unproven until a fixture seeds them (visible labels of equal/greater length
  all fit cleanly).
