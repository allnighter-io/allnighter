# Hot Fix Cleanup

Status: Complete
Created: 2026-06-19
Archived: 2026-06-19
Owner: hot-fix cleanup orchestration (2026-06-19)

## Why This Exists

The app moved faster than the Code Maintainer loop. A readonly health check found
two classes of work:

- a current compile break from the `dispatch` / `workOrder` / `returnReview`
  vocabulary cutover to `mutatingRun`;
- structural debt in the Mac app shell, especially `AppModel.swift` and
  `ThreadsViewModel.swift`.

This file is the immediate cleanup work order. Keep fixes small, behavior
preserving, and explicitly proven.

## Guardrails

- Do not run broad cleanup in the same commit as the compile hot fix.
- Stage explicit paths only. Do not sweep unrelated dirty files.
- Do not reintroduce retired product vocabulary as API: `workOrder`, `dispatch`,
  `returnReview`, `Council`, `Fan out`, `Build` as craft, or `worktree` in user
  visible surfaces.
- SwiftUI may render truth; it must not become durable product truth.
- Generated output must not be hand-edited.
- Every slice below needs focused proof plus the green wall when practical.

## Baseline From Health Check

Current risk:

- `swift test --disable-sandbox --package-path Packages/AllnighterCore` reached
  compile and failed in `UnreadDerivation.swift`.
- `ThreadTurnKind` now declares `.mutatingRun` and no longer declares
  `.workOrder`, `.dispatch`, or `.returnReview`.
- Tests and comments still reference old names.

Largest Mac app source files:

| File | Lines | Cleanup pressure |
| --- | ---: | --- |
| `Apps/AllnighterMac/Sources/ThreadsViewModel.swift` | 986 | mixed view model, routing, fixtures, notification behavior |
| `Apps/AllnighterMac/Sources/DesignComponents.swift` | 904 | component grab bag |
| `Apps/AllnighterMac/Sources/AppModel.swift` | 791 | setup, census, run lifecycle, presets, model catalog, history |
| `Apps/AllnighterMac/Sources/SetupViews.swift` | 748 | many related setup components |
| `Apps/AllnighterMac/Sources/TeamEditorView.swift` | 706 | draft model plus editor UI |
| `Apps/AllnighterMac/Sources/ReadinessView.swift` | 611 | readiness UI and repair surface |
| `Apps/AllnighterMac/Sources/HomeView.swift` | 608 | rail, rows, empty state, composer pane |
| `Apps/AllnighterMac/Sources/ThreadView.swift` | 601 | conversation panes and rich turn rows |
| `Apps/AllnighterMac/Sources/ThreadsView.swift` | 550 | legacy thread list/detail/composer |
| `Apps/AllnighterMac/Sources/RootView.swift` | 517 | app shell, title bar orchestration, debug routing |

## Slice 0 - Stabilize Git Scope

Goal: make sure the developer knows what is already dirty before editing.

- [ ] Run `git status --short --branch`.
- [ ] Identify unrelated dirty files.
- [ ] Do not revert user or prior-agent changes unless explicitly asked.
- [ ] Stage only files touched by each slice.

Done when: the developer can name exactly which files their commit will include.

## Slice 1 - P0 Compile Hot Fix: `ThreadTurnKind` Cutover

Goal: restore package compilation after the cutover to `.mutatingRun`.

Truth owner:

- `Packages/AllnighterCore/Sources/AllnighterCore/ThreadTurn.swift`

Lie-prone layers:

- unread eligibility;
- rail/presenter tests;
- Mac view-model tests;
- stale comments that still describe removed storage kinds.

Tasks:

- [ ] Update `Packages/AllnighterCore/Sources/AllnighterCore/UnreadDerivation.swift`.
- [ ] Remove all references to `.workOrder`, `.dispatch`, and `.returnReview`.
- [ ] Treat `.mutatingRun` as a heavy worker/team result turn for unread
  eligibility.
- [ ] Preserve current user-authored and cancelled-turn behavior.
- [ ] Preserve current `systemEvent` behavior.
- [ ] Update `Apps/AllnighterMac/Tests/ThreadsPresenterTests.swift` references
  from `.dispatch` to `.mutatingRun`.
