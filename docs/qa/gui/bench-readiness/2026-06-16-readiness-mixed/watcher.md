# Team readiness / Repair — layout-watcher verdict

Surface: Team readiness / Repair (Screen #4)
Fixture: `readiness-mixed` (2 ready, codex probeFailed selected, grok not installed)
Command: `bash scripts/gui_proof.sh readiness-mixed`
Render: `native.png`

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- "Available to add" Grok card sits at the scroll fold — reachable via page
  scroll, not clipped.
- Repair panel "View log" copies probe reason to clipboard (log viewer is a
  follow-up slice).

Missing captures:
- Scrolled state showing Grok card fully (optional; content exists below fold).

One-line summary: Split-column readiness page renders correctly — compact roster
with accent selection ring on Codex, repair panel on the right, stats and header
intact.
