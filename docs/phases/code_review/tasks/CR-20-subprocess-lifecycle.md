# CR-20 — SubprocessCommandRunner lifecycle

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **CommandRunner timeout and zombies** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Timeout kill semantics
2. Zombie after timeout
3. Pipe buffer deadlock
4. Working directory

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/SubprocessCommandRunner.swift` lines 1-160

## Touch only

- `docs/phases/code_review/findings/CR-20.md`

## MCP packet

[`packets/CR-20.json`](../packets/CR-20.json) → expand before dispatch
