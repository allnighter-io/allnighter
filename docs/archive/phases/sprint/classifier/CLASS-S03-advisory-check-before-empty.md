# CLASS-S03 — Advisory review: check before empty-output stall

Status: **done**
Source: [`code_review/triage/CR-02-findings.md`](../../code_review/triage/CR-02-findings.md) (P1)

## Goal

Stop classifying successful advisory-review slices as `.stalled` when the worker
writes findings to disk but leaves `visible` output empty — evaluate check result
before the empty-output stall rule.

## Copy-paste prompt

```text
You are implementing sprint work order CLASS-S03 ONLY.

Read ONLY:
- docs/phases/sprint/classifier/CLASS-S03-advisory-check-before-empty.md
- Packages/AllnighterCore/Sources/AllnighterEngine/SliceTerminalClassifier.swift
- Packages/AllnighterCore/Sources/AllnighterCore/WorkSlicePacket.swift (isAdvisoryReview only)

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/SliceTerminalClassifier.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/SliceTerminalClassifierTests.swift

When `advisoryReview` is true OR check is not skipped: evaluate check.passed/skipped
BEFORE returning `.stalled` for empty visible text on `.done` workers.

Add test: advisoryReview + empty visible + check passed → `.passed`.

Proof: swift test --package-path Packages/AllnighterCore --filter SliceTerminalClassifier
```

## Read only

- `SliceTerminalClassifier.swift` (`classify` method)
- `WorkSlicePacket.isAdvisoryReview`

## Touch only

- `SliceTerminalClassifier.swift`
- `SliceTerminalClassifierTests.swift`

## Steps

1. Reorder: for `.done`, if check passed/skipped → return before empty-visible stall.
2. Optionally narrow empty-visible stall to non-advisory runs only.
3. Regression test mirroring GLM code-review slice (file write, empty chat).

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter SliceTerminalClassifier
```

## Done when

- [ ] Advisory review with passed check never returns `.stalled` for empty visible
- [ ] Non-advisory empty-output stall behavior preserved
- [ ] Tests prove dogfood path
