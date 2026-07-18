# CR-14 — OpenCodeServeClient streaming

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **OpenCodeServeClient.streamRun** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Tool-only completion vs empty_output
2. IdleGate / session.idle contract
3. Stream timeout vs GLM reasoning
4. Terminal event missing fallback
5. Parser toolActionCount accuracy

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/OpenCodeServeClient.swift`

## Touch only

- `docs/phases/code_review/findings/CR-14.md`

## MCP packet

[`packets/CR-14.json`](../packets/CR-14.json) → expand before dispatch
