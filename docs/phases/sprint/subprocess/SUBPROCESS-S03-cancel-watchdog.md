# SUBPROCESS-S03 — Cancel timeout watchdog when child exits

Status: **done**
Source: [`code_review/triage/CR-20-findings.md`](../../code_review/triage/CR-20-findings.md) (P1, planner upheld)

## Goal

`SubprocessCommandRunner.run` must cancel its timeout watchdog `Task` when the
child exits normally so completed runs do not retain `Process` + pipe state until
the full timeout elapses.

## Copy-paste prompt

```text
You are implementing sprint work order SUBPROCESS-S03 ONLY.

Read ONLY:
- docs/phases/sprint/subprocess/SUBPROCESS-S03-cancel-watchdog.md
- Packages/AllnighterCore/Sources/AllnighterEngine/SubprocessCommandRunner.swift (run path ~85-144)

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/SubprocessCommandRunner.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/SubprocessCommandRunnerTests.swift (or add minimal test)

In run(): hold the watchdog Task in a variable; call task.cancel() inside
terminationHandler after resumer.claim() succeeds (before resume). Verify
Task.sleep throws CancellationError and does not kill an already-finished process.

Proof: swift test --package-path Packages/AllnighterCore --filter SubprocessCommandRunner
```

## Read only

- `SubprocessCommandRunner.swift` (`run`, lines 85–144)

## Touch only

- `SubprocessCommandRunner.swift`
- Subprocess tests (create if missing)

## Steps

1. `let watchdog = Task { … sleep … }` instead of fire-and-forget `Task`.
2. In `terminationHandler`, after successful `resumer.claim()`, `watchdog.cancel()`.
3. Test: short-lived child completes before timeout; no retained leak (smoke via test timing or mock).

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter SubprocessCommandRunner
```

## Done when

- [ ] Watchdog cancelled on normal child exit
- [ ] Timeout path still kills hung children
- [ ] Tests green

## SSOT

CheckRunner / worker subprocess path