- [ ] Update `Apps/AllnighterMac/Tests/ThreadsViewModelDispatchTests.swift`
  references from `.dispatch` to `.mutatingRun`.
- [ ] Update `Packages/AllnighterCore/Tests/AllnighterCoreTests/UnreadDerivationTests.swift`.
- [ ] Replace the old `testWorkOrderNeverUnreadEligible` expectation with a
  current equivalent, such as user-authored turns are never unread eligible.
- [ ] Add or keep proof that `.mutatingRun` terminal statuses behave like other
  result turns.
- [ ] Update `Packages/AllnighterCore/Tests/AllnighterCoreTests/WorkThreadTests.swift`.
- [ ] Expected family/heavy mapping must match `ThreadTurn.swift`; do not invent
  a new family unless product docs require it.
- [ ] Run a focused search:

```bash
rg -n '\.workOrder|\.dispatch|\.returnReview|work_order|return_review' Apps Packages -g '*.swift'
```

Acceptable remaining hits: historical comments only when clearly not runtime API,
but prefer cleaning active comments in touched files.

Focused proof:

```bash
swift test --disable-sandbox --package-path Packages/AllnighterCore
```

If the normal command works locally, also run:

```bash
swift test --package-path Packages/AllnighterCore
```

Done when:

- package tests compile past `UnreadDerivation.swift`;
- no app or package tests reference removed `ThreadTurnKind` cases;
- the commit contains only the cutover hot-fix files.

Suggested commit:

```bash
git add \
  Packages/AllnighterCore/Sources/AllnighterCore/UnreadDerivation.swift \
  Packages/AllnighterCore/Tests/AllnighterCoreTests/UnreadDerivationTests.swift \
  Packages/AllnighterCore/Tests/AllnighterCoreTests/WorkThreadTests.swift \
  Apps/AllnighterMac/Tests/ThreadsPresenterTests.swift \
  Apps/AllnighterMac/Tests/ThreadsViewModelDispatchTests.swift
git commit -m "core: finish mutating run turn cutover"
```

## Slice 2 - Green Wall Recovery

Goal: prove the hot fix did not mask a wider break.

Tasks:

- [ ] Run the package proof from Slice 1.
- [ ] Run the Mac app proof if XcodeGen and Xcode are available:

