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
