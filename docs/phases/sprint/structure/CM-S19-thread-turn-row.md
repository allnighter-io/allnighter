# CM-S19 — Extract ThreadTurnRow from ThreadView

Status: done (`fb4eae45`, Gemini via `alln run`)
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move `ThreadTurnRow` out of `ThreadView.swift` into `ThreadTurnRow.swift`.
**Move only — no behavior change.** Follow `ThreadBoardRow.swift` pattern.

## Copy-paste prompt

```text
Implement CM-S19 only. Read this file.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadView.swift (remove ThreadTurnRow)
- Apps/AllnighterMac/Sources/ThreadTurnRow.swift (NEW — struct ThreadTurnRow: View)

Move the entire ThreadTurnRow struct including userBubble, workerBubble, stubTurn,
and all helpers. Change `private struct` → `struct`.

Also move ThreadAgentGlyph and ThreadAgentHeader to the new file (they are only used
by turn rows).

Keep call site in ThreadTurnTimeline: `ThreadTurnRow(turn:turn, isLastTurn:)` unchanged.

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract ThreadTurnRow from ThreadView (CM-S19)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
