# pm — pm-cards — layout-watcher verdict

Fixture: pm-cards
Command: bash scripts/gui_proof.sh pm-cards

## VERDICT: PASS

PRJ-S15: the Project Manager card surface — the Manager's typed turns made visible.
A reading column over a designer-mock propose→approve→verify slice on halo-app:
a "Project Manager · halo-app" bar, the Manager's markdown answer (inline code),
then the typed cards (UI Contract minimums):
- PROPOSAL card: EXECUTE SLICE kind badge · title · PROPOSED status; WHY NOW, SCOPE,
  NON-GOALS, RISKS/UNKNOWNS fields; Approve (amber primary) / Edit / Postpone.
- WORK ORDER card: WORK ORDER badge · title · CODE lane; target/root/base meta;
  PROMPT (mono); PROOF COMMANDS (mono); EXPECTED RETURN; Dispatch/Reveal (below fold).
- VERIFICATION card (below fold): outcome badge + per-command ✓/exit + recommendation.

P1 — broken (blocks): none

P2 — advisory (field-label contrast addressed: textFaint→textMuted before seal):
- Inter-card vertical spacing is a touch tight (not overlapping).
- Proposal accent rail is thin against the dark card.
- Dispatch/Reveal buttons + the Verification card are below the fold (scroll view) —
  expected; unreviewed in this single-viewport capture.
