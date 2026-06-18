# studio — layout-watcher verdict

Fixtures: studio-worker-editor
Command: bash scripts/gui_proof.sh studio-worker-editor

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory: none

Scope note: this slice is **behavior-only** inside the dropdown popovers —
`ALSearchableDropdown` gains ↑/↓ + ⏎ keyboard navigation with the top row
highlighted by default, and `ALDropdown` sorts its options A→Z. Neither is visible
in a resting (closed) capture; the static render confirms the worker editor and its
closed SKILL/MODEL triggers still render with no regression. The keyboard/sort
behavior is verified by build + code review (mirrors the shipped ⌘K command-palette
key handling), not by pixels — the open popover is a native anchored popover the
static studio-* snapshot harness cannot capture.

One-line summary: Worker editor + closed dropdown triggers render unchanged; the new
keyboard nav and A→Z model sort live in the (uncapturable) open popover.
