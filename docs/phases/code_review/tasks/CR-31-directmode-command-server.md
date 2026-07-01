# CR-31 — DirectModeCommandServer boundary

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **DirectModeCommandServer handlers** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Unauthenticated local access
2. Command injection
3. Snapshot path escape
4. Concurrent handlers

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/DirectModeCommandServer.swift` lines 520-650

## Touch only

- `docs/phases/code_review/findings/CR-31.md`

## MCP packet

[`packets/CR-31.json`](../packets/CR-31.json) → expand before dispatch
