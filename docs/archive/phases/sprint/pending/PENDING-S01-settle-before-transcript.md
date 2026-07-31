# PENDING-S01 — Settle Pending run before transcript write

Status: **done**
Source: [`code_review/triage/CR-23-findings.md`](../../../archive/phases/code_review/triage/CR-23-findings.md) (P1, planner upheld)

## Goal

`PendingRunExecutor.runWorkerChat` must settle the Pending item after the worker
completes even when `writeTranscript` throws — a receipt write failure must not
leave the item stuck in "running".

## Copy-paste prompt

```text
You are implementing sprint work order PENDING-S01 ONLY.

Read ONLY:
- docs/phases/sprint/pending/PENDING-S01-settle-before-transcript.md
- Packages/AllnighterCore/Sources/AllnighterEngine/PendingRunExecutor.swift (runWorkerChat)

Touch ONLY:
- PendingRunExecutor.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/PendingServiceTests.swift (or PendingRunExecutor tests)

Reorder runWorkerChat: settle with outcome first (transcriptRef optional), then
write transcript with try? (mirror teamRun path). Worker work must not be lost on
disk write failure.

Proof: swift test --package-path Packages/AllnighterCore --filter Pending
```

## Read only

- `PendingRunExecutor.swift` (`runWorkerChat`, `writeTranscript`)

## Touch only

- `PendingRunExecutor.swift`
- Pending tests

## Steps

1. Call `settleRun` with outcome before transcript write.
2. Use `try?` for transcript (or settle with nil ref on failure).
3. Test: simulate write failure → item not left running.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter Pending
```

## Done when

- [ ] Transcript failure does not block settlement
- [ ] Tests green

## SSOT

Code SSOT `RunService.swift` (Pending substrate)
