# CR-13 — ThreadsViewModel reload coalescing

Status: **ready** (Phase 2)
SSOT: [`Team_Run_Load_Performance.md`](../../Team_Run_Load_Performance.md) PERF-S01

## Goal

Review `reload`, `requestReload`, and `applyLiveDelta` — the PERF-S01 hot path.

## Why this chunk

`ThreadsViewModel` is 1155 lines; chunk **lines 199–257** (~60 LOC): coalesced reload +
in-memory live delta + throttled checkpoint.

## Review lenses

1. `requestReload` Task — can two reloads slip through same tick?
2. `applyLiveDelta` mutates `threads` but not `railRows` — stale rail until reload?
3. `liveCheckpointInterval` — lost data on crash between checkpoints?
4. `store.get` inside hot path every checkpoint — still too heavy?
5. `markReadOnOpen` → `reload()` — bypasses coalescing?

## Read only

- `Apps/AllnighterMac/Sources/ThreadsViewModel.swift` lines 199–257

## Touch only

- `docs/phases/code_review/findings/CR-13.md`

## MCP packet

[`packets/CR-13.json`](../packets/CR-13.json)
