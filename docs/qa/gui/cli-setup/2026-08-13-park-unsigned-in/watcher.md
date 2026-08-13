# CLI setup — park unsigned-in CLIs — layout-watcher verdict

Surface: CLI setup (`TeamReadinessView` / `BenchRepairPanel`)
Fixture: `readiness-muse-needs-login` (Muse Code needs sign-in, park control visible)
Command: `bash scripts/gui_proof.sh readiness-muse-needs-login`
Render: `native.png`

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- The caption "Not using this CLI? Park it — it won't show up in Needs attention." sits quite close to the segmented control directly below it; vertical breathing room is tight but text is fully legible and nothing is clipped — lower-right detail panel

Missing captures:
- Parked segment selected state (to confirm the segmented control's active/inactive visual swap is correct)
- Scrolled-down state of the left list (bottom rows near the window edge are partially cropped by the screenshot frame — cannot confirm if "Grok Build CLI" row is fully visible)

One-line summary: Detail panel is intact — actions, caption, and segmented control all visible and unclipped; no P1 issues.
