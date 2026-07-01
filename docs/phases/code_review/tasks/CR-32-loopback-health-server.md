# CR-32 — LoopbackHealthServer trust

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **LoopbackHealthServer** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Binds 127.0.0.1 only
2. Health info leakage
3. Stop/join lifecycle
4. Port reuse

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/LoopbackHealthServer.swift`

## Touch only

- `docs/phases/code_review/findings/CR-32.md`

## MCP packet

[`packets/CR-32.json`](../packets/CR-32.json) → expand before dispatch
