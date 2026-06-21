# GUI Bug Handoff

**Date reported:** 2026-06-20  
**Status:** Intake only. Do not treat this file as an implementation plan or proof of a fix.  
**Surfaces:** Team launcher, Team Studio, Customize Teams, Composer.  
**Reporter evidence:** User reports plus screenshots from the original Codex requests.

## User-Reported Bugs

### 1. `Add team` on main Team page routes to CLI Setup

**Priority:** P1 / workflow blocker.  
**Surface:** Main Teams page / Team launcher (`TEAMS · YOUR ROSTER`).  
**Observed:** Pressing the primary `Add team` button on the main Team page sends the user to CLI Setup. The user wants to create a team from this action.  
**Expected:** `Add team` should start a create-team flow: open Team Studio on the Teams route and/or directly create a new unsaved team draft. It must not route to CLI Setup unless the user explicitly chose a CLI/setup action.  
**Impact:** The primary roster action breaks the user's mental model and blocks team creation from the place where creation is advertised.  
**Notes for dev:** `TeamsLauncherView` owns the visible button. `TeamStudioView` already has a `newDraftBase` / `addTeamButton` path that creates a blank unsaved team. Check whether the launcher is opening `TeamStudioView` with its default route (`.clis`) instead of a Teams route, and whether it lacks a way to request the new-team draft once Studio opens.

### 2. Duplicate `Auto` option in Customize Teams model dropdown

**Priority:** P1 / biggest dropdown bug.  
**Surface:** Team Studio → Customize Teams → worker model dropdowns.  
**Observed:** The opened model dropdown shows `Auto` twice at the top. Both visible `Auto` rows appear selected with checkmarks.  
**Expected:** `Auto` should appear exactly once as the nil/default model choice. If selected, only that single row should carry the selected/check state.  
**Notes for dev:** `Auto` is the default model concept, not a concrete catalog model duplicate. Confirm whether the dropdown is combining the explicit `Auto` sentinel with a concrete model whose display name is also `Auto` (for example Cursor Agent Auto), then dedupe by identity/semantics rather than label-only guesswork.

### 3. Return/Enter in Composer should send, Shift+Return should newline

**Priority:** P1 / core composer usability.  
**Surface:** Composer prompt editor.  
**Observed:** Pressing Return or Enter in the Composer does not submit/send the prompt the way Cursor does.  
**Expected:** Match Cursor behavior: plain Return or Enter sends the prompt. Shift+Return or Shift+Enter inserts a line break. Empty/disabled sends should still be blocked by the existing send rules.  
**Impact:** The primary chat/composer muscle memory is inverted; users expect Enter to send and only use Shift+Enter for multiline input.  
**Notes for dev:** Preserve special composer subflows. If the `@` file-reference picker is open, Return may still need to accept the highlighted file reference before normal send behavior resumes. Outside those subflows, plain Return/Enter should call the same send path as the send button.

### 4. Composer attachment icon does nothing and reads as photo-only

**Priority:** P1 for dead action; P2 for icon/attachment-scope mismatch.  
**Surface:** Composer prompt editor.  
**Observed:** Pressing the photo/image icon in the Composer does not open an attachment flow or otherwise respond. The icon also implies photos only.  
**Expected:** Pressing the attachment control should work. It should let the user attach supported files to the next turn. The affordance should be a general attachment control, likely a paperclip icon, because users should be able to attach documents too, not just photos.  
**Impact:** The composer advertises attachment support but the control is inert, and the current photo icon under-communicates the intended scope.  
**Notes for dev:** Current image attachment contracts appear image-first. If document attachments are not yet supported in Core/CLI/MCP, either wire the supported image flow honestly and split document support into a scoped contract, or extend the attachment contract deliberately. Do not make arbitrary document files look attached if they are not included in the worker context.

### 5. Up/down arrows do not select Customize Teams dropdown rows

**Priority:** P2 / keyboard usability.  
**Surface:** Team Studio → Customize Teams → worker model dropdowns.  
**Observed:** With the dropdown open, the user cannot use up/down arrow keys to move the row selection.  
**Expected:** Up/down should move an active highlight through dropdown rows; return should pick the highlighted row. This should match the behavior already added to the searchable Compose / Customize-worker style popup.  
**Notes for dev:** `ALSearchableDropdown` already has `highlighted`, `onKeyPress(.downArrow)`, `onKeyPress(.upArrow)`, `onKeyPress(.return)`, and `.onHover` handling. The simpler `ALDropdown` used for model pickers likely needs the same interaction model.

### 6. Mouse hover does not display the selected Customize Teams dropdown row correctly

**Priority:** P2 / visual feedback regression.  
**Surface:** Team Studio → Customize Teams → worker model dropdowns.  
**Observed:** Mousing over the selected row does not display the row state correctly. The user notes this was already fixed in the Compose popup / overlay form.  
**Expected:** Hover and selected states should be visible and coherent. The selected row should remain visibly selected; the hovered row should highlight; when the hovered row is also selected, it should still read as selected.  
**Notes for dev:** Reuse the interaction/state treatment from the Compose popup or `ALSearchableDropdown` rather than inventing a separate hover style.

