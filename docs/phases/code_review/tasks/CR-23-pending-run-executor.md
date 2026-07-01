# CR-23 — PendingRunExecutor queue drain

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **PendingRunExecutor** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Pending file durability
2. Concurrent drain
3. Failed pending retry
4. Origin tagging

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/PendingRunExecutor.swift`

## Touch only

- `docs/phases/code_review/findings/CR-23.md`

## MCP packet

[`packets/CR-23.json`](../packets/CR-23.json) → expand before dispatch
