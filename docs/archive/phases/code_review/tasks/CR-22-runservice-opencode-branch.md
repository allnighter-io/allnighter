# CR-22 — RunService OpenCode execution branch

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **RunService.runExecution OpenCode** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Gate acquire before stream
2. Fallback invoke after empty stream
3. spawnConcurrencyLimit
4. Event emission vs terminal

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift` lines 548-615

## Touch only

- `docs/phases/code_review/findings/CR-22.md`

## MCP packet

[`packets/CR-22.json`](../packets/CR-22.json) → expand before dispatch