## Repro Sketch

### `Add team` routes to CLI Setup

1. Open Allnighter Mac app.
2. Go to the main Team page / Team launcher.
3. Press the primary `Add team` button beside the search field.
4. Observe that the app routes to CLI Setup.
5. Expected: a team creation flow opens instead.

### Composer Return/Enter send behavior

1. Open a normal Composer prompt editor.
2. Type a prompt.
3. Press Return or Enter.
4. Expected: the prompt sends, same as pressing the send button.
5. Type a multiline prompt and press Shift+Return or Shift+Enter.
6. Expected: a newline is inserted instead of sending.
7. Check the `@` file-reference flow separately so Return still accepts the highlighted file when that picker is open.

### Composer attachment control

1. Open a normal Composer prompt editor.
2. Press the photo/image icon in the composer bar.
3. Expected: an attachment picker or supported attachment flow opens.
4. Observe whether any attachment chip/state appears after choosing a file.
5. Expected affordance: use a general attachment icon such as paperclip if the flow accepts documents as well as images.

### Customize Teams dropdown bugs

1. Open Allnighter Mac app.
2. Go to Team Studio / Customize Teams.
3. Open a worker model dropdown in the team editor.
4. Verify the first rows in the model list.
5. Try arrow-key navigation and mouse hover over the selected `Auto` row.

## Likely Touchpoints

- `Apps/AllnighterMac/Sources/TeamsLauncherView.swift`
  - Owns the main `Add team` button shown on the roster page.
- `Apps/AllnighterMac/Sources/RootView.swift`
  - Wires `TeamsLauncherView(onAddTeam:)`; current behavior should be checked for defaulting Team Studio to `.clis`.
- `Apps/AllnighterMac/Sources/TeamStudioView.swift`
  - `StudioRoute` defaults to `.clis`.
  - `StudioTeamListView` already has `newDraftBase` and an inline `addTeamButton` that creates a blank team draft.
- `Apps/AllnighterMac/Sources/RoutingComposer.swift`
  - Owns the send button, `performSend()`, and `handleEditorCommand(_:)`.
  - Current send button advertises Command+Return; future behavior should decide whether that remains as an extra shortcut while plain Return becomes primary.
  - Also contains the composer attachment icon button; current touchpoint appears to be `IconButton(systemImage: "photo", accessibilityLabel: "Attach image", small: true) {}`.
- `Apps/AllnighterMac/Sources/AllnighterTextEditor.swift`
  - `ALTextEditor` maps `insertNewline(_:)` to `.returnKey`; this is the likely interception point for plain Return/Enter versus Shift+Return/Shift+Enter.
- `Apps/AllnighterMac/Sources/TeamEditorView.swift`
  - `modelPicker(_:, onPick:)` currently prepends an explicit `Auto` sentinel before model catalog entries.
  - Worker editor model dropdown also uses `ALDropdown`.
- `Apps/AllnighterMac/Sources/AllnighterDropdowns.swift`
  - `ALDropdown` renders option rows and selected checkmarks.
  - `ALSearchableDropdown` is the local reference for keyboard highlight and hover behavior.
- `Packages/AllnighterCore/Sources/AllnighterCore/ModelCatalog.swift`
  - Contains concrete model entries, including a model whose display name may be `Auto`.
- `Packages/AllnighterCore/Sources/AllnighterCore/DefaultModelSettings.swift`
  - Owns the default-model / `Auto` semantics.

## Relevant Prior Art

- `docs/qa/gui/teams-launcher/2026-06-19-favorites-featured/watcher.md`
  - Confirms the `+ Add team` button renders on the Team launcher, but does not prove the action opens the right flow.
- `docs/phases/Team_And_Skill_Catalogs.md`
  - Owns custom team creation/editing semantics and CLI commands.
- `docs/phases/Composer_File_References.md`
  - Relevant because Return already has a picker-accept behavior while an `@` file-reference panel is open.
- `docs/phases/Composer_Image_Attachments.md`
  - Owns the built image attachment contract and calls out GUI gaps. It is image-focused; document attachment support may need a separate contract extension.
- `docs/qa/gui/studio/2026-06-17-combo-keys/watcher.md`
  - Notes keyboard behavior added for dropdown popovers.
- `docs/phases/wiring/design_handoff_default_substitutions/README.md`
  - Defines `Auto` as the default model concept and says pickers should render that shared contract.
- `docs/phases/wiring/design_handoff_cli_setup_redesign/README.md`
  - Defines the available-model set used by model pickers.
- `docs/gui/patterns/Anchored_Popups.md`
  - Popup anchoring rule for dropdown work.

## Debug Packet Starter

### `Add team` routes to CLI Setup

