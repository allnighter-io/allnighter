# Allnighter - Phases

Status: Active post-MVP planning and execution
Updated: 2026-06-22

## Purpose

The MVP team-run substrate has been built. Going forward,
`docs/phases/` is the active home for post-MVP product slices, mentor-review
notes, and implementation phase docs.

> **Launch authority hotfix is built and archived:** ordinary app launch is
> process-quiet before setup/recheck/run. Historical policy/proof:
> [`docs/archive/phases/Launch_Authority_TCC_Hotfix.md`](../archive/phases/Launch_Authority_TCC_Hotfix.md).
>
> **Run model:** a run = message + optional preset + worker, in the repo root.
> Answer teams are read-only (parallel); execution teams are one worker (mutating)
> under the per-root write lock. Active law: [`Unified_Run_Model.md`](Unified_Run_Model.md).
> Historical source-gate proof:
> [`docs/archive/phases/Execution_Team_Source_Gate.md`](../archive/phases/Execution_Team_Source_Gate.md).
>
> **▶ [`setup/`](setup/README.md) — First-Run Setup ("assemble your team").**
> Phase 0 (packaging) and Phase 1 (detection engine: `CLIDetector` +
> `ShellResolver` + `SetupStore`, reachable headless via `alln detect`) are
> **built**; Phase 2 health == runs, Phase 3 lean setup surfaces, and Phase 4
> auto-team are also built. Remaining setup work is live founder smoke on a real
> machine plus repair polish found in use. See `setup/README.md` for live status.
>
> **▶ [`sprint/`](sprint/README.md) — Sprint work orders** (one-slice implementer
> prompts; use for 32K-context agents instead of full phase docs).

`docs/mvp/` remains the source of truth for what has already shipped and for the
foundation it created: workers, drivers, fan-out, synthesis, design boards, and
the Mac app substrate. New forward work starts here unless a routed doc says
otherwise.

