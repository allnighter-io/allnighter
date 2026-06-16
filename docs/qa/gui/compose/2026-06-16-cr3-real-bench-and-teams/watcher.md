# compose — layout-watcher verdict (CR3 real bench + teams)

Fixtures: compose-base · compose-target-chat · compose-target-fanout ·
compose-target-exec · compose-mode-menu · home-empty
Command: `bash scripts/gui_proof.sh <fixture>`

CR3: the composer now reads REAL app data —
- Bench = `AppModel.composeBench` (the user's enabled models + live readiness
  from `toolStatuses`); the chip/popovers show real models, default = a ready one.
- Executor list = models whose source is a headless-CLI agent.
- Fan-out teams = `BuiltInTeams.teams(in:)` per lane (Design Core / Premium
  Polish / Conversion Studio / …), default = the lane's default-for-lane team.
Send remains a hook (the run loop lands with the thread in CR4).

## VERDICT: PASS

Disinterested layout-watcher on all current renders.

base: P1 none · P2 none.
target-chat: P1 none · P2 none — 6 model rows + effort.
target-fanout: P1 none · P2 none — lane tabs + real team list + Customize + effort.
home: P1 none · P2 none — rail + hero + bench + cards + composer.

One-line summary: Composer controls + both popovers (anchored, no clip/overlap)
+ home rail/hero/bench/cards all visible and aligned; teams + bench are now real.
