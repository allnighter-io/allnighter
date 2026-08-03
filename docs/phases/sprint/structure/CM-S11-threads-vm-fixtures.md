# CM-S11 — Extract ThreadsViewModel fixtures

Status: ready
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move `MARK: - GUI fixtures` out of `ThreadsViewModel.swift` into
`ThreadsViewModel+Fixtures.swift`. **Move only — no behavior change.**

## Copy-paste prompt

```text
Implement CM-S11 only. Read docs/operations/code-maintainer/plans/ThreadsViewModel-split.md.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadsViewModel.swift (remove moved code)
- Apps/AllnighterMac/Sources/ThreadsViewModel+Fixtures.swift (NEW extension)

Move the entire `// MARK: - GUI fixtures` section including:
- applyFixture
- seedLiveArtifactFixture (#if DEBUG block)

Use `extension ThreadsViewModel { }`. Preserve all `#if DEBUG` guards.
Widen `private` → `internal` where the extension needs access (store, runStore, models,
registry, liveArtifactByRunId, bumpPublishGeneration, etc.).

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract ThreadsViewModel fixtures (CM-S11)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
