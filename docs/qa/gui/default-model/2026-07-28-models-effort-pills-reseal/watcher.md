# default-model — layout-watcher verdict

Fixtures: studio-default-model, compose-target-inline, relay-launch-r-s08
Commands:
- `bash scripts/gui_proof.sh studio-default-model`
- `bash scripts/gui_proof.sh compose-target-inline`
- `bash scripts/gui_proof.sh relay-launch-r-s08`

## VERDICT: PASS

P1 — broken (blocks): none

Evidence:
- **studio-default-model**: DefaultModelView tier columns render cleanly; no clip/overlap/collapse.
- **compose-target-inline**: RoutingComposer inline team picker renders within bounds; list scroll cutoff is container-bound, not window-sliced.
- **relay-launch-r-s08**: RelayLaunchView welcome state stacks correctly; worker pills and chip row on-screen.

P2 — advisory:
- compose-target-inline team list continues below fold (expected scroll).
- relay-launch icon-chip row is dense but readable.
