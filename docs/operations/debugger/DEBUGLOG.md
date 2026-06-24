# Debug Log

Append repeated bugs, `T3` bugs, and `T2-T3` fixes with deferred proof.

```text
## YYYY-MM-DD - <fingerprint>

Tier:
Symptom:
Truth owner:
Lie-prone layer:
RCA:
Fix boundary:
Proof:
Deferred proof:
Pattern candidate:
```

## 2026-06-24 - Apps/AllnighteriOS TestFlight Release + no credentials + dead onboarding fallback

Tier: T3 Critical (repeated founder-visible TestFlight launch regression)
Symptom: Launching the TestFlight app opens the old sign-in/onboarding wall instead of the dogfoodable iOS home/preview surface. The failure survived multiple rounds and was misattributed to target cleaning/archive ritual.
Truth owner: `RemoteAppModel.activate()` owns the launch fallback after live remote credentials are unavailable; the runtime App Store receipt identifies TestFlight (`sandboxReceipt`) versus App Store (`receipt`).
Lie-prone layer: Xcode archive state, DerivedData, target selection, and build-number churn can all look relevant while the Release code path deterministically selects `.needsConfiguration`.
RCA: Release builds skipped the DEBUG preview fallback. With no live `RemoteSupabaseEnvironment` credentials/session in TestFlight, `activate()` always set `connectionPhase = .needsConfiguration`, which renders `RemoteOnboardingView`. Clearing the target or archiving again could only rebuild the same branch. TestFlight needs its own explicit release fallback until sign-in/pairing is wired.
Fix boundary: Add a testable unauthenticated fallback policy in `RemoteAppModel`: Debug builds use preview, TestFlight Release builds with `sandboxReceipt` use preview/home, and App Store Release builds with a normal receipt keep onboarding. No signing, bundle identifier, auth, transport, or distribution settings changed.
Proof: Added `AllnighteriOSTests.testUnauthenticatedReleaseFallbackUsesPreviewInTestFlight`, plus App Store and Debug fallback tests. `bash scripts/check_swiftui_state.sh` passed.
Deferred proof: Targeted `xcodebuild test -project Apps/AllnighteriOS/AllnighteriOS.xcodeproj -scheme AllnighteriOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AllnighteriOSTests/AllnighteriOSTests/testUnauthenticatedReleaseFallbackUsesPreviewInTestFlight -derivedDataPath /private/tmp/alln-ios-testflight-fallback-dd -clonedSourcePackagesDirPath /private/tmp/alln-ios-testflight-fallback-spm CODE_SIGNING_ALLOWED=NO` is blocked in this sandbox before compilation because Xcode/SwiftPM writes diagnostics to `/Users/mike/Library/Caches/org.swift.swiftpm/...` (Operation not permitted).
Pattern candidate: TestFlight launch behavior is owned by the Release runtime fallback policy, not cache clearing. Any future TestFlight launch-screen regression must prove the receipt-mode branch.
What was the agent allowed to do that must never be allowed again: Treat TestFlight as a build-cache/archive problem without proving what the Release `activate()` branch does when no credentials are available.

## 2026-06-21 - Cursor Composer visible thread loses prior context + no worker session id

