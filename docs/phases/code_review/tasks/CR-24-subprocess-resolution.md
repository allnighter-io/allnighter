# CR-24 — SubprocessCommandRunner resolution

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **SubprocessCommandRunner resolveExecutable** — bounded hardening slice for GLM serial pass.

## Review lenses

1. resolveExecutable security
2. Env inheritance
3. Partial read hangs
4. Symlink PATH

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/SubprocessCommandRunner.swift` lines 160-336

## Touch only

- `docs/phases/code_review/findings/CR-24.md`

## MCP packet

[`packets/CR-24.json`](../packets/CR-24.json) → expand before dispatch
