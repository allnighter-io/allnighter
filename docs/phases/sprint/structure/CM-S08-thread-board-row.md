# CM-S08 — Extract ThreadBoardRow from ThreadView

Status: ready
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move `ThreadBoardRow` out of `ThreadView.swift` into `ThreadBoardRow.swift`.
**Move only — no behavior change.** Follow `RelayEscalationRow.swift` pattern.

## Copy-paste prompt

```text
Implement CM-S08 only. Read this file.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadView.swift (remove ThreadBoardRow)
- Apps/AllnighterMac/Sources/ThreadBoardRow.swift (NEW — struct ThreadBoardRow: View)

Move the entire `private struct ThreadBoardRow` block (// MARK: - CR4c team board)
including all helpers (`workerTitle`, `answerPreview`, `answerCard`, `workerTurnStatus`).

Change `private struct` → `struct` in the new file. Add required imports (SwiftUI,
AllnighterCore, AllnighterEngine as needed — match RelayEscalationRow.swift).

Keep the call site in ThreadView: `ThreadBoardRow(turn: turn)` unchanged.

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract ThreadBoardRow from ThreadView (CM-S08)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