Tier: T3 Critical (core product promise failure; session-state truth bug)
Symptom: In one Allnighter conversation with Composer 2.5, the second turn says it does not have prior context even though the user did not switch models.
Truth owner: `WorkThread` owns the visible conversation; missing owner is a durable per-thread/per-driver external worker session mapping. `TeamRun` owns each run record, but today it does not carry worker-vendor session identity.
Lie-prone layer: `ThreadsViewModel` and the timeline make the conversation look continuous while `RunService` / `WorkerRunner` starts a fresh Cursor Agent headless one-shot process for each turn.
RCA: Active composer sends go through `ThreadsViewModel.runViaRunService`, which creates a fresh `TeamRun` UUID and `RunRequest` with no `threadId` or external session id. `RunService` constructs a `WorkerRunner` and the Cursor manifest resolves to `agent -p ... --workspace {{workingDir}} {{prompt}}`; no `--resume <chatId>` is ever passed. `WorkThread`, `ThreadTurn`, `WorkerAnswer`, and `WorkerRunOutcome` have no vendor session receipt field. Cursor Agent local help does expose `--resume [chatId]`, `--continue`, and `create-chat`, so this is an Allnighter session-contract gap, not a vendor impossibility.
Fix boundary: Documentation only in this slice. Future fix must add an explicit driver-session contract and pass thread-scoped Cursor chat ids through RunService/WorkerRunner/manifest resolution. Do not fix by stuffing more prior turns into prompts. Do not use global `agent --continue`; it can resume the wrong Cursor session.
Proof: Code-read packet written at `docs/operations/debugger/2026-06-21-cursor-composer-session-continuity-code-red.md`. Local help inspection only: `agent --help`, `agent create-chat --help`, `agent resume --help`, `agent ls --help`; no quota-bearing prompt was sent.
Deferred proof: Add kill tests proving second turn in the same Allnighter thread invokes Cursor with `--resume <stored-chat-id>`, different threads do not share ids, reload preserves the id, and no path uses `--continue` for thread continuity.
Pattern candidate: A visible Allnighter thread is not conversation-continuity proof. For any driver with a resume handle, turn 2 must prove a thread-scoped persisted vendor session id was used in the worker invocation.

## 2026-06-16 - Apps/AllnighterMac launch + TCC protected-folder prompts + startup shell/CLI probe authority leak

Tier: T3 Critical
Symptom: Launching Allnighter raises macOS TCC prompts for Documents, Downloads, and network-volume access before useful interaction.
Truth owner: AppModel launch/setup state plus CLIDetector probe policy; persisted setup truth is SetupStore.
Lie-prone layer: RootView.onAppear and login-shell PATH bridging treat startup health as harmless UI but spawn shell/CLI child processes.
RCA: Ordinary launch runs LoginShell.applyToProcessEnvironment(), then RootView.onAppear calls AppModel.runDetection(), which calls CLIDetector.probeAll with smoke defaulting true; smoke invokes real agent CLIs under the GUI app identity. Dev launch also places Allnighter.app under ~/Documents.
Fix boundary: Do not patch UI paint or individual manifests first. Make launch process-quiet: render cached setup truth only, require explicit user intent for shell resolve/smoke, and move dev app output outside protected folders or document the limitation.
Proof: Investigation packet only; no runtime fix.
Deferred proof: Add a wall-reachable test that first-window launch does not call CommandRunner.run or spawn shells/worker CLIs before explicit setup/recheck/run.
Pattern candidate: Mac app launch may render cached setup truth, but must not spawn shells, worker CLIs, or smoke probes before explicit user intent.

## 2026-06-16 - Apps/AllnighterMac GUI surface + "fixed" without rendered proof + missing visual gate

Tier: T3 Critical
Symptom: Agents claim SwiftUI GUI fixes are done, but founder opens the app and finds first-order visual failures such as missing rows, clipped popovers, wrong sublines, z-order/scrim damage, or overlapping copy.
Truth owner: Product/domain truth remains AllnighterCore and routed phase docs; visual truth is the design system/UI kit; GUI closeout truth is `docs/phases/GUI_Visual_Proof_Gate.md`.
Lie-prone layer: SwiftUI views, previews, and build/test closeouts can all pass without proving the rendered surface.
RCA: The workflow allowed agents to close visible GUI work from code confidence. HTML prototypes were optional reference material, native render screenshots were not required, and founder review became the first visual test.
Fix boundary: Add a mandatory GUI visual proof gate — render the surface, then a separate layout-watcher agent looks at the pixels. Layout only; CLI/Core own content truth. No XCUITest, goldens, or accessibility assertions.
Proof: Shipped 2026-06-16 — `Apps/AllnighterMac/Sources/GUIFixture.swift` (env-gated self-capture, no Screen-Recording TCC) + `scripts/gui_proof.sh` + `.claude/agents/layout-watcher.md`. Proven on the Team dropdown: render → watcher FAIL (clipped header, detached popover) → fix (panel moved to a RootView overlay below the title bar) → watcher PASS. Pilot packet: `docs/qa/gui/team-dropdown/2026-06-16-pilot/`. Bound into `docs/operations/Debugger.md` (GUI-Visible Bugs + Forbidden Moves + DoD).
Deferred proof: NONE — wall-gate shipped 2026-06-16: `scripts/check_gui_proof.sh` (in `scripts/check.sh`) fails a visible `Sources/*.swift` change with no proof packet/waiver, scoped by `scripts/.gui_proof_baseline`.
Pattern candidate: GUI-visible work is not fixed until a separate layout-watcher passes a real render; if the surface cannot be rendered/inspected, closeout says visually unverified or blocked.

