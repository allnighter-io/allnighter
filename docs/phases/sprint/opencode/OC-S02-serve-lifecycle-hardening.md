# OC-S02 — OpenCode serve lifecycle hardening

Status: **done**
Source: [`code_review/triage/CR-05-findings.md`](../../code_review/triage/CR-05-findings.md) (P0/P1)

## Goal

Harden `OpenCodeServeCoordinator` so a crashed `opencode serve` child can be restarted,
health proves port ownership (not any random 2xx on :4096), and spawn errors are visible
in stderr instead of masking as `healthCheckTimedOut`.

This directly affects GLM review reliability — Round 2 dogfood showed coordinator gaps
while four parallel slices contended for one serve.

## Copy-paste prompt

```text
You are implementing sprint work order OC-S02 ONLY.

Read ONLY:
- docs/phases/sprint/opencode/OC-S02-serve-lifecycle-hardening.md
- Packages/AllnighterCore/Sources/AllnighterEngine/OpenCodeServeCoordinator.swift

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/OpenCodeServeCoordinator.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/OpenCodeServeCoordinatorTests.swift

Do NOT touch WorkerRunner, OpenCodeServeClient, or batch scripts.

Minimum fixes from CR-05:
1. Retain Process in SpawnState; terminationHandler → releaseSpawn on child exit.
2. Drain or redirect stdout/stderr pipes; surface stderr on spawn/health failure.
3. Port-ownership proof on health (PID matches spawned child, or adopt-or-fail loud).
4. Waiting callers see spawn failure, not a 10s healthCheckTimedOut after loser path.

Proof: swift test --package-path Packages/AllnighterCore --filter OpenCodeServeCoordinator
```

## Read only

- `OpenCodeServeCoordinator.swift` (CR-05 inlined source in triage archive)

## Touch only

- `Packages/AllnighterCore/Sources/AllnighterEngine/OpenCodeServeCoordinator.swift`
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/OpenCodeServeCoordinatorTests.swift`

## Steps

1. Store `Process` (or wrapper) in `SpawnState`; clear claim on `terminationHandler`.
2. Background-drain or nullDevice the spawn pipes; attach captured stderr to errors.
3. Add ownership check: spawned PID owns :4096 before trusting `isHealthy`.
4. Propagate spawn failure to waiters instead of blind 10s poll timeout.
5. Optional: `stop()` for clean teardown before re-spawn.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter OpenCodeServeCoordinator
```

## Done when

- [ ] Child exit clears spawn claim; `ensureRunning` can respawn
- [ ] Spawn stderr visible in thrown errors (not silent timeout)
- [ ] Tests cover exit + respawn path (mocked health/PID)
- [ ] No other production files changed

## Related (backlog from CR-05)

- Derive `defaultURL` from `defaultPort` (P2 drift)
- Lower per-poll health timeout inside wait loop (P2)
