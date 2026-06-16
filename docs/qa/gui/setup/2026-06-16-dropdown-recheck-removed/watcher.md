# setup — layout-watcher verdict (dropdown re-check removed)

Fixtures: team-open-ready · team-open-mixed
Command: `bash scripts/gui_proof.sh <fixture>`
Renders: native-team-open-ready.png · native-team-open-mixed.png

Change under review: the bench-dropdown footer no longer shows a re-check
action. When all tools are ready the footer is just "Manage team" (clutter-free);
when anything is not ready it shows a primary "Open CLI setup" that routes to the
CLI setup page. (Re-check still lives on the CLI setup page + the health-badge
popover.)

## VERDICT: PASS

Disinterested layout-watcher on both current renders.

ready: P1 none · P2 bottom row scroll-fold clip (expected). Footer is "Manage
team" only — no re-check / setup / census button.

mixed: P1 none · P2 bottom row scroll-fold clip (expected). Footer shows primary
"Open CLI setup" above "Manage team"; status pills (Not signed in / Probe failed)
+ Repair links sit inline without overlapping the model name.

One-line summary: Both popovers well-anchored with correctly differentiated
footers; only expected scroll-fold clipping, no visible-element layout breaks.
