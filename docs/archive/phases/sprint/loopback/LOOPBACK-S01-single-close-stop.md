# LOOPBACK-S01 — Single-owner listen FD close in stop()

Status: **done**
Source: [`code_review/triage/CR-31-findings.md`](../../code_review/triage/CR-31-findings.md), [`CR-32-findings.md`](../../code_review/triage/CR-32-findings.md) (P0/P1, planner upheld)

## Goal

`DirectModeCommandServer.stop()` and `LoopbackHealthServer.stop()` must close
the listen socket exactly once. The `DispatchSource` cancel handler already owns
`close(fd)` — remove the duplicate synchronous `close(listenFD)` in `stop()`.

## Copy-paste prompt

```text
You are implementing sprint work order LOOPBACK-S01 ONLY.

Read ONLY:
- docs/phases/sprint/loopback/LOOPBACK-S01-single-close-stop.md
- Packages/AllnighterCore/Sources/AllnighterEngine/DirectModeCommandServer.swift (start/stop)
- Packages/AllnighterCore/Sources/AllnighterEngine/LoopbackHealthServer.swift (start/stop)

Touch ONLY:
- DirectModeCommandServer.swift
- LoopbackHealthServer.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/DirectModeCommandServerTests.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/LoopbackHealthServerTests.swift (if present)

In both servers: stop() should cancel the accept source and clear listenFD;
do NOT also close(listenFD) when cancel handler already closes captured fd.

Proof: swift test --package-path Packages/AllnighterCore --filter 'DirectModeCommandServer|LoopbackHealth'
```

## Read only

- `DirectModeCommandServer.swift` (`start`, `stop`)
- `LoopbackHealthServer.swift` (`start`, `stop`)

## Touch only

- Both server files + existing tests

## Steps

1. Remove `if listenFD >= 0 { close(listenFD) }` from each `stop()` (keep cancel + nil source + `listenFD = -1`).
2. Ensure cancel handler remains sole `close(fd)` owner.
3. Run existing server tests; add stop/start cycle test if missing.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter 'DirectModeCommandServer|LoopbackHealth'
```

## Done when

- [ ] No double-close on stop in either server
- [ ] Tests green

## SSOT

Mac standalone / loopback boundary (`docs/phases/Mac_Standalone_App_And_Background_Coordinator.md`)
