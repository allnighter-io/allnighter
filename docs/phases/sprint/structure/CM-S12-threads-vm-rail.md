# CM-S12 — Extract ThreadsViewModel rail + visibility

Status: done (`2d45a77c`, Gemini via `alln run`)
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move timeline visibility + rail controls out of `ThreadsViewModel.swift` into
`ThreadsViewModel+RailControls.swift`. **Move only — no behavior change.**

## Copy-paste prompt

```text
Implement CM-S12 only. Read docs/operations/code-maintainer/plans/ThreadsViewModel-split.md.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadsViewModel.swift (remove moved code)
- Apps/AllnighterMac/Sources/ThreadsViewModel+RailControls.swift (NEW extension)

Move these MARK sections and their helpers:
- `// MARK: - Timeline visibility / read clear (06 S05)` — reportTimelineVisibility,
  applyReadClearIfNeeded
- `// MARK: - Rail controls (07)` — renameThread, setPinned, archiveThread, unarchiveThread,
  togglePin (both overloads), select(threadId:), newThread, newRun
- ProjectScope struct, bindThread, projectScope, scope(forProjectId:), fixtureThread (#if DEBUG)

Use `extension ThreadsViewModel { }`. Widen `private` → `internal` as needed.
ProjectScope can live in the extension file.

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract ThreadsViewModel rail controls (CM-S12)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
