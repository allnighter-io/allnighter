# teams-launcher — layout-watcher verdict

Fixtures: teams-compose-modal
Command: bash scripts/gui_proof.sh teams-compose-modal

## VERDICT: PASS

Surface: the Send-to-team composer modal — one click on a launcher card opens a
centered modal over the dimmed launcher: eyebrow ("SEND TO SIGNAL TEAM"), team
name, two starter-prompt chips, and the reused `RoutingComposer` locked to
send-to-team (no mode pill; "Signal team" lane pill + attach + send).

P1 — broken (blocks): none

P2 — advisory:
- Modal reads a few px left-of-center (launcher content is left-aligned) — minor.
- Scrim intentionally dims (not hides) the launcher behind; the modal card itself
  is solid `bg-raised`, no bleed-through into the modal.
- Left starter chip truncates with an ellipsis (expected lineLimit); both chips
  sit on one row without overlap.
