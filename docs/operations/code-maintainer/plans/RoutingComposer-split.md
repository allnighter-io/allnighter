# RoutingComposer split plan

Status: **CM-S01–S05 complete** — monolith decomposed into focused extensions.
Updated: 2026-08-03
Owner: code-maintainer Structure lens

## Final layout

| File | LOC | Job |
| --- | ---: | --- |
| `RoutingComposerTypes.swift` | ~130 | Shared compose models + popover key catcher |
| `ComposerAttachmentTile.swift` | ~80 | Attachment chip/tile UI |
| `RoutingComposer.swift` | ~470 | Shell: body, composer box, attachments, effort popover |
| `RoutingComposerTargetPopover.swift` | ~470 | Model/team/loop target popover |
| `RoutingComposerFileSearch.swift` | ~300 | `@` file-reference scan, rank, palette, chips |
| `RoutingComposerSend.swift` | ~235 | Auto-resolution, routing bar, send path |

**Total:** ~1,685 LOC across 6 files (was 1,648 in one file). `RoutingComposer.swift`
orchestrates; each extension owns one job.

## Batches

| Batch | File | Status |
| --- | --- | --- |
| CM-S01 | `RoutingComposerTypes.swift` + `ComposerAttachmentTile.swift` | **done** |
| CM-S02 | `RelayEscalationRow.swift` | **done** |
| CM-S03 | `RoutingComposerTargetPopover.swift` | **done** (`748b2098`) |
| CM-S04 | `RoutingComposerFileSearch.swift` | **done** (`84f31482`) |
| CM-S05 | `RoutingComposerSend.swift` | **done** (this commit) |

## Optional follow-ups (not queued)

- Extract effort popover (`effortChip` / `effortEditPanel`) to `RoutingComposerEffortPopover.swift`
- Extract attachment capture (`captureImage`, `pickImages`) to `RoutingComposerAttachments.swift`

## Done when

- [x] `RoutingComposer.swift` ≤ 600 LOC orchestrating child views
- [x] Each extension file ≤ 500 LOC, one MARK-owned job
- [x] Green `xcodebuild build -scheme AllnighterMac`
