# CHECK-S01 — CheckRunner minimal subprocess environment

Status: **done**
Source: [`code_review/triage/CR-04-findings.md`](../../code_review/triage/CR-04-findings.md) (P0)

## Goal

Stop forwarding the full host `ProcessInfo.processInfo.environment` into repo-declared
`/bin/sh -c` check subprocesses — a secret-exfiltration surface when stdout/stderr is
captured into `CheckResult.stdoutTail`.

## Copy-paste prompt

```text
You are implementing sprint work order CHECK-S01 ONLY.

Read ONLY:
- docs/phases/sprint/checkrunner/CHECK-S01-minimal-subprocess-env.md
- Packages/AllnighterCore/Sources/AllnighterEngine/CheckRunner.swift

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/CheckRunner.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/CheckRunnerTests.swift (new or extend)

Do NOT touch WorkSlicePacket, PairCoordinator, or other runners.

Replace `env: ProcessInfo.processInfo.environment` with an explicit minimal map:
PATH, HOME, LANG, TMPDIR, plus allowlisted `ALLN_*` vars. Strip known credential
prefixes (OPENAI_, ANTHROPIC_, FEATHERLESS_, etc.) even if accidentally present.

Proof: swift test --package-path Packages/AllnighterCore --filter CheckRunner
```

## Read only

- `CheckRunner.swift` (inlined in CR-04 findings)

## Touch only

- `Packages/AllnighterCore/Sources/AllnighterEngine/CheckRunner.swift`
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/CheckRunnerTests.swift`

## Steps

1. Add `CheckRunner.minimalCheckEnvironment()` (or similar) building the allowlisted map.
2. Use it in the `.command` branch instead of full parent env.
3. Test: subprocess does not see a planted secret env var; PATH/HOME still present.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter CheckRunner
```

## Done when

- [x] Check subprocess no longer inherits full parent env
- [x] Tests prove secret keys are stripped
- [x] No other production files changed

## Related (backlog from CR-04)

- **CHECK-S02** — `CheckResult`: never `exitCode: 0` on skipped GUI/observation branch
- **CHECK-S03** — `WorkSlicePacket.Check`: document/enforce repo-declared provenance for `command`
