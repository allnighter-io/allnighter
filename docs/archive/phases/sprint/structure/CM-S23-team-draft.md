# CM-S23 — Extract TeamDraft from TeamEditorView

Status: done (`204ac582`, Gemini via `alln run`)
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move `TeamDraft` (pure edit state + `commit()`) out of `TeamEditorView.swift` into
`TeamDraft.swift`. **Move only — no behavior change.**

## Copy-paste prompt

```text
Implement CM-S23 only. Read this file.

Touch ONLY:
- Apps/AllnighterMac/Sources/TeamEditorView.swift (remove TeamDraft)
- Apps/AllnighterMac/Sources/TeamDraft.swift (NEW)

Move the entire `struct TeamDraft` including nested `Row` and all methods
(`init(base:)`, `rowComplete`, `isSavable`, `commit()`, `resolvedExecutionSourceId`).

Add required imports (AllnighterCore). Keep `TeamDraft` and `TeamDraft.Row` internal.

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract TeamDraft from TeamEditorView (CM-S23)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
