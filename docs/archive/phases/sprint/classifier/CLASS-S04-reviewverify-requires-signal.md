# CLASS-S04 — reviewVerify must not pass on empty output

Status: **done**
Source: [`code_review/triage/CR-15-findings.md`](../../code_review/triage/CR-15-findings.md) (P1, planner upheld)

## Goal

A `reviewVerify` slice (`WorkSlicePacket.mode == .reviewVerify`) must not return
`.passed` when the worker emits no visible output — silent verify is not
verification.

## Copy-paste prompt

```text
You are implementing sprint work order CLASS-S04 ONLY.

Read ONLY:
- docs/phases/sprint/classifier/CLASS-S04-reviewverify-requires-signal.md
- Packages/AllnighterCore/Sources/AllnighterEngine/SliceTerminalClassifier.swift
- Packages/AllnighterCore/Sources/AllnighterCore/WorkSlicePacket.swift (mode + isAdvisoryReview)

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/SliceTerminalClassifier.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/SliceTerminalClassifierTests.swift

In classify(): when worker is .done, check passed, and visible output is empty:
- mode .review → .passed (no dissent is OK)
- mode .reviewVerify → .stalled (or .failed) — verify must emit a verdict

Add tests for both modes. Do not change initial review behavior fixed in CLASS-S03.

Proof: swift test --package-path Packages/AllnighterCore --filter SliceTerminalClassifier
```

## Read only

- `SliceTerminalClassifier.swift` (`classify`)
- `WorkSlicePacket.swift` (`mode`, `isAdvisoryReview`)

## Touch only

- `SliceTerminalClassifier.swift`
- `SliceTerminalClassifierTests.swift`

## Steps

1. Branch empty-visible handling on `packet.mode` (not only `isAdvisoryReview`).
2. Keep `.review` empty + green check → `.passed`.
3. `.reviewVerify` empty + green check → `.stalled` (or `.failed` if product prefers).
4. Add unit tests for both modes.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter SliceTerminalClassifier
```

## Done when

- [ ] Verify pass cannot close silent with `.passed`
- [ ] Initial advisory review still passes with empty visible + findings check
- [ ] Tests green

## SSOT

[`Pair_Programming_Team.md`](../../Pair_Programming_Team.md) · CLASS-S03 sibling
