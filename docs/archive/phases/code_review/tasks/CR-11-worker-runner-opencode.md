# CR-11 — WorkerRunner OpenCode path

Status: **ready** (Phase 2)
SSOT: [`setup/OpenCode_CLI_Support.md`](../../setup/OpenCode_CLI_Support.md)

## Goal

Review `runOpenCode` — the HTTP serve path every GLM slice uses.

## Why this chunk

`WorkerRunner` is 874 lines; this chunk is **lines 251–331 only** (~80 LOC): ensure serve,
stream vs sync fallback, empty terminal handling.

## Review lenses

1. New `OpenCodeServeCoordinator()` per call — redundant ensure vs PairCoordinator's?
2. Stream ended without terminal — retry-worthy or hard fail?
3. Working directory fallback chain — wrong repo risk?
4. `canStream` branch vs sync — outcome shape parity?
5. Error kind mapping (`emptyOutput` vs `nonzeroExit`) — queue signals?

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/WorkerRunner.swift` lines 251–331

## Touch only

- `docs/phases/code_review/findings/CR-11.md`

## MCP packet

[`packets/CR-11.json`](../packets/CR-11.json) → expand before dispatch
