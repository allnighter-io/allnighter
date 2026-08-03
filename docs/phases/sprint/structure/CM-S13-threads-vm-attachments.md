# CM-S13 — Extract ThreadsViewModel attachments

Status: ready
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move attachment resolution/harvest/desktop helpers out of `ThreadsViewModel.swift` into
`ThreadsViewModel+Attachments.swift`. **Move only — no behavior change.**

## Copy-paste prompt

```text
Implement CM-S13 only. Read docs/operations/code-maintainer/plans/ThreadsViewModel-split.md.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadsViewModel.swift (remove moved code)
- Apps/AllnighterMac/Sources/ThreadsViewModel+Attachments.swift (NEW extension)

Move these members:
- runDirectory(forRunId:)
- resolvedAttachments(threadId:turn:)
- HarvestedImages struct
- harvestWorkerImages (private → internal)
- attachmentThumb(for:), openAttachmentPath, revealAttachmentInFinder, copyAttachmentImage
- attachmentThumbCache property

Use `extension ThreadsViewModel { }`. Widen `private` → `internal` as needed.

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract ThreadsViewModel attachments (CM-S13)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
