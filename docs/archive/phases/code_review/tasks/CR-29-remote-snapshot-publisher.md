# CR-29 — RemoteSnapshotPublisher consistency

Status: **ready** (Phase 2)
Source: [`follow-up-recommendations.md`](../follow-up-recommendations.md)

## Goal

Review **RemoteSnapshotPublisher** — bounded hardening slice for GLM serial pass.

## Review lenses

1. Snapshot atomicity
2. Stale thread mirror
3. Publish failure retry
4. PII in snapshot

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/RemoteSnapshotPublisher.swift`

## Touch only

- `docs/phases/code_review/findings/CR-29.md`

## MCP packet

[`packets/CR-29.json`](../packets/CR-29.json) → expand before dispatch
