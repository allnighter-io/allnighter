# composer — layout-watcher verdict

Fixtures: compose-target-inline
Command: bash scripts/gui_proof.sh compose-target-inline

## VERDICT: PASS

Target popover Team tab: the top row (Code Core) is highlighted by DEFAULT — the new
keyboard/hover navigation highlight (↑/↓ move it, hover follows, ⏎ picks; wired like the
existing skill-picker). Checkmark still marks the actual selection separately. Effort
chip "Med" present; the target chip no longer repeats effort (no "· Med  Med" duplicate).
One-line rows, never-blank ranked list. No clipping/overlap.

P1 — broken (blocks): none
P2 — advisory: arrow-key handling relies on NSPopover focus — verify live.