## 2026-06-16 - AsyncTeamService team cancel flake (testTeamCancel) — lost cancel under two races

Tier: T2-T3 (recurring flaky test on the green wall)
Symptom: MCPAsyncTeamTests.testTeamCancel failed intermittently three ways — (a) persisted run.status "fanningOut" not "cancelled", (b) cancel returned RUN_NOT_FOUND ("expected cancel success"), (c) cancel response "interrupted" (surfaced under heavy parallel-test load).
Truth owner: AsyncTeamService cancellation + RunStore persisted run state + orphan recovery.
Lie-prone layer: the background coordinator persists progress OFF the actor via a plain @Sendable persist closure (looks serialized with cancel but is not); RunStore writes look durable but are non-atomic; orphan recovery trusts an owner.pid read that can tear.
RCA: THREE concurrency races on the run journal. (1) TOCTOU: persistDuringRun checked "not cancelled" then saved; cancel could flip+save .cancelled in between, then the progress save resumed and clobbered it back. (2) run.json torn read: RunStore.save wrote run.json non-atomically (truncate-then-write), so a concurrent reader decoded an empty/partial file → nil → RUN_NOT_FOUND. (3) owner.pid torn/absent read: orphan recovery (RunStore.recovered) flips a non-terminal run to .interrupted when owner.pid is unreadable; owner.pid was written non-atomically AND after run.json, so a reader could see a live run.json with a torn/absent marker and misclassify a running run as .interrupted.
Fix boundary: Do not add test sleeps. (1) Serialize a run's cancelled-flag flip and its saves under one lock (CancelledRunRegistry.saveIfActive / cancelAndSave) so cancel is always the last write. (2) Write run.json atomically (.atomic). (3) Write owner.pid atomically AND before run.json on non-terminal saves, so a visible run.json always implies a complete owner.pid.
Proof: Shipped 2026-06-16. testTeamCancel 30x green; testTeamCancelWinsRepeatedly 20x (240 cancels) green; full AllnighterCore suite (333 tests) 6x green under parallel load + 3 rounds of two concurrent suites (heavy contention) green. Regression laws: RunStoreConcurrencyTests.testConcurrentSaveAndLoadNeverReturnsNil (atomic write; load never nil AND never spuriously .interrupted under concurrent save/load) + MCPAsyncTeamTests.testTeamCancelWinsRepeatedly (12x cancel-after-start, asserts cancel response + persisted both .cancelled).
Deferred proof: NONE.
Pattern candidate: A file-backed run/state store read+written from concurrent contexts must (a) write every state file atomically, (b) order dependent files so a visible primary (run.json) never implies a missing/torn companion (owner.pid), and (c) serialize terminal-status transitions against in-flight progress saves — else a late write reverts a terminal state or a torn companion read misclassifies a live run.

## 2026-06-16 - Worker run inherits app CWD → TCC Documents prompt on first chat send

