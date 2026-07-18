# CR-21 — DriverConcurrencyGate cancellation and timeout

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **DriverConcurrencyGate liveness** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Cancellation drops waiter
2. Acquire timeout
3. withPermit defer release on throw
4. FIFO starvation

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/DriverConcurrencyGate.swift`

## Touch only

- `docs/phases/code_review/findings/CR-21.md`

## MCP packet

[`packets/CR-21.json`](../packets/CR-21.json) → expand before dispatch
