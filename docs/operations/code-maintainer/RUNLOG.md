# Code Maintainer Runlog

```text
## 2026-08-03 - Structure CM-S07 (ThreadsViewModel scout)

Scope: Analyze ThreadsViewModel.swift (~1,627 LOC) and write split plan for CM-S10+ batches
Class: Structure lens (index 0) — scout only, no Swift
Delegation: Gemini 3.6 Flash via `alln run --model model_gemini`
Files touched: NEW plans/ThreadsViewModel-split.md; MAINTENANCE-QUEUE.md
Behavior guarantee: Docs only — no code change
Proof: test -f plans/ThreadsViewModel-split.md
Before/after signal: 7 proposed extension batches; shell target ~400 LOC
Next lens: CM-S08 ThreadBoardRow extract, then CM-S09 composer attachments
```

```text
## 2026-08-03 - Structure CM-S06 (RoutingComposer effort popover)

Scope: Extract effort chip/panel/key monitor to RoutingComposerEffortPopover.swift
Class: Structure lens (index 0)
Lens: Structure (index 0)
Delegation: Gemini 3.6 Flash via `alln run --model model_gemini` (PM did not edit Swift)
Files touched: NEW RoutingComposerEffortPopover.swift; RoutingComposer.swift 470→390 LOC
Behavior guarantee: Move-only extraction; effort popover behavior unchanged
Proof: xcodebuild build -scheme AllnighterMac (BUILD SUCCEEDED via alln proof)
Before/after signal: RoutingComposer split plan CM-S01–S06 complete; 7 focused files
Next lens: ThreadsViewModel Structure scout or ThreadView ThreadBoardRow extract
```

```text
## 2026-08-03 - Structure CM-S03–S05 (RoutingComposer complete)

Scope: Decompose RoutingComposer monolith into 6 single-job files
Class: Structure lens (index 0)
Lens: Structure (index 0)
Files touched: RoutingComposerTargetPopover.swift, RoutingComposerFileSearch.swift, RoutingComposerSend.swift, RoutingComposerTypes.swift, ComposerAttachmentTile.swift; RoutingComposer.swift 1648→470 LOC
Behavior guarantee: Move-only extractions; composer send, @ refs, target picker unchanged
Proof: xcodebuild build -scheme AllnighterMac (BUILD SUCCEEDED)
Before/after signal: Split plan CM-S01–S05 complete; MAINTENANCE-QUEUE row closed
Next lens: Duplication (index 1) or ThreadsViewModel Structure scout
```

```text
## 2026-08-03 - Hygiene epoch closeout (Doc truth lens)

Scope: HY-S09–S12 vocabulary cutover — PM Relay → Loop across Mac GUI, prompts,
error explain, thread titles, fixtures; tail Core comment scrub
Class: Doc truth / product vocabulary alignment (behavior-preserving)
Lens: Doc truth (index 3)
Files touched: Apps/AllnighterMac/Sources/{ThreadView,RelayLaunchView,RelayGUIRuntime,RootView,ThreadsFixtureSeeder}.swift; Packages/AllnighterCore/Sources/{LoopPrompts,ContractRegistry+Milestone1,LoopState,LoopJSON,ThreadTurn,ProjectWorkerReadinessProjector}.swift; Packages/AllnighterCore/Sources/AllnighterEngine/LoopThreadProjector.swift; Packages/AllnighterCore/Sources/AllnighterCLI/LoopEngineCLI.swift; matching tests; docs/phases/sprint/hygiene/HY-S09–S12; docs/operations/code-maintainer/MAINTENANCE-QUEUE.md
Behavior guarantee: Product noun is Loop everywhere user/agent-facing; internal relay id/json field names unchanged
Proof: scripts/swift-test.sh --filter 'RetiredVocabulary|LoopThreadProjection|StalledWork|LoopCoordinator' (33+ tests green on filtered suites)
Before/after signal: 0 remaining "PM Relay" in active Swift sources except LoopThreadProjector PM_Relay.md stem guard and archive/historical docs
Next lens: Structure (index 0) — CM-S03 target popover extraction per `plans/RoutingComposer-split.md`
```

```text
## 2026-08-03 - Structure batch CM-S01 (RoutingComposer + ThreadView)

Scope: Extract shared composer types, attachment tile, and loop escalation row
Class: Structure lens (index 0) — behavior-preserving file splits
Lens: Structure (index 0)
Files touched: NEW RoutingComposerTypes.swift, ComposerAttachmentTile.swift, RelayEscalationRow.swift; trimmed RoutingComposer.swift (1648→1448 LOC), ThreadView.swift (1326→1238 LOC); plans/RoutingComposer-split.md
Behavior guarantee: No UI or send-path behavior change — move-only extractions
Proof: xcodebuild build -scheme AllnighterMac (BUILD SUCCEEDED); 3 pre-existing CapacityStripModelTests failures unrelated
Before/after signal: RoutingComposer −200 LOC; ThreadView −88 LOC; 3 new single-job files
Next lens: Structure continues — CM-S03 target popover per split plan
```

