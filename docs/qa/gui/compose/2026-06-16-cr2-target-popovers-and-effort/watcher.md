# compose — layout-watcher verdict (CR2 target popovers + effort)

Fixtures: compose-target-chat · compose-target-exec · compose-target-fanout ·
compose-base · compose-mode-menu · home-empty
Command: `bash scripts/gui_proof.sh <fixture>`

CR2: the routing composer is now interactive. The target chip routes to a MODEL
(Opus 4.8), never a CLI. Target popovers:
- Chat → "Route to model" (all 6 models, glyph + vendor·CLI sub, not-ready
  disabled w/ badge).
- Execute → "Hand to executor" (executor-capable models only).
- Fan out → "Send to team" (Build/Design/Copy lane tabs + team list w/ default
  tag + Customize…).
Shared Low/Med/High EFFORT row. Single open popover; Fan out auto-opens the
target. Bench renamed to models throughout (incl. the home chips).

## VERDICT: PASS

Disinterested layout-watcher on all current renders.

target-chat: P1 none · P2 none.
target-exec: P1 none · P2 none — shorter executor list.
target-fanout: P1 none · P2 none — lane tabs + team list + Customize + effort.
home: P1 none · P2 none — bench chips show model names.

One-line summary: Popovers sit directly above their chips; model/team lists and
effort rows fully visible with no clipping/overlap/z-order issues; chip reads the
model, and home bench chips show model names.
