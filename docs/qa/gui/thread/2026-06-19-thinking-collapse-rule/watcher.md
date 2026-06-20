# thread — layout-watcher verdict

Fixtures: thread-thinking-history
Command: bash scripts/gui_proof.sh thread-thinking-history

## VERDICT: PASS

P1 — broken (blocks): none
P2 — advisory: streaming line cuts mid-word (intentional); spinner sits close under it.

Thinking now COLLAPSES to one line ("▸ Thought for Ns") on prior turns and stays
EXPANDED ("▾ Thinking") on the latest/running turn — never removed (no jitter),
click-toggleable, dimmed, and wrapping inside the column (overflow fixed).
