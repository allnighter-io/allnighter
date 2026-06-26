# Bug Hunt Packet: Mac Composer Paste Inserts Nothing (text)

Date: 2026-06-26
Fingerprint: mac-composer-paste-text-dead + representable-binding-roundtrip + repeated-failed-fixes
Related DEBUGLOG entries: 2026-06-20 (composer + paste does nothing + responder/menu proof gap), 2026-06-21 (paste into RoutingComposer dead + no first-responder kill test), 2026-06-20 (RoutingComposer + paste does nothing (repeated 4+) + representable bridge clobber)
Related: REGRESSION_LAW_BACKLOG.md (native composer paste law), BUG_PATTERNS.json (mac-composer-paste-*, repeated-native-bug-needs-isolation-harness), ISOLATION_HARNESS.md (image-paste harness precedent)

## Tier
T3 Critical (repeated founder bug after multiple claimed fixes; core text-entry contract for the composer surface; survived "paste works" patches at least 4 times per git history and DEBUGLOG)

## Symptom
Pressing Paste inserts nothing into any Mac composer. The text never appears in the editable area. The symptom is specific to the paste gesture reaching the composer; other mutations of the same draft (typing, quick-capture prefill via `pendingQuickCaptureText`, direct `text = ` in code, file-ref chip removal) can succeed in the same session.

## Minimal Reproducible Scenario (smallest faithful reduction)

**Environment facts (observed in tree):**
- App launches as LSUIElement then promoted to .regular (AllnighterMacApp.swift, AppDelegate.applicationDidFinishLaunching).
- Manual Edit menu is installed at launch with `Paste` wired to `#selector(NSText.paste(_:))`.
- All composers route through `RoutingComposer` → `ALTextEditor` (NSViewRepresentable) → `ComposerTextView` (NSTextView subclass).
- No SwiftUI `.onPasteCommand` or `.paste` modifiers intercept the path for the editor.
- `ComposerPasteboardReader` and `readablePasteboardTypes` / `validateUserInterfaceItem` advertise `.string` (and images).
- Short plain-text pastes go through `consumePasteboard` → `insertText(text, replacementRange: selectedRange())`; long text is diverted to attachment.
- `textDidChange` in Coordinator is the sole path that writes back to the `@Binding var text` (and thus `RoutingComposer.@State private var text`).
- `updateNSView` does `if textView.string != text { textView.string = text }` plus focus and style.

**Concrete steps:**
1. Build/run the Mac app (sandbox constraints on xcodebuild noted below).
2. Ensure a composer is visible and empty (HomeView big RoutingComposer is the minimal surface; also reproduces in ThreadDockedComposer, team send modal, pending review).
3. Place plain text on the general pasteboard (e.g., copy "hello world" from TextEdit or via `NSPasteboard.general.setString("hello world", forType: .string)` in a test helper).
4. Click inside the composer so the insertion caret is visible. Confirm it is the first responder (window.firstResponder === the inner NSTextView).
5. Invoke paste via the user's gesture: Cmd+V, or Edit > Paste from the installed menu, or right-click context Paste.
6. Do not send; inspect the visible editor content and (in debug) the bound `text` value before any further interaction.

**Inputs:**
- Pasteboard: NSPasteboard.general containing a non-empty `.string` value whose length is <= ComposerPasteContract.longTextThreshold (so it is not diverted to onPasteLongText attachment).
- Selection: any range (insertion point or replacement).
- Composer state: focused, editable, no active file-search popover swallowing keys.

**Expected behavior:**
- The exact clipboard string appears at the caret (or replaces the selection) in the visible NSTextView.
- The Coordinator receives the change (textDidChange or equivalent) and writes it into the Binding, so `RoutingComposer.text` now contains the pasted content.
- A follow-up `updateNSView` sees `textView.string == text` and does not clobber.
- The text survives height growth, further typing, file-ref insertion, and is the body passed to `performSend` → `ComposeRouting.text` (trimmed).
- Paste menu item is enabled when text (or image) is on the board.

**Observed behavior (per founder reports and prior entries):**
- Nothing appears in the field. No insertion, no visible change.
- The field may remain empty (or retain prior content).
- Direct typing in the same composer may still work.
- Quick-capture prefill and explicit `text = ` assignments from other paths succeed.
- Symptom has recurred after patches that made the selector reach `paste(_:)` and `insertText`.

