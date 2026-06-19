# home — projects-rail — layout-watcher verdict

Fixture: projects-rail
Command: bash scripts/gui_proof.sh projects-rail

## VERDICT: PASS

PRJ-S14 sidebar + the S15 reachability/composer additions, on REAL bound data
(seeded threads carry real `projectId`s — pinned=1, halo-app=5, websitemd.studio=1,
FareWellMarket=0, Unassigned=1).

Sidebar: New work order + search; PINNED section (cross-project single-line row);
PROJECTS header + new-project action; one collapsible group per project (chevron ·
folder · name · aggregate amber unread dot · `+`); a "Project Manager" row at the top
of each project group (opens the live Manager conversation); single-line ~32px thread
rows (unread dot · title · time); an unread row's amber dot + brighter title; a
"1 more" affordance past 4 rows; "No conversations" for an empty project; an
Unassigned (tray) group; Archive at the bottom. Filter chips + status-pill theater
gone, per spec.

Composer: the home composer's control bar leads with the active-project indicator
("📁 halo-app · main") — the project a send runs against (PRJ-S14) — then the mode
pill / target / send. The chip fits the bar with no crowding or clipping.

P1 — broken (blocks): none

P2 — advisory (minor polish):
- "Project Manager" row antenna icon is small/faint at this scale.
- "1 more" + PROJECTS header spacing slightly tight; Archive close to window edge.

(This capture lands on the home composer, so the selected-row active rail is not
shown here; it was validated in the prior projects-rail seal.)
