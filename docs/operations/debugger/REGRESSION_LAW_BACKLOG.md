# Regression Law Backlog

DEBUGLOG entries without a wall-reachable regression law are tracked here until
each pattern has a gate or test. Expired rows should fail the green wall once
meta-gates exist.

## Open

- `Repeated native/platform bugs need a clean-room positive control before more
  product patches`:
  OPEN 2026-06-21 from repeated composer image-paste failure. The successful fix
  came from a throwaway new folder/project/repo reduced to one text field and one
  image-paste job; only after that did the product delta become obvious. Required
  process gate: repeated `T3`/native DEBUGLOG entries must name `Clean-room
  baseline` plus the baseline-to-product delta, or explicitly waive it with a
  boundary decision. Future wall gate should scan repeated DEBUGLOG entries for
  that field.

- `Native composer paste is not fixed until first-responder selector/key-equivalent
  tests prove the focused editor and SwiftUI draft binding both change`:
  OPEN 2026-06-21 from repeated composer paste failure. Required wall-reachable
  gates should live in `Apps/AllnighterMac/Tests/` and run under
  `xcodebuild test -scheme AllnighterMac -destination 'platform=macOS'`:
  low-level `AllnighterTextEditorTests.testComposerPasteInsertsPlainTextAtSelection`
  / `testComposerPasteReplacesSelectedText`, plus kill tests
  `AllnighterTextEditorTests.testCommandVKeyEquivalentPastesClipboardWithoutEditMenu`,
  `AllnighterTextEditorTests.testPasteViaFirstResponderSelectorReachesFocusedComposerTextView`,
  `RoutingComposerPasteIntegrationTests.testEditMenuPasteUpdatesDraftAndSendPayload`,
  and negative
  `RoutingComposerPasteIntegrationTests.testDirectTextViewPasteIsNotEnoughWhenComposerIsNotFirstResponder`.
  GUI proof: render a `compose-paste` fixture with `bash scripts/gui_proof.sh
  compose-paste`, obtain layout-watcher PASS, then seal it with
  `bash scripts/gui_proof_seal.sh composer <slug> compose-paste`.

## Closed

- `GUI-visible work is not fixed until a layout-watcher passes a real render`:
  CLOSED 2026-06-16 by the GUI Visual Proof Gate. Harness: `GUIFixture.swift`
  (env-gated self-capture) + `scripts/gui_proof.sh` + `.claude/agents/layout-watcher.md`.
  Wall-reachable gate: `scripts/check_gui_proof.sh` (in `scripts/check.sh`) fails
  when a visible SwiftUI surface changed with no proof packet or waiver, scoped
  by `scripts/.gui_proof_baseline`. Process binding: `docs/operations/Debugger.md`
  (GUI-Visible Bugs + Forbidden Moves + DoD). Proof: `bash scripts/check.sh`.

- `Mac app launch is process-quiet before explicit setup/recheck/run`: CLOSED
  2026-06-16 by the Launch Authority TCC hotfix (H0–H6). Wall-reachable gates:
  `AppModelTests.testLoadCachedSetupStateDoesNotStartDetection` /
  `testFullSetupProbeWithoutUserIntentDoesNotDetect` (cold launch + non-user
  full probe never start detection),
  `LaunchAuthorityProbeTests` (neutral probe CWD + `smoke:false` runs no model
  call), and a `scripts/check.sh` guard asserting `scripts/dev.sh` builds
  outside the repo. Proof: `bash scripts/check.sh`.
