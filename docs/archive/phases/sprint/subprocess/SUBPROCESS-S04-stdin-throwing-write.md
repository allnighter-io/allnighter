# SUBPROCESS-S04 — Use throwing stdin write (no NSException on EPIPE)

Status: **done**
Source: [`code_review/triage/CR-24-findings.md`](../../code_review/triage/CR-24-findings.md) (P1, planner upheld)

## Goal

Replace deprecated non-throwing `FileHandle.write(_:)` on stdin with
`write(contentsOf:)` so a fast-exiting child cannot crash the host via
`NSFileHandleOperationException` on broken pipe.

## Copy-paste prompt

```text
You are implementing sprint work order SUBPROCESS-S04 ONLY.

Read ONLY:
- docs/phases/sprint/subprocess/SUBPROCESS-S04-stdin-throwing-write.md
- Packages/AllnighterCore/Sources/AllnighterEngine/SubprocessCommandRunner.swift (launch / configure stdin write)

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/SubprocessCommandRunner.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/SubprocessCommandRunnerTests.swift

Replace handle.write(Data(...)) with try? handle.write(contentsOf: Data(...)).
Do not let EPIPE surface as NSException.

Proof: swift test --package-path Packages/AllnighterCore --filter SubprocessCommandRunner
```

## Read only

- `SubprocessCommandRunner.swift` (stdin write in `launch`)

## Touch only

- `SubprocessCommandRunner.swift`
- Subprocess tests

## Steps

1. Find stdin write using deprecated `FileHandle.write(_:)`.
2. Switch to throwing `write(contentsOf:)` with `try?` or handled error.
3. Add regression test or document manual proof if untestable.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter SubprocessCommandRunner
```

## Done when

- [ ] No deprecated non-throwing stdin write on subprocess path
- [ ] Tests green

## SSOT

CHECK-S01 subprocess hardening family