Tier: T3 Critical (TCC launch-trust regression, surfaced by CR4b GUI chat)
Symptom: Pressing Send on the first chat raised "Allnighter would like to access files in your Documents folder."
Truth owner: WorkerRunner spawn working directory; Launch Authority TCC hotfix is the probe-authority owner.
Lie-prone layer: a worker run with no explicit working dir looks harmless but the child CLI inherits the app's process CWD.
RCA: The hotfix neutralized setup/health probe CWDs (CLIDetector → ProbeScratch) but explicitly DEFERRED worker runs ("keep worker runs using their existing working dir"). WorkerRunner.invoke passed `workingDirectory: workingDirectoryOverride ?? invoke.workingDir` — nil for chat/team runs → the spawned CLI inherits the app's CWD (in dev the checkout under ~/Documents), so the CLI reading its cwd trips a TCC Documents prompt attributed to the app. CR4b made GUI chat the first reachable worker run, exposing the deferred gap.
Fix boundary: Do not request a Documents entitlement. Spawn worker runs in an Allnighter-owned neutral scratch when no explicit dir is given; preserve explicit dirs (dispatch). Args still resolve against the real workingDir (nil → no token); only the process CWD is neutralized.
Fix: WorkerRunner.invoke computes `spawnWorkingDir = workingDir ?? AllnighterPaths.ensuredProbeScratchPath()` and passes it as the process CWD.
Proof: WorkerRunnerCWDTests (no-dir run spawns in probeScratch; explicit dir preserved); full AllnighterCore suite green; chat send verified on the founder's machine (Grok Build → "Hi!") with no Documents prompt after the fix.
Pattern candidate: Any spawned child process (probe OR run) must use an owned neutral CWD unless an explicit, user-chosen dir is given — never inherit the app's process CWD, which in dev is under ~/Documents and trips TCC.

## 2026-06-20 - Apps/AllnighterMac home rail + visible "Unassigned" project bucket + rootless thread fallback

Tier: T2 SSOT
Symptom: Home sidebar could show an "Unassigned" project group and rootless GUI sends could fall back to worker chat instead of the unified Project-root run path.
Truth owner: `ProjectStore` plus `WorkThread.projectId`; folder/repo binding is owned by `ProjectBinding`.
Lie-prone layer: `ThreadsPresenter.projectSections` synthesized a user-visible repair bucket, and `ThreadsViewModel.repoRoot(for:)` treated legacy `workingDir` as a run root without binding it to a Project.
RCA: PRJ-era repair-bucket semantics survived the Unified Run Model. The binder auto-created Projects for git roots but not plain available folders, while the GUI still tolerated nil-project threads.
Fix boundary: Bind available folders as Projects, require GUI sends/new threads to resolve a Project root, hide unbound legacy records from the project rail, and remove the rootless worker-chat fallback.
Proof: `swift test --disable-sandbox --package-path Packages/AllnighterCore` (747 tests, 0 failures).
Deferred proof: Mac `xcodebuild` tests and GUI `projects-rail` render are blocked in this sandbox because Xcode still writes SwiftPM diagnostics to `/Users/mike/Library/Caches/org.swift.swiftpm/...` (Operation not permitted), even with tmp DerivedData/package cache overrides.
Pattern candidate: GUI run surfaces must not create a user-visible repair bucket for missing `projectId`; a local folder is enough Project truth, and rootless legacy records are hidden or refused until bound.

## 2026-06-20 - Apps/AllnighterMac composer + paste does nothing + responder/menu proof gap

