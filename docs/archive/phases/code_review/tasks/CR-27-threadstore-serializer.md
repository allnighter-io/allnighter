# CR-27 — ThreadStore write serialization

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **ThreadStore + ThreadStoreWriteSerializer** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Reentrant synchronized
2. Lane per root forever
3. Symlink duplicate lanes
4. Write coalescing

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ThreadStoreWriteSerializer.swift`
- `Packages/AllnighterCore/Sources/AllnighterEngine/ThreadStore.swift` lines 1-120

## Touch only

- `docs/phases/code_review/findings/CR-27.md`

## MCP packet

[`packets/CR-27.json`](../packets/CR-27.json) → expand before dispatch
