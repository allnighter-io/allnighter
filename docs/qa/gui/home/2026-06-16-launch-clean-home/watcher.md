# home — layout-watcher verdict (clean launch home)

Fixtures: home-empty · compose-base · compose-mode-menu
Command: `bash scripts/gui_proof.sh <fixture>`
Renders: native-home-empty.png · native-compose-base.png · native-compose-mode-menu.png

Surface: the app now LAUNCHES into the clean conversation home (reference
FirstRun / compose-routing) instead of the old Team/Threads workspace or the
auto-opened CLI setup page. Left rail (New work order + search + filters + "No
conversations yet") + "You already pay for the team" empty state (bench chips +
3 mode cards + routing composer). Setup opens over it on intent only.

## VERDICT: PASS

Disinterested layout-watcher on all three current renders.

home: P1 none · P2 none — left rail, all four filter chips (All/Design/Build/
Running, no truncation), bench chips, mode cards, composer, and hint all aligned
and on-screen.
compose-base: P1 none · P2 none.
compose-mode-menu: P1 none · P2 none — mode menu fully visible, anchored above
the composer.

One-line summary: All elements visible and aligned; filter chips render in full;
bench/mode-cards/composer intact; mode menu properly anchored.
