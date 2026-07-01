# CR-15 — Review terminal semantics for advisory review

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **SliceTerminalClassifier + advisory review** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Check-before-classifier ordering
2. Advisory review should pass on findings+check
3. empty output branch vs tool-only
4. isAdvisoryReview on RunRequest path

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/SliceTerminalClassifier.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/WorkSlicePacket.swift` lines 70-90

## Touch only

- `docs/phases/code_review/findings/CR-15.md`

## MCP packet

[`packets/CR-15.json`](../packets/CR-15.json) → expand before dispatch
