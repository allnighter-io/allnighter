# CLASS-S02 — Classifier infraBackoff ordering on `.done`

Status: **done**
Source: [`code_review/triage/CR-02-findings.md`](../../code_review/triage/CR-02-findings.md) (P1)

## Goal

Ensure `isInfraBackoff` does not classify a `.done` worker as `.infraBackoff` when
terminal output merely contains backoff substrings — run infraBackoff only for
non-terminal worker statuses.

## Copy-paste prompt

```text
You are implementing sprint work order CLASS-S02 ONLY.

Read ONLY:
- docs/phases/sprint/classifier/CLASS-S02-infra-backoff-ordering.md
- Packages/AllnighterCore/Sources/AllnighterEngine/SliceTerminalClassifier.swift

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/SliceTerminalClassifier.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/SliceTerminalClassifierTests.swift (extend)

Do NOT touch PairCoordinator or WorkerRunner.

Move `isInfraBackoff` check after `outcome.status != .done` guard (or gate it on
non-done statuses). Add test: `.done` worker with "busy" in visible text + passed
check → `.passed`, not `.infraBackoff`.

Proof: swift test --package-path Packages/AllnighterCore --filter SliceTerminalClassifier
```

## Read only

- `SliceTerminalClassifier.swift` (lines ~30–50)

## Touch only

- `Packages/AllnighterCore/Sources/AllnighterEngine/SliceTerminalClassifier.swift`
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/SliceTerminalClassifierTests.swift`

## Steps

1. Reorder guards so infraBackoff substring match applies only when status is not `.done`.
2. Add regression test for done + backoff-like substring + check passed.
3. Run classifier tests.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter SliceTerminalClassifier
```

## Done when

- [x] `.done` outcomes never classified as `.infraBackoff` via substring alone
- [x] Existing classifier tests still pass
- [x] No other production files changed
