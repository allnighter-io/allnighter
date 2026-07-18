# CR-12 — RunService write-lock acquisition

Status: **ready** (Phase 2)
SSOT: [`Unified_Run_Model.md`](../../Unified_Run_Model.md)

## Goal

Review mutating-run write-lock acquire/release in `RunService.run`.

## Why this chunk

Lines **226–292** only: queue timing stamp, lock wait, defer release — the path pair slices share.

## Review lenses

1. `defer { Task { await release } }` — release ordering on throw/cancel?
2. 1800s wait timeout vs worker timeout — wedged holder?
3. Read runs skip lock — any mutating preset misclassified?
4. Lock held across entire run including slow worker — queue depth?
5. `RootNormalization.observeRootState` vs lock — race?

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift` lines 226–292

## Touch only

- `docs/phases/code_review/findings/CR-12.md`

## MCP packet

[`packets/CR-12.json`](../packets/CR-12.json)