## Current Phase Board

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Agent_Front_Door.md`](Agent_Front_Door.md) | **SHIPPED** (gate 1 — findable) | `alln install-cli` performs, bootstrap self-heals, no empty silence. Trust guarantees extracted as SSOT (never swaps your model / fakes completion / lets two agents edit behind your back). |
| [`Agent_Onboarding.md`](Agent_Onboarding.md) | **Specced v3** (gate 2 — suggested; panel-hardened 2026-07-16, sharpened 2026-07-18) | From findable to suggested: the app teaches every CLI session about alln. v3 — trigger line points at `team hello --for` (teach the reflex, not the catalog), recipes retitled by intent, adversarial works test. V1 = 3 slices; per-project offer + graduation nudge parked. |
| [`Agent_Intent_Router.md`](Agent_Intent_Router.md) | **Specced v1** (gate 3 — routes intent → right team) | `alln team hello --for "<intent>"` becomes a local solutions engineer. **IR-S00 = founder-gated catalog normalization** (every family → Min/Default/Max + obvious names; only Spec Review + Growth locked today) is a hard prerequisite. |
| [`Run_Latency_And_Streaming_Recovery.md`](Run_Latency_And_Streaming_Recovery.md) | **CODE RED PERF PRIORITY** — recovery phase for default-chat startup, first answer latency, streaming throughput, terminal settlement, and scroll jank | Dogfood response to the 2026-06-21 "2/10 product is dead" finding: a Composer-family run took ~30s to first visible answer, completed in the run artifact, but left the thread turn stuck `running`; stream debug logging and live timeline rendering can also poison throughput and scrolling. Owns the 10x recovery plan before broader feature work. |
| [`Team_Run_Load_Performance.md`](Team_Run_Load_Performance.md) | **TOP PERF PRIORITY** — initial Team-run open stall fixed; live thread/reload hot path remains | Dogfood diagnosis for Team-run lockups and broader app sluggishness. Initial fix shipped run-decode cache, lazy terminal worker markdown, and Open Factory Floor. Next recommendation is first-principles hot-path hardening: coalesced reloads, in-memory/throttled live deltas, derived rail state, unread/index memoization, background store reads, and performance gates. |
| [`Language_Cutover.md`](Language_Cutover.md) | **DONE** (CUT-S00–S06, 2026-06-18; check.sh green) | Hard, no-alias rename to the locked vocabulary (Chat / Delegate "Send to team" / Execute; Team; Code/Design/Copy + Signal; effort = model reasoning level). Landed: craft Build→Code, Fan out→Send to team, effort→worker-count gating ripped out, Fanout_Team_Catalog→Team_Catalog. Stays as the canonical word list/SSOT. |
| [`Team_Delegation_Surface.md`](Team_Delegation_Surface.md) | Draft spec — Core cards built; **GUI browse surface unbuilt; ⚠ overlaps `Team_Run_Floor.md` (FOUNDER DECISION)** | Send to team as the discoverable delegation surface: Team Card projection, Signal/Code/Design/Copy families, Project Manager recommendations, direct team send, and Execute approval for mutating work. TeamCard + family + mutating routing exist in Core; the discovery/browse UX is unbuilt and its narrative overlaps the Floor — decide ownership (picker vs workroom) before building. |
| [`Team_Run_Floor.md`](Team_Run_Floor.md) | **Core projection BUILT** (FloorRun + worker lanes + typed Insight + timeline + artifact refs); CLI/MCP retrieval + GUI rendering remain | The inspectable Floor for every team run: worker lanes, durable per-worker artifacts, typed Return/Insight, receipts, timeline, richer next actions, and Execute requirements. (See `FloorRun.swift`/`FloorProjector.swift`.) Note: team-discovery narrative overlaps `Team_Delegation_Surface.md` — ownership split unresolved. |
| [`Live_Team_Board.md`](Live_Team_Board.md) | Draft feature packet — no-theater contract | In-thread live board for running answer-team runs: show every assigned worker/job/model, sourced started/running/done/failed states, and real per-worker answer deltas only when emitted. Terminal results land in the Factory Floor; the thread keeps a compact receipt card. Explicitly forbids fake activity prose and fake progress. |
| [`GUI_Visual_Proof_Gate.md`](GUI_Visual_Proof_Gate.md) | **ACTIVE BUILT GATE** (S00–S05 built, policy still live) | Stops blind GUI "fixed" claims: render the surface, a separate layout-watcher looks at the pixels (layout-only; CLI owns content truth), and a content-bound proof packet is wall-enforced by `scripts/check_gui_proof.sh`. Keep active until this policy is promoted to an operations/GUI SSOT. |
| [`Unified_Run_Model.md`](Unified_Run_Model.md) | **Decision — replacement root model; Core + CLI/MCP BUILT** (Default Team raw passthrough live; Execution Playbook preset + composer simplification remain) | A run = message + optional preset + worker, in the repo root. Default chat = the Default Team (raw passthrough). Answer teams (parallel, read-only) vs execution teams (one worker, mutating, write-locked). Replaces the deleted Project Manager / work-order / propose→dispatch→verify loop. |
| [`Default_Team_Override.md`](Default_Team_Override.md) | **Ready for Implementation** (founder-found T2 SSOT bug packet, 2026-06-21) | Lets the user edit/reset the global Default Team without creating a duplicate row: immutable `default_chat` seed, optional same-id user override, one effective catalog entry across Core/CLI/MCP/GUI, Restore deletes the override and reveals the seed. |
| [`Try_Fix_Auto_Implement.md`](Try_Fix_Auto_Implement.md) | Draft feature packet | "Try Fix" checkbox / Auto-Implement chain after Bug Hunt: read-only Code Bug Hunt returns a high-confidence typed FixPacket, Core gates it, then one proof-aware execution worker tries the recommended fix under the repo write lock. CLI/MCP-first; Mac checkbox presents the shared contract. |
| [`Pilot_Panel.md`](Pilot_Panel.md) | **SHIPPED** (PN-S01–S06, works test passed live 2026-07-16; first real five-seat run panel_753613c7 same day) | Session-led blind jury on any target: blind fan-out, structured findings, read-only by mechanism (driver RO mode or ephemeral clone), durable rounds, target-hash run-truth. Panel hardens the judgment, Pilot builds the work, Relay runs the night. |
| [`Process_Ownership.md`](Process_Ownership.md) | **Approved for implementation** (founder, 2026-07-17; reliability slice) | The law: every process Allnighter creates has a durable owner, `setsid` process-group ownership (kill is total), a heartbeat (reconcile only on stale+dead), and surfaced contention (typed lane-busy naming the holder — no silent 0%-CPU waits). PO-S01 self-owning async `team start` runners; PO-S02 harness-owned proof (reuse ProjectVerificationService) + total turn kill + `endReason`; PO-S03 relay/pilot turns+proofs under the one per-root execution lane. Non-goals: no resident-serve ownership, no build farms. |
| [`Panel_Polish.md`](Panel_Polish.md) | **Specced** (PP-S01–S03, from first-real-use notes 2026-07-16) | The burrs from panel_753613c7: `unstructuredSeats` envelope-top warning, schema-contract placement law (the agy_opus "in the artifact" escape), stray-parked advisory + `panel abandon`, mechanical convergence flag, FR8 line-JSON law recorded as keep-forever. |
| [`PM_Relay.md`](PM_Relay.md) | **SHIPPED** (R-S01–R-S07 + R-S09, 2026-07-16; R-S08 GUI entry open) | Mechanizes the founder's PM↔dev copy-paste loop: a PM seat reviews the repo and writes a handover, a dev seat builds and commits, round after round, unattended. Supersedes `Pair_Programming_Team.md` (the old slice-queue pair loop — deleted outright at R-S09). |
| [`OpenCode_Smoke_Probe_Blocker.md`](OpenCode_Smoke_Probe_Blocker.md) | **BLOCKED — handoff** (2026-06-26) | OC-S01 plumbing landed; `alln doctor --full` + Mac setup smoke still fail (headless stdout empty). Wrong-level fixes exhausted — needs integration-contract spike (stdout vs export vs json). |
| [`Team_Lab_Run_Factory.md`](Team_Lab_Run_Factory.md) | Draft feature packet — re-based CLI-native 2026-07-16 | CLI-native run factory for making default Teams excellent: benchmark suites, full CLI JSON envelope / stream transcripts, per-worker/writer scoring, run-contract scoring, artifact completeness checks, and stop-the-line fixes for CLI/run-contract bugs found while calibrating Teams. |
| [`Team_Lab_Slice_1_Full_Package.md`](Team_Lab_Slice_1_Full_Package.md) | **Active implementation spec** (2026-06-21) | Whole v1 package: PRE-S0 + LAB-S00–S05 + Judge Loop v2 for Bug Hunt calibration; autopromote champion overlays; post–Slice 1 good-to-great roadmap (substrate hardening, CI gates, Team sweep, evidence automation). |
| [`Team_Lab_Composition_And_Seat_Economics.md`](Team_Lab_Composition_And_Seat_Economics.md) | **Active implementation spec** (2026-06-23; Spec Review depth note 2026-07-18) | Post–Slice 1 macro loop: seat economics, VNRC, forward selection, necessity suite, LAB-C00–C08. Variant naming superseded by `Team_Depth_Naming.md`. Spec Review Min/Default/Max already ship — Lab validates/tunes those IDs; never invents/deletes them or auto-routes to Min. |
| [`Team_Depth_Naming.md`](Team_Depth_Naming.md) | **DECIDED — convention SSOT; Spec Review tiers shipped 2026-07-18** | Family = the job; depth = universal Min / (bare name) / Max; bare name is the default send, never Min. Spec Review now ships a resilient 3-worker Min, 5-worker Default, and full 7-worker + scout Max with ordered cross-CLI fallbacks; Team Lab validates/tunes the curated rosters. No numbers in names. "Pressure Test" is retired everywhere. |
| [`Signal_Scout_Triangulation_And_Graph.md`](Signal_Scout_Triangulation_And_Graph.md) | **ORPHAN — was unlisted; ⚠ FOUNDER DECISION** | Signal craft foundations exist in Core (`WorkLane.signal`, `SignalInsight.swift`, `SignalScoutPolicy.swift`, signal teams/skills), but all 8 spec slices (Scout→Graph→Surface) are unbuilt and the doc was missing from this board. Decide: still the Signal direction (re-list + build), or archive the deep-build doc and keep only the shipped foundations? |
| [`Composer_Image_Attachments.md`](Composer_Image_Attachments.md) | **Backend BUILT** (CIA-S00–S07, 2026-06-17); GUI S03/S04/S08/S09 remain | Image attachments: coordinator send transaction, canonical store, CLI/MCP send, fan-out mapping. GUI paste, timeline chips, proof seal, and DnD deferred. |
| [`Composer_Model_Popup_Update.md`](Composer_Model_Popup_Update.md) | **BUILT** (2026-06-20; `composer/team-picker` proof sealed) | Composer team/model popover simplified to a fast picker: Auto pinned first ("Auto" / "Default model"), a search field directly under it (searches the whole roster, no lane filter), Recent (max 3, in-memory) + Favorites as the default surface, non-favorites hidden until searched. Craft chips (Code/Design/Copy/Signal) + the All chip removed. The collapsed chip now reads "Auto · <model>" in Auto mode. Full Teams screen stays the roster/management surface. |
| [`Composer_File_References.md`](Composer_File_References.md) | **Backend BUILT** (FR-S00–S03, verified 2026-06-20); Mac GUI remains | `@` file references. BUILT: `ThreadFileReference` models, `ProjectFileReferenceResolver` (path catalog + send-time SHA256 audit), `alln thread send --ref path:start-end`, MCP `thread_send.fileReferences[]`, FILE_REFERENCE_* error codes, tests. Remaining = **GUI only**: the composer `@` palette, file chips, draft persistence, context reveal (no eligible non-GUI work left here). |
| [`Persistent_Work_Threads.md`](Persistent_Work_Threads.md) | Parent/router (2026-06-21); core MLP + CR4 conversation send paths delivered | Work-thread lane router: shipped thread/chat/CR4 send paths, then store hardening, unread lights, rail controls, notifications, streaming, observed usage, and thread forking via child docs. |
| [`threads/09_Thread_Forking.md`](threads/09_Thread_Forking.md) | Draft feature packet — MCP/CLI-first | Fork a chat/thread from a terminal turn prefix into a new active child thread. Acceptance starts with MCP `thread_fork` + CLI `alln thread fork`; Mac inline/rail Fork actions present the shared contract after storage, attachment/context copy, and run-index proof. |
| [`threads/06_Unread_Message_Light.md`](threads/06_Unread_Message_Light.md) | **UNR-S01–S06 + S07 BUILT** (2026-06-17); S08 remains | Durable read cursor, Core unread derivation, `ThreadStore.markRead*`, presenter triage buckets, Mac rail light, viewport clear, notification suppression hooks, `home-rail-unr` GUI matrix. Rich-turn clear defers to S08; iOS protocol in `ios/03`. |
| [`threads/02_Notifications.md`](threads/02_Notifications.md) | **BUILT** (NOTIF-S01–S05 + UNR-S06, 2026-06-17) | Mac local notifications for landed work and attention states; menu-bar live/needs-attention indicator; per-thread mute; debounce/quiet-hours policy. Mobile push parked in `ios/03`. |
| [`Message_Image_Rendering.md`](Message_Image_Rendering.md) | **Ready for implementation packet** — engine + `thread_send` landed; read-path/GUI remain | Umbrella spec: images in thread messages (single-lane worker replies, user attachments, Design fan-out tiles). MCP/CLI first (`thread get/status` route + attachment resolve, design run paths) then Mac timeline/board/Floor rendering with `docs/gui/surfaces/threads/brief.md`. |
| [`threads/08_Worker_Image_Output_In_Chat.md`](threads/08_Worker_Image_Output_In_Chat.md) | **Backend BUILT** (WIO-S00–S03, S05, 2026-06-17); WIO-S04 GUI deferred | Worker image output in chat (design continuity): chat to imageGen workers captures + commits canonical attachments (same store as user paste); prior/picked images flow into next context; WIO-S04 Mac timeline thumbnails remain. |
| [`Stalled_Work_Watchdog.md`](Stalled_Work_Watchdog.md) | WTK-S00-S04 + SWW-S00-S03 + **SWW-S04 recovery (S04b+c) BUILT** (2026-06-20); next S04a/S04d (non-GUI) + S05 (GUI) | Separates expected capacity sleep from unexpected stall. Built: capacity observation, Wake Tickets, CLI/MCP Pending run parity, resident one-shot wake, teamRun Pending execution, detector, refresh-before-declare, read-only CLI/MCP stalled projections, and **executable+agent-callable recovery** (`StallRecoveryService` + `alln stalled check\|wait\|dismiss` + MCP stall_* tools). Remaining non-GUI: periodic resident scan loop (S04a), run/project attention projection (S04d). S05 Mac notification/menu = GUI. |
| [`Pending_Work_And_Drain.md`](Pending_Work_And_Drain.md) | **Pending0 + Pending1 BUILT** (2026-06-17); workerChat/teamRun CLI/MCP run + Wake Tickets built; broad native drain parked | Public `alln pending` CRUD + local Pending model/persistence are built. CLI/MCP `pending run` executes/settles workerChat and non-mutating teamRun Pending, exposes Wake facts, and `alln serve` wakes due workerChat tickets once. FollowUp/returnReview execution and mutating work-order/dispatch paths remain separate gated follow-on work; Away Mode, fairness drain, PTY probes, and admission ledgers remain parked. |
| [`CLI_Product_Spine.md`](CLI_Product_Spine.md) | **CLI M1 BUILT** (2026-06-15) | `alln` is the first-class agent-ready contract; RB6 grammar retired. Still owns the forward spine + naming/agent-first laws. |
| [`CLI_Implementation_Contract.md`](CLI_Implementation_Contract.md) | **CLI M1 BUILT** (2026-06-15), full wall green; **Pending0/1 BUILT** (2026-06-17) | M1 shipped: `TeamRunJSON`/`DoctorResult`/`ErrorEnvelope`, Core registry + generated artifacts + drift gate, `team --json` + live run-lifecycle `--stream` (not answer deltas), `doctor --json/--full`, `docs`/`show`/`export`/`history`/`doctor explain`, MCP `serve --stdio` (registry-derived). `alln pending` add/list/show/submit/edit/reorder/cancel/run + `PendingItemJSON` fixture/schema. Still owns: MCP advertising/async tools; `pending stop`; native Pending drain is parked. |
| ~~`Team_Catalog.md`~~ | **BUILT — ARCHIVED** (2026-06-20) | Built-in lane team catalog substrate, shipped + stable (`TeamCatalog.swift`). Completed M1 substrate spec → moved to `docs/archive/phases/`. Forward catalog work lives in `Team_And_Skill_Catalogs.md`; code is SSOT. |
| [`Team_And_Skill_Catalogs.md`](Team_And_Skill_Catalogs.md) | **S00–S04 BUILT** (catalogs/IDs/persistence/CLI/resolver); S05 (Mac Settings lane-first nav) in progress; Default Team carve-out routed | Cleanup-first lane catalog feature: `TeamCatalog` + `SkillCatalog`, `TeamID` + `SkillID`, built-in and custom teams/skills in one catalog model, lane-first Settings, no Store vocabulary, no migration, no skill versioning. Ordinary built-ins remain duplicate-to-edit; `default_chat` override semantics live in `Default_Team_Override.md`. |
| [`Model_Catalog_And_Bench_Roster.md`](Model_Catalog_And_Bench_Roster.md) | **BUILT** (MCBR-S01–S08, 2026-06-18) | Core `ModelCatalog` as the owner for built-in/custom per-CLI models, persistent Bench enablement, manual add/update/delete, CLI model commands, ToolRuntime/probe-label hardening, and the live-discovery seam. Model management stays inside CLIs; Bench is derived. |
| ~~`Substitution_Bench_Default_Settings.md`~~ | **BUILT — ARCHIVED** (2026-06-20) | Default model & Substitutions shipped end-to-end (many-to-many tiers, no pinned, `alln defaults` + `defaults_get` MCP + Default-model screen). The spec body was a stale pre-cutover draft (retired "pinned"/one-shelf concepts) → moved to `docs/archive/phases/`. **Code is SSOT:** `DefaultModelSettings.swift`. |
| [`Team_Configuration_UX_Rescue.md`](Team_Configuration_UX_Rescue.md) | **Contract-hardened implementation spec** (2026-06-17) | Mac team configuration rescue after first-use rejection: composer Customize wiring, primary Customize team drawer, level-2 Customize worker modal, built-ins as lazy custom drafts, TeamWorkerDraft prompt edits, save-time skill forking with rollback, visible default-team control, search-first skill picker, ready-first model picker, and proof slices. |
| [`Agent_First_MCP_And_Messaging_Workflows.md`](Agent_First_MCP_And_Messaging_Workflows.md) | PARTIAL: bootstrap/preflight/discovery + spec retrieval + A0 async team loop + A1 Pending read/run BUILT; **help system (H0a–H3) BUILT** (see `MCP_Help_System.md`); A3–A6 (install artifacts / messaging UX / provenance-safety / entitlement) PARKED | Agent-first workflow layer for OpenClaw/Hermes-style messaging and voice agents: bootstrap/doctor recovery loop, MCP async team tools, Pending over MCP, full spec retrieval, provenance, approval handoffs, and entitlement hooks. |
| [`MCP_Help_System.md`](MCP_Help_System.md) | **H0a–H3 BUILT** (2026-06-20); H4 reframed, H5 + installed-bundle remain | Installed, repo-free Allnighter help. BUILT: HelpTopicRegistry/HelpService SSOT, `alln help search\|get\|topics`, MCP `help_search`/`help_get`, help-first routing in `mcp_hello`, error→help bridge, `mcp install --target` host snippets. Remaining (non-GUI): help-pack export + `helpBundleVersion`/drift gate (H0), golden transcripts (H5). H4 in-app = **normal compose** (the worker answers via installed help; no help screen). |
| [`Mac_Standalone_App_And_Background_Coordinator.md`](Mac_Standalone_App_And_Background_Coordinator.md) | Draft forward phase | Convert the Mac shell from menu-bar-first to standalone Dock app plus explicit background coordinator/resident lifecycle. |
| [`Work_Order_Team_Model.md`](Work_Order_Team_Model.md) | Active language contract | Source, bench, model, skill, worker, team, lane, type, model reasoning effort, and preset vocabulary for work-order specs. |
| [`copy/README.md`](copy/README.md) | Draft post-MVP lane | Copy work orders: prompt-first `/copy`, copy type, Copy team, copy board, and later specialized copy packs. |
| [`ios/README.md`](ios/README.md) | Parked iOS spine; deferred until macOS app is done | Future remote Project Manager specs live here so they do not block Mac delivery. `ios/03_iOS_Thread_Read_State_And_Push.md` owns future iOS unread/push. |

## Execution Order

Recommended order for upcoming work, foundation-first: the CLI/MCP contract is the
product surface, so it is hardened before the GUI/iOS that present it (see the
CLI/MCP-First rule in `docs/workflows/SSOT_Feature_Workflow.md`). With zero users,
this is the window to build the killer foundation rather than patch later. The
founder may reprioritize; the dependency logic is what matters.

1. **Language cutover — ✅ DONE (2026-06-18).** `Language_Cutover.md` CUT-S00–S06
   landed on `feat/design-chain`; full `check.sh` green. The locked vocabulary
   (Chat / Delegate "Send to team" / Execute; Team; Code/Design/Copy + Signal;
   effort = model reasoning level) is now the codebase reality. **Next up is step 2.**
2. **Project spine continuation** — `Project_Spine_And_Project_Manager.md`
   **PRJ-S07–S13**: Project CLI foundation, Manager chat, proposal engine,
   approval/work-order, handoff/reveal/dispatch, return verification, and MCP
   Project tools. PRJ-S00–S06 are built; the execution source gate is built and
   archived, and remains a dispatch law before worker invocation.
3. **MCP contract discipline (gate before any new CLI/MCP surface)** —
   `Agent_First_MCP_And_Messaging_Workflows.md` § MCP Solidity Plan **M-A** (schemas
   for every tool), **M-C** (exit codes + error catalog), **M-B** (CLI<->MCP parity
   proof). Establish this standard before building new agent surfaces so they are
   built to it, not retrofitted. The Project doc already depends on the shared error
   envelope + exit codes, so this lands alongside / just before Project CLI/MCP work.
4. **Composer File References** — `Composer_File_References.md` **FR-S00–S07**
   (Core resolver/catalog, CLI/MCP `--ref`, send-time audit, prompt renderer, Mac
   `@` palette, chips, reveal, and delayed-dispatch revalidation). This is the
   missing context-delivery feature for Project Manager chat and Send to team:
   agents should receive the exact Project file contents the user selected.
5. **Send-to-team surface + gating** — `Team_Delegation_Surface.md` for the
   discoverable product surface, plus `Agent_First_MCP_...` **M-D** (team
   discovery/run tools), **M-E** (sync-ask resolution), **M-F** (provenance /
   client approval / entitlement gate).
6. **Wake Tickets + Stalled Work Watchdog** — `Stalled_Work_Watchdog.md`
   backend/CLI/MCP MVP is built through WTK-S00-S04 and SWW-S00-S03. Next is the
   product attention loop in one bundle: SWW-S04 Project Manager wait nudges +
   typed actions, resident periodic stall scanning, SWW-S05 notifications/menu
   integration, and safe Pending follow-up/review leftovers. Keep this narrow:
   no broad drain, no provider probes, no worker substitution, and no ungated
   mutating Pending execution.
7. **MCP proof wall** — `Agent_First_MCP_...` **M-G**, wired into CI once the tools
   above exist (the MCP analogue of the GUI Visual Proof Gate).
8. **Default Settings + Substitution Bench** — `Substitution_Bench_Default_Settings.md`
   after `Model_Catalog_And_Bench_Roster.md`: define `Auto on <shelf>`,
   Flagship/Balanced/Fast shelf membership, CLI/MCP settings tools, and
   same-shelf resolver proof before Mac Settings renders the controls.
9. **GUI/app surfaces that present the contracts** — `Project_Spine_...`
   **PRJ-S14–S15** (Projects rail + dogfood proof), `Team_Configuration_UX_Rescue.md`,
   the composer/team-library GUI, Composer image GUI, and other deferred GUI slices.
   The GUI presents the stabilized CLI/MCP contract; it never invents parallel truth.
10. **iOS companion** — `ios/README.md`, last (parked until the macOS app is done).

## Operating Rules

- Founder input is intent. Durable semantics go through a phase doc or routed
  SSOT before implementation.
- New phase docs must name one trusted workflow slice, one truth owner, and one
  Works Test or proof waiver.
- Product truth belongs in `AllnighterCore`, protocol docs, or the owning phase
  doc. SwiftUI may render truth; it must not invent it.
- Generated output is derived. Change the source contract, then regenerate.
- Finished phase docs should be archived only after their durable truth has been
  promoted to the owning source.

## Post-MVP Product Laws

- Allnighter coordinates workers the user already pays for. It is not a model
  provider, IDE, chat aggregator, cloud coding service, or terminal viewer.
- A Project is the durable local repo/folder floor. A work thread is the durable
  conversation unit inside a Project. Chat is the default turn; team run, design
  board, work order, dispatch, and return review are stronger turn types inside
  the same thread.
- Global CLI setup does not imply Project worker readiness. Allnighter may
  auto-detect ready workers per Project root with safe probes, but must not
  auto-configure or auto-authorize vendor CLIs.
- The user-facing words are: project, project manager, model, skill, worker,
  team, team run, worker answer, plan, work order, thread.
- Do not add new public `team` language. `Work_Order_Team_Model.md`
  owns the active vocabulary contract (cleanup slice complete — see
  `docs/archive/phases/Team_First_Vocabulary_Cleanup.md`).
- Workers fail honestly. A failed worker is shown failed, never hidden or faked.
- Team selection owns work shape. Do not add a generic Low/Med/High team-depth
  toggle; provider/model reasoning effort is separate worker/model config when
  supported.
- Healthy model substitution is same-shelf only. The shelves are user-governed
  Flagship/Balanced/Fast groups from `Substitution_Bench_Default_Settings.md`;
  substitution may cross CLIs inside a shelf, but never silently upgrades,
  downgrades, or leaves the selected shelf.
- Do not estimate future cost, quota burn, runtime, or task complexity.
- Capacity state is observed, sourced, timestamped, and local by default.
- Pending separates Project-scoped user intent from immediate execution.
  queueing is internal machinery language, global Pending is aggregate-only, and
  native scheduling/drain is parked unless explicitly revived. One-shot Wake
  Tickets are the scoped exception for already-authorized work with sourced
  CLI capacity/cooldown output.
- Pending is public CLI-first: `alln pending` must exist before the GUI promises
  Draft/Pending/Running state. External agents may trigger Pending through
  CLI/MCP.
- The Project Manager is the default chat identity inside a Project and the
  approval/verification layer above specialist lanes. It may answer, propose
  next work, and verify completion, but v1 must not auto-execute unapproved
  work.
- Execution queue state is derived from git, docs, active runs, proof artifacts,
  and approvals. It must not become a competing source of product truth.
- Forward Mac app work targets a standalone Dock app plus explicit background
  coordinator. The menu bar is status/quick controls, not the primary shell.
- iOS is a future remote Project Manager surface. The Mac remains the execution
  and run-truth owner, and iOS must not block macOS app delivery.
- Work-order creation stays prompt-first. Code/Design/Copy and Team route the
  work; they must not become an intake form.
- Code, Design, and Copy are the peer creation lanes. A fourth lane requires a
  new substrate or output class; otherwise it is a type or preset inside the
  existing lanes.
- Send to team never infers lane from prompt prose. The user chooses Code / Design /
  Copy. Send to team targets a lane-scoped team, not a bare model.
- Every built-in and custom team belongs to exactly one lane. There are no
  shared or multi-lane teams; duplicate and tune a lineup when it belongs in
  another lane.
- Every built-in and custom skill belongs to exactly one lane. There are no
  shared or multi-lane skills; similar roles (Skeptic, Contrarian, etc.) ship as
  separate lane-sharpened built-ins — duplicate and tune when a hat belongs in
  another lane.
- Mixed-source teams are for judgment. Teams with `posture == execute` or
  `mutating == true` must resolve to one source/driver before any mutating spawn;
  see `Work_Order_Team_Model.md`. Execution lane serialization is collision
  control, not permission to run mixed-source execution.
- Settings navigation is **lane-first**: CLIs (lane-agnostic), then BUILD /
  DESIGN / COPY, each with Teams and Skills — not noun-first Teams | Skills with
  lane filters inside. Default: health badge → CLIs; composer Manage team → that
  lane's Teams.
- Team definitions are reusable units. Built-in and custom teams may resolve to
  multiple workers on one ready model when the user has only one CLI connected;
  show that truthfully as many workers / one model.
- A worker is one model wearing one skill. Lanes ship default teams, but advanced
  users can customize the worker lineup as `Skill | Model` one level below the
  main composer.
- The first new team-run machine contract is `TeamRunJSON`: `teamRun`, `models`,
  `workers`, `workerAnswers`, `stages`, and `plan`. GUI, MCP, and iOS must not
  invent parallel run schemas.
- Messaging-first agents are first-class clients. OpenClaw/Hermes-style agents
  should call Allnighter through the same CLI/MCP/Core contracts as the GUI.
- Agent-first surfaces must bootstrap and recover headlessly: `mcp_hello`,
  doctor v2, explain tools, safe auto-fix, and exact human actions are part of
  the product surface.
- Agent-originated runs and Pending items are not a pricing bypass. They follow
  the same entitlement policy once billing is implemented.

## Adding a Phase Doc

Use this shape unless a narrower workflow requires more:

```text
# Phase Name