```bash
xcodebuild test \
  -project Apps/AllnighterMac/AllnighterMac.xcodeproj \
  -scheme AllnighterMac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

- [ ] Run the full green wall only after the tree is clean enough for generation:

```bash
bash scripts/check.sh
```

Notes:

- `scripts/check.sh` runs `xcodegen generate`; avoid it when unrelated dirty app
  project files would make scope unclear.
- If SwiftPM fails with `sandbox-exec: sandbox_apply: Operation not permitted`,
  retry with `--disable-sandbox` and record the environment issue in closeout.

Done when:

- the exact proof commands and outcomes are recorded in the implementation
  closeout;
- any failing command has a named owner and next action.

## Slice 3 - Vocabulary Residue Sweep

Goal: remove active-code residue from the retired language cutover.

Read first:

- `docs/phases/Language_Cutover.md`

Tasks:

- [ ] Search active app/package source for retired vocabulary:

```bash
rg -n 'Council|council|Fan out|fan-out|master-plan|worktree|workOrder|work_order|returnReview|return_review|\.dispatch|case dispatch' Apps Packages docs -g '*.swift' -g '*.md'
```

- [ ] Fix active comments in code where they describe current behavior.
- [ ] Do not churn archived docs unless they are actively routed as current truth.
- [ ] Keep user-facing language aligned to Chat / Delegate / Execute and Team.
- [ ] Do not change Codable raw values without an explicit migration decision.

Known active examples from the health check:

- `Apps/AllnighterMac/Sources/RootView.swift` has a `Council` workspace switcher
  comment.
- `Apps/AllnighterMac/Sources/AllnighterTokens.swift` has a `Council` app
  comment.
- `Apps/AllnighterMac/Sources/DesignComponents.swift` points at an old
  `docs/gui/surfaces/council/handoff.md` route.
- Several comments still say dispatch/build where the current runtime concept is
  a mutating run.

Proof:

```bash
rg -n 'Council|council|Fan out|fan-out|master-plan|worktree|workOrder|work_order|returnReview|return_review|\.dispatch|case dispatch' Apps Packages -g '*.swift'
```

Done when:

- active source no longer references removed API names;
- any remaining historical wording is intentionally scoped and not user-visible.

## Slice 4 - Code Maintainer Reboot

Goal: restart the maintenance process so this does not drift again.

Read first:

- `docs/operations/code-maintainer/SKILL.md`
- `docs/operations/code-maintainer/RUNLOG.md`
- `docs/operations/code-maintainer/MAINTENANCE-QUEUE.md`
- `docs/operations/code-maintainer/DYNAMIC_RULES.json`

Tasks:

- [ ] Append a real Code Maintainer runlog entry for the health-check scout.
- [ ] Record lens: `Structure (index 0)`.
- [ ] Record that the next regular lens is `Duplication (index 1)`.
- [ ] Add bounded queue rows for the cleanup slices below.
- [ ] Update `docs/operations/code-maintainer/HEALTH.md` so it no longer claims
  the repo has no Swift targets.

Suggested queue rows:

- [ ] `Apps/AllnighterMac/Sources/ThreadsViewModel.swift` fixture extraction.
- [ ] `Apps/AllnighterMac/Sources/AppModel.swift` setup/census extraction.
- [ ] `Apps/AllnighterMac/Sources/DesignComponents.swift` component split plan.
- [ ] `Apps/AllnighterMac/Sources/RootView.swift` shell/debug-routing split.
- [ ] Vocabulary residue sweep after hot fix.

Proof:

```bash
git diff -- docs/operations/code-maintainer
```

Done when:

- maintainer docs truthfully describe current app-code state;
- queue rows are bounded and executable.

## Slice 5 - `ThreadsViewModel` Structure Cleanup

Goal: reduce the highest-risk Mac app file without behavior changes.

Target:

- `Apps/AllnighterMac/Sources/ThreadsViewModel.swift`

Primary extraction:

- Move GUI fixture seeding out of `ThreadsViewModel.swift`.

Recommended new file:

- `Apps/AllnighterMac/Sources/ThreadsFixtureSeeder.swift`

Tasks:

- [ ] Extract `applyFixture(_:)` fixture routing and private `seedFixture*`
  helpers.
- [ ] Keep fixture code DEBUG-safe where applicable.
- [ ] Preserve existing fixture names, especially:
  `thread-empty`, `home-with-threads`, `thread-with-turns`, `thread-chat`,
  `thread-team-board`, `thread-dispatch`, `home-rail`, `home-rail-th2`,
  `home-rail-unr`, `projects-rail`.
- [ ] Keep `ThreadsViewModel` as the API the UI calls.
- [ ] Do not change fixture visuals or durable thread/run shapes in this slice.

Likely pattern:

- Add an internal helper type that accepts the required stores/models/registry,
  or add a private extension in a new file if that keeps access simple.
- If private access blocks a clean split, first make a small internal fixture API
  on `ThreadsViewModel`; do not expose production mutation paths.

Focused proof:

```bash
xcodebuild test \
  -project Apps/AllnighterMac/AllnighterMac.xcodeproj \
  -scheme AllnighterMac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Done when:

- `ThreadsViewModel.swift` is materially shorter;
- fixture behavior remains covered by existing GUI proof flow or Mac tests;
- no production behavior changes.

## Slice 6 - `AppModel` Structure Cleanup

Goal: separate setup/census/model-catalog concerns from run lifecycle.

Target:

- `Apps/AllnighterMac/Sources/AppModel.swift`

Candidate extractions:

- setup card mapping and cached setup state;
- full setup probe;
- census discovery and merge policy;
- model catalog mutation extension.

Recommended new files:

- `Apps/AllnighterMac/Sources/AppSetupModel.swift`
- `Apps/AllnighterMac/Sources/AppCensusModel.swift`
- `Apps/AllnighterMac/Sources/AppModelCatalogActions.swift`

Tasks:

- [ ] Start with pure/static helpers that are already unit-tested:
  `unresolvedSupported(...)` and `mergedToolStatuses(...)`.
