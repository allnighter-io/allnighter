# setup — layout-watcher verdict (cold first-run roster fix)

Fixtures: readiness-cold · readiness-mixed · team-open-mixed · doctor-open-mixed
Command: `bash scripts/gui_proof.sh <fixture>`
Renders: native-readiness-cold.png · native-readiness-mixed.png ·
native-team-open-mixed.png · native-doctor-open-mixed.png

Bug fixed: the cold first-run setup page rendered BLANK because `setupCards`
only listed cached probe records — a never-scanned machine had none. Now
`setupCards` lists every supported headless driver; an unprobed one shows as a
new `.notChecked` state under a "Not checked yet" group, so onboarding always
shows the supported CLIs (the founder's "we support N, found M") before the first
scan. New `readiness-cold` fixture + dev route exercise it.

## VERDICT: PASS

Disinterested layout-watcher on all four current renders.

cold: P1 none — full "NOT CHECKED YET" group with all 4 CLI cards + "0 / 4 CLIs
ready" (not blank). P2 last card at the scroll fold (expected).
mixed-page: P1 none. P2 bottom card + repair-log at fold (expected).
team: P1 none — footer "Open CLI setup" + "Manage team". P2 bottom row fold.
doctor: P1 none. P2 bottom card fold.

One-line summary: All four render correctly with aligned, on-screen elements and
no overlap; the cold page shows the full not-checked roster (not blank).