**Missing observations (named gaps — do not assume):**
- Exact gesture at failure time (Cmd+V vs. main Edit > Paste vs. context menu vs. trackpad three-finger paste vs. Continuity/universal clipboard).
- Pasteboard content/type at the moment of the failing gesture (is `.string` present? only rich text? empty?).
- Menu item enabled state (`validateUserInterfaceItem` result) immediately before the gesture.
- Whether the app beeps on the failed paste.
- Whether the caret is visibly blinking and the editor is first responder at paste time.
- Whether the failure is uniform across all composer hosts (Home big, docked thread reply, send-to-team modal, pending review) or specific to one.
- Whether normal typing, backspace, and Return work in the identical composer instance where paste fails.
- Runloop timing: does `textDidChange` fire at all for the `insertText` call in the current override, and is the Binding write observed before the next `updateNSView`?
- Behavior with empty vs. non-empty initial text, with prior selection vs. insertion point.
- Whether the failure reproduces when the composer is the only first responder candidate (no popovers, no other text fields).
- Sandbox / permission state of the pasteboard (unlikely for plain text but unrecorded).

## Truth Owner
`RoutingComposer.@State private var text: String` (and its projected Binding passed to ALTextEditor) is the owner of the live draft. It is the value read by `performSend` into `ComposeRouting.text`, which becomes the user turn body.

`ComposerTextView` (inside ALTextEditor) owns the native editable surface that must mutate that draft via the representable contract.

`Coordinator.textDidChange` is the required bridge that turns an AppKit mutation into SwiftUI-owned truth.

Downstream consumers (ThreadsViewModel, ThreadStore, run path, attachments, workers) are never reached on a failed paste and are not owners of this symptom.

## Lie-Prone Layer
The NSViewRepresentable glue:
- `ALTextEditor.updateNSView` guarded assignment: `if textView.string != text { textView.string = text }`
- `ComposerTextView.consumePasteboard` / `insertText(text, replacementRange:)` path (bypasses some standard user-edit notification paths)
- `Coordinator` only listening via the `textDidChange(_ notification:)` delegate method
- First-responder delivery (`performKeyEquivalent` for Cmd+V inside the subclass + selector routing from the manual main menu) into a focused representable-hosted view

This layer can accept the gesture, mutate the NSTextView's `.string`, and still leave the `@State` stale so the next SwiftUI-driven `updateNSView` reverts the visible text.

Secondary lying surfaces historically: SwiftUI `.commands` (absent for LSUIElement), menu installation timing, and bare subclass tests that never exercised the binding roundtrip.

## RCA (summary from existing entries, no new invention)
- Patches (AllnighterMacApp installMainMenu ~4a4f9970, AllnighterTextEditor performKeyEquivalent + custom paste ~acf8b3df, readableTypes + consume) made the selector and the mutation site reachable.
- All existing `AllnighterTextEditorTests` (testComposerPasteInsertsPlainTextAtSelection, testComposerPasteReplacesSelectedText) create a bare `ComposerTextView`, call `paste(nil)`, and assert `.string`. They do not host the representable, do not drive a first-responder gesture through the app's responder chain, and do not assert any Binding or `RoutingComposer` state.
- No test has ever mounted `ALTextEditor(text: $text)` or `RoutingComposer`, focused the inner view, seeded the general pasteboard, invoked the real paste gesture (key equiv or menu selector), yielded the runloop, and asserted the bound value changed and survived a subsequent `updateNSView`.
- Image paste received a successful isolation harness ("one text field, paste an image, a chip appears") that proved the seam outside product routing/attachments/send. Text paste never had an equivalent harness or cross-layer kill test.
- The representable contract (widget mutates → coordinator pushes → @State → re-render must not clobber) is the fidelity owner for any native edit reaching the draft used by Send.

## Smallest Fix Boundary
Only the paste-to-binding roundtrip inside the editor bridge.

Allowed:
- Changes inside `ComposerTextView` (paste, readSelection, consumePasteboard, or performKeyEquivalent) to guarantee a delegate notification or explicit Binding push reaches the Coordinator for short text.
- Guard or latch inside `ALTextEditor.updateNSView` / Coordinator so a just-inserted value from the view is not overwritten by a stale outer `text` during the same or next update pass.
- New tests that prove the full path (first-responder gesture into focused hosted editor → bound `text` updated and stable).
- Documentation of the harness delta if one is built.

Forbidden in this slice:
- Any change to `performSend`, `ComposeRouting`, attachment handling, long-text capture, file references, `onChange(text)`, send routing, ThreadStore, run model, Core contracts, or menus beyond paste enablement.
- Broad composer refactors or styling.
- Assuming a menu or key-equiv fix alone is sufficient.

Port rule (per ISOLATION_HARNESS.md): if a harness is built, only the narrow delta that made the primitive + binding seam work is ported.