- [ ] Move setup card mapping only after preserving existing `AppModel` public
  surface consumed by SwiftUI.
- [ ] Keep launch process quiet: `loadCachedSetupState()` must not spawn
  subprocesses.
- [ ] Keep full setup probe user-initiated only.
- [ ] Preserve tests in `Apps/AllnighterMac/Tests/AppModelTests.swift`.
- [ ] Do not mix run lifecycle or review-board changes into this slice.

Focused proof:

```bash
xcodebuild test \
  -project Apps/AllnighterMac/AllnighterMac.xcodeproj \
  -scheme AllnighterMac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Done when:

- `AppModel.swift` has a sentence-sized remaining responsibility;
- setup/census invariants still have tests;
- launch remains process-quiet until explicit user intent.

## Slice 7 - Component File Split Plan

Goal: make `DesignComponents.swift` navigable without inventing a new design
system.

Target:

- `Apps/AllnighterMac/Sources/DesignComponents.swift`

Recommended split:

- `StatusPill.swift`
- `WorkerGlyph.swift`
- `WorkerChip.swift`
- `AllnighterButtons.swift`
- `AllnighterDropdowns.swift`
- `IconButton.swift`
- `Badge.swift`
- `AllnighterCard.swift`
- `SegmentedTabs.swift`
- `AllnighterTextEditor.swift`

Tasks:

- [ ] Move components mechanically.
- [ ] Preserve type names and call sites.
- [ ] Do not restyle components in this slice.
- [ ] Do not leave a barrel-only parent file as the only outcome.
- [ ] Delete the parent file only after all moved types compile.

Proof:

```bash
xcodebuild test \
  -project Apps/AllnighterMac/AllnighterMac.xcodeproj \
  -scheme AllnighterMac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Done when:

- components are grouped by responsibility;
- no UI styling changed.

## Slice 8 - `RootView` Shell Split

Goal: keep app shell orchestration readable.

Target:

- `Apps/AllnighterMac/Sources/RootView.swift`

Candidate extractions:

- `RootTitleBar.swift` for `TitleBar` and `WindowDragArea`;
- `WorkspaceMode.swift` for `WorkspaceMode` and `InboxTeamsSwitch`;
- debug-only navigation helpers into a small `RootDebugRouting.swift`.

Tasks:

- [ ] Preserve app launch behavior: clean home first, setup only on intent.
- [ ] Preserve quick capture behavior.
- [ ] Preserve notification deep-link behavior.
- [ ] Preserve debug GUI fixture routing.
- [ ] Remove stale `Council` comments during this slice.

Proof:

```bash
xcodebuild test \
  -project Apps/AllnighterMac/AllnighterMac.xcodeproj \
  -scheme AllnighterMac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Done when:

- `RootView.swift` primarily composes the shell;
- title bar, workspace switcher, and debug routing are easier to find.

## Slice 9 - Closeout Audit

Goal: make sure the cleanup itself did not become another drift source.

Tasks:

- [ ] Run Code Audit after non-trivial structure changes:

```text
Verdict: CLEAN | REFACTOR REQUIRED | INCONCLUSIVE
Scope reviewed:
Proof reviewed:
Findings:
Residual risk:
```

- [ ] Run `bash scripts/check.sh` on a clean-enough tree.
- [ ] Update `docs/operations/code-maintainer/RUNLOG.md`.
- [ ] Mark completed queue rows done in
  `docs/operations/code-maintainer/MAINTENANCE-QUEUE.md`.
- [ ] Commit each slice separately.

Done when:

- the green wall passes or every failure has a named owner;
- maintenance docs point to the next lens and next cleanup pressure;
- no finished cleanup is left uncommitted.

## Preferred Order

1. Slice 0 - stabilize git scope.
2. Slice 1 - fix compile break.
3. Slice 2 - recover proof.
4. Slice 3 - vocabulary residue sweep.
5. Slice 4 - reboot Code Maintainer docs.
6. Slice 5 - extract `ThreadsViewModel` fixtures.
7. Slice 6 - extract `AppModel` setup/census.
8. Slice 7 - split `DesignComponents`.
9. Slice 8 - split `RootView`.
10. Slice 9 - closeout audit.

