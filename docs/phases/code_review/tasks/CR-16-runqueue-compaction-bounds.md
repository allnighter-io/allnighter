# CR-16 — runQueue compaction and infraBackoff bounds

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **PairCoordinator.runQueue retry caps** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Infinite compaction loop
2. infraBackoff 5s spin
3. Separate counters vs executorAttempt
4. Escalate vs planner handoff

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/PairCoordinator.swift` lines 280-295

## Touch only

- `docs/phases/code_review/findings/CR-16.md`

## MCP packet

[`packets/CR-16.json`](../packets/CR-16.json) → expand before dispatch
