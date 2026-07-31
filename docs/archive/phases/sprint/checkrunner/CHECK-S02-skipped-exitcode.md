# CHECK-S02 — Skipped check must not report exitCode 0

Status: **done**
Source: [`code_review/triage/CR-04-findings.md`](../../code_review/triage/CR-04-findings.md) (P1)

## Goal

When a check is skipped (GUI fixture / observation branch), `CheckResult.exitCode`
must not be `0` — consumers treat `0` as success; use a sentinel or omit success signal.

## Copy-paste prompt

```text
You are implementing sprint work order CHECK-S02 ONLY.

Read ONLY:
- docs/phases/sprint/checkrunner/CHECK-S02-skipped-exitcode.md
- Packages/AllnighterCore/Sources/AllnighterEngine/CheckRunner.swift

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/CheckRunner.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/CheckRunnerTests.swift

For `.guiFixture` / skipped branches: set exitCode to nil or explicit skipped sentinel;
never `exitCode: 0` with `skipped: true`. Update any classifier consumer expectations in tests only.

Proof: swift test --package-path Packages/AllnighterCore --filter CheckRunner
```

## Read only

- `CheckRunner.swift` (GUI/skipped branch ~line 57)

## Touch only

- `CheckRunner.swift`
- `CheckRunnerTests.swift`

## Steps

1. Change skipped branch `exitCode` from `0` to `nil` (or documented sentinel).
2. Test asserts skipped result is not interpreted as command success.
3. Do not change command-runner branch.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter CheckRunner
```

## Done when

- [x] Skipped checks never emit `exitCode: 0`
- [x] Tests cover GUI fixture path
- [x] Single-file production change (+ tests)
