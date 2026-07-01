# CR-18 — SliceGate allowlist and check.method

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **SliceGate.evaluate** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Whitespace-only allowlist entries
2. default: break on check.method
3. Fail-closed on unknown methods
4. Scope vs runtime enforcement

## Read only

- `Packages/AllnighterCore/Sources/AllnighterCore/SliceGate.swift`

## Touch only

- `docs/phases/code_review/findings/CR-18.md`

## MCP packet

[`packets/CR-18.json`](../packets/CR-18.json) → expand before dispatch
