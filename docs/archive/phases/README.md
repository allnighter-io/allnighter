# Archived Phases

Completed phase docs move here after closeout.

`Docs/phases/` is only for live phase work.

## Index

| Phase | Archived | Final status | Proof | Successor owner |
| --- | --- | --- | --- | --- |
| [Estimate Cleanup and Effort Dial](Estimate_Cleanup_And_Effort_Dial.md) | 2026-06-15 | Complete | `bash scripts/check.sh` + static rg (see phase doc) | `WorkOrder.summary` in `AllnighterCore`; `docs/WORKING_RULES.md` § Forecast Guardrail |
| [Team-First Vocabulary Cleanup](Team_First_Vocabulary_Cleanup.md) | 2026-06-15 | Complete | `swift test` in `Packages/AllnighterCore` + static rg (see phase doc § Works Test) | `Work_Order_Team_Model.md`; `CLI_Product_Spine.md`; `CLI_Implementation_Contract.md`; codebase types (`TeamRun`, `Model`, `Worker`, `alln team`) |
| [Compose Routing CR4 — Send + Conversations](Compose_Routing_CR4_Send_And_Conversations.md) | 2026-06-17 | Built: CR4a–CR4e delivered | CR4 watcher packets: `docs/qa/gui/thread/2026-06-16-cr4a-conversations-shell/watcher.md`, `…/cr4b-chat-reply/watcher.md`, `…/2026-06-16-cr4c-team-board/watcher.md`, `…/cr4d-dispatch/watcher.md`, `docs/qa/gui/home/2026-06-17-cr4e-rail/watcher.md` (+ `home/2026-06-16-cr4a-reseal-sck`, `compose/2026-06-16-cr4a-popover-anchor`) | `Persistent_Work_Threads.md` |
| [Launch Authority TCC Hotfix](Launch_Authority_TCC_Hotfix.md) | 2026-06-17 | Built: H0-H6 delivered | `AppModelTests.testLoadCachedSetupStateDoesNotStartDetection`; `testFullSetupProbeWithoutUserIntentDoesNotDetect`; `LaunchAuthorityProbeTests`; `scripts/check.sh` dev-path guard; founder TCC reset smoke remains manual | `AppModel.loadCachedSetupState`, `AppModel.runFullSetupProbe(userInitiated:)`, `CLIDetector`, `ModelHealthChecker`, `scripts/dev.sh`, setup docs |
| [ThreadStore Hardening](05_ThreadStore_Hardening.md) | 2026-06-17 | Built: TSH-S00–S07 delivered | `bash scripts/check.sh` green; focused `ThreadStoreTests`, `ThreadStoreConcurrencyTests`, and caller audit tests (see phase doc § Works Test) | `ThreadStore` / `WorkThread` code; live follow-ups: `docs/phases/threads/06_Unread_Message_Light.md`, `docs/phases/Persistent_Work_Threads.md` |
| [Threads 2.0](07_Threads_2_0.md) | 2026-06-17 | Built: TH2-S01–S10 delivered | `bash scripts/check.sh` green; `ThreadsPresenterTests`; GUI proof `docs/qa/gui/home/2026-06-17-th2-rail/` (see phase doc § Works Test) | `ThreadsPresenter`, `ThreadRailComponents`, Home/Threads rail UI; live follow-up: `docs/phases/threads/06_Unread_Message_Light.md` (viewport clear S05+) |
| [Skills Library And Editing](Skills_Library_And_Editing.md) | 2026-06-19 | Superseded before implementation | Active route audit: no live references outside the file itself; replacement spec owns the combined Team/Skill catalog | `docs/phases/Team_And_Skill_Catalogs.md` |
| [Cursor Agent CLI Support](setup/Cursor_Agent_CLI_Support.md) | 2026-06-19 | Built: CUR-S01–S03 delivered | `CursorAgentTests`; `SetupCursorPresentationTests`; GUI proof `docs/qa/gui/setup/2026-06-19-cursor-agent-gui/`; GUI-launched live smoke | `ModelCatalog`, `cursor_agent` manifest, Mac CLI setup UI |
| [Execution Team Source Gate](Execution_Team_Source_Gate.md) | 2026-06-19 | Built: ETS-S00–S07 delivered | `swift test --package-path Packages/AllnighterCore --disable-sandbox --filter 'ExecutionTeamSourceGateTests\|ProjectMutatingDispatchGateTests\|WorkOrderBuilderTests'` (16 tests, 0 failures) | `Work_Order_Team_Model.md`; `Project_Spine_And_Project_Manager.md`; `CLI_Implementation_Contract.md`; Core `ExecutionTeamSourceGate` / `ProjectMutatingDispatchEvaluator` |
