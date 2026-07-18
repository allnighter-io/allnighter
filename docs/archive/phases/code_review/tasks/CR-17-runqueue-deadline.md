# CR-17 — runQueue until deadline mid-slice

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **PairCoordinator.runQueue deadline** — bounded hardening slice for GLM serial pass.

## Review lenses

1. until check inside inner loop
2. compactionGrace sleep vs deadline
3. Task cancellation
4. stoppedReason semantics

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/PairCoordinator.swift` lines 185-210
- `Packages/AllnighterCore/Sources/AllnighterEngine/PairCoordinator.swift` lines 325-350

## Touch only

- `docs/phases/code_review/findings/CR-17.md`

## MCP packet

[`packets/CR-17.json`](../packets/CR-17.json) → expand before dispatch
