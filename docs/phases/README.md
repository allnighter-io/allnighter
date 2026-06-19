# Allnighter - Phases

Status: Active post-MVP planning and execution
Updated: 2026-06-18

## Purpose

The MVP team-run substrate has been built. Going forward,
`docs/phases/` is the active home for post-MVP product slices, mentor-review
notes, and implementation phase docs.

> **Launch authority hotfix is built and archived:** ordinary app launch is
> process-quiet before setup/recheck/run. Historical policy/proof:
> [`docs/archive/phases/Launch_Authority_TCC_Hotfix.md`](../archive/phases/Launch_Authority_TCC_Hotfix.md).
>
> **▶ [`setup/`](setup/README.md) — First-Run Setup ("assemble your team").**
> Phase 0 (packaging) and Phase 1 (detection engine: `CLIDetector` +
> `ShellResolver` + `SetupStore`, reachable headless via `alln detect`) are
> **built**; Phase 2 health == runs, Phase 3 lean setup surfaces, and Phase 4
> auto-team are also built. Remaining setup work is live founder smoke on a real
> machine plus repair polish found in use. See `setup/README.md` for live status.

`docs/mvp/` remains the source of truth for what has already shipped and for the
foundation it created: workers, drivers, fan-out, synthesis, design boards, and
the Mac app substrate. New forward work starts here unless a routed doc says
otherwise.