## Kill Tests Required Before Any Patch
All must be red on the pre-fix tree and green after. A single-turn or bare-view-only test does not count.

1. Keep (and run): `AllnighterTextEditorTests.testComposerPasteInsertsPlainTextAtSelection`
2. Keep (and run): `AllnighterTextEditorTests.testComposerPasteReplacesSelectedText`
3. `AllnighterTextEditorTests.testCommandVKeyEquivalentPastesClipboardWithoutEditMenu` — drive `performKeyEquivalent` for ⌘V on a focused `ComposerTextView` (or its scroll) with text on the general pasteboard; assert the view string updated.
4. `AllnighterTextEditorTests.testPasteViaFirstResponderSelectorReachesFocusedComposerTextView` — use the responder chain / `NSApp.sendAction` or window `tryToPerform` for the paste: selector into a properly installed first responder; assert mutation.
5. New integration test file or extension: `RoutingComposerPasteIntegrationTests.testEditMenuPasteUpdatesDraftAndSendPayload` (or equivalent) — host or seed a `RoutingComposer` (via ComposeSpecimen or minimal host), focus the inner editor, seed general pasteboard, invoke the menu item's action through the first responder, spin the runloop, assert the draft `text` (or a test-exposed binding) now contains the pasted string, and that `canSend` / the value passed to onSend reflects it. Must survive one `updateNSView` cycle.
6. Negative control: `RoutingComposerPasteIntegrationTests.testDirectTextViewPasteIsNotEnoughWhenComposerIsNotFirstResponder` (or equivalent) — demonstrates that a bare textView paste that never reaches the hosted representable under app conditions is insufficient proof.
7. GUI-visible: Define and render a `compose-paste` fixture (or extend ComposeSpecimen) that performs the paste action during capture. Run `bash scripts/gui_proof.sh compose-paste`, obtain layout-watcher PASS on the rendered post-paste composer (text visibly present), then seal. No fixture of this name exists today.

Additional requirements from prior entries:
- At least one test must be a focused representable integration that asserts the SwiftUI-owned draft used by performSend, not only the NSTextView.string.
- xcodebuild test targeting the Mac scheme (AllnighterMacTests) must be the wall command once the env permits it.
- Repro the "nothing" symptom with a failing test on the exact pre-patch commit/tree before claiming a fix.

## Proof Gaps (current state)
- Sandbox blocks full `xcodebuild test -project Apps/AllnighterMac/...` (SwiftPM diagnostics writes to ~/Library/Caches/... "Operation not permitted"). `swift test --package-path Packages/AllnighterCore` does not cover the Mac AppKit representable seam.
- No recorded observation log of exact gesture + beep + menu-enabled + focus-state + pasteboard contents from a failing run (2026-06-21 entry explicitly lists these as unknown).
- No isolation harness has been built for the text-paste + binding roundtrip seam (image paste had one; the mandate in ISOLATION_HARNESS.md + REGRESSION_LAW_BACKLOG applies because this survived two+ honest fixes and crosses AppKit/SwiftUI + responder).
- Existing pasteboard reader tests and bare textView tests do not traverse the failing seam.
- No `compose-paste` (or equivalent) rendered fixture + watcher verdict exists.
- No wall-reachable two-layer test (gesture → binding → send payload) has been executed on the product tree in this environment.

## Pattern Candidate
For any `NSViewRepresentable` wrapping an editable AppKit control (NSTextView, etc.), "the selector reached the subclass", "performKeyEquivalent returned true", "insertText was called", "menu item exists", or "bare widget unit test passes" is not proof that user data reaches the SwiftUI-owned state. The binding roundtrip (native mutation → coordinator push → @State → re-render calls update without clobber) must be asserted by a test that drives the real first-responder path into a hosted instance.

## What the agent was allowed to do that must never be allowed again
Iterate "add menu", "add key equivalent", "override paste and insertText", "write a direct NSTextView.paste test that asserts .string", and claim "paste works" multiple times while touching the composer, without ever writing or running a test that proves a user paste gesture (Cmd+V or menu selector) results in the SwiftUI `@State text` (the value owned by RoutingComposer and read by performSend) containing the pasted content after the representable update cycle. The bridge owns the fidelity contract; it must also own the kill proof.

## Isolation Harness Status (per mandate)
Required by DEBUGLOG + REGRESSION_LAW_BACKLOG + ISOLATION_HARNESS.md because:
- Same fingerprint survived multiple honest fixes (≥4).
- Crosses native/framework seam (AppKit pasteboard/responder + NSViewRepresentable + SwiftUI @State binding).
- Only evidence has been founder confirmation + build + low-level tests below the seam.

