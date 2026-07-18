# CR-26 — Timeline read-clear and ThreadTurn kinds

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **TimelineVisibility + ThreadTurn** — bounded hardening slice for GLM serial pass.

## Review lenses

1. countsTowardReadClear coverage
2. Delegate/execute turn kinds
3. UnreadDerivation interaction
4. Perf fix validation

## Read only

- `Apps/AllnighterMac/Sources/TimelineVisibility.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/ThreadTurn.swift` lines 1-120

## Touch only

- `docs/phases/code_review/findings/CR-26.md`

## MCP packet

[`packets/CR-26.json`](../packets/CR-26.json) → expand before dispatch
