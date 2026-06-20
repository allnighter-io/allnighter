# composer — layout-watcher verdict
Fixtures: compose-file-reference
Command: bash scripts/gui_proof.sh compose-file-reference

## VERDICT: PASS
@ picker renders the seeded matches. The panel now shows whenever @ is open and NEVER
silently empty: an honest status line ("Scanning project files…" / "Open a project to
reference its files." / "No files match …") replaces blank nothing.

P1 — broken: none
P2 — advisory: none
