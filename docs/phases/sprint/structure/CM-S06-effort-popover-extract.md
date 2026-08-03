# CM-S06 — Extract effort popover from RoutingComposer

Status: ready
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move `effortChip`, `effortEditPanel`, `effortPickerRows`, and `effortKeyMonitor`
out of `RoutingComposer.swift` into `RoutingComposerEffortPopover.swift`
(extension on `RoutingComposer`). **Move only — no behavior change.**

## Copy-paste prompt

```text
Implement CM-S06 only. Read this file.

Touch ONLY:
- Apps/AllnighterMac/Sources/RoutingComposer.swift (remove moved code)
- Apps/AllnighterMac/Sources/RoutingComposerEffortPopover.swift (new extension file)

Move these members to the new extension (same signatures, remove private where
needed for cross-file access):
- effortChip
- effortEditPanel
- effortPickerRows
- effortKeyMonitor

Keep @State owner on RoutingComposer: effortOpen, effortHighlight, effort.
effortEditPanel is also called from RoutingComposerTargetPopover.swift — keep it
internal on RoutingComposer (already is).

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two files above.
Message: refactor(mac): extract RoutingComposer effort popover (CM-S06)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