Tier: T3 Critical
Symptom: Pressing Paste in the composer inserts nothing; repeated failed fixes left the app-level paste path untrusted.
Truth owner: `RoutingComposer.text` is the draft state owner; `ComposerTextView` / `ALTextEditor` own the editable AppKit presenter that mutates that draft before Send.
Lie-prone layer: SwiftUI `.commands`, an installed AppKit Edit menu, and implicit first-responder routing can look like a paste fix while the promoted `LSUIElement` SwiftUI app still drops the actual editor paste action.
RCA: Prior fixes made paste depend on app/menu/key-equivalent routing instead of proving the text view's own `paste(_:)` operation. The editor had a shortcut shim, but no kill test that `ComposerTextView` inserts NSPasteboard plain text into its selected range.
Fix boundary: Keep the change inside `ComposerTextView`; do not touch send routing, file-reference resolver, thread persistence, worker dispatch, or unrelated composer cleanup. Override `paste(_:)` to read plain text from `NSPasteboard.general` and insert it through the text view selection.
Proof: `xcrun swiftc -module-cache-path /private/tmp/allnighter-module-cache -typecheck Apps/AllnighterMac/Sources/AllnighterTokens.swift Apps/AllnighterMac/Sources/AllnighterTextEditor.swift` passed. Added wall-reachable regression tests in `AllnighterTextEditorTests` for append and replacement paste.
Deferred proof: Focused hosted test command `xcodebuild test -project Apps/AllnighterMac/AllnighterMac.xcodeproj -scheme AllnighterMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:AllnighterMacTests/AllnighterTextEditorTests` is blocked in this sandbox before compilation because Xcode/SwiftPM writes diagnostics to `/Users/mike/Library/Caches/org.swift.swiftpm/...` (Operation not permitted). `swift test --package-path Packages/AllnighterCore` was also blocked waiting on another SwiftPM process holding `.build`.
Pattern candidate: Mac composer paste must be owned and regression-tested at `ComposerTextView.paste(_:)`; an Edit menu or command shortcut is not proof that paste works in the composer.

## 2026-06-21 - Apps/AllnighterMac composer + paste into RoutingComposer dead + no first-responder kill test

Tier: T3 Critical
Symptom: Founder presses Paste in the composer and nothing appears. This has survived multiple claimed fixes. The exact paste gesture is not yet observed: unknown whether it is Cmd+V, Edit > Paste, context-menu Paste, trackpad/iOS Continuity paste, or another paste affordance. Unknown whether the app beeps, whether the insertion caret is visible in the composer, whether the Paste menu item is enabled, and whether text is present on the pasteboard at failure time.
Truth owner: `ComposerTextView` / `ALTextEditor` owns text editing behavior; `RoutingComposer` owns draft text binding; AppKit first-responder/menu routing owns Paste delivery.
Lie-prone layer: SwiftUI composer surface and app menu setup can compile and look correct while the actual focused `NSTextView` never receives `paste:` or never syncs the pasted string back into the draft.
RCA: Not proven. Current tree has attempted fixes in `AllnighterMacApp.swift` (`4a4f9970`, manual AppKit Edit menu for the LSUIElement-promoted app) and `AllnighterTextEditor.swift` (`acf8b3df`, `performKeyEquivalent` handles Cmd+V/C/X/A/Z), but no wall-reachable test drives paste through the real first-responder/editor path. Agents were allowed to close paste from code confidence instead of a kill test.
Fix boundary: Do not patch another random SwiftUI wrapper first. Smallest repro is text-only paste into the empty home composer: seed the pasteboard with plain text, focus the composer editor, invoke the user's paste gesture, and assert the composer contains that exact text before any send. Ignore send/team routing, worker dispatch, attachment persistence, images, files, and model state unless a later observation proves they matter. Direct `ComposerTextView.paste(nil)` tests are useful but insufficient because they bypass the failing app/responder path.
Proof: Existing untracked `Apps/AllnighterMac/Tests/AllnighterTextEditorTests.swift` covers direct `ComposerTextView.paste(nil)` insertion/replacement only; it does not prove focused app paste dispatch or SwiftUI binding update. Required semantic proof plan: keep low-level `AllnighterTextEditorTests.testComposerPasteInsertsPlainTextAtSelection` / `testComposerPasteReplacesSelectedText`, then add kill tests `AllnighterTextEditorTests.testCommandVKeyEquivalentPastesClipboardWithoutEditMenu`, `AllnighterTextEditorTests.testPasteViaFirstResponderSelectorReachesFocusedComposerTextView`, `RoutingComposerPasteIntegrationTests.testEditMenuPasteUpdatesDraftAndSendPayload`, and negative `RoutingComposerPasteIntegrationTests.testDirectTextViewPasteIsNotEnoughWhenComposerIsNotFirstResponder`. Targeted `xcodebuild test -project Apps/AllnighterMac/AllnighterMac.xcodeproj -scheme AllnighterMac -destination 'platform=macOS' -only-testing:AllnighterMacTests/CommandCenterTests -derivedDataPath /private/tmp/alln-xcdd-paste-repro -clonedSourcePackagesDirPath /private/tmp/alln-spm-paste-repro` was blocked by SwiftPM diagnostics writing to `/Users/mike/Library/Caches/org.swift.swiftpm/...` under sandbox.
Deferred proof: GUI-visible proof must render `compose-paste` (or equivalent composer fixture seeded after paste) with `bash scripts/gui_proof.sh compose-paste`, followed by layout-watcher PASS and `bash scripts/gui_proof_seal.sh composer <slug> compose-paste`. Required observations before fixing: exact paste gesture, pasteboard content/type, composer focus/caret state, menu enabled/beep behavior, and whether direct typing in the same composer works.
Pattern candidate: A native text-entry regression is not fixed until a wall-reachable AppKit first-responder test drives the actual selector/key-equivalent into the focused editor and proves the SwiftUI binding changed; GUI-visible composer changes also need a rendered fixture and watcher PASS.