```text
## 2026-07-02 - AgentOS runner cutover (F2_B)

Scope: Cut Allnighter (AgentOS consumer #1) onto the shared AgentOS DefaultWorkerRunner
Class: Single-core adoption — delete Allnighter's duplicate worker runtime, drive AgentOS's core directly via WorkerInvoking
Files touched: DELETED Packages/AllnighterCore/Sources/AllnighterEngine/{WorkerRunner,WorkerStreaming,Claude/Codex/Cursor/Grok StreamParser}.swift + Sources/AllnighterCore/WorkerAnswer.swift (WorkerAnswer struct); NEW AllnighterEngine/{WorkerInvokerFactory,CommandRunnerAsStreaming,WorkerInvocationCWD,WorkerRunOutcome,GatedWorkerRunner,AntigravityAwareWorkerRunner,SpawnResolvingCommandRunner,OpenCodeRoutingWorkerRunner}.swift; retyped WorkerAnswer->AgentOSTeam.TeamAnswer/WorkerRunResult across ~35 files (RunService, TeamRun, both team coordinators, ThreadSendCoordinator, Mac app AppModel/views, etc.); Package.swift + AgentOSReexports (AgentOSTeam dep, plain import); AGENTS-side plan in AgentOS repo
Behavior guarantee: Runtime behavior preserved; mutation write-lock/one-writer spine intact (ThreadsViewModelMutatingRunTests green). Parsing/normalization/session/capacity/timeout now single-sourced in AgentOS DefaultWorkerRunner (parity-netted). No API keys. Only thin app-specific glue (gate, opencode-serve routing, agy transcript, ToolInvocation, TCC cwd) remains Allnighter-side.
Proof: swift test --package-path Packages/AllnighterCore (1392 tests, 9 pre-existing failures — AgentBootstrap/CodeReviewParallelSafety/ExitCodeContract/DefaultConfigDrift/MCPPairHandlers, all unrelated to this cutover, A/B-confirmed); xcodegen + xcodebuild test -scheme AllnighterMac (139 tests, 0 failures); AgentOS bash scripts/check.sh (180 tests, 0 failures)
Before/after signal: -664 net LOC in the cutover commit (deleted the 896-line WorkerRunner + 4 parser classes + local WorkerAnswer); Allnighter no longer owns any worker-runtime core. Follow-ups: migrate DriverConcurrencyGate + OpenCode-serve INTO AgentOS (D3); build a run.json schema migration for pre-cutover persisted runs.
Next lens: Per MAINTENANCE-QUEUE or next scheduled maintainer pass
```

```text
## 2026-06-19 - Batch 3

Scope: Dead weight lens (index 2)
Class: Remove superseded legacy UI, stale aliases, and unused helpers after home/thread cutover
Lens: Dead weight (index 2)
Files touched: deleted Apps/AllnighterMac/Sources/ThreadsView.swift; Apps/AllnighterMac/Sources/{ThreadsViewModel,ThreadsPresenter,SetupViews,ThreadsFixtureSeeder,AppModel}.swift; Apps/AllnighterMac/Tests/AppModelTests.swift; AllnighterMac.xcodeproj (xcodegen); docs/operations/code-maintainer/{RUNLOG,HEALTH}.md; docs/qa/gui/WAIVERS.manifest
Behavior guarantee: Production routes HomeView + ThreadView only; routing composer send path unchanged
Proof: swift test --package-path Packages/AllnighterCore (639 tests, 0 failures); xcodebuild test -scheme AllnighterMac (84 tests, 0 failures); bash scripts/check.sh
Before/after signal: Deleted legacy ThreadsView (550 LOC); removed legacy composer/send/reveal VM APIs, TeamHealthPopover alias, thread-dispatch fixture alias, deprecated railGroups/RailGroup, AppModel.unresolvedSupported shim
Next lens: Per MAINTENANCE-QUEUE or next scheduled maintainer pass
```

```text
## 2026-06-19 - Batch 2

Scope: Duplication lens (index 1)
Class: Bounded dedup — setup roster grouping, status pills, action handlers, invocation map
Lens: Duplication (index 1)
Files touched: Apps/AllnighterMac/Sources/{SetupViews,ReadinessView,AppSetupModel,AppModel,ThreadsViewModel}.swift; docs/operations/code-maintainer/{RUNLOG,HEALTH}.md
Behavior guarantee: No UI restyle; same setup roster groups, pill labels, and repair actions
Proof: swift test --package-path Packages/AllnighterCore (639 tests, 0 failures); xcodebuild test -scheme AllnighterMac (84 tests, 0 failures); bash scripts/check.sh
Before/after signal: Extracted SetupCardBuckets, SetupCardState roster/repair pills, SetupActions.handle; AppSetupModel.invocations shared by AppModel + ThreadsViewModel
Next lens: Dead weight (index 2)
```

```text
## 2026-06-19 - Batch 1

Scope: Hot-fix cleanup health-check scout (Structure lens)
Class: Scout + bounded queue seed from HOT_FIX_CLEANUP.md
Lens: Structure (index 0)
Files touched: docs/operations/code-maintainer/{RUNLOG,MAINTENANCE-QUEUE,HEALTH}.md
Behavior guarantee: Readonly scout; no product behavior changes in this batch
Proof: swift test --disable-sandbox --package-path Packages/AllnighterCore (639 tests, 0 failures); xcodebuild test -scheme AllnighterMac (84 tests, 0 failures)
Before/after signal: Identified ThreadsViewModel (986 LOC), AppModel (791), DesignComponents (904), RootView (517) as top Mac shell pressure; compile hot fix already landed on mutatingRun cutover
Next lens: Duplication (index 1)
```
