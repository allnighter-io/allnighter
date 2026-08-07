# CM-S09 — Extract RoutingComposer attachment capture

Status: done (`d4e971bb`, Gemini via `alln run`)
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move attachment capture/chip helpers out of `RoutingComposer.swift` into
`RoutingComposerAttachments.swift` (extension on `RoutingComposer`). **Move only.**

## Copy-paste prompt

```text
Implement CM-S09 only. Read this file.

Touch ONLY:
- Apps/AllnighterMac/Sources/RoutingComposer.swift (remove moved code)
- Apps/AllnighterMac/Sources/RoutingComposerAttachments.swift (NEW extension file)

Move these members to the new extension (same signatures, widen private → internal where
needed for cross-file access):
- attachmentChips (computed var)
- captureImage
- captureLongText
- pickImages
- addAttachment
- removeAttachment
- openAttachment

Keep @State owners on RoutingComposer: attachments, attachmentThumbs, composerFocused.
`pickImages` is referenced from RoutingComposerSend.swift — keep it internal.
`captureImage` / `captureLongText` stay wired to ALTextEditor callbacks in RoutingComposer.

Proof:
cd Apps/AllnighterMac && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract RoutingComposer attachments (CM-S09)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
