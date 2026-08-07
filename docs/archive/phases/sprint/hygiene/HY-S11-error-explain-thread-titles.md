# HY-S11 — Error explain strings + loop thread titles

Status: ready
Owner: hygiene / product vocabulary
Updated: 2026-08-03

## Goal

Agent/user-facing error explain text and loop thread title projection: retire
`PM Relay` product noun. `docs/phases/PM_Relay.md` doc path → title `Delivery Loop`
(not `Delivery Loop: PM Relay`).

## Copy-paste prompt

```text
Implement HY-S11 only. Read this file.

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift
  (RELAY_NOT_FOUND explain string only)
- Packages/AllnighterCore/Sources/AllnighterEngine/LoopThreadProjector.swift
  (title(forDocPath:) — when stem normalizes to "PM Relay", return "Delivery Loop")
- Packages/AllnighterCore/Tests/AllnighterEngineTests/LoopThreadProjectionTests.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/StalledWorkDetectorTests.swift
  (fixture title "PM Relay: museum" → "Loop: museum")

In comments in ThreadTurn.swift, LoopState.swift, LoopJSON.swift,
ProjectWorkerReadinessProjector.swift, LoopEngineCLI.swift:
- "PM Relay" → "Loop" in // and /// lines only (if in allowlist above, skip others).

Actually touch ONLY the four files listed in Touch ONLY above.

Proof:
scripts/swift-test.sh --filter 'RetiredVocabulary|LoopThreadProjection|StalledWork'

Commit only listed files.
Message: docs(core): loop error explain + thread titles PM Relay → Loop
```

## Works Test

```text
scripts/swift-test.sh --filter 'RetiredVocabulary|LoopThreadProjection|StalledWork'
```
