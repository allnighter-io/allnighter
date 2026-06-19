# pm — pm-live — layout-watcher verdict

Fixture: pm-live
Command: bash scripts/gui_proof.sh pm-live

## VERDICT: PASS

PRJ-S15 wiring: the LIVE Project Manager conversation view, rendered from a
`ProjectManagerViewModel` timeline (here seeded with a propose→approve→verify slice
on halo-app). Top bar (back · "Project Manager · halo-app" · amber "What's next?");
a scrolling timeline of the Manager's markdown answer + the typed cards (proposal
with Approve/Edit/Postpone, work order with target/root/base/prompt/proof, and a
verification card below the fold); a docked "Ask the Project Manager…" composer.
Card actions and the composer drive the real Engine services (send/propose/approve/
dispatch/verify) through the view model.

P1 — broken (blocks): none

P2 — advisory:
- Proposal field labels (WHY NOW / SCOPE / NON-GOALS / RISKS) small/low-contrast.
- Work-order PROMPT and PROOF COMMANDS mono blocks sit tight.
- "· halo-app" subtitle close to "Project Manager" in the top bar.
- Verification card + work-order buttons are below the fold (scroll) — expected.
