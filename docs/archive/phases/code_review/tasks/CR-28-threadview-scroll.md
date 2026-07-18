# CR-28 — ThreadView scroll and live-follow

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **ThreadView scroll policy** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Live-follow only at bottom
2. Double scrollToBottom
3. Thread open position
4. Streaming tail anchor

## Read only

- `Apps/AllnighterMac/Sources/ThreadView.swift` lines 265-360

## Touch only

- `docs/phases/code_review/findings/CR-28.md`

## MCP packet

[`packets/CR-28.json`](../packets/CR-28.json) → expand before dispatch
