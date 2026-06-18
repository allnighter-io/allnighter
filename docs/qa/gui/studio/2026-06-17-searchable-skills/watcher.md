# studio — layout-watcher verdict

Fixtures: studio-skills-build, studio-worker-editor
Command: bash scripts/gui_proof.sh studio-skills-build
         bash scripts/gui_proof.sh studio-worker-editor

Disinterested layout-watcher (rubric `.claude/agents/layout-watcher.md`), run via a
separate agent that did not write the code.

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory: none

Missing captures:
- The skill picker's *open* searchable popover (search field + A→Z rows with
  built-in/custom tags + "+ Create …") is a native anchored popover and is not
  capturable by the static studio-* snapshot harness. The closed SKILL trigger is
  shown in studio-worker-editor; the search/filter/sort/create logic is exercised
  at runtime via the shared `ALSearchableDropdown` component. The Skills *page*
  search field + A→Z sort ARE statically visible in studio-skills-build.

One-line summary: Skills page shows the "Search skills…" field above an
alphabetically-sorted list with the detail pane intact; the worker editor's
SKILL/MODEL/chips/PROMPT/footer all render aligned and unclipped.
