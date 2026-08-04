# CM-S18 — Extract AnswerBody from ThreadView

Status: ready
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move `AnswerBody` and `CopyButton` out of `ThreadView.swift` into `AnswerBody.swift`.
**Move only — no behavior change.**

## Copy-paste prompt

```text
Implement CM-S18 only. Read this file.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadView.swift (remove moved code)
- Apps/AllnighterMac/Sources/AnswerBody.swift (NEW)

Move:
- struct AnswerBody (keep name)
- private struct CopyButton → struct CopyButton in new file

Add required imports. AnswerBody uses ThreadsViewModel environment — keep that.

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract AnswerBody from ThreadView (CM-S18)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
