# PTD-1c — Run terminal writes pm-turn

Status: **READY**
Depends: PTD-1a, PTD-1b
Packet: [`PM_Turn_Delivery.md`](../../PM_Turn_Delivery.md)

## Slice packet

```text
Slice: PTD-1c — team run terminal → PMTurnStore.write
Goal: When a TeamRun reaches terminal lifecycle (done/failed/timedOut/cancelled),
      write pm-turn.json BEFORE final run.json persist. NOT on vendor park.
Out of scope: CLI embed, --wait-for, teaching, wake
Truth owner: Run completion path (RunService / CatalogRunCoordinator / team settle)
Works Test: hermetic test — terminal run → pm-turn with report + nextCommands
Proof: swift test --filter 'PMTurn|RunPMTurn|TeamRun'
Done when: committed `ptd: write pm-turn on run terminal`
```

## Implementation notes

- Report source table from spec: single worker = answer markdown; team = synthesis/lead answer
- Failed/timedOut/cancelled still write PM Turn (reason + report or null+note)
- Skip vendor park (`waitingForVendor`) — no pm-turn
- `nextCommands`: `alln show <id> --json`, `alln team result <id> --json` when applicable
- Inject PMTurnStore like RelayCoordinator
- Write order: pm-turn then run state

Commit: `ptd: write pm-turn on run terminal`