Status:
Owner:
Updated:

Founder intent:
Product value:
Trusted workflow slice:
Non-goals:

Current state:
Truth owner:
Lie-prone layers:
New/changed semantic rules:
Duplicate truth to delete:

Implementation impact:
Mac app impact:
iOS app impact:
Driver/protocol impact:
Auth/privacy/permissions impact:

Works Test:
Proof command:
Missing proof / waiver:

Done when:
Open questions:
```

## Routing

| Work | Read first |
| --- | --- |
| Mac launch TCC prompts, startup shell/CLI probes, process-quiet launch | **BUILT** — `docs/archive/phases/Launch_Authority_TCC_Hotfix.md`; new regressions route through `docs/operations/Debugger.md` |
| Default-chat startup latency, first answer delay, streaming throughput, stuck running turns, scroll jank while streaming | `Run_Latency_And_Streaming_Recovery.md` + `threads/03_Mac_Streaming.md` + `Team_Run_Load_Performance.md` |
| GUI visual bugs, SwiftUI "fixed" claims, screenshot/proof gates | `GUI_Visual_Proof_Gate.md` + `docs/gui/GUI_Workflow.md` |
| Send to team, Delegate surface, Team Cards, Signal/Code/Design/Copy team map | `Team_Delegation_Surface.md` + `docs/gui/surfaces/send-to-team/brief.md` |
| Team run Floor, inspectable worker lanes, worker artifacts, Signal Insights, run receipts | `Team_Run_Floor.md` + `CLI_Implementation_Contract.md` |
| Team run load performance, rail click stalls, thread-vs-Floor result navigation | `Team_Run_Load_Performance.md` + `Live_Team_Board.md` + `Team_Run_Floor.md` |
| Bug Hunt auto-implement, "Try Fix" checkbox, diagnosis-to-fix child runs | `Try_Fix_Auto_Implement.md` + `Unified_Run_Model.md` + `docs/operations/Debugger.md` |
| CLI-native run factory, default Team benchmarking/calibration, per-worker scoring, run-contract bugs found through CLI | `Team_Lab_Run_Factory.md` + `CLI_Product_Spine.md` + `CLI_Implementation_Contract.md` + `Team_Run_Floor.md` |
| Team lab seat economics, roster ablation, named team variants, necessity suite, macro vs micro loop | `Team_Lab_Composition_And_Seat_Economics.md` + `Team_Lab_Run_Factory.md` + `Team_Lab_Slice_1_Full_Package.md` |
| Team naming, depth tiers (Min/Default/Max), family names, picker depth control, bug-family rename map | `Team_Depth_Naming.md` + `Team_Lab_Composition_And_Seat_Economics.md` |
| Live in-thread team run progress, per-worker status rows, honest streaming excerpts | `Live_Team_Board.md` + `threads/03_Mac_Streaming.md` + `CLI_Implementation_Contract.md` |
| Execution teams, mutating team runs, dispatch/source safety | `Work_Order_Team_Model.md` + `Project_Spine_And_Project_Manager.md` + `CLI_Implementation_Contract.md` |
| Projects, local repo/folder roots, Project Manager chat, project-scoped threads/runs/pending/dispatch | `Project_Spine_And_Project_Manager.md` |
| Next-item proposals, execution queue, approval gates, worker handoffs, proof verification | `Project_Spine_And_Project_Manager.md` + `docs/operations/Execution-Playbook.md` |
| Public vocabulary, model/skill/worker/team language | `Work_Order_Team_Model.md` (historical cleanup: `docs/archive/phases/Team_First_Vocabulary_Cleanup.md`) |
| CLI-first product spine, `alln`, product grammar, agent-first posture | `CLI_Product_Spine.md` |
| CLI implementation detail, generated docs/doctor/errors/events, proof gates | `CLI_Implementation_Contract.md` |
| Team-run JSON/schema, MCP rename, RB6 CLI cutover | `CLI_Product_Spine.md` + `CLI_Implementation_Contract.md` |
| Send to team composer, built-in lane team packs, team resolver substrate | `Team_And_Skill_Catalogs.md` + `Work_Order_Team_Model.md` (substrate spec archived: `archive/phases/Team_Catalog.md`; code SSOT `TeamCatalog.swift`) |
| Model catalog, Bench enable/disable, per-CLI model lists, custom model add/update/delete, model discovery seam | `Model_Catalog_And_Bench_Roster.md` + `Work_Order_Team_Model.md` |
| Team configuration UX rescue, first-use team management feedback, Customize worker modal, save-time skill forking, default-team UI, searchable skill picker | `Team_Configuration_UX_Rescue.md` + `Team_And_Skill_Catalogs.md` + `docs/gui/GUI_Workflow.md` |
| Team/skill catalogs, custom team + skill editing, `alln teams`, `alln skills`, lane-first Settings | `Team_And_Skill_Catalogs.md` + `Work_Order_Team_Model.md` |
| Team lineup edit, customize/new/duplicate team, worker rows referencing SkillID | `Team_And_Skill_Catalogs.md` first, then `CLI_Implementation_Contract.md` |
| Default model (Auto), healthy substitutions, Flagship/Balanced/Fast tiers (many-to-many) | **BUILT — code SSOT** `DefaultModelSettings.swift` + `alln defaults` / `defaults_get`; spec archived: `archive/phases/Substitution_Bench_Default_Settings.md` |
| Composer `@` file references, Project file search, file chips, prompt file-read blocks | `Composer_File_References.md` + `Project_Spine_And_Project_Manager.md` + `CLI_Implementation_Contract.md` |
| OpenClaw/Hermes, messaging agents, voice-to-text workflows, doctor recovery, Pending over MCP, full spec retrieval | `Agent_First_MCP_And_Messaging_Workflows.md` + `CLI_Product_Spine.md` + `CLI_Implementation_Contract.md` + `Pending_Work_And_Drain.md` |
| Installed Allnighter help, MCP help search/get, repo-free product docs, agent help routing, generated help drift gates | `MCP_Help_System.md` + `Agent_First_MCP_And_Messaging_Workflows.md` + `CLI_Implementation_Contract.md` |
| Standalone Mac app, Dock presence, menu-bar role, background coordinator, resident lifecycle | `Mac_Standalone_App_And_Background_Coordinator.md` |
| Built MVP behavior, worker drivers, team-run/design-board substrate | `docs/mvp/README.md` |
| Work-order vocabulary, model/skill/worker/team model | `Work_Order_Team_Model.md` |
| Images in thread messages (worker replies, user paste, Design fan-out tiles) | `Message_Image_Rendering.md` + `Composer_Image_Attachments.md` + `threads/08_Worker_Image_Output_In_Chat.md` |
| Persistent chat, routable turns, thread backend, run-to-thread linkage, compose routing send | `Persistent_Work_Threads.md` -> child docs (01 MLP core; 06 unread; 08 worker image output in chat) |
| ThreadStore write gate, serialized thread mutation, schema/migration safety, timestamp/transcript law | **BUILT** — `docs/archive/phases/05_ThreadStore_Hardening.md` |
| Read/unread thread state, new-message indication light, read cursor semantics | `Persistent_Work_Threads.md` -> `threads/06_Unread_Message_Light.md` |
| Thread rail rename/pin/archive, archive view, Home/Threads triage convergence | **BUILT** — `docs/archive/phases/07_Threads_2_0.md` |
| Mac local notifications | `threads/02_Notifications.md` |
| iOS remote unread / mobile push | `ios/03_iOS_Thread_Read_State_And_Push.md` |
| Mac token streaming / live worker output | `threads/03_Mac_Streaming.md` |
| Source-labeled observed usage metadata | `threads/04_Observed_Usage.md` |
| Stalled worker turns, stuck async team runs, Project Manager nudges, refresh/cancel/keep-waiting recovery | `Stalled_Work_Watchdog.md` |
| Pending CRUD, Project-scoped deferred work, external-agent Pending triggers | `Pending_Work_And_Drain.md` + `Agent_First_MCP_And_Messaging_Workflows.md` |
| Copy lane, `/copy`, copy type packs, copy board | `copy/README.md` |
| iOS remote Project Manager | `ios/README.md` |
| Feature semantics before implementation | `docs/workflows/SSOT_Feature_Workflow.md` |
| Sprint execution and closeout | `docs/operations/Execution-Playbook.md` |
| Stack and proof commands | `docs/operations/TechStack.md` |

## Retired Content

The old numbered roadmap docs that previously lived here were removed. Do not
infer active product truth from missing `XX_*.md` phase links or archived
worktree-era plans. New forward phases are added explicitly to this folder.

Thread child-doc numbering (2026-06-17): unread moved from slot **05** to
`threads/06_Unread_Message_Light.md` after ThreadStore hardening was inserted
and completed. The completed hardening packet is archived at
`docs/archive/phases/05_ThreadStore_Hardening.md`; rail controls are archived at
`docs/archive/phases/07_Threads_2_0.md`. Route live thread work through
`Persistent_Work_Threads.md`.