## 2026-06-20 - Apps/AllnighterMac RoutingComposer + paste does nothing (repeated 4+) + representable bridge clobber

Tier: T3 Critical (repeated founder bug after multiple attempted fixes)
Symptom / repro: "I press paste right in here and nothing happens." Focus any composer (home empty state, thread reply bar, team send modal, pending review), have text on clipboard, Cmd+V (or menu/context Paste). No insertion, no visible change, no beep necessarily. Can still type in some cases; prefill paths (quick capture) and direct `text = ` mutations work. Cannot paste a prompt.
Bug fingerprint: `RoutingComposer` + `ALTextEditor`/`ComposerTextView.paste(override using insertText) + updateNSView clobber` + insufficient roundtrip proof after "paste works" commits
Truth owner: `RoutingComposer.@State private var text: String` (and its $binding) is the owner of live compose draft content presented to ALTextEditor. On send it is read into `ComposeRouting.text`, trimmed, turned into user `ThreadTurn.text`, appended via ThreadsViewModel, and persisted by `ThreadStore` as part of `WorkThread` (thread_<id>/thread.json under AllnighterPaths.threads). The prompt text is transient UI state until send.
Lie-prone layer (first): UI layer — specifically the glue in [Apps/AllnighterMac/Sources/AllnighterTextEditor.swift](/Users/mike/Documents/GitHub/Allnighter/Apps/AllnighterMac/Sources/AllnighterTextEditor.swift) (ComposerTextView lines 29-35 custom paste + performKeyEquivalent 42; ALTextEditor updateNSView 107-108 `if != { string = }`; Coordinator.textDidChange 162-166 only listener). 
  The menu layer (AllnighterMacApp.swift installMainMenu Edit>Paste) and key layer were also involved historically.
  Presenter/model layer (RoutingComposer:316 box/ALTextEditor usage, 249 onChange(text), 616 performSend packing ComposeRouting, 643 handleEditorCommand which only does fileSearch), ThreadsViewModel.sendRouting (360) etc. are not reached.
  Engine (RunService, ThreadSendCoordinator, ThreadContextBuilder, SubprocessCommandRunner), store (ThreadStore.appendTurn), contract (ThreadTurn, WorkThread, TeamRunJSON), persisted file, external CLI — all downstream and innocent for this symptom.
