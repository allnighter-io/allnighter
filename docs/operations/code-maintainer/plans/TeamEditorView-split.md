# TeamEditorView split plan

Status: **CM-S22–S23 complete** — model + level-2 editor extracted; CM-S24 deferred.
Updated: 2026-08-03
Owner: code-maintainer Structure lens

## Current layout

| MARK Section / Area | LOC | Job |
| --- | ---: | --- |
| Header & `TeamDraft` state | ~181 | Pure in-memory draft state (`TeamDraft`, `TeamDraft.Row`), `isSavable`, and `commit()` catalog persistence |
| View declaration & computed helpers | ~153 | View properties, initializers, `isDefaultAutoTeam`, `resolvedDefaultModelName`, `pickerSkills`, top-level `body` router |
| Header bar, name field & deletion | ~102 | Editor header bar (`TeamVisibility` toggle), team name textfield, custom team delete dialog & action |
| Roster sections (Lead & Workers) | ~107 | `leadSection`, `leadRow`, worker agents list (`workers`), `rosterColumnHeaders`, add/remove agent buttons |
| Model pickers & Scout section | ~114 | Model pickers (`defaultModelCell`, `modelPicker`, `triangulatedModelCell`), `scoutSection` (stage-0 Grok scout & warnings) |
| Posture settings & Footer controls | ~140 | `substitutionsToggle`, `executionPostureSection` (mutating single-CLI source check), `summary`, save/restore/cancel `footer` |
| `MARK: - Edit skill (level 2)` | ~239 | Level-2 `EditSkillView` for editing `skill.md` templates, search/create skill dropdowns, and `WorkerSkillCommit` integration |

**Total:** ~1,036 LOC in one file (`Apps/AllnighterMac/Sources/TeamEditorView.swift`).

## Proposed layout & batches (CM-S22+)

| Batch | File | LOC | Status | Job |
| --- | --- | ---: | --- | --- |
| CM-S22 | `EditSkillView.swift` | ~239 | **done** (`86969cc9`, Gemini) |
| CM-S24 | `TeamEditorView+Roster.swift` | ~221 | **deferred** | Roster/pickers — extract when actively editing |
| Shell | `TeamEditorView.swift` | ~625 | **done** | Editor shell (roster UI remains until CM-S24) |

## Natural seams

1. **`EditSkillView` (Level-2 Detail Editor)**: Lines 799–1037 form a standalone, self-contained subview (`EditSkillView`) that manages level-2 skill template editing and catalog writes via `WorkerSkillCommit`. It communicates with `TeamEditorView` purely via closure callbacks (`onDone`, `onCancel`).
2. **`TeamDraft` State & Catalog Commit**: Lines 9–181 define the pure domain model struct `TeamDraft` (and `Row`) along with validation logic (`isSavable`) and catalog persistence (`commit()`, `resolvedExecutionSourceId`). Moving this out decouples UI components from data model and catalog mutation.
3. **Roster Rows & Model Pickers**: Roster display components (`leadSection`, `leadRow`, `workers`, `rosterColumnHeaders`), model picker helper views (`defaultModelCell`, `modelPicker`, `triangulatedModelCell`), and `scoutSection` can be grouped cleanly into a roster/picker extension.
4. **Editor View Shell**: The main `TeamEditorView` remains as a clean container (~403 LOC) managing top-level state bindings (`draft`, `editingRow`, `editingLead`, `showOnTeamsPage`), header bar navigation, name input, execution posture toggles, deletion confirmation, and save/restore footer actions.

## Risks

1. **Access control (`private` vs `package`/`internal`)**: Extracting `TeamDraft`, `EditSkillView`, and subview extensions from `TeamEditorView.swift` requires adjusting `private` view state properties (such as `draft`, `editingRow`, `editingLead`, `models`, `laneSkills`) to `internal` or passing them explicitly into subview initializers.
2. **SwiftUI `@State` and binding sync**: `EditSkillView` receives bindings/closures from `TeamEditorView`. When moved to its own file, ensure property signatures and closure call sites remain identical so state updates propagate back to `TeamDraft` without UI glitches.
3. **SwiftUI `@ViewBuilder` helper scoping**: Subview methods like `modelPicker` or `defaultModelCell` access `models`, `readyModels`, `draft`, or `onOpenDefaultModel`. When extracted into extensions or subviews, dependencies must be cleanly passed as parameters or scoped properties.

## First extraction batch recommendation

Recommend **CM-S22 (`EditSkillView.swift`)** as the first extraction batch:
- **Low risk**: ~239 LOC at the bottom of the file (lines 799–1037) that is already a distinct `private struct EditSkillView: View`.
- **Clean boundary**: Self-contained level-2 view communicating with `TeamEditorView` only through `onDone` and `onCancel` closures.
- **Immediate gain**: Instantly cuts file size by ~24%, establishing the pattern before touching `TeamDraft` or roster subviews.

## Done when (for future extraction)

- [ ] `TeamEditorView.swift` shell ≤ 500 LOC orchestrating child views and extensions
- [ ] Each extracted file ≤ 500 LOC, focused on one job
- [ ] Green `xcodebuild build -scheme AllnighterMac`
