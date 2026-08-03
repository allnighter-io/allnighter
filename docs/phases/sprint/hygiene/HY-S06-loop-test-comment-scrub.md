# HY-S06 — Loop test comment scrub

Status: ready
Owner: hygiene / comment truth
Updated: 2026-08-03

## Goal

Test file comments that teach `pair relay` → `alln loop` prose. Comments only.

## Copy-paste prompt

```text
Implement HY-S06 only.

Touch ONLY // and /// comment lines in:
- Packages/AllnighterCore/Tests/AllnighterEngineTests/LoopCoordinatorTests.swift
- Packages/AllnighterCore/Tests/AllnighterCoreTests/LoopJSONTests.swift
- Packages/AllnighterCore/Tests/AllnighterCoreTests/FixtureRoundTripTests.swift

Replace comment teaching prose: pair relay → alln loop (+ subcommands).
Do NOT change test code, assertions, string literals in tests, or symbol names.

Proof: scripts/swift-test.sh --filter 'LoopCoordinatorTests|LoopJSONTests|FixtureRoundTrip'

Commit only those three test files.
Message: docs(test): loop comment scrub in loop-related tests
```

## Works Test

```text
scripts/swift-test.sh --filter 'LoopCoordinatorTests|LoopJSONTests|FixtureRoundTrip'
```
