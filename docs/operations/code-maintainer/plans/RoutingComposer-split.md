# RoutingComposer split plan

Status: **CM-S01–S09 complete** — monolith decomposed into focused extensions.
Updated: 2026-08-03
Owner: code-maintainer Structure lens

## Final layout

| File | LOC | Job |
| --- | ---: | --- |
| `RoutingComposerTypes.swift` | ~130 | Shared compose models + popover key catcher |
| `ComposerAttachmentTile.swift` | ~80 | Attachment chip/tile UI |
| `RoutingComposer.swift` | ~308 | Shell: body, composer box |
| `RoutingComposerAttachments.swift` | ~90 | Attachment chips, paste/pick capture, open/remove |
| `RoutingComposerEffortPopover.swift` | ~86 | Effort chip + edit panel + key monitor |
| `RoutingComposerTargetPopover.swift` | ~470 | Model/team/loop target popover |
| `RoutingComposerFileSearch.swift` | ~300 | `@` file-reference scan, rank, palette, chips |
| `RoutingComposerSend.swift` | ~235 | Auto-resolution, routing bar, send path |

**Total:** ~1,622 LOC across 8 files (was 1,648 in one file). `RoutingComposer.swift`
orchestrates; each extension owns one job.

## Batches

| Batch | File | Status |
| --- | --- | --- |
| CM-S01 | `RoutingComposerTypes.swift` + `ComposerAttachmentTile.swift` | **done** |
| CM-S02 | `RelayEscalationRow.swift` | **done** |
| CM-S03 | `RoutingComposerTargetPopover.swift` | **done** (`748b2098`) |
| CM-S04 | `RoutingComposerFileSearch.swift` | **done** (`84f31482`) |
| CM-S05 | `RoutingComposerSend.swift` | **done** (`354f17e9`) |
| CM-S06 | `RoutingComposerEffortPopover.swift` | **done** (`1679c5c2`, Gemini via `alln run`) |
| CM-S09 | `RoutingComposerAttachments.swift` | **done** (`d4e971bb`, Gemini via `alln run`) |

## Optional follow-ups (not queued)

- Extract `captureLongText` wiring if ever split further from attachments extension

## Done when

- [x] `RoutingComposer.swift` ≤ 600 LOC orchestrating child views
- [x] Each extension file ≤ 500 LOC, one MARK-owned job
- [x] Green `xcodebuild build -scheme AllnighterMac`
