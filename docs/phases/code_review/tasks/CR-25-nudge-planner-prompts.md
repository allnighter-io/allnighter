# CR-25 — Nudge and planner takeover prompts

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **NudgePrompt + PlannerTakeoverPrompt** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Nudge leaks secrets from tail
2. Takeover check pass definition
3. Context size
4. Planner mutating vs review

## Read only

- `Packages/AllnighterCore/Sources/AllnighterCore/NudgePrompt.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/PlannerTakeoverPrompt.swift`

## Touch only

- `docs/phases/code_review/findings/CR-25.md`

## MCP packet

[`packets/CR-25.json`](../packets/CR-25.json) → expand before dispatch
