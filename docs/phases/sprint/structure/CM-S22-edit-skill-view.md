# CM-S22 — Extract EditSkillView from TeamEditorView

Status: ready
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move `EditSkillView` out of `TeamEditorView.swift` into `EditSkillView.swift`.
**Move only — no behavior change.** Depends on CM-S23 (`TeamDraft` in own file).

## Copy-paste prompt

```text
Implement CM-S22 only. Read this file.

Touch ONLY:
- Apps/AllnighterMac/Sources/TeamEditorView.swift (remove EditSkillView)
- Apps/AllnighterMac/Sources/EditSkillView.swift (NEW — struct EditSkillView: View)

Move the entire `// MARK: - Edit skill (level 2)` block (`private struct EditSkillView`).
Change `private struct` → `struct`. Add required imports (SwiftUI, AllnighterCore).

Keep call sites in TeamEditorView unchanged (EditSkillView(...) for lead and worker rows).

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract EditSkillView from TeamEditorView (CM-S22)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
