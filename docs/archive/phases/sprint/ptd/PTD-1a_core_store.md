# PTD-1a — PMTurnJSON + PMTurnStore

Status: **IN PROGRESS** (orchestrator: Cursor; implementer: Terra via pilot)
Packet: [`PM_Turn_Delivery.md`](../../PM_Turn_Delivery.md)

## Slice packet

```text
Slice: PTD-1a — core types and durable store
Goal: PMTurnJSON Codable model + PMTurnStore atomic read/write under Runs/ and Relays/
Out of scope: RelayCoordinator/RunService integration, CLI --wait-for, teaching
Truth owner: PMTurnStore (write/read), PMTurnJSON (wire shape)
Lie-prone layer: sequence dedupe, crash between pm-turn and subject state (store only here)
Works Test: unit tests — write/read round-trip, sequence monotonic, missing file → load nil
Proof command: swift test --package-path Packages/AllnighterCore --filter PMTurn
Done when: types + store + tests green; committed
```

## Spec fields (from PM_Turn_Delivery.md)

- `schemaVersion`, `kind` (`run`|`relay`), `subjectId`, `sequence`, `round?`, `createdAt`
- `reason`, `lifecycleStatus`, `report`, `workerRunId?`, `workRecovery?`, `nextCommands`, `notes`
- Relay-only: `pmMode?`
- Paths: `…/Runs/<id>/pm-turn.json`, `…/Relays/<id>/pm-turn.json`
- Atomic write: temp + rename; `nextSequence(for:)` helper

## Files to add

- `Packages/AllnighterCore/Sources/AllnighterCore/PMTurnJSON.swift`
- `Packages/AllnighterCore/Sources/AllnighterEngine/PMTurnStore.swift`
- `Packages/AllnighterCore/Tests/AllnighterCoreTests/PMTurnStoreTests.swift`

Match `RelayStateStore` / `RunStore` patterns for root directory injection in tests.