First layer likely to be lying: The NSViewRepresentable <-> NSTextView sync (paste override does not guarantee the didChange notification that the Coordinator uses to push into @Binding; subsequent updateNSView from SwiftUI re-render sees stale `text` and does the clobber assignment). This is the only place native widget mutation must become SwiftUI model truth for the composer draft.
RCA (full trace through layers):
  - UI: Custom `paste(_:)` (added in the "menu didn't stick" patch acf8b3df) reads NSPasteboard and calls `insertText(pasted, replacementRange:)`. This is not the standard NSTextView user-edit path that posts NSText.didChangeNotification to the delegate. Bare `ComposerTextView` tests only create the subclass and assert `.string` immediately — no representable, no binding, no update pass. performKeyEquivalent for Cmd+V calls it; menu action from the manually installed NSMenu also reaches the override. Normal typing bypasses and may succeed.
  - Presenter/model: RoutingComposer owns the @State and passes $text. updateNSView always style + guarded string assign + focus makeFirstResponder. onChange(text) drives @ search. performSend reads local text only. No persistence of in-flight draft.
  - Engine/store/contract/persisted/external: Never entered. The user message only becomes a ThreadTurn (and thus persisted + sent to worker) after a successful send.
  Multiple prior "fixes" (paste beep via menu; then paste works via key-equiv + custom paste) only ensured the selector reached a mutation site. They never proved the mutation survived the representable contract. Current dirty state touches unrelated files (timeout, handoff doc); the broken composer code is committed.
Regression considered: DEBUGLOG had no detailed entry; BUG_PATTERNS.json empty. REGRESSION_LAW_BACKLOG already sketches the exact needed tests for composer paste + binding. The "4+ times" history lives in git log (acf8b3df, 4a4f9970, earlier composer fixes).
Isolation harness / breakthrough: The real image-paste fix came only after the founder forced a new folder/project/repo with the product stripped down to one text field and one job: make copied images paste. That harness proved the primitive outside Allnighter's SwiftUI routing, menus, attachments, and send path while still exercising the native paste seam. The working control made the required product delta obvious: advertise image pasteboard types so Paste stays enabled, read image file URLs/raw pixels before `.string`, consume image paste as an attachment, then port that narrow behavior back into the composer. Debugger was missing this escape hatch; it let agents keep patching the real app instead of first proving the native paste primitive in isolation.
Fix boundary: Only the input bridge for user edits reaching the composer's `text` binding. Do not change send semantics, file refs (activeFileTrigger etc), Core run model, stores, or CLIs. Make the mutation reliable (use proper editing APIs + didChangeText or force the notification + last-pushed guard in representable) and add the cross-layer test.
Missing kill test / proof: 
  1. Focused representable integration test: mount ALTextEditor or RoutingComposer, focus the inner view, write string to general pasteboard, invoke paste action (or Cmd+V path), yield to runloop/update, assert bound `text` value now contains pasted content and a follow-up updateNSView does not revert it.
  2. Must be red on the tree containing the current paste override + update guard.
  3. Existing subclass tests stay but are called out as insufficient.
  4. GUI: a compose fixture after simulated paste + layout-watcher.
Proof command / founder test: After the fix lands + tests: `swift test --package-path Packages/AllnighterCore`. When xcode harness available under the user's perms: `xcodebuild test ... -only-testing AllnighterMacTests/AllnighterTextEditorTests` (plus new integration) green. Founder: copy arbitrary text, focus composer "right in here", press paste (keyboard and menu), text appears, survives typing more + height grow + file ref, Send succeeds and the text is the user turn. Repro the "nothing" on the pre-fix commit first.
Pattern candidate: For any NSViewRepresentable wrapping an editable AppKit control, "the widget accepted the gesture" or "subclass method ran" is not proof. The binding roundtrip (widget mutates -> coordinator pushes -> @State -> re-render calls update without clobber) must be asserted. Direct widget tests + "founder confirms" are forbidden as sole evidence on repeated UI-input bugs.
What was the agent allowed to do that must never be allowed again: Iterate "make paste reach a mutation" + custom bypass + subclass unit test + claim "paste works" four times, touching the composer surface, without ever writing (or running) a test that proves a user paste gesture results in the SwiftUI-owned draft state used by performSend and the rest of the app. The bridge owns the fidelity contract; it must be the proof owner.
