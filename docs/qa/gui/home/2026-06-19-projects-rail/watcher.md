# home — projects-rail — layout-watcher verdict

Fixture: projects-rail
Command: bash scripts/gui_proof.sh projects-rail

## VERDICT: PASS

PRJ-S14: the left sidebar rebuilt around projects (docs/phases/wiring/sidebar-with-projects).
Renders on REAL bound data — the seeded threads carry real `projectId`s and group
under their projects (verified: pinned=1, halo-app=5, websitemd.studio=1,
FareWellMarket=0, Unassigned=1).

Required elements all present and intact: New work order + search; a PINNED section
(cross-project) with a single-line row; a PROJECTS header with a new-project
(folder-plus) action; one collapsible group per project (chevron · folder · name ·
aggregate amber unread dot · `+`); single-line ~32px thread rows (unread dot · title ·
time); the selected row's 2.5px amber left rail + active background; an unread row's
amber dot + brighter title; a "1 more" affordance past 4 rows; "No conversations" for
an empty project; an Unassigned (tray) group; and the Archive entry pinned at the
bottom. The All/Design/Code/Running filter chips and status-pill theater are gone, as
the spec requires.

P1 — broken (blocks): none

P2 — advisory (minor polish, not blocking):
- PINNED label sits a touch tight under the search field; vertical rhythm slightly
  inconsistent with the PROJECTS gap.
- PROJECTS header label baseline drifts a hair below the row icons.
- "1 more" reads lighter than the rows — it is the amber accent (interactive) color,
  but could be bumped for affordance clarity.
- Archive bottom entry has minimal clearance from the window edge.

Note: an earlier capture caught stray search text + empty groups — traced to leftover
background app instances bleeding events into the capture, not a layout bug. Killing
them produced this clean, deterministic render.
