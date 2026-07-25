# Archived Phases

Completed phase docs move here after closeout.

`Docs/phases/` is only for live phase work.

## Index

| Phase | Archived | Final status | Proof | Successor owner |
| --- | --- | --- | --- | --- |
| [Model Catalog Quick Fixes](Model_Catalog_Quick_Fixes.md) | 2026-07-25 | Complete — MCV-S03 shipped (`a26a264d`, contract 4.0.1): `teams duplicate`/`new`/`edit` return editable `TeamPreset`; show-projection refusal names the expected shape; `set-default` stays on show. Remaining ledger (S00/S04a unauthorized, S01 closed, S02 rejected, S04b deferred) is history — do not resume without a new founder ruling | `CatalogCLITests.testTeamsAuthoringReceiptsRoundTripThroughEdit`; `swift test --package-path Packages/AllnighterCore` — 2,179 tests, 6 skipped, 0 failures; `alln dev export-contracts --check` green | Code SSOT: `AllnighterCLI.teamDefinitionJSONString` on authoring printers, `loadTeamDefinition` / `teamShowProjectionRefusal`, `ContractRegistry.OutputSchema.teamPreset` / `.teamShowJSON` |
| [Sandbox Hand-off Hot Fix](Sandbox_Handoff_Hotfix.md) | 2026-07-25 | CLOSED — S1–S10 + S12 shipped; S11 ruled DO-NOT-BUILD after two independent pressure tests (Gemini 3.6 Flash, Grok 4.5); cross-process writer coordination cancelled by founder ruling. `alln` now works from inside a Codex sandbox: proven end to end by the founder (a 3-seat team returns in 1m31s, having been 2m49s and before that not working at all). Panel deleted outright in the same packet; contract cut 3.4.0 -> 4.0.0, binary 0.9.17 -> 0.10.0 | `swift test --package-path Packages/AllnighterCore` — 2,177 tests, 6 skipped, 0 failures; `xcodebuild -scheme AllnighterMac` green; founder-run live proof from inside Codex (`handoff-B9FF0FB0…`, `handoff-4672AC6B…`) | Code SSOT: `SandboxHandoffSpool` (mailbox), `SandboxHandoffRunner` + `SandboxHandoffHost` (the host half), `SandboxHandoff` (the caller half), `HandoffDoctor` + `alln doctor handoff`, `HostSandboxAdvice` (detection), `HandoffLog`. Contract-visible: `alln run` now exits non-zero on a failed/interrupted/cancelled run (`RunCLI.exitCode(for:)` on `RunStatus.lifecycle`) |
| [Unified Run Model](Unified_Run_Model.md) | 2026-07-24 | CLOSED — root run-model law; deletion manifest executed (`WorkOrder`/`ProjectProposal`/`VerificationRecord`/`ProjectManagerTurn`/`TeamPosture` confirmed gone from code); banned-term sweep clean over active code+docs | `swift test --package-path Packages/AllnighterCore` + `bash scripts/check.sh` green; `bash scripts/check_architecture_policy.sh` + `--self-test` green | Code SSOT: `RunService.swift` (the one run owner), `TeamPreset`/`TeamCatalog`, `RunWriteLockRegistry`; enforcement `config/architecture-policy.json` + `scripts/check_architecture_policy.sh` |
| [CLI Agent Ergonomics](CLI_Agent_Ergonomics.md) | 2026-07-24 | Complete — AE-S00–S15 shipped (contractVersion `1.6.0`) | `scripts/agent_eval.sh --suite menu-not-router`; works test in phase doc | `AllnighterCLI.helpText`/`ContractRegistry` (generated help), `RetiredVocabulary`, `TeamCatalog.isLabTeam`, `RunService` explicit-worker choke point |
| [Team Lab Run Factory](Team_Lab_Run_Factory.md) | 2026-07-24 | SHUT DOWN (founder ruling — we have all the teams we want/need for now); archived **un-rebased**, scripts still reference the dead `code_bug_hunt_lite` team | None run — do not resume without a new founder ruling | Built-in Teams ship as-is via `TeamCatalog`/`BuiltInTeams.swift`; harness code left at `scripts/team_lab/` unused |
| [Team Lab Composition And Seat Economics](Team_Lab_Composition_And_Seat_Economics.md) | 2026-07-24 | SHUT DOWN (founder ruling, same as above); archived un-rebased | None run | `Team_Depth_Naming.md` keeps the naming-only rename record; roster/seat-economics content is historical |
| [Team Lab Slice 1 Full Package](Team_Lab_Slice_1_Full_Package.md) | 2026-07-24 | SHUT DOWN (founder ruling, same as above); archived un-rebased; wire format was already superseded by CLI-native before shutdown | None run | Historical only |
| [Agent Dogfood Papercuts](Agent_Dogfood_Papercuts.md) | 2026-07-22 | Done — ADP-S01–S05 (`ca97d7c1` / `73353988` / `40914d97` / `7a89dacc` / `3acbe695`); binary `0.9.1` | Focused Core filters green: `swift test … --filter 'ReproduceCommand\|ResolvedRunInvocation\|TeamCatalog\|HelpTopicRegistry\|RetiredVocabulary\|VersionIdentity'`; `alln dev export-contracts --check` green (contract stays 3.0.0) | `CLI_Implementation_Contract.md` (no new laws); code: `TeamRun.explicitWorkerIds` + `RunCLI.reproduceCommand`, `RunDryRunJSON.alternatives`, `TeamPreset.disclosedDisplayName`, `HelpTopicRegistry`, `AllnighterVersionIdentity.binaryVersion` |
| [Alln Sharpening](Alln_Sharpening.md) | 2026-07-21 | Complete — SH-S00–S10 | `scripts/agent_eval.sh --suite sharpening` green on release `alln` (contract 3.0.0); focused Core filters green; full `check.sh` may still hit SH-S00 quarantined Pilot/Relay reds (`docs/operations/debugger/QUARANTINE.md`) | `CLI_Implementation_Contract.md`; code: `ResolvedRunInvocation`, `TeamRunJSON.answer`, `CommandProjection`, `ContractRegistry`, `TeamCatalog` |
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

