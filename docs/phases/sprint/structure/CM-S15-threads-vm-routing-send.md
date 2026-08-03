# CM-S15 — Extract ThreadsViewModel routing send

Status: ready
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move composer send path out of `ThreadsViewModel.swift` into
`ThreadsViewModel+RoutingSend.swift`. **Move only — no behavior change.**

## Copy-paste prompt

```text
Implement CM-S15 only. Read docs/operations/code-maintainer/plans/ThreadsViewModel-split.md.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadsViewModel.swift (remove moved code)
- Apps/AllnighterMac/Sources/ThreadsViewModel+RoutingSend.swift (NEW extension)

Move these members from `// MARK: - Routing composer`:
- applyQuickCapture, sendRouting
- repoRoot(for:)
- runChat
- FileReferenceSendContext struct (move to extension file)
- prepareFileReferenceContext, fileReferenceFailureText
- appendUserTurn, stageRunAttachments
- newChatTitle static, title(from:) static

Use `extension ThreadsViewModel { }`. Widen `private` → `internal` as needed.

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract ThreadsViewModel routing send (CM-S15)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
