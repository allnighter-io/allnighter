# cutover — layout-watcher verdict

Fixtures: team-open-mixed compose-mode-menu readiness-mixed studio-team-editor studio-teams-build thread-team-board

Change under proof: pure vocabulary relabel + effort cutover with no layout edits —
craft lanes "Build"→"Code", composer route "Fan out"→"Send to team", effort tooltip
→ "more reasoning time", readiness "Code · Design · Copy", and the team editor/studio
now showing the full fixed worker lineup (effort no longer gates worker count).

## VERDICT: PASS

A sighted layout-watcher reviewed each fixture (layout-only; CLI owns content):

| Fixture | Surface(s) | Verdict |
| --- | --- | --- |
| team-open-mixed | RoutingComposer + HomeView (team dropdown, Code/Design/Copy) | PASS |
| compose-mode-menu | RoutingComposer mode menu (Chat / Send to team / Execute) | PASS |
| readiness-mixed | ReadinessView ("Code · Design · Copy") | PASS |
| studio-team-editor | TeamEditorView (full fixed lineup, no min-effort field) | PASS |
| studio-teams-build | TeamStudioView (fixed "N workers" count) | PASS |
| thread-team-board | ThreadView (lane inference Build→Code) | PASS |

P1 — broken (blocks): none
P2 — advisory: minor pre-existing tightness only (a couple of tiles/rows with tight
padding; one truncated model name in the bench dropdown) — none introduced by this
relabel. Relabels confirmed rendering correctly (e.g. "Code · Design · Copy",
"Send to team", "saved as a code team").
