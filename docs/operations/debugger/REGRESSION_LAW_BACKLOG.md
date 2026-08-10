# Regression Law Backlog

DEBUGLOG entries without a wall-reachable regression law are tracked here until
each pattern has a gate or test. Expired rows should fail the green wall once
meta-gates exist.

## Open

- `A bug fix cannot introduce a second repository truth or run owner`:
  OPEN 2026-07-24 from the repeated resident/mirror incident. Required
  wall-reachable gates are specified in
  `docs/archive/phases/CODE_RED_Core_Infrastructure_Repair.md`: an early architecture
  policy check must reject mirrors, clones, read-only injection, alternate-root
  request fields, duplicate run-semantics owners, and extra resident operations;
  positive tests must prove canonical worker CWD and the single `RunService.run`
  owner. Close this backlog row only when the gate runs from
  `scripts/check.sh`, its violating fixtures prove it can fail, and the live
  Code Red Works Test is checked in.

- `Visible thread continuity requires worker-vendor session continuity when the
  driver exposes a resume handle`:
  OPEN 2026-06-21 from Cursor Composer second-turn context loss. Required
  wall-reachable gates should prove that the second send in the same
  `WorkThread` and same Cursor worker uses a persisted thread-scoped
  `--resume <chatId>`, never global `--continue`; different Allnighter threads
  must not share the id; reloading the store between turns must preserve it.
  Future gate names proposed in
  `docs/operations/debugger/2026-06-21-cursor-composer-session-continuity-code-red.md`:
  `CursorSessionContinuityTests.testSecondTurnUsesStoredCursorChatId`,
  `testDoesNotUseGlobalContinueForThreadResume`,
  `testDifferentThreadsDoNotShareCursorChatId`, and
  `testReloadedThreadStillResumesCursorChatId`.

- `Repeated native/platform bugs need an isolation harness before more
  product patches`:
  OPEN 2026-06-21 from repeated composer image-paste failure. The successful fix
  came from a throwaway new folder/project/repo reduced to one text field and one
  image-paste job; only after that did the product delta become obvious. Required
  process gate: repeated `T3`/native DEBUGLOG entries must name `Attempt count`,
  `Seam`, `Isolation harness`, and the harness-to-product delta, or explicitly
  waive it with a boundary decision. Future wall gate should scan repeated
  DEBUGLOG entries for those fields.

- `Seam bugs cannot close on proof-by-proximity`:
  OPEN 2026-06-21 from repeated composer paste/image-paste failure. A true layer
  proof ("menu exists", "reader reads", "text view mutates") is not proof that
  the user path works. Required future gate: BUG_PATTERNS entries for recurring
  seam bugs should name `seam` and, when needed, `requiresHarness: true`.

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
  2026-06-16 by the Launch Authority TCC hotfix (H0–H6); **re-opened and
  re-closed 2026-08-10** when capacity silent acquire, strip `loadLive→refreshAll`,
  ServeAutoLaunch demand-heal, and remote relay bootstrap walked past the
  CLIDetector-only gates. Wall-reachable gates now also include
  `CapacityFeatureOffTests.testStartupWhenONWiresSchedulerWithoutSilentLaunch`,
  `CapacityStripModelTests.testLoadLiveDoesNotProbe`,
  `ServeAutoLaunchTests.testMacAppLaunchDoesNotDemandHealServe`,
  `AppModelTests.testCapacityStripLoadLiveDoesNotCallRefreshAll`,
  `AppModelTests.testRemoteBootstrapDoesNotEnsureRelayRunning`. Packet:
  `docs/operations/debugger/2026-08-10-first-launch-tcc-popups-PACKET.md`.
  Original H0–H6 gates:
  `AppModelTests.testLoadCachedSetupStateDoesNotStartDetection` /
  `testFullSetupProbeWithoutUserIntentDoesNotDetect` (cold launch + non-user
  full probe never start detection),
  `LaunchAuthorityProbeTests` (neutral probe CWD + `smoke:false` runs no model
  call), and a `scripts/check.sh` guard asserting `scripts/dev.sh` builds
  outside the repo. Proof: `bash scripts/check.sh`.
