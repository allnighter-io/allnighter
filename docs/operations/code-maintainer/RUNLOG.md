# Code Maintainer Runlog

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
Next lens: Structure (index 0) — RoutingComposer.swift split plan queued in MAINTENANCE-QUEUE
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
