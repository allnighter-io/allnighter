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
| [Hot Fix Cleanup](HOT_FIX_CLEANUP.md) | 2026-06-19 | Complete: mutatingRun cutover proof + Mac shell structure cleanup | `swift test --disable-sandbox --package-path Packages/AllnighterCore` (639 tests); `xcodebuild test -scheme AllnighterMac` (84 tests); `bash scripts/check.sh` | Code Maintainer queue; `docs/operations/code-maintainer/`; next lens Duplication |

## Bulk delivered-doc sweep — 2026-07-18

Archived after a hard cleanup pass that verified each doc against **code** (not
its own status header). Every doc below has its durable truth in the named
source; remaining leftovers were pure GUI-polish unless noted. Live successors
(where the forward work continues) are called out.

### MCP surface — retired 2026-07-16 (CLI-only; no `MCP*.swift` remain)

| Doc | Final status | Code SSOT / successor |
| --- | --- | --- |
| [MCP_Retirement.md](MCP_Retirement.md) | DONE — the completed-cutover record | CLI surface is the sole agent contract |
| [MCP_Tool_Upgrade.md](MCP_Tool_Upgrade.md) | Historical — subject (MCP wire protocol) fully retired | — |
| [MCP_Help_System.md](MCP_Help_System.md) | Help SSOT built CLI-only; MCP half deleted | `HelpService.swift`, `HelpTopicRegistry.swift`, `alln help` |
| [Agent_First_MCP_And_Messaging_Workflows.md](Agent_First_MCP_And_Messaging_Workflows.md) | Core built; every `MCP*Handlers` tool it specced deleted | `AgentReadiness`/`TeamPreflight`/`SpecRetrieval.swift`; CLI parity |

### Agent front door — gate 1 shipped; gate 3 Complete

| Doc | Final status | Code SSOT / successor |
| --- | --- | --- |
| [Agent_Front_Door.md](Agent_Front_Door.md) | SHIPPED (gate 1 — findable) | `InstallCLI.swift`, `Bootstrap.swift`; gate 2 live: `Agent_Onboarding.md`; gate 3 archived: `Agent_Intent_Router.md` |
| [Agent_Intent_Router.md](Agent_Intent_Router.md) | Complete 2026-07-19 — IR-S00–S02 (`3d515ff0` / `aafb6ce6` / `df334af8`); PARKED remain parked | `AgentIntentRouter.swift`, `AgentHello.swift`; live works probe + 29/29 golden tests; successor: `Agent_Onboarding.md` |

### Team / catalog / model / run substrate — built

| Doc | Final status | Code SSOT / successor |
| --- | --- | --- |
| [Team_And_Skill_Catalogs.md](Team_And_Skill_Catalogs.md) | S00–S04 built (only S05 Mac nav was GUI leftover) | `TeamCatalog.swift`, `SkillCatalog.swift`, `TeamResolver.swift`, `alln teams`/`skills` |
| [Team_Run_Floor.md](Team_Run_Floor.md) | Built end-to-end (substrate + CLI + GUI reader) | `FloorRun.swift`, `FloorProjector.swift`, `FactoryFloorView.swift`, `alln floor` |
| [Default_Team_Override.md](Default_Team_Override.md) | Built (edit-in-place at same id + Restore-to-seed) | `TeamCatalog.swift` (`setDefault`/`restore`), `alln teams set-default` |
| [Model_Catalog_And_Bench_Roster.md](Model_Catalog_And_Bench_Roster.md) | Built (self-declared historical requirements record) | `ModelCatalog.swift`, `alln models` |

### Composer / thread / image — built (GUI-polish leftovers only)

| Doc | Final status | Code SSOT / successor |
| --- | --- | --- |
| [Composer_Image_Attachments.md](Composer_Image_Attachments.md) | Backend CIA-S00–S07 built | `RunAttachmentStager.swift`, `ComposerPasteboardReader` |
| [Composer_Model_Popup_Update.md](Composer_Model_Popup_Update.md) | Built (Auto-pinned picker, craft chips removed) | `RoutingComposer.swift` |
| [Message_Image_Rendering.md](Message_Image_Rendering.md) | Mac render delivered; remaining framing was MCP (moot) | `TimelineAttachmentChip.swift`, `ThreadView` |
| [Worker_Session_Continuity.md](Worker_Session_Continuity.md) | SOLVED (CONT-S0–S5); stale "CODE RED" header | `WorkerSessionStore`, `VendorSessionManifest` |
| [threads/01_Work_Threads_MLP.md](threads/01_Work_Threads_MLP.md) | MLP done; foundation | `WorkThread.swift`; router `Persistent_Work_Threads.md` (live) |
| [threads/02_Notifications.md](threads/02_Notifications.md) | Built NOTIF-S01–S05 | `MacNotificationDelivery.swift` |
| [threads/03_Mac_Streaming.md](threads/03_Mac_Streaming.md) | Built; stale "Ready for implementation" header | `ThreadsViewModel.applyLiveDelta`, `PerfCounters` |
| [threads/06_Unread_Message_Light.md](threads/06_Unread_Message_Light.md) | Built UNR-S01–S07 (S08 rich-turn residue) | `ThreadRailComponents.swift` |
| [threads/08_Worker_Image_Output_In_Chat.md](threads/08_Worker_Image_Output_In_Chat.md) | Built incl. WIO-S04 GUI | `WorkerImageCapture`, `ThreadView` workerBubble |

### Pilot / Relay / Panel — shipped 2026-07-16

