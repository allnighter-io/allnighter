# CM-S17 — Extract thread turn indicators from ThreadView

Status: ready
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move shared turn-indicator views out of `ThreadView.swift` into `ThreadTurnIndicators.swift`.
**Move only — no behavior change.**

## Copy-paste prompt

```text
Implement CM-S17 only. Read this file.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadView.swift (remove moved code)
- Apps/AllnighterMac/Sources/ThreadTurnIndicators.swift (NEW)

Move these types unchanged to the new file:
- enum ReasoningRenderPolicy
- enum DurationFormat
- struct RunningStatusLabel
- struct StreamingIndicator
- struct WorkingIndicator
- struct ThreadThinkingBlock

Add required imports (SwiftUI, AllnighterCore as needed). Keep public/internal
visibility as today (these are already internal structs/enums).

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract thread turn indicators (CM-S17)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