### Agent front door — V1 Complete (gates 1–3 archived 2026-07-20)

| Doc | Final status | Code SSOT / successor |
| --- | --- | --- |
| [Agent_Front_Door.md](Agent_Front_Door.md) | SHIPPED (gate 1 — findable) | `InstallCLI.swift`, `Bootstrap.swift` |
| [Agent_Onboarding.md](Agent_Onboarding.md) | Complete 2026-07-20 — ONB-S01–S03 (`b6083575` / `bd28ebf0` / `a732d234` / `99fb5778`); PARKED remain parked | `TeachingSnippet.swift`, `TeachingInstalledCheck.swift`, `GlobalTeachingInstaller.swift`, `RecipeCatalog`; Mac Teach your CLIs / Use from your CLI; mechanical tests green; adversarial cold-agent battery = human/harness criterion |
| [Agent_Intent_Router.md](Agent_Intent_Router.md) | TOMBSTONED — superseded by Menu_Not_Router; IR-S00–S02 deleted under MR-S02 | Historical only; do not revive router |
| [Menu_Not_Router.md](Menu_Not_Router.md) | Complete 2026-07-20 — MR-S01–S06 (`2ef2ed43` / `e1519edd` / `e724595d` / `e2ab104f` / `f0bd3e02` / `9fd50e19`) | `MenuCatalog`, `TeachingSnippet`, exact-id resolvers, `alln menu` / `alln run`; harness `scripts/agent_eval.sh --suite menu-not-router`; sprint archive `sprint/menu-not-router/` |
| [CLI_Agent_Surface_Fidelity.md](CLI_Agent_Surface_Fidelity.md) | Complete 2026-07-20 — ASF-S00–S08 (`ddd6cc39` / `5b1f27ba` / `791d591e` / `02819c6b` / `ce65caf3`) | `HelpTopicRegistry`, `HelpDiscoveryIndex`, `RetiredVocabulary`, `BuildInfo`; help + nextActions CLI-only; check.sh deny-list + export-contracts |

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
| [Field_Reports_1.md](Field_Reports_1.md) | Shipped (delivery #5) | code SSOT (FR1–FR4); `RunIdentity`, `alln run` help/registry |
| [Field_Reports_2.md](Field_Reports_2.md) | Shipped (delivery #8, FR5+FR6) | code SSOT; `TeamRunJSON.outcome`, trailer convention |
| [Field_Reports_3.md](Field_Reports_3.md) | Shipped 2026-07-16 (delivery #10, FR7–FR11; `8882c8e3` / `4dfe97db` / `12b9fb49` / `70aefa02` / `d998b0da`) | `RunIdentity.laneLabel`, `JSONStreamLawTests`/`RunStreamContractTests`, delivered-not-stalled retry, handoff-ack + panel `isolation`, unattended vocabulary |
| [Field_Reports_4.md](Field_Reports_4.md) | Shipped 2026-07-16 (delivery #11, FR12–FR14; `021b120f` / `ca1f0001`) | `--commit-message` + `commitMessageMatched` (`ProvenanceConvention`), `--proof` (`proofCommand`/`proofTimeoutSeconds`), `ReportedTokenUsage`/`outcome.usage`; tests `RunCommitProofTests`/`RunFlagConstraintTests`/`RunTokenUsageTests` |

### GLM code-review run logs — historical

| Doc | Final status | Code SSOT / successor |
| --- | --- | --- |
| [`Menu_Relations.md`](Menu_Relations.md) | **KILLED 2026-07-24 by its own MRL-S01 kill gate** — 13/13 cold-agent cases pass from the flat menu, so a `relations` table would add bytes for no gain. MRL-S00 shipped (headroom 792 → 2,134). Code SSOT: `MenuCatalog.swift`, `MenuSelectionCopy.swift`; matrix `scripts/menu_not_router_eval.py`. |
| [code_review/](code_review/) | Historical GLM review run logs, packets, findings, triage | Pair queue (`alln pair slice`) deleted at R-S09; superseded by `PM_Relay.md` |
