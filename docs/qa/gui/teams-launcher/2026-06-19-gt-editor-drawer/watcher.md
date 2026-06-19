# teams-launcher — layout-watcher verdict

Fixtures: teams-edit-drawer
Command: bash scripts/gui_proof.sh teams-edit-drawer

## VERDICT: PASS

Surface: hover a launcher card → pencil → the existing `TeamEditorView` opens as a
right-hand drawer (REVIEW & CUSTOMIZE · Code Core: team name, lead, 7 workers,
substitutions toggle, Revert / Save as my team) over the dimmed launcher.

P1 — broken (blocks): none

P2 — advisory:
- Drawer stops ~10–15px short of the window bottom (sliver of dimmed launcher
  visible) — minor, not a break.
- The editor's "N workers + 1 lead · saved as a code team…" caption (from the
  existing TeamEditorView) isn't visible in this width — existing-editor content,
  not the drawer.
- Worker-row X buttons sit slightly tight to the right edge; nothing clipped.
