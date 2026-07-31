# WATCHDOG-S01 — Slow GLM / pair-aware stall threshold

Status: **done**
Source: [`code_review/triage/CR-07-findings.md`](../../code_review/triage/CR-07-findings.md) (P1)

## Goal

Stop false stall detection for slow GLM pair-programming slices — either lengthen
threshold for advisory/pair runs or key off `input.runs` / observable events instead
of a fixed 30-minute `workerChatSeconds` for all workloads.

## Copy-paste prompt

```text
You are implementing sprint work order WATCHDOG-S01 ONLY.

Read ONLY:
- docs/phases/sprint/watchdog/WATCHDOG-S01-slow-glm-threshold.md
- Packages/AllnighterCore/Sources/AllnighterEngine/StalledWorkDetector.swift
- Packages/AllnighterCore/Sources/AllnighterEngine/PairCoordinator.swift (how detector is fed — read only)

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/StalledWorkDetector.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/StalledWorkDetectorTests.swift (extend)

Adjust threshold for pair/advisory contexts OR require progress signals from runs
before declaring stall. Do not break fast-fail for truly stuck default chat.

Proof: swift test --package-path Packages/AllnighterCore --filter StalledWorkDetector
```

## Read only

- `StalledWorkDetector.swift` (`workerChatSeconds = 30 * 60`)
- Pair coordinator stall wiring (read-only)

## Touch only

- `StalledWorkDetector.swift`
- `StalledWorkDetectorTests.swift`

## Steps

1. Add configuration or mode for long-running worker review (e.g. 90–120 min or disabled when advisory).
2. Optionally incorporate `input.runs` heartbeat if already available on detector input.
3. Test: slow-but-active run below new threshold does not stall; idle run still stalls.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter StalledWorkDetector
```

## Done when

- [x] GLM code-review slices survive realistic duration without false stall
- [x] True idle stall still detected
- [x] Threshold documented in detector API
