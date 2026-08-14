# ask-ai — layout-watcher verdict

Fixtures: ask-ai-open ask-ai-done
Command: bash scripts/gui_proof.sh ask-ai-open && bash scripts/gui_proof.sh ask-ai-done
Watcher: [Ask AI layout](e139f69e-35e2-4c5c-b030-eb4a8fc76cb1) then compact-panel recapture [Ask AI layout](7f1213d6-8703-44d5-9e98-bfb3d4a76914)

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory: none

Empty-scroll P2 (done-state greedy ScrollView): RESOLVED. Done panel is compact — answer body, billing email line, and "Email a person" footer are snug with no dead vertical region below.

Missing captures (not blocking): running state, failed state.

One-line summary: Both states are clean; panel fits content correctly in done state.
