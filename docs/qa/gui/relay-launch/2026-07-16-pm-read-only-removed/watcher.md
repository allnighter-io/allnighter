# relay-launch — layout-watcher verdict

Fixtures: relay-launch
Command: bash scripts/gui_proof.sh relay-launch

## VERDICT: PASS

Re-sealed after `Relay_ReadOnly_Removal.md`: the "PM is mechanically read-only"
toggle (and its fail-closed seat annotation) that used to sit between the PM
SEAT and DEV SEAT sections is gone. Checked specifically for (1) any leftover
trace of the removed toggle — a switch control, orphaned label, or gap where
it used to be, (2) general layout breakage — clipping, overlap, collapse,
z-order/scrim issues, off-screen content, misalignment, and (3) that the
footer (helper text + orange "Start" button, fixed via `.safeAreaInset` in
the prior footer-overlap-fix packet) still stays clear of the DEV SEAT model
list.

No leftover trace of the removed toggle between PM SEAT and DEV SEAT — the
form now flows doc → PM seat → dev seat → ceilings directly. The footer sits
cleanly in its own bar below the DEV SEAT list with no overlap or crossing
border; the prior footer-overlap fix survives.

P1 — broken (blocks): none

P2 — advisory:
- CEILINGS row ("Max rounds" stepper / "Until (HH:MM, optional)" field)
  borders are low-contrast against the dark background — pre-existing, not
  introduced by this change.
- The 4th row subtitle text ("OpenCode") in both PM SEAT and DEV SEAT lists
  reads low-contrast at a glance (fully rendered on close inspection, not
  clipped) — same pre-existing cosmetic note as the prior footer-overlap-fix
  packet.

One-line summary: the read-only toggle removal left no visual residue and
the previously-fixed footer/seat-list layout holds.
