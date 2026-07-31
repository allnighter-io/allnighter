# PTD-1d — Embed pmTurn in status/result JSON

Status: **READY**
Depends: PTD-1a/b/c
Packet: [`PM_Turn_Delivery.md`](../../PM_Turn_Delivery.md)

## Slice packet

```text
Slice: PTD-1d — status embed pmTurn from PMTurnStore.load
Goal: PilotStatusJSON, RelayJSON status, TeamStatusResponse (and terminal TeamRunJSON)
      include optional `pmTurn` loaded from store when subject parked/terminal.
      Missing file → pmTurn null + note pm_turn_missing per spec.
Out of scope: --wait-for loop, --no-wait delivery ack, teaching, wake
Truth owner: CLI projectors + PMTurnStore.load
Works Test: PilotCLITests / RelayJSONTests / team status tests with fixture pm-turn on disk
Proof: swift test --filter 'PMTurn|PilotCLI|RelayJSON|TeamStatus'
Done when: committed `ptd: embed pmTurn in status JSON`
```

## Files

- `PilotCLI.makeStatusJSON` → add `pmTurn`
- `RelayJSON.project` or RelayCLI status path
- `AsyncTeamStatusMapper` / `TeamStatusResponse`
- Contract types if needed in Core

Commit: `ptd: embed pmTurn in status JSON`
