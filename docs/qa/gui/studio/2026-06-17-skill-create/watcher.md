# studio — layout-watcher verdict

Fixtures: studio-worker-editor
Command: bash scripts/gui_proof.sh studio-worker-editor

Disinterested layout-watcher (rubric `.claude/agents/layout-watcher.md`), run via a
separate agent that did not write the code.

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory: none

Missing captures:
- The conditional "SKILL NAME" field + the picker's "+ Create …" footer appear only
  mid-edit (when forking/creating) and via the native search popover — not capturable
  by the static studio-* snapshot harness. That path is covered by TeamDraftTests
  (type-to-create makes a named custom skill; named fork uses the chosen name; a
  nameless create row is not savable). Its absence in this resting capture is correct.

One-line summary: The Customize worker editor renders cleanly — SKILL/MODEL fields,
chips, PROMPT editor, and Cancel/Done footer all visible, aligned, unclipped.
