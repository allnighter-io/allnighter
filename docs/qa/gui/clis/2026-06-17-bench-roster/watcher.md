# clis — layout-watcher verdict

Fixtures: studio-clis
Command: bash scripts/gui_proof.sh studio-clis

Disinterested layout-watcher (rubric `.claude/agents/layout-watcher.md`), run via a
separate agent that did not write the code.

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- "+ Add model" sits slightly tight under the single model row — minor vertical
  spacing drift, right panel "MODELS ON THIS CLI" section.

Missing captures:
- The "Add model" inline form (two fields + Add/Cancel) and the per-model switch
  in its toggled-off state appear only on interaction — not in this resting capture.
  The roster mutations are covered by the Core ModelCatalog backend tests
  (MCBR-S01–S08).

One-line summary: Right panel renders cleanly — the editable "MODELS ON THIS CLI"
roster (model name + monospace label + on-bench toggle) and "+ Add model" sit above
the repair section, all visible, aligned, unclipped.
