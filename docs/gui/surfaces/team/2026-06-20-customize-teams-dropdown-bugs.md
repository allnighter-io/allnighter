# Customize Teams Dropdown Bugs — Handoff

**Date reported:** 2026-06-20  
**Status:** Intake only. Do not treat this file as an implementation plan or proof of a fix.  
**Surface:** Team Studio → Customize Teams → worker model dropdowns.  
**Reporter evidence:** User report plus screenshot from the original Codex request. The screenshot shows a model dropdown opened over the worker rows with duplicate `Auto` entries, each showing a checkmark.

## User-Reported Bugs

### 1. Duplicate `Auto` option in model dropdown

**Priority:** P1 / biggest reported bug.  
**Observed:** The opened model dropdown shows `Auto` twice at the top. Both visible `Auto` rows appear selected with checkmarks.  
**Expected:** `Auto` should appear exactly once as the nil/default model choice. If selected, only that single row should carry the selected/check state.  
**Notes for dev:** `Auto` is the default model concept, not a concrete catalog model duplicate. Confirm whether the dropdown is combining the explicit `Auto` sentinel with a concrete model whose display name is also `Auto` (for example Cursor Agent Auto), then dedupe by identity/semantics rather than label-only guesswork.

### 2. Up/down arrows do not select rows

**Priority:** P2 / keyboard usability.  
**Observed:** With the dropdown open, the user cannot use up/down arrow keys to move the row selection.  
**Expected:** Up/down should move an active highlight through dropdown rows; return should pick the highlighted row. This should match the behavior already added to the searchable Compose / Customize-worker style popup.  
**Notes for dev:** `ALSearchableDropdown` already has `highlighted`, `onKeyPress(.downArrow)`, `onKeyPress(.upArrow)`, `onKeyPress(.return)`, and `.onHover` handling. The simpler `ALDropdown` used for model pickers likely needs the same interaction model.

### 3. Mouse hover does not display the selected row correctly

**Priority:** P2 / visual feedback regression.  
**Observed:** Mousing over the selected row does not display the row state correctly. The user notes this was already fixed in the Compose popup / overlay form.  
**Expected:** Hover and selected states should be visible and coherent. The selected row should remain visibly selected; the hovered row should highlight; when the hovered row is also selected, it should still read as selected.  
**Notes for dev:** Reuse the interaction/state treatment from the Compose popup or `ALSearchableDropdown` rather than inventing a separate hover style.

## Repro Sketch

1. Open Allnighter Mac app.
2. Go to Team Studio / Customize Teams.
3. Open a worker model dropdown in the team editor.
4. Verify the first rows in the model list.
5. Try arrow-key navigation and mouse hover over the selected `Auto` row.

## Likely Touchpoints

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

- `docs/qa/gui/studio/2026-06-17-combo-keys/watcher.md`
  - Notes keyboard behavior added for dropdown popovers.
- `docs/phases/wiring/design_handoff_default_substitutions/README.md`
  - Defines `Auto` as the default model concept and says pickers should render that shared contract.
- `docs/phases/wiring/design_handoff_cli_setup_redesign/README.md`
  - Defines the available-model set used by model pickers.
- `docs/gui/patterns/Anchored_Popups.md`
  - Popup anchoring rule for dropdown work.

## Debug Packet Starter

**Tier:** T1 Boundary unless investigation shows a shared model-contract bug; escalate to T2 SSOT if `Auto` duplication comes from model/default truth drift across Core and GUI.  
**Symptom / repro:** Customize Teams model dropdown shows duplicate `Auto`, lacks arrow-key selection, and has incorrect selected-row hover display.  
**Bug fingerprint:** `TeamEditorView` model picker + duplicate `Auto` / missing keyboard-highlight behavior + likely `ALDropdown` interaction gap.  
**Truth owner:** Core default-model contract (`DefaultModelSettings`) and available model catalog; GUI dropdown should only render that contract.  
**Lie-prone layer:** SwiftUI dropdown option construction and row selection/hover rendering.  
**Regression considered:** Compose / searchable dropdown behavior already fixed; non-searchable model dropdown may have missed the same interaction treatment.  
**Missing kill test / proof:** A focused presenter/unit test or view-level assertion that the model picker option list contains one semantic Auto option, plus a GUI proof for the open dropdown if the harness can capture it.  
**Fix boundary:** Dropdown option normalization and interaction state only. Do not change team/run semantics, default-model resolution, or model catalog availability without separate evidence.  
**Proof command / founder test:** Run targeted Swift tests plus `bash scripts/gui_proof.sh studio-team-editor` or the narrowest fixture that can capture the open model dropdown. Founder test: open Customize Teams, confirm one `Auto`, arrow keys move selection, hover/selected state is visually clear.

