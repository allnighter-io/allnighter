# HY-S10 — Loop prompt headers (PM Relay → Loop)

Status: ready
Owner: hygiene / product vocabulary
Updated: 2026-08-03

## Goal

Live worker prompt header lines in `LoopPrompts.swift`: `# PM Relay —` → `# Loop —`.
Update matching test assertions. **Prompt semantics unchanged — header noun only.**

## Copy-paste prompt

```text
Implement HY-S10 only. Read this file.

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterCore/LoopPrompts.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/LoopCoordinatorTests.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/PilotCoordinatorTests.swift

In LoopPrompts.swift string literals:
- "# PM Relay —" → "# Loop —" (all three header sites)

In tests: update assertions/comments that check for the old header text.

Do NOT touch GUI, ContractRegistry, or LoopThreadProjector.

Proof:
scripts/swift-test.sh --filter 'LoopCoordinator|PilotCoordinator'

Commit only listed files.
Message: docs(prompts): loop prompt headers PM Relay → Loop
```

## Works Test

```text
scripts/swift-test.sh --filter 'LoopCoordinator|PilotCoordinator'
```
