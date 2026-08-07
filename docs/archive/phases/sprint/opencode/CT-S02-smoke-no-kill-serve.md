# CT-S02 — Smoke/doctor must not kill a live serve

Status: **in_progress**
SSOT: [`OpenCode_Completion_Truth_Followup.md`](../../OpenCode_Completion_Truth_Followup.md) CT-05
Repo: **AgentOS**

## Goal

`smokeReason` / doctor must never SIGTERM another process’s healthy `opencode serve` on `:4096`.

## Slice packet

```text
Slice: CT-S02
Goal: Refuse foreign listeners; take spawn lock in smoke; don’t reclaim-kill
Out of scope: idle TTL redesign beyond not killing foreign; CT-06 sticky failure
Truth owner: OpenCodeServeCoordinator.reclaimForeignListenerIfNeeded + smokeReason
Lie-prone layer: SIGTERM on any :4096 listener when spawnedPID nil
Works Test: coordinator unit — foreign healthy listener → portOwnedByForeignProcess
Proof: swift test --filter OpenCodeServeCoordinatorTests --filter OpenCodeRoutingWorkerRunnerTests
```

## Touch only

- `Sources/AgentOSCLI/OpenCodeServeClient.swift` (smokeReason + lock)
- `Sources/AgentOSCLI/OpenCodeServeCoordinator.swift`
- `Tests/AgentOSCLITests/OpenCodeServeCoordinatorTests.swift`
- `Tests/AgentOSCLITests/OpenCodeRoutingWorkerRunnerTests.swift` (if mapping asserted)

## Done when

- [ ] Foreign listener → throw `portOwnedByForeignProcess` (no kill)
- [ ] smokeReason holds `OpenCodeSpawnLock`
- [ ] Filtered tests green + AgentOS commit
