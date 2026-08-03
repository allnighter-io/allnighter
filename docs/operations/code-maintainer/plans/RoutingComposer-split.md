# RoutingComposer split plan

Status: plan only — no code movement authorized beyond CM-S01/S02 (types + attachment tile).
Updated: 2026-08-03
Owner: code-maintainer Structure lens

## Current state (post CM-S01)

| File | LOC | Job |
| --- | ---: | --- |
| `RoutingComposerTypes.swift` | ~130 | Shared compose models + popover key catcher |
| `ComposerAttachmentTile.swift` | ~80 | Attachment chip/tile UI |
| `RoutingComposer.swift` | ~1,450 | Main composer view + target popover + @ file search |

`RoutingComposer.swift` still mixes four concerns:

1. **Send path** — `sendRouting`, auto-resolution, effort/team/model state (~lines 200–430)
2. **Composer chrome** — text field, chips, attachment strip, keyboard shortcuts (~431–1030)
3. **Target popover** — model/team/loop picker UI (~1032–1240)
4. **Target navigation** — highlight/hover/keyboard in popover (~1242–1570)

## Proposed extractions (next batches)

| Batch | New file | Extract from | Proof |
| --- | --- | --- | --- |
| CM-S03 | `RoutingComposerTargetPopover.swift` | Target popover + navigation (sections 3–4) | xcodebuild test AllnighterMac |
| CM-S04 | `RoutingComposerFileSearch.swift` | `@` file-reference session (scan, rank, palette) | xcodebuild + FR-S04 Works Test when palette ships |
| CM-S05 | `RoutingComposerSend.swift` | Send + auto-resolution helpers | AppModelTests / composer send tests |

## Rules

- `RoutingComposer` keeps the `@State` owner — extractions receive bindings/callbacks, not duplicated state.
- No barrel re-exports only (code-maintainer `no-barrel-only-splits` policy).
- `ComposeSpecimen` stays beside `RoutingComposer` until CM-S03 proves the split.

## Done when

- `RoutingComposer.swift` ≤ 600 LOC orchestrating child views
- Each child file ≤ 400 LOC, one MARK-owned job
- Green `xcodebuild test -scheme AllnighterMac`
