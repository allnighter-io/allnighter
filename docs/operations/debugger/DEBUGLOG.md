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
