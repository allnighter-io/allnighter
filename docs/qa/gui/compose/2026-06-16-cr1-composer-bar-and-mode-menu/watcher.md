# compose — layout-watcher verdict (CR1 composer bar + mode menu)

Fixtures: compose-base · compose-mode-menu
Command: `bash scripts/gui_proof.sh <fixture>`
Renders: native-compose-base.png · native-compose-mode-menu.png

Surface: the Compose Routing composer (docs/phases/wiring/design_handoff_compose_routing),
CR1 = the bar + mode menu. Textarea + control bar (mode pill, "to", adaptive
target chip showing who·effort, attach, amber Send) + hint line; mode menu
popover (Chat/Fan out/Execute + ⌘1/2/3 + descriptions). Rendered as a specimen
(real thread placement = CR4).

## VERDICT: PASS

Disinterested layout-watcher on both current renders.

base: P1 none · P2 none — composer box, control bar (Chat pill, "to", target
chip, attach, amber Send) and hint line all aligned and on-screen.

mode-menu: P1 none · P2 popover bottom edge sits close to the mode pill (small
gap); ⌘1/2/3 kbd tags are faint — minor only.

One-line summary: Composer bar reads as the intended sentence (verb → who →
effort); mode menu anchored above its pill with three highlighted rows, no
clipping or overlap.
