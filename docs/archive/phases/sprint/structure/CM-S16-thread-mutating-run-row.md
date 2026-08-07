# CM-S16 — Extract ThreadMutatingRunRow from ThreadView

Status: done (`04983459`, Gemini via `alln run`)
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move `ThreadMutatingRunRow` out of `ThreadView.swift` into `ThreadMutatingRunRow.swift`.
**Move only — no behavior change.** Follow `ThreadBoardRow.swift` pattern.

## Copy-paste prompt

```text
Implement CM-S16 only. Read this file.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadView.swift (remove ThreadMutatingRunRow)
- Apps/AllnighterMac/Sources/ThreadMutatingRunRow.swift (NEW — struct ThreadMutatingRunRow: View)

Move the entire `// MARK: - Mutating run row` block including all helpers
(displayText, parkBanner, content, resultCard, attachmentRow, etc.).

Change `private struct` → `struct` in the new file. Add required imports (SwiftUI,
AllnighterCore, AllnighterEngine, AgentOSTeam as needed — match ThreadBoardRow.swift).

Keep the call site in ThreadView: `ThreadMutatingRunRow(turn: turn, isLastTurn: isLastTurn)` unchanged.

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract ThreadMutatingRunRow from ThreadView (CM-S16)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
