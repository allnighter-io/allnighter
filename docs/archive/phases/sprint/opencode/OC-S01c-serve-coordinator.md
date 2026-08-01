# OC-S01c — OpenCode serve coordinator

Status: **superseded — shipped** (archive 2026-08-01)
SSOT: `docs/phases/setup/OpenCode_CLI_Support.md` (V1 Integration Model section)

## Goal

Idempotent `opencode serve --port 4096` lifecycle: start if down, health-check, optional stop.

## Copy-paste prompt

```text
You are implementing sprint work order OC-S01c ONLY.

Read ONLY:
- docs/phases/sprint/opencode/OC-S01c-serve-coordinator.md
- Packages/AllnighterCore/Sources/AllnighterEngine/SubprocessCommandRunner.swift OR any small Process-spawn helper in AllnighterEngine (first 80 lines)

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/OpenCodeServeCoordinator.swift (new)
- Packages/AllnighterCore/Tests/AllnighterEngineTests/OpenCodeServeCoordinatorTests.swift (new, mock HTTP or skip live if hard)

Do NOT touch WorkerRunner, CLIDetector, or Mac app targets.

OpenCodeServeCoordinator API (suggested):
- static let defaultURL = "http://127.0.0.1:4096"
- func ensureRunning() async throws  // start serve if curl health fails
- func isHealthy() async -> Bool      // GET defaultURL returns 2xx

Spawn: `opencode serve --port 4096` detached; poll health up to ~10s.

Proof: swift test --package-path Packages/AllnighterCore --filter OpenCodeServeCoordinator
```

## Read only

- One existing `Process` / subprocess helper in `AllnighterEngine` (pattern only)

## Touch only

- `Packages/AllnighterCore/Sources/AllnighterEngine/OpenCodeServeCoordinator.swift` **(new)**
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/OpenCodeServeCoordinatorTests.swift` **(new)**

## Do not read / do not touch

- `WorkerRunner.swift`, `CLIDetector.swift`, Mac app, manifests

## Steps

1. Add coordinator type with health check (URLSession GET to `127.0.0.1:4096`).
2. `ensureRunning()` spawns `opencode serve --port 4096` if unhealthy.
3. Guard double-start (process already running).
4. Unit test with injectable health checker or document live-test waiver in test skip.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter OpenCodeServeCoordinator
```

## Done when

- [ ] Coordinator compiles in AllnighterEngine
- [ ] Tests pass or one explicit `XCTSkip` with reason (live serve optional)
- [ ] No other production files changed