**Tier:** T1 Boundary; escalate to T2 only if investigation finds Team Studio route/state is inventing catalog truth or losing draft persistence.  
**Symptom / repro:** Main Team page `Add team` button routes to CLI Setup instead of team creation.  
**Bug fingerprint:** `TeamsLauncherView` `Add team` action + wrong `TeamStudioView` initial route / missing new-draft intent.  
**Truth owner:** Team catalog / Team Studio team editor flow.  
**Lie-prone layer:** Root-level navigation wiring from the Team launcher.  
**Regression considered:** Team Studio already has a `New <lane> team` draft path; launcher action may have been wired only to "open settings" and inherited the default `.clis` route.  
**Missing kill test / proof:** UI/navigation test or fixture that invokes `Add team` from the Team launcher and proves the resulting view is a team draft, not CLI Setup.  
**Fix boundary:** Navigation and new-team intent only. Do not change CLI Setup, model readiness, team catalog persistence, or built-in team semantics unless separate evidence requires it.  
**Proof command / founder test:** Run targeted Swift tests plus the narrowest GUI fixture that can show Team launcher → team creation. Founder test: press `Add team`; a new editable team appears with a team name and worker rows ready to edit.

### Composer Return/Enter send behavior

**Tier:** T1 Boundary; escalate to T2 only if the change touches thread/run dispatch semantics beyond invoking the existing send path.  
**Symptom / repro:** Composer plain Return/Enter does not submit the prompt; desired behavior is Cursor parity, with Shift+Return/Shift+Enter for newline.  
**Bug fingerprint:** `RoutingComposer` + `ALTextEditor` newline command handling + send shortcut mismatch.  
**Truth owner:** Composer send contract and existing `performSend()` path.  
**Lie-prone layer:** NSTextView command routing; Return/Enter/Shift+Return modifier handling around multiline input and file-reference picker state.  
**Regression considered:** Return currently accepts highlighted `@` file references when that picker is open; changing send behavior must not break that picker flow.  
**Missing kill test / proof:** Focused test or UI harness proving plain Return sends, Shift+Return inserts newline, empty prompt does not send, and Return still accepts a highlighted file-reference candidate while the picker is open.  
**Fix boundary:** Keyboard handling in Composer editor only. Do not alter `performSend()` semantics, thread persistence, run routing, model selection, or file-reference attachment semantics except to call the existing paths.  
**Proof command / founder test:** Run targeted Swift tests plus a manual founder test in Composer: Return sends; Shift+Return creates a new line; `@` picker Return still accepts the highlighted file.

### Composer attachment control

**Tier:** T2 SSOT if document attachments are included; T1 Boundary if the fix only wires the existing image attachment flow.  
**Symptom / repro:** Composer photo icon is clickable-looking but inert; the affordance implies photos only while the desired user workflow is general file attachment, including docs.  
**Bug fingerprint:** `RoutingComposer` attachment icon + empty action / attachment contract mismatch.  
**Truth owner:** Attachment contract (`Composer_Image_Attachments.md`, `ThreadAttachmentStore`, `ThreadSendCoordinator`) and any future document attachment contract.  
**Lie-prone layer:** SwiftUI composer button and icon/accessibility label; GUI state may show an attachment without Core actually sending it.  
**Regression considered:** Images have a built CLI/MCP/Core path; arbitrary documents may not. Existing `@` file references are not the same as attaching an external document unless the contract says so.  
**Missing kill test / proof:** GUI test or manual proof that pressing the attachment button opens the picker, selecting a supported file creates visible attachment state, and send includes the attachment in the committed turn/worker context. If docs are supported, prove a document reaches the worker context; if not, do not present docs as supported.  
**Fix boundary:** Wire the composer attachment affordance to supported attachment ingest and rename/icon it honestly. Do not broaden attachment types without updating Core/CLI/MCP contracts and tests.  
**Proof command / founder test:** Press the paperclip/attachment button, choose an image and a document if supported, send, then verify the turn and worker context include the selected attachment(s).

### Customize Teams dropdown bugs

**Tier:** T1 Boundary unless investigation shows a shared model-contract bug; escalate to T2 SSOT if `Auto` duplication comes from model/default truth drift across Core and GUI.  
**Symptom / repro:** Customize Teams model dropdown shows duplicate `Auto`, lacks arrow-key selection, and has incorrect selected-row hover display.  
**Bug fingerprint:** `TeamEditorView` model picker + duplicate `Auto` / missing keyboard-highlight behavior + likely `ALDropdown` interaction gap.  
**Truth owner:** Core default-model contract (`DefaultModelSettings`) and available model catalog; GUI dropdown should only render that contract.  
**Lie-prone layer:** SwiftUI dropdown option construction and row selection/hover rendering.  
**Regression considered:** Compose / searchable dropdown behavior already fixed; non-searchable model dropdown may have missed the same interaction treatment.  
**Missing kill test / proof:** A focused presenter/unit test or view-level assertion that the model picker option list contains one semantic Auto option, plus a GUI proof for the open dropdown if the harness can capture it.  
**Fix boundary:** Dropdown option normalization and interaction state only. Do not change team/run semantics, default-model resolution, or model catalog availability without separate evidence.  
**Proof command / founder test:** Run targeted Swift tests plus `bash scripts/gui_proof.sh studio-team-editor` or the narrowest fixture that can capture the open model dropdown. Founder test: open Customize Teams, confirm one `Auto`, arrow keys move selection, hover/selected state is visually clear.