## Current Phase Board

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Language_Cutover.md`](Language_Cutover.md) | **DONE** (CUT-S00–S06, 2026-06-18; check.sh green) | Hard, no-alias rename to the locked vocabulary (Chat / Delegate "Send to team" / Execute; Team; Code/Design/Copy + Signal; effort = model reasoning level). Landed: craft Build→Code, Fan out→Send to team, effort→worker-count gating ripped out, Fanout_Team_Catalog→Team_Catalog. Stays as the canonical word list/SSOT. |
| [`Team_Delegation_Surface.md`](Team_Delegation_Surface.md) | Draft product/implementation spec | Send to team as the discoverable delegation surface: Team Card projection, Signal/Code/Design/Copy families, Project Manager recommendations, direct team send, and Execute approval for mutating work. |
| [`Team_Run_Floor.md`](Team_Run_Floor.md) | Draft backend/product spec | The inspectable Floor for every team run: worker lanes, durable per-worker artifacts, typed Return/Insight, receipts, timeline, richer next actions, and Execute requirements. |
| [`GUI_Visual_Proof_Gate.md`](GUI_Visual_Proof_Gate.md) | **ACTIVE BUILT GATE** (S00–S05 built, policy still live) | Stops blind GUI "fixed" claims: render the surface, a separate layout-watcher looks at the pixels (layout-only; CLI owns content truth), and a content-bound proof packet is wall-enforced by `scripts/check_gui_proof.sh`. Keep active until this policy is promoted to an operations/GUI SSOT. |
| [`Project_Spine_And_Project_Manager.md`](Project_Spine_And_Project_Manager.md) | **CODE RED spec** - must land before Project Manager queue/autopropose | Projects are the durable repo/folder floor above threads, runs, pending, proposals, work orders, returns, worker readiness, and verification. Regular chat inside a Project is chat with that Project's Manager. Backend/CLI/MCP slices PRJ-S00-S13 first; GUI Projects rail and dogfood proof PRJ-S14/S15 after Core/CLI. |
| [`Composer_Image_Attachments.md`](Composer_Image_Attachments.md) | **Backend BUILT** (CIA-S00–S07, 2026-06-17); GUI S03/S04/S08/S09 remain | Image attachments: coordinator send transaction, canonical store, CLI/MCP send, fan-out mapping. GUI paste, timeline chips, proof seal, and DnD deferred. |
| [`Composer_File_References.md`](Composer_File_References.md) | Draft Mac v1 feature packet | `@` file references in the composer: warmed Project path catalog, recency-ranked fuzzy picker, durable file chips, send-time content/hash audit, CLI/MCP `--ref`, and delayed dispatch revalidation. |
| [`Persistent_Work_Threads.md`](Persistent_Work_Threads.md) | Parent/router (2026-06-17); core MLP + CR4 conversation send paths delivered | Work-thread lane router: shipped thread/chat/CR4 send paths, then store hardening, unread lights, rail controls, notifications, streaming, and observed usage via child docs. |
| [`threads/06_Unread_Message_Light.md`](threads/06_Unread_Message_Light.md) | **UNR-S01–S06 + S07 BUILT** (2026-06-17); S08 remains | Durable read cursor, Core unread derivation, `ThreadStore.markRead*`, presenter triage buckets, Mac rail light, viewport clear, notification suppression hooks, `home-rail-unr` GUI matrix. Rich-turn clear defers to S08; iOS protocol in `ios/03`. |
| [`threads/02_Notifications.md`](threads/02_Notifications.md) | **BUILT** (NOTIF-S01–S05 + UNR-S06, 2026-06-17) | Mac local notifications for landed work and attention states; menu-bar live/needs-attention indicator; per-thread mute; debounce/quiet-hours policy. Mobile push parked in `ios/03`. |
| [`threads/08_Worker_Image_Output_In_Chat.md`](threads/08_Worker_Image_Output_In_Chat.md) | **Backend BUILT** (WIO-S00–S03, S05, 2026-06-17); WIO-S04 GUI deferred | Worker image output in chat (design continuity): chat to imageGen workers captures + commits canonical attachments (same store as user paste); prior/picked images flow into next context; WIO-S04 Mac timeline thumbnails remain. |
| [`Stalled_Work_Watchdog.md`](Stalled_Work_Watchdog.md) | WTK-S00/S01a BUILT (2026-06-19); **not end-to-end handoff ready** until WTK-S01b–S02 + live A1 Pending-over-MCP handlers land | Separates expected capacity sleep from unexpected stall. Built: `CapacityObservation`, CLI-to-CLI classifier fixtures, Pending JSON capacity projection, MCP Pending specs. Next slice is WTK-S01b worker-output capture before reduction. Real Wake Tickets still need a real Pending execution/settlement seam and live MCP Pending parity before resident wake/watchdog handoff. |
| [`Pending_Work_And_Drain.md`](Pending_Work_And_Drain.md) | **Pending0 + Pending1 BUILT** (2026-06-17); WTK-S00/S01a capacity contract built; broad native drain/scheduling parked | Public `alln pending` CRUD + local Pending model/persistence are built, but code reality: `pending run` currently records a queued attempt only and does not execute worker/team work. Pending-over-MCP handlers must expose the same Pending/Wake facts before watchdog work is ship-ready for external agents; Away Mode, fairness drain, PTY probes, and admission ledgers remain parked. |
| [`CLI_Product_Spine.md`](CLI_Product_Spine.md) | **CLI M1 BUILT** (2026-06-15) | `alln` is the first-class agent-ready contract; RB6 grammar retired. Still owns the forward spine + naming/agent-first laws. |
| [`CLI_Implementation_Contract.md`](CLI_Implementation_Contract.md) | **CLI M1 BUILT** (2026-06-15), full wall green; **Pending0/1 BUILT** (2026-06-17) | M1 shipped: `TeamRunJSON`/`DoctorResult`/`ErrorEnvelope`, Core registry + generated artifacts + drift gate, `team --json` + **live `--stream`**, `doctor --json/--full`, `docs`/`show`/`export`/`history`/`doctor explain`, MCP `serve --stdio` (registry-derived). `alln pending` add/list/show/submit/edit/reorder/cancel/run + `PendingItemJSON` fixture/schema. Still owns: MCP advertising/async tools; `pending stop`; native Pending drain is parked. |
| [`Team_Catalog.md`](Team_Catalog.md) | Backend BUILT (S00-S05); GUI/iOS deferred | Built-in Code/Design/Copy specialist team catalog substrate for Send to team: team picker, named team variants, and one-CLI multi-skill self-fusion. Custom catalog editing is owned by `Team_And_Skill_Catalogs.md`. |
| [`Team_And_Skill_Catalogs.md`](Team_And_Skill_Catalogs.md) | Founder review packet (2026-06-17) | Cleanup-first lane catalog feature: `TeamCatalog` + `SkillCatalog`, `TeamID` + `SkillID`, built-in and custom teams/skills in one catalog model, lane-first Settings, no Store vocabulary, no migration, no skill versioning. |
| [`Model_Catalog_And_Bench_Roster.md`](Model_Catalog_And_Bench_Roster.md) | Ready CLI-first backend spec (2026-06-18) | Core `ModelCatalog` as the owner for built-in/custom per-CLI models, persistent Bench enablement, manual add/update/delete, CLI model commands, ToolRuntime/probe-label hardening, and the live-discovery seam. Model management stays inside CLIs; Bench is derived. |
| [`Team_Configuration_UX_Rescue.md`](Team_Configuration_UX_Rescue.md) | **Contract-hardened implementation spec** (2026-06-17) | Mac team configuration rescue after first-use rejection: composer Customize wiring, primary Customize team drawer, level-2 Customize worker modal, built-ins as lazy custom drafts, TeamWorkerDraft prompt edits, save-time skill forking with rollback, visible default-team control, search-first skill picker, ready-first model picker, and proof slices. |
| [`Agent_First_MCP_And_Messaging_Workflows.md`](Agent_First_MCP_And_Messaging_Workflows.md) | PARTIAL: bootstrap/preflight/discovery, spec retrieval, and A0 async team loop built; Pending deferred | Agent-first workflow layer for OpenClaw/Hermes-style messaging and voice agents: bootstrap/doctor recovery loop, MCP async team tools, Pending over MCP, full spec retrieval, provenance, approval handoffs, and entitlement hooks. |
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
2. **Project spine Core** — `Project_Spine_And_Project_Manager.md` slices
   **PRJ-S00–S06** (CODE RED): Project models, ProjectStore, context packet, thread
   + Pending binding repair/forward schema, Project worker readiness, and Project-scoped
   send/execute. This is the durable floor under runs, Pending, proposals, and work
   orders; it is pure Core with no MCP dependency, so it goes first after the
   cutover. Nothing else is safe without it.
3. **MCP contract discipline (gate before any new CLI/MCP surface)** —
   `Agent_First_MCP_And_Messaging_Workflows.md` § MCP Solidity Plan **M-A** (schemas
   for every tool), **M-C** (exit codes + error catalog), **M-B** (CLI<->MCP parity
   proof). Establish this standard before building new agent surfaces so they are
   built to it, not retrofitted. The Project doc already depends on the shared error
   envelope + exit codes, so this lands alongside / just before step 4.
4. **Project CLI + Manager + dispatch/verify** — `Project_Spine_...` **PRJ-S07–S13**
   (CLI Project foundation, Manager chat, proposal engine, approval/work-order,
   handoff/dispatch, verification, MCP Project tools). Built on steps 2–3 so
   `project_*` commands and tools meet the hardened contract discipline.
5. **Composer File References** — `Composer_File_References.md` **FR-S00–S07**
   (Core resolver/catalog, CLI/MCP `--ref`, send-time audit, prompt renderer, Mac
   `@` palette, chips, reveal, and delayed-dispatch revalidation). This is the
   missing context-delivery feature for Project Manager chat and Send to team:
   agents should receive the exact Project file contents the user selected.
6. **Send-to-team surface + gating** — `Team_Delegation_Surface.md` for the
   discoverable product surface, plus `Agent_First_MCP_...` **M-D** (team
   discovery/run tools), **M-E** (sync-ask resolution), **M-F** (provenance /
   client approval / entitlement gate).
7. **Wake Tickets + Stalled Work Watchdog** — `Stalled_Work_Watchdog.md`
   WTK-S00/S01a are built. Next is WTK-S01b worker-output capture before
   `errorReason` reduction, then WTK-S01c/Pending writer as the safe call site
   appears, then WTK-S02 real Pending execution/settlement + MCP `pending_run`
   parity, then WTK-S03–S04 resident wake and suppression, then SWW-S00–S03
   stalled-work contract/detector/read-only CLI/MCP projection. Do not hand off
   the whole watchdog until WTK-S01b–S02 and live A1 Pending-over-MCP handlers
   exist in code; otherwise expected cooldown sleep cannot be separated from true
   stalls and external agents cannot operate the surface.
8. **MCP proof wall** — `Agent_First_MCP_...` **M-G**, wired into CI once the tools
   above exist (the MCP analogue of the GUI Visual Proof Gate).
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
| GUI visual bugs, SwiftUI "fixed" claims, screenshot/proof gates | `GUI_Visual_Proof_Gate.md` + `docs/gui/GUI_Workflow.md` |
| Send to team, Delegate surface, Team Cards, Signal/Code/Design/Copy team map | `Team_Delegation_Surface.md` + `docs/gui/surfaces/send-to-team/brief.md` |
| Team run Floor, inspectable worker lanes, worker artifacts, Signal Insights, run receipts | `Team_Run_Floor.md` + `CLI_Implementation_Contract.md` |
| Projects, local repo/folder roots, Project Manager chat, project-scoped threads/runs/pending/dispatch | `Project_Spine_And_Project_Manager.md` |
| Next-item proposals, execution queue, approval gates, worker handoffs, proof verification | `Project_Spine_And_Project_Manager.md` + `docs/operations/Execution-Playbook.md` |
| Public vocabulary, model/skill/worker/team language | `Work_Order_Team_Model.md` (historical cleanup: `docs/archive/phases/Team_First_Vocabulary_Cleanup.md`) |
| CLI-first product spine, `alln`, product grammar, agent-first posture | `CLI_Product_Spine.md` |
| CLI implementation detail, generated docs/doctor/errors/events, proof gates | `CLI_Implementation_Contract.md` |
| Team-run JSON/schema, MCP rename, RB6 CLI cutover | `CLI_Product_Spine.md` + `CLI_Implementation_Contract.md` |
| Send to team composer, built-in lane team packs, team resolver substrate | `Team_Catalog.md` + `Work_Order_Team_Model.md` |
| Model catalog, Bench enable/disable, per-CLI model lists, custom model add/update/delete, model discovery seam | `Model_Catalog_And_Bench_Roster.md` + `Work_Order_Team_Model.md` |
| Team configuration UX rescue, first-use team management feedback, Customize worker modal, save-time skill forking, default-team UI, searchable skill picker | `Team_Configuration_UX_Rescue.md` + `Team_And_Skill_Catalogs.md` + `docs/gui/GUI_Workflow.md` |
| Team/skill catalogs, custom team + skill editing, `alln teams`, `alln skills`, lane-first Settings | `Team_And_Skill_Catalogs.md` + `Work_Order_Team_Model.md` |
| Team lineup edit, customize/new/duplicate team, worker rows referencing SkillID | `Team_And_Skill_Catalogs.md` first, then `CLI_Implementation_Contract.md` + `Team_Catalog.md` |
| Composer `@` file references, Project file search, file chips, prompt file-read blocks | `Composer_File_References.md` + `Project_Spine_And_Project_Manager.md` + `CLI_Implementation_Contract.md` |
| OpenClaw/Hermes, messaging agents, voice-to-text workflows, doctor recovery, Pending over MCP, full spec retrieval | `Agent_First_MCP_And_Messaging_Workflows.md` + `CLI_Product_Spine.md` + `CLI_Implementation_Contract.md` + `Pending_Work_And_Drain.md` |
| Standalone Mac app, Dock presence, menu-bar role, background coordinator, resident lifecycle | `Mac_Standalone_App_And_Background_Coordinator.md` |
| Built MVP behavior, worker drivers, team-run/design-board substrate | `docs/mvp/README.md` |
| Work-order vocabulary, model/skill/worker/team model | `Work_Order_Team_Model.md` |
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