| Doc | Final status | Code SSOT / successor |
| --- | --- | --- |
| [PM_Relay.md](PM_Relay.md) | Shipped R-S01–S09 | `RelayCLI.swift`, `RelayVerdict.swift`, `HandoverGate.swift` |
| [Pilot_Panel.md](Pilot_Panel.md) | Shipped PN-S01–S06 | `PanelCLI.swift`, `PanelCoordinator.swift` |
| [Pilot_Relay.md](Pilot_Relay.md) | Shipped (start/handoff/status/watch/adopt) | `PilotCLI.swift` |
| [Pilot_DX.md](Pilot_DX.md) | Shipped DX rounds 1–3 | `PilotCLI.swift` |
| [Pilot_Defect_Fixes.md](Pilot_Defect_Fixes.md) | Shipped (dogfood defect log) | relay/RunService path |
| [Pilot_Polish_And_Agent_UX.md](Pilot_Polish_And_Agent_UX.md) | Shipped | `RelayVerdictParser`, hello schema |
| [Panel_Polish.md](Panel_Polish.md) | Shipped PP-S01–S03 | `PanelJSON.unstructuredSeats`, `PanelConvergence.swift` |
| [Relay_ReadOnly_Removal.md](Relay_ReadOnly_Removal.md) | Done — toggle removed (zero `pmReadOnly`/`readOnly` hits) | — |
| [Sol_Review_Hardening.md](Sol_Review_Hardening.md) | SR-1..SR-15 landed w/ tests (SR-16..23 low-value) | review ledger |

### Reliability / process — built

| Doc | Final status | Code SSOT / successor |
| --- | --- | --- |
| [Process_Ownership.md](Process_Ownership.md) | Built PO-S01–S05 + F9/F10/F11 | `ProcessOwnership.swift`, `ProcessOwnershipSurface`, `…GarbageCollector`; extended by archived `Concurrent_Invocation_Isolation.md` |
| [Concurrent_Invocation_Isolation.md](Concurrent_Invocation_Isolation.md) | SHIPPED 2026-07-19 — F1–F5b + two-process gates | `IdempotencyStore.claim`, scoped `reconcileAll`/`killAll`, `RunContextProvenance`, `ConcurrentInvocationTwoProcessTests` |
| [Stalled_Work_Watchdog.md](Stalled_Work_Watchdog.md) | Built (check/dismiss/list/wait) | `StalledCLI.swift`, `StallRecoveryService.swift` |
| [Pending_Work_And_Drain.md](Pending_Work_And_Drain.md) | Built (GUI-polish leftovers only) | `PendingCLI.swift` |
| [Try_Fix_Auto_Implement.md](Try_Fix_Auto_Implement.md) | Built (Mac checkbox GUI leftover) | `TryFixGate.swift`, `TryFixChainJSON.swift`, `alln run --try-fix` |
| [Warm_Single_Lane_Chat.md](Warm_Single_Lane_Chat.md) | Built (4 warm dialects; agy cold by decision) | `WarmWorker.swift` |
| [Utilization_Window_Priming.md](Utilization_Window_Priming.md) | Built | `BoostWindowCLI.swift`, `BoostWindowOperations` |
| [Run_Latency_And_Streaming_Recovery.md](Run_Latency_And_Streaming_Recovery.md) | Investigation absorbed; superseded by Warm | archived `Team_Run_Load_Performance.md` + `Warm_Single_Lane_Chat.md` |
| [Run_Latency_Findings.md](Run_Latency_Findings.md) | Findings log; warm path shipped | `Warm_Single_Lane_Chat.md` (archived) |
| [Team_Run_Load_Performance.md](Team_Run_Load_Performance.md) | SHIPPED 2026-07-19 — S01–S04b, S05a, S06; S05b deferred | `ThreadsViewModel.applyLiveDelta` / `reloadAsync`, `PerfCounters`, `RunDecodeCache`; Mac `ThreadStreamingPerformanceTests` / `TeamRunOpenPerformanceTests` |
| [Rate_Limit_Continuity.md](Rate_Limit_Continuity.md) | Complete 2026-07-19 — RLC-S01–S04 | `VendorBackoffPolicy`, `VendorBackoffReconciler`, `VendorSubstitutionPolicy`, `RunBlocker.vendorBackoff`, `alln run resume`, `alln continuity receipt`; sprint: `sprint/rlc/` |
| [Run_Lifecycle_Reliability.md](Run_Lifecycle_Reliability.md) | Complete 2026-07-19 — RLR-S00–S06 (item 7 waived) | `KillSettlement`, `RunClockEnforcer`, `RunContradiction`, `IdempotencyStore` expiry/conflict, `RunLifecycleReliabilityWorksTest`; plans: `rlr/` |
| [Mac_Standalone_App_And_Background_Coordinator.md](Mac_Standalone_App_And_Background_Coordinator.md) | Delivered | `AllnighterMac`, `alln serve` |
| [OpenCode_Smoke_Probe_Blocker.md](OpenCode_Smoke_Probe_Blocker.md) | RESOLVED (OC-B0/B1) despite "Blocker" title | `OpenCodeRoutingWorkerRunner` |

### Dogfood field-report logs — shipped

| Doc | Final status | Code SSOT / successor |
| --- | --- | --- |
| [Field_Reports_1.md](Field_Reports_1.md) | Shipped (delivery #5) | live: `Field_Reports_3.md`, `Field_Reports_4.md` |
| [Field_Reports_2.md](Field_Reports_2.md) | Shipped (delivery #8, FR5+FR6) | live: `Field_Reports_3.md`, `Field_Reports_4.md` |

### GLM code-review run logs — historical

| Doc | Final status | Code SSOT / successor |
| --- | --- | --- |
| [code_review/](code_review/) | Historical GLM review run logs, packets, findings, triage | Pair queue (`alln pair slice`) deleted at R-S09; superseded by `PM_Relay.md` |
