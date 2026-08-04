# CM-S20 — Extract ThreadTurnTimeline from ThreadView

Status: ready
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move `ThreadTurnTimeline` out of `ThreadView.swift` into `ThreadTurnTimeline.swift`.
**Move only — no behavior change.**

## Copy-paste prompt

```text
Implement CM-S20 only. Read this file.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadView.swift (remove ThreadTurnTimeline)
- Apps/AllnighterMac/Sources/ThreadTurnTimeline.swift (NEW — struct ThreadTurnTimeline: View)

Move the entire ThreadTurnTimeline struct including scrollTimelineToOpenPosition.
Change `private struct` → `struct`. Add required imports.

Keep usage in ThreadConversationBody unchanged.

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract ThreadTurnTimeline from ThreadView (CM-S20)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