If a harness is created next:
- Harness must be smaller than product: one NSViewRepresentable-hosted text field + one job (focus, seed pasteboard, invoke real paste gesture or selector, assert bound string visible and stable).
- Mirror the exact frameworks (AppKit text view inside representable, Coordinator binding, updateNSView guard).
- Success criterion: non-coder can copy text, click the field, press paste (or menu), and see the text appear.
- Record: harness path/command, seam mirrored, working API/path, baseline-to-product delta, kill test(s) derived from it.

Only the necessary delta is ported back.

## Closeout (per T1-T3 requirements in Debugger.md)
Tier: T3 Critical
Boundary verdict: Analysis and packet only. No code change. Smallest boundary is the paste-to-@Binding roundtrip in the ALTextEditor representable.
Proof gap: No wall-reachable first-responder + representable integration test that proves bound draft text changes and survives updateNSView. No isolation harness executed for the text seam. No rendered compose-paste fixture + layout-watcher. Sandbox blocks xcodebuild Mac tests. Multiple critical observations (gesture, beep, enabled state, focus, exact pasteboard) remain unrecorded from a failing instance.
Attempt count: 4+ (per DEBUGLOG 2026-06-20 entry citing repeated failed fixes and git commits acf8b3df, 4a4f9970, earlier).
Seam: AppKit NSTextView paste delivery (performKeyEquivalent + menu selector + consume/insertText) through NSViewRepresentable (ALTextEditor) ↔ SwiftUI @State binding roundtrip (Coordinator.textDidChange + updateNSView guard) in RoutingComposer.
Isolation harness: Not yet built for text paste (image paste had one). Mandate applies.
Fix boundary: Only the input bridge for user edits reaching the composer's `text` binding. (See above.)
RCA: See above (paste reached a mutation site in the view but never proved the SwiftUI draft used by Send was updated and stable).
Proof: None yet. Existing bare-textView tests and pasteboard reader tests do not traverse the seam. Packet + DEBUGLOG entries are the current record.
Founder test: Confirmation of feel only (copy text, focus composer "right in here", press paste via keyboard and menu, text appears and Send carries it). Never sole proof.

## Recommended Next (no code)
1. Capture the missing observations on the founder's machine (exact gesture, menu state, beep?, caret visible?, pasteboard contents, typing works?, all composer hosts).
2. Build the isolation harness (throwaway project) that reproduces "one focused text field in NSViewRepresentable, real paste gesture, bound string updates" before any further product patch.
3. Write the kill tests listed above so they are red on current tree.
4. Only after harness + red kill tests exist, port the narrow working delta and re-run the wall command.
5. Add the compose-paste GUI fixture + require layout-watcher PASS for any visible composer edit surface change.
6. Append this packet summary (or a condensed form) to DEBUGLOG.md under 2026-06-26 following the standard header.

Definition of done for a future fix (excerpted):
- Kill test exists that is red pre-fix, green post (including first-responder + binding roundtrip).
- GUI fixture + watcher PASS named.
- DEBUGLOG Proof: names a wall-reachable test.
- Isolation harness path/command + delta recorded if used.
- No unrelated cleanup in the same change.
- Repro "nothing" on the pre-fix state first.

---

Sources used (read-only):
- docs/operations/debugger/DEBUGLOG.md (2026-06-20 and 2026-06-21 composer paste entries + 2026-06-24 patterns)
- docs/operations/debugger/ISOLATION_HARNESS.md
- docs/operations/debugger/REGRESSION_LAW_BACKLOG.md
- docs/operations/debugger/BUG_PATTERNS.json
- docs/operations/Debugger.md
- Apps/AllnighterMac/Sources/AllnighterTextEditor.swift (ComposerTextView, ALTextEditor, Coordinator)
- Apps/AllnighterMac/Sources/RoutingComposer.swift (@State text, ALTextEditor usage, performSend, capture paths)
- Apps/AllnighterMac/Sources/ComposerPasteboardReader.swift
- Apps/AllnighterMac/Sources/AllnighterMacApp.swift (installMainMenu)
- Apps/AllnighterMac/Tests/AllnighterTextEditorTests.swift
- Apps/AllnighterMac/Tests/ComposerPasteboardReaderTests.swift
- Apps/AllnighterMac/Sources/HomeView.swift, ThreadView.swift (composer hosts)
- team-lab reports and suites referencing composer_paste_dead_v1 (for context only; no new claims)

All statements above derive directly from these files. Unknowns are explicitly called out rather than assumed. No implementation files were edited.