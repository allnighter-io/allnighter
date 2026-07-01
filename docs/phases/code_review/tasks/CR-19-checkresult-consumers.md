# CR-19 — CheckResult exitCode consumers

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **CheckResult.passed footgun** — bounded hardening slice for GLM serial pass.

## Review lenses

1. skipped GUI exitCode 0
2. Planner takeover exitCode==0 pass
3. Classifier exitCode before skipped
4. nil exitCode spawn failure

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/CheckRunner.swift` lines 1-25
- `Packages/AllnighterCore/Sources/AllnighterEngine/SliceTerminalClassifier.swift` lines 40-47
- `Packages/AllnighterCore/Sources/AllnighterEngine/PairCoordinator.swift` lines 388-400

## Touch only

- `docs/phases/code_review/findings/CR-19.md`

## MCP packet

[`packets/CR-19.json`](../packets/CR-19.json) → expand before dispatch
