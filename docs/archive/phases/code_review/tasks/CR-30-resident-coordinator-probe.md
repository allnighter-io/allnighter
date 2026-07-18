# CR-30 — ResidentCoordinatorProbe liveness

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **ResidentCoordinatorProbe** — bounded hardening slice for GLM serial pass.

## Review lenses

1. PID reuse false positive
2. Probe interval vs hang
3. Coordinator restart
4. Menu bar state lie

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ResidentCoordinatorProbe.swift`

## Touch only

- `docs/phases/code_review/findings/CR-30.md`

## MCP packet

[`packets/CR-30.json`](../packets/CR-30.json) → expand before dispatch
