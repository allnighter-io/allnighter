# PTD-1b — RelayCoordinator writes pm-turn on park

Status: **READY**
Depends: PTD-1a (`17989bfb` — PMTurnJSON + PMTurnStore)
Packet: [`PM_Turn_Delivery.md`](../../PM_Turn_Delivery.md)

## Slice packet

```text
Slice: PTD-1b — relay park → PMTurnStore.write
Goal: On every relay PM boundary (awaitingPM, escalated, stopped, done after dev round),
      write pm-turn.json BEFORE persisting relay state (spec write order 1→2→3)
Out of scope: CLI status embed, run path, --wait-for, teaching
Truth owner: RelayCoordinator + PMTurnStore
Works Test: PilotCoordinatorTests or new RelayPMTurnTests — handoff completes → pm-turn exists with report
Proof: swift test --filter 'RelayPMTurn|PilotCoordinator'
Done when: all relay park transitions write pm-turn; tests green; committed
```

## Implementation notes

- Add `PMTurnStore` injection to `RelayCoordinator` (default `PMTurnStore()`)
- Helper `writePMTurn(for state: RelayState, reason:, report:, nextCommands:)` using
  `settledDevReport`, `nextSequence`, relay fields from spec
- Call from `runExternalRound` success path (awaitingPM), escalate, stop, done paths
- Write order: build PMTurnJSON → `pmTurnStore.save` → `stateStore.save`
- `nextCommands`: use real relay id, status-valid pilot handoff / relay-resume strings
- `workRecovery`: null + note until WRC-S00
- Hermetic tests with temp relay root

Commit message: `ptd: write pm-turn on relay park`
