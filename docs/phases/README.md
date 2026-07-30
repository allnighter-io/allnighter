# Allnighter — Phases

Status: Active post-MVP planning and execution
Updated: 2026-07-30

## Purpose

`docs/phases/` holds **ephemeral build packets** — open product slices, spikes,
and work-in-progress specs while a feature is being built.

**SSOT is never in `docs/phases/`.** When a packet closes, archive it to
[`docs/archive/phases/`](../archive/phases/README.md). Before archive, **promote
anything that must stay live** into its durable home:

| Kind of truth | Durable home (examples) |
| --- | --- |
| Runtime / product behavior | Code (`Packages/AllnighterCore`, apps, contracts) |
| How we build / operate | `docs/operations/` (playbooks, debugger, tech stack) |
| How we intake & packet work | `docs/workflows/` |
| Visual / brand law | `docs/design-system/` |
| Standing GUI engineering | `docs/gui/` |
| Strategy (non-build) | `docs/strategy/` |

Do not leave “living law” or “product shipped” docs in `phases/` as pseudo-SSOTs.
Archived phase docs are **history**, not the owner of keepable invariants.

`docs/mvp/` remains the record of what shipped in the MVP substrate.

> **Trust rule:** a phase doc's own "SHIPPED/BUILT/DONE" banner is not evidence
> that phases owns the truth. Verify the **successor** (code and/or standing
> doc). A shipped banner means **promote + archive is overdue**.

## Current Phase Board

### Active priorities

One founder-decision packet open. Forward work otherwise is optional feature
packets below (or dogfood of shipped surfaces).
Signal Graph deep-build and CLI Implementation Contract are archived — do not
revive.

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Worker_To_Agent_Migration.md`](Worker_To_Agent_Migration.md) | **CLOSED — optional hygiene only** | Ship line complete (2026-07-29): living contracts + teaching use `agentId` + `modelId`. **Do not start** unless founder allocates time. Backlog: journal rename, lying locals, S07. SSOT: `Product_Vocabulary.md`; history: [`archive`](../archive/phases/Worker_To_Agent_Migration.md). |
| [`Completion_Delivery.md`](Completion_Delivery.md) | **OPEN — v2 (2026-07-30)** | **Agent completion notification** (CLI→CLI): honest dev-leg projection + existing waiters; CD-S01a fixture-first. Spec Review Min Ready. Not Mac banners. |
| [`Observed_Usage_On_Receipts_And_Live_Status.md`](Observed_Usage_On_Receipts_And_Live_Status.md) | **OPEN — v5 (2026-07-30)** | **Live pilot/relay status** primary (S02 hero). v5 tech-gap pass: bugs table, `devRunId` active-seat selection, human `pilot status` parity, per-answer contract (S01), receipts (S03). AgentOS OTU. |
| [`Receipt_Portability_And_Call_Sites.md`](Receipt_Portability_And_Call_Sites.md) | **⚠ FOUNDER DECISION** | Should the shipped artifact become portable and checkable off the machine that made it? RP-S00 room test is free; RP-S01 digest needs a ruling against the TRR-S02 signing cut. |
| [`Agent_Visible_Queuing.md`](Agent_Visible_Queuing.md) | **OPEN — incident-driven** | Agent status honesty: AVQ-S04 **`alln run --read-only`** (ship first — no write-lock queue for feedback), S01–S03 honest status/ps/teaching. Origin: 2026-07-30 dogfood pain (silent FIFO, lying `running`, mutating default for read-only asks). |
| [`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md) | **OPEN — incident-driven** | When any seat dies, a recovery agent finds work in 30s (commits + uncommitted + resume commands), gets notified when dev lands, and can substitute PM model. WRC-S00–S04: workRecovery envelope, `relayAwaitingPM` notify, `--pm-model` on resume, `work scan`, relay guard. Origin: 2026-07-29 PM outage mid relay. |
| [`CLI_Capacity_TUI_Sampling.md`](CLI_Capacity_TUI_Sampling.md) | **OPEN — intake FINAL, ready for slice scoping** | Cross-CLI headroom in one glance (founder checks 6 CLIs 5×/day by hand). **Acquisition ladder** — on-disk log > stream > TUI probe > failure; Codex verified tier 1 (`rate_limits` already in `~/.codex` rollouts, 6 weeks backfillable), Claude verified tier-3-only. Ships `alln capacity [--refresh\|--history\|--json]` + launch strip + utilization tab + waste ledger + weekly-rollover notification + read-only harvest posture. Amends parked utilization “no quota %” for **vendor-printed** windows only; **projection killed** (anchored decrement + retrospective facts instead). Free tier by design. Start at CAP-S00 spike. Orthogonal to receipt token usage; Cost Advisor stays parked. |
| [`CLI_Park.md`](CLI_Park.md) | **Implementing** | Park a CLI (ignore, not delete): skip probe, gray UI, out of Ready/pickers; `alln drivers park|unpark`; parked last for future capacity/status. Code SSOT `SetupStore.parkedDriverIds`. |

> Recently completed and archived — do not reopen the phase packet; read the
> **successor** (code and/or standing docs named in the archive index):
> [`Round_Survives_The_Caller.md`](../archive/phases/Round_Survives_The_Caller.md)
> + [`Round_Survives_The_Caller_Hot_Fixes.md`](../archive/phases/Round_Survives_The_Caller_Hot_Fixes.md)
> (Complete 2026-07-28 — S01–S05 + HF redesign: ack-after-accept, no hidden
> relay verbs, public `--run-id` removed, contract 5.0.0 / binary 0.10.6; code
> SSOT `DetachedHandoff`, `DetachedDispatch`, `RelayCoordinator.claimStart`);
> [`Model_Catalog_Simplification.md`](../archive/phases/Model_Catalog_Simplification.md)
> (Complete 2026-07-28 — MCAT-S01a–S07: AgentOS `catalog.json` + Allnighter
> `catalog_overlay.json` cutover, legacy driver JSON removed, `alln catalog
> validate`; S06 live-label smoke opt-in manual; code SSOT `CatalogLoader`,
> `ModelCatalog`, `CatalogOverlayLoader`, `ModelCatalogValidator`);
> [`Ephemeral_Teams.md`](../archive/phases/Ephemeral_Teams.md)
> (Complete 2026-07-28 — RSO-S01/S02: runtime `--seat` on `alln run` for
> one-off judgment-team crew staffing; contract 5.0.0→5.1.0; code SSOT
> `TeamExplicitSeats`, `RunInvocationResolver`, `TeamRun.explicitSeatModelIds`,
> `SandboxHandoffSpool.Request`);
> [`Pilot_Status_Liveness_Lie_Hotfix.md`](../archive/phases/Pilot_Status_Liveness_Lie_Hotfix.md)
> (Complete 2026-07-28 — PLS-S01/S02: `pilot status` stream-primary liveness +
> `streamSilenceWarning`, early `devRunId` stamp; PLS-S03 deferred; code SSOT
> `PilotCLI.resolveLastProgressAt`, `RelayCoordinator` early `persistDeliveredDevRun`);
> [`Core_Loop_Improvements.md`](../archive/phases/Core_Loop_Improvements.md)
> (Complete 2026-07-28 — CLP-S01 stream liveness on `ps`/status, S02 reconcile-on-read,
> S03 default `ps` floor + `--all`, S05 golden-path teaching, S08 stream-stall URN;
> code SSOT `StreamLiveness`, `ProcessOwnershipSurface`, `NotificationScheduler`);
> [`Unattended_Round_Notification.md`](../archive/phases/Unattended_Round_Notification.md)
> (Code Complete 2026-07-27 — URN-S01/S02/S03 shipped: `alln serve` posts local
> notifications for relay/pilot/team-run state and auto-launches itself, silent
> default-on, so CLI-only work notifies the founder without the Mac app open;
> full automated proof green, deslop+audit CLEAN; **on-host banner confirmation
> still needed** on the founder's own Mac before calling it fully proven;
> URN-S04–S06 deferred, don't resume without fresh scoping; code SSOT
> `NotificationScheduler.swift`, `ServeAutoLaunch.swift`,
> `NotificationCandidateDetection.swift`, `PilotCLI.swift`, `RelayCLI.swift`);
> [`Cross_Model_Review_Hardening.md`](../archive/phases/Cross_Model_Review_Hardening.md)
> (CLOSED 2026-07-27 — partial ship: CMR-S03 staffing invariant + CMR-S05
> writer/reviewer pairing line shipped; CMR-S01/S02/S04 deferred pending real
> pairing telemetry, re-scope as a fresh packet, don't resume this one; code
> SSOT `BuiltInTeamsTests.testLeadCaliberDominatesWorkers`,
> `ArtifactProjector.Card.writerReviewerLine`);
> [`Unattended_Worker_Auth_Prompt_Stall.md`](../archive/phases/Unattended_Worker_Auth_Prompt_Stall.md)
> (Complete 2026-07-27 — non-interactive spawn env + stall diagnosis; does **not**
> claim Security.framework prompt-proof; code SSOT `AllnighterSpawnEnvironmentPolicy` /
> `ProcessOwnership` stall diagnosis);
> Hygiene promote 2026-07-26 — standing homes (not phases):
> [`Product_Vocabulary.md`](../workflows/Product_Vocabulary.md)
> (from Language_Cutover + Work_Order_Team_Model + Team_Depth_Naming),
> [`Visual_Proof_Gate.md`](../gui/Visual_Proof_Gate.md),
> [`Design_Lane.md`](../operations/Design_Lane.md),
> [`Spec_Review.md`](../operations/Spec_Review.md);
> archived packets under `docs/archive/phases/` for those names;
> [`Signal_Scout_Triangulation_And_Graph.md`](../archive/phases/Signal_Scout_Triangulation_And_Graph.md)
> (ARCHIVED 2026-07-26 — keep Research; Graph = not now),
> [`CLI_Implementation_Contract.md`](../archive/phases/CLI_Implementation_Contract.md)
> (ARCHIVED 2026-07-26 — Remaining list ruled stale; code/`ContractRegistry` SSOT;
> do not resume June Pending/SWW leftovers),
> [`Team_Run_Receipt.md`](../archive/phases/Team_Run_Receipt.md)
> (ARCHIVED 2026-07-26 — artifact product shipped; code SSOT `ArtifactProjector` /
> `ArtifactWriter` / `ArtifactCLI`; S00 growth disposition still historical),
> [`Pilot_Long_Turn_Survival.md`](../archive/phases/Pilot_Long_Turn_Survival.md)
> (Complete 2026-07-26 — S01/S03/S04/S02 + audit `5761dd59`/`abb00890`/`c06c3f3d`/`9074f9ae`/`01402ab3`;
> contract 4.0.9; durable round vs disposable waiter),
> [`Idle_Stall_False_Kill_Hotfix.md`](../archive/phases/Idle_Stall_False_Kill_Hotfix.md)
> (Complete 2026-07-25 — S01 1800 idle floors + drift guard; S04 stall demotion +
> silence telemetry; S02 pgid child/CPU progress; S03 deferred),
> [`Capacity_False_Auth_Mislabel_Hotfix.md`](../archive/phases/Capacity_False_Auth_Mislabel_Hotfix.md)
> (Complete 2026-07-25 — AgentOS `bec4f9e` stderr-only auth blockers + idle kill-reason
> priority; CAP-HF-S03 dropped; Allnighter mirror `CapacityClassifierTests`),
> [`Seating_Tier_And_CLI_Diversity.md`](../archive/phases/Seating_Tier_And_CLI_Diversity.md)
> (Complete 2026-07-25 — S1–S3 `6c3dff3d`/`dd319f72`/`70e045c4`, contract 4.0.2;
> unrated customs@40 + family/CLI diversity + dry-run `seats[]`),
> [`Model_Catalog_Quick_Fixes.md`](../archive/phases/Model_Catalog_Quick_Fixes.md)
> (Complete 2026-07-25 — MCV-S03 shipped `a26a264d` / contract 4.0.1; remaining
> ledger items unauthorized — do not resume without a new founder ruling),
> [`CODE_RED_Core_Infrastructure_Repair.md`](../archive/phases/CODE_RED_Core_Infrastructure_Repair.md)
> (CLOSED 2026-07-24, CR-S00–S07, live proof GREEN ×3; resident control plane
> deleted to zero; `Resident_Execution_Broker.md` archived with it),
> [`Alln_Sharpening.md`](../archive/phases/Alln_Sharpening.md),
> [`CLI_Agent_Surface_Fidelity.md`](../archive/phases/CLI_Agent_Surface_Fidelity.md),
> [`Concurrent_Invocation_Isolation.md`](../archive/phases/Concurrent_Invocation_Isolation.md),
> [`Run_Lifecycle_Reliability.md`](../archive/phases/Run_Lifecycle_Reliability.md),
> [`Team_Run_Load_Performance.md`](../archive/phases/Team_Run_Load_Performance.md),
> [`Unified_Run_Model.md`](../archive/phases/Unified_Run_Model.md) (root run-model
> law, CLOSED 2026-07-24 — code SSOT `RunService.swift`, `TeamPreset`/
> `TeamCatalog`, `RunWriteLockRegistry`; enforcement `config/architecture-policy.json`
> + `scripts/check_architecture_policy.sh`),
> [`CLI_Agent_Ergonomics.md`](../archive/phases/CLI_Agent_Ergonomics.md)
> (Complete, AE-S00–S15). Team Lab is **SHUT DOWN** (founder ruling
> 2026-07-24 — we have all the teams we want/need for now) and its specs
> archived un-rebased: [`Team_Lab_Run_Factory.md`](../archive/phases/Team_Lab_Run_Factory.md),
> [`Team_Lab_Composition_And_Seat_Economics.md`](../archive/phases/Team_Lab_Composition_And_Seat_Economics.md),
> [`Team_Lab_Slice_1_Full_Package.md`](../archive/phases/Team_Lab_Slice_1_Full_Package.md).

### Agent front door (V1 Complete — gates 1–3 archived)

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Team_Catalog_Normalization.md`](../archive/Team_Catalog_Normalization.md) | **SHIPPED 2026-07-19, archived** (founder-approved; CN-S01–S06 + Law 4 guards landed) | Decisive normalized family list: obvious job names, optional Min/Default/Max tiers (Spec Review, Bug Hunt, Growth, Design), Law 3 caliber+capability staffing, Law 4 unique typeTags. The catalog in `BuiltInTeams.swift` now matches this doc. |
| [`Menu_Not_Router.md`](../archive/phases/Menu_Not_Router.md) | **Complete 2026-07-20, archived** — MR-S01–S06 (`2ef2ed43` / `e1519edd` / `e724595d` / `e2ab104f` / `f0bd3e02` / `9fd50e19`) | Live `alln menu --json` owns discovery; caller chooses; no intent router. Code SSOT: `MenuCatalog`, `TeachingSnippet`, exact-id resolvers; harness `scripts/agent_eval.sh --suite menu-not-router`. |
| [`Agent_Front_Door.md`](../archive/phases/Agent_Front_Door.md) | **SHIPPED, archived** (gate 1 — findable) | `install-cli` / `bootstrap` / no empty silence. Code SSOT: `InstallCLI.swift`, `Bootstrap.swift`. |
| [`Agent_Onboarding.md`](../archive/phases/Agent_Onboarding.md) | **Complete 2026-07-20, archived** — ONB-S01–S03 (`b6083575` / `bd28ebf0` / `a732d234` / `99fb5778`); PARKED remain parked | From findable to suggested: Teach your CLIs + recipe cards + `teaching.installed` doctor. Code SSOT: `TeachingSnippet.swift`, `GlobalTeachingInstaller.swift`, `RecipeCatalog`. |
| [`Agent_Intent_Router.md`](../archive/phases/Agent_Intent_Router.md) | **TOMBSTONED** — superseded by archived `Menu_Not_Router.md` | Historical intent-router phase. Do not implement; selection truth is the live menu. |

### Open phase packets (not SSOT — archive when the open work closes)

These may still have **forward** slices. They are build packets, not durable
law. Shipped subsections already belong to code; do not cite these paths as
“the SSOT.”

| Doc | Status | Purpose |
| --- | --- | --- |
| [`CLI_Product_Spine.md`](CLI_Product_Spine.md) | Open / M1 built — **archive when no forward CLI naming work remains** | `alln` agent-first naming while still evolving. Code owns shipped contract bits. |

### Team catalog & delegation (forward)

Team Lab is **SHUT DOWN** (founder ruling 2026-07-24 — we have all the teams we
want/need for now). Its three specs are archived un-rebased (their scripts still
reference the dead `code_bug_hunt_lite` team); see
[`docs/archive/phases/README.md`](../archive/phases/README.md). Do not resume
without a new founder ruling.

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Worker_Skill_Sharing.md`](Worker_Skill_Sharing.md) | **Code Complete (WSS-S01)** — archive after Works Test | Same-ID shared Skill overrides + Restore; roster-only Team Save; CLI 5.2.0 + Mac worker editor cutover. |
| [`Team_Delegation_Surface.md`](Team_Delegation_Surface.md) | **Draft — needs re-base** against `Unified_Run_Model.md` (its Execute-approval mutating gate is retired ceremony); Core routing built, GUI browse surface unbuilt | Send-to-team as the discoverable delegation surface: Team Card projection, family map, direct team send. |
| [`Live_Team_Board.md`](Live_Team_Board.md) | **Draft feature packet** — no-theater contract | In-thread live board for running answer-team runs: sourced per-worker states + real deltas only when emitted. Forbids fake activity/progress. |

### Forward feature packets

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Buzz_Harness_Spike.md`](Buzz_Harness_Spike.md) | **SPIKE — deferred**; throwaway-permitted | After artifacts exist: does the same object feel valuable in an attended Buzz thread? Strategy: `docs/strategy/Buzz_And_The_Judgment_Layer.md`. |
| [`Share_To_Research.md`](Share_To_Research.md) | **Draft feature packet — not started**; pre-launch, not urgent | Share an X post / video / article from the iOS share sheet, confirm once, and the Mac's Research team returns a project-aware read. Mostly wiring: typed `startRun`, the cloud relay drain loop, the Research team, and `SignalSourceRouter` all exist — new work is the iOS Share Extension + confirm sheet. The iOS app's first defensible feature (needs the user's own multi-CLI bench; no vendor can copy it). |
| [`Composer_File_References.md`](Composer_File_References.md) | **Backend built** (FR-S00–S03 + picker); FR-S04 `@`-palette + FR-S05/06/07 forward | `@` file references. Remaining: Mac `@` palette (ranking/highlight/paste/DnD/persistence), pending/work-order revalidation, context reveal, GUI proof seal. |
| [`Persistent_Work_Threads.md`](Persistent_Work_Threads.md) | **Parent/router** — MLP core delivered | Work-thread lane router; index for still-open children below. |
| [`threads/04_Observed_Usage.md`](threads/04_Observed_Usage.md) | **Unbuilt** (USG-S01–S07) | Source-labeled observed usage: `ObservedUsage` model, driver parsers, attach-to-chat, scorecard, UI display. Engine token capture exists; the model/UI do not. |
| [`threads/09_Thread_Forking.md`](threads/09_Thread_Forking.md) | **Draft — unbuilt** (needs CLI-only reframe) | Fork a thread from a terminal turn prefix into a new child thread. No code yet. |
| [`Keyboard_Shortcuts.md`](Keyboard_Shortcuts.md) | **KBD-S00/S01 done**; S02–S06 forward | Tier-2 list nav (j/k), ⌘P quick-switcher, output/manage keys, PM/pending keys, settings override page. |
| [`Folder_Native_Memory.md`](Folder_Native_Memory.md) | **Pointer only shipped** — consolidation engine unbuilt | Only the memory pointer line ships (referenced by relay/pilot scaffolds); the consolidation round, seat-line loop, and second-run works-test are unbuilt. |
| [`Chat_Module_Extraction.md`](Chat_Module_Extraction.md) | **Plan — not started** | Consolidate Allnighter's two chat substrates and extract into the shared AgentOS `AgentOSChatCore`/`AgentOSChatUI` packages. |
| [`Contradiction_Pass.md`](Contradiction_Pass.md) | **Draft — NOT AUTHORIZED**; queued behind Code Red + Menu Relations | Give Max a structural difference instead of more bodies: mechanical contradiction/co-attribution detection from anchored findings (all tiers, zero model cost), false/factual/judgment classification, and one bounded Max-only resolution seat. Default escalates via `escalationRecommended`, never silently spends. Extends archived Spec Review packet. |

### Subdirectories

| Dir | Status | Purpose |
| --- | --- | --- |
| [`setup/`](setup/README.md) | Detection engine built; WOW-experience is live design source | First-Run Setup ("assemble your team"): `CLIDetector`/`ShellResolver`/`SetupStore` built (`alln detect`); remaining work is the first-run UX + per-CLI support docs (Antigravity, Grok Build, OpenCode). |
| [`copy/`](copy/README.md) | **Draft** post-MVP lane — unbuilt | Copy work orders: prompt-first `/copy`, copy type, Copy team, copy board. |
| [`ios/`](ios/README.md) | **Parked** — deferred until macOS app is done | Future remote Project Manager spine; must not block Mac delivery. |
| [`parked/`](parked/README.md) | **Parked** — intentionally out of the active board | e.g. `Utilization_Admission_Control.md` (premature scheduler machinery). |
| [`sprint/`](sprint/README.md) | Mostly `done` — mixed | One-slice implementer work orders (32K-context agents). Done topics should migrate to `archive/phases/sprint/`; the pair-queue topics are historical (slice queue deleted at R-S09). Active: `opencode/` OC-S01 chain. |
| `wiring/`, `mockups/` | Design-handoff assets/tokens | Design source material for specific composer/setup/send-to-team surfaces. |

## Operating Rules

- Founder input is intent. While building, capture it in a phase **packet**.
  Durable semantics land in **code** and/or **standing docs outside phases**
  (operations, workflows, design-system, gui, strategy) — never as a permanent
  resident of `docs/phases/`.
- New phase docs must name one trusted workflow slice, one truth owner, and one
  Works Test or proof waiver. Use the template in **Adding a Phase Doc** below.
- Closeout = **promote keepable law** into the right standing doc and/or code,
  then **archive** the phase packet. Skipping promotion dumps truth into the
  archive where agents stop reading it.
- SwiftUI may render truth; it must not invent it.
- Generated output is derived. Change the source contract, then regenerate.
- Do not leave “Product shipped” / “Living SSOT” docs in `docs/phases/`. A hard
  cleanup pass on 2026-07-18 archived ~40 delivered docs; keep that habit —
  with promotion, not archive-only amnesia.

## Post-MVP Product Laws

- Allnighter coordinates workers the user already pays for. It is not a model
  provider, IDE, chat aggregator, cloud coding service, or terminal viewer.
- Allnighter uses the user's existing CLI subscriptions/logins, **never** API
  keys / BYOK. Setup/login flows must not suggest API keys.
- Allnighter has nothing to do with git. It sends orders; the repo + CLIs own
  all git. Safety = one mutating worker + write lock + bounded order + proof
  surface + hard stops + the user's own undo.
- The agent-facing contract is CLI-only. **MCP was retired 2026-07-16** — never
  reintroduce MCP surfaces. CLI/MCP parity was total; nothing was lost.
- A Project is the durable local repo/folder floor. A work thread is the durable
  conversation unit inside a Project. Chat is the default turn; team run, design
  board, and execution are stronger turn types inside the same thread.
- Workers fail honestly. A failed worker is shown failed, never hidden or faked.
- Team selection owns work shape. Effort (Low/Med/High) is per-worker model
  reasoning level only — never a generic team-depth toggle. Depth is a bigger
  team (Min/Default/Max families), not an effort dial.
- Healthy model substitution is same-tier only (user-governed Frontier /
  Balanced / Economy tiers); it may cross CLIs inside a tier, never silently
  upgrades/downgrades or leaves the selected shelf.
- Do not estimate future cost, quota burn, runtime, or task complexity.
- Capacity state is observed, sourced, timestamped, and local by default.
- Pending separates Project-scoped user intent from immediate execution. It is
  public CLI-first (`alln pending`) before any GUI promises Draft/Pending/Running.
- Execution lane serialization is INVIOLABLE: one Running worker per branch/
  session lane. Mixed-source teams are for judgment; anything mutating resolves
  to one source/driver before any mutating spawn.
- Every built-in and custom team/skill belongs to exactly one lane. Duplicate
  and tune when a lineup or hat belongs in another lane.
- Code, Design, Copy are the peer creation lanes (+ Signal as the 4th craft). A
  new lane requires a new substrate or output class. Send-to-team never infers
  lane from prompt prose — the user chooses the lane.
- Settings navigation is lane-first: CLIs, then BUILD / DESIGN / COPY, each with
  Teams and Skills.
- Forward Mac app work targets a standalone Dock app plus explicit background
  coordinator. iOS is a future remote surface that must not block macOS delivery.

## Adding a Phase Doc

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

Live docs on the left; historical truth points into the archive or code SSOT.

| Work | Read first |
| --- | --- |
| Core execution is broken, Team research does not return real answers, execution does not change the real repo, or any “fixed again” incident | Code SSOT: `RunService.swift` (the one run owner), `TeamPreset`/`TeamCatalog`, `RunWriteLockRegistry`; enforcement — `config/architecture-policy.json` + `scripts/check_architecture_policy.sh` |
| Codex/host sandbox blocks child CLIs, source processes absent from ownership | The sandbox blocks the Keychain, not the repo. Code SSOT: `SandboxHandoffSpool.swift`, `SandboxHandoffRunner.swift`, `HostSandboxAdvice.swift` |
| `alln serve`, background scheduler scope | A scheduler only (Pending wake, Boost seed, vendor-backoff continuation, cloud relay). Owns no run semantics; `alln run` never needs it. Code SSOT: `ServeDaemon.swift` |
| Foreground/async run stuck, journal/status mismatch, opaque blocker, orphan worker, kill/retry failure, missing lifecycle stream | archived `Run_Lifecycle_Reliability.md` (Complete; extends archived Process Ownership + Concurrent Invocation Isolation) |
| Vendor usage limit / session cap, parked run, wake/resume, authorized substitute | archived `Rate_Limit_Continuity.md` (code SSOT: `VendorBackoffReconciler`, `VendorSubstitutionPolicy`) |
| Two `alln`s on different projects colliding, scoped reconcile/kill, per-invocation isolation | archived `Concurrent_Invocation_Isolation.md` (code SSOT; extends archived `Process_Ownership.md`) |
| Default-chat / team-run latency, streaming throughput, rail click stalls, scroll jank | archived `Team_Run_Load_Performance.md` (code SSOT; warm path: archived `Warm_Single_Lane_Chat.md`) |
| GUI visual bugs, SwiftUI "fixed" claims, screenshot/proof gates | `docs/gui/Visual_Proof_Gate.md` + `docs/gui/GUI_Workflow.md` |
| Agent front door — findable/suggested/selection, catalog normalization | Front door V1 Complete — archived `Agent_Front_Door.md` (gate 1) → archived `Agent_Onboarding.md` (gate 2) → archived `Menu_Not_Router.md` (selection; gate 3 router tombstone: `Agent_Intent_Router.md`); catalog: archived `Team_Catalog_Normalization.md` |
| Stale MCP/help language, empty help search, invented flags, dead `pair slice` in living docs, version freshness | archived `CLI_Agent_Surface_Fidelity.md` (Complete; code SSOT `RetiredVocabulary` + HelpTopicRegistry) |
| CLI-first product spine, `alln`, product grammar, agent-first posture | `CLI_Product_Spine.md`; shipped schemas/commands = `ContractRegistry` / code |
| Team authoring shape (`teams duplicate`/`new`/`edit` JSON), model-catalog quick fixes | archived [`Model_Catalog_Quick_Fixes.md`](../archive/phases/Model_Catalog_Quick_Fixes.md) — MCV-S03 shipped (code SSOT: `AllnighterCLI` authoring printers + `ContractRegistry` `teamPreset`/`teamShowJSON`); remaining ledger items unauthorized |
| Run model, answer vs execution teams, dispatch/source safety | Code SSOT: `RunService.swift`, `RunWriteLockRegistry` + `docs/workflows/Product_Vocabulary.md` |
| Public vocabulary, model/skill/worker/team language | `docs/workflows/Product_Vocabulary.md` |
| Send to team, delegation surface, Team Cards | `Team_Delegation_Surface.md` + `docs/gui/surfaces/send-to-team/brief.md` |
| Live in-thread team run progress, honest streaming excerpts | `Live_Team_Board.md` |
| Team naming, depth tiers (Min/Default/Max), family names | `docs/workflows/Product_Vocabulary.md` (applied by `Team_Catalog_Normalization.md`) |
| Team lab — benchmarking, seat economics, roster ablation, calibration | Team Lab is SHUT DOWN (founder, 2026-07-24) — do not resume; archived `Team_Lab_Run_Factory.md` + `Team_Lab_Composition_And_Seat_Economics.md` + `Team_Lab_Slice_1_Full_Package.md` (un-rebased) |
| Spec Review hero loop, review lenses, positioning | `docs/operations/Spec_Review.md` |
| Team seating, Haiku/custom rank inheritance, CLI/family diversity | archived [`Seating_Tier_And_CLI_Diversity.md`](../archive/phases/Seating_Tier_And_CLI_Diversity.md) — Complete 2026-07-25 (S1–S3, contract 4.0.2); code SSOT `ModelCatalog` + `TeamResolver` + `RunDryRunJSON.seats` |
| One-off crew staffing, custom-Team picker sprawl, `teams duplicate` for throwaways | archived [`Ephemeral_Teams.md`](../archive/phases/Ephemeral_Teams.md) — Complete 2026-07-28; `alln run --team <built-in> --seat <model_id>…` (Option C); code SSOT `TeamExplicitSeats`, `RunInvocationResolver`, `TeamRun.explicitSeatModelIds` |
| Menu byte budget, cold-agent selection and composition | Code SSOT: `MenuCatalog.swift`, `MenuSelectionCopy.swift`; gate `scripts/verify_menu_contract.py`; matrix `scripts/agent_eval.sh --suite menu-not-router`. The relations phase was killed by its own measurement — do not reopen. |
| Panel disagreement, contradiction detection, what Max does beyond more seats, anchored findings | `Contradiction_Pass.md` (extends `docs/operations/Spec_Review.md`) |
| Gorgeous private team run report / artifact, deliberate share (not Mac-only) | Code SSOT: `ArtifactProjector` / `ArtifactWriter` / `ArtifactCLI`; closed record: archived `Team_Run_Receipt.md` |
| Design team / design edits — code mockup → host screenshot (not Midjourney) | `docs/operations/Design_Lane.md` |
| Buzz / attended agent-chat rooms as a call site for alln (after receipts) | `Buzz_Harness_Spike.md` + `docs/strategy/Buzz_And_The_Judgment_Layer.md` (firm-member mythology retired; receipt-first) |
| Share a link from the phone into a Research run, iOS share sheet intake | `Share_To_Research.md` (reuses `RemoteCommandRouter` `startRun` + `SignalSourceRouter`; no new protocol operation) |
| Pilot/Relay long deploy or ops turn; harness killed `pilot watch`; detached handoff cwd/binary; status vs watch recovery | archived [`Pilot_Long_Turn_Survival.md`](../archive/phases/Pilot_Long_Turn_Survival.md) — code SSOT `PilotCLI.swift` / `RelayCoordinator.swift` (substrate: archived `Pilot_Relay.md` / `Pilot_DX.md`; idle floors: archived `Idle_Stall_False_Kill_Hotfix.md`) |
| `pair pilot status` fresh silenceAge while `alln ps` says no stream for Ns; hung child under worker (e.g. wrangler tail); pgid heartbeat lie | archived `docs/archive/phases/Pilot_Status_Liveness_Lie_Hotfix.md` — Complete 2026-07-28; code SSOT `PilotCLI.resolveLastProgressAt`, `PilotStatusJSON.streamSilenceWarning`, `RelayCoordinator` early `persistDeliveredDevRun` |
| Relay/pilot round lands or escalates with nobody notified (Mac app closed, caller already gone) | archived [`Unattended_Round_Notification.md`](../archive/phases/Unattended_Round_Notification.md) — Code Complete 2026-07-27, on-host banner confirmation still needed; code SSOT `NotificationScheduler.swift`, `ServeAutoLaunch.swift`, `NotificationCandidateDetection.swift`; extends archived `threads/02_Notifications.md` (Mac-app-only NOTIF-S01–S05) |
| Mac Compose Loop / Agent Team Loop; remove relay spinner; kickoff handoff; Stop+Status parity with CLI | [`Agent_Team_Loop.md`](../archive/phases/Agent_Team_Loop.md) — **ARCHIVED 2026-07-30**, S01–S04 shipped; optional ATL-S05 never started |
| `pair relay`/`relay-resume`/`relay adopt`/`alln run` die when the caller dies (no `--no-wait` equivalent); relay dispatch has no in-flight guard | **Archived** — `docs/archive/phases/Round_Survives_The_Caller.md` + Hot Fixes; code SSOT `DetachedHandoff` / `DetachedDispatch` / `RelayCoordinator` |
| Composer `@` file references, file chips, prompt file-read blocks | `Composer_File_References.md` |
| Persistent chat, routable turns, thread backend | `Persistent_Work_Threads.md` → `threads/04_Observed_Usage.md`, `threads/09_Thread_Forking.md` |
| Keyboard shortcuts, quick-switcher, list nav | `Keyboard_Shortcuts.md` |
| Folder-native memory / seat-line consolidation | `Folder_Native_Memory.md` |
| Signal / Research team | Code: `BuiltInTeams.signalPostToProject` + `SignalSourceRouter`; deep Graph packet archived |
| Chat module consolidation + AgentOS extraction | `Chat_Module_Extraction.md` |
| First-run setup, CLI detection/auth, per-CLI support | `setup/README.md` |
| Copy lane, `/copy`, copy board | `copy/README.md` |
| iOS remote Project Manager | `ios/README.md` |
| Sprint work orders (one-slice implementer prompts) | `sprint/README.md` |
| Built MVP behavior, worker drivers, team-run/design-board substrate | `docs/mvp/README.md` |
| Feature semantics before implementation | `docs/workflows/SSOT_Feature_Workflow.md` |
| Sprint execution and closeout | `docs/operations/Execution-Playbook.md` |
| Stack and proof commands | `docs/operations/TechStack.md` |
| Post-Sharpening dogfood batch — reproduce selector round-trip, dry-run read-only steer, team-name disclosure, authoring findability, single-source binary version | archived `Agent_Dogfood_Papercuts.md` (Done — code SSOT: `TeamRun.explicitWorkerIds`, `RunDryRunJSON.alternatives`, `TeamPreset.disclosedDisplayName`, `AllnighterVersionIdentity.binaryVersion`) |
| Piloted-delivery field reports #10/#11 — lane-label truth, `--json` stream law, retry idempotency, unattended vocabulary, commit fidelity, proof surfacing, token truth | archived `Field_Reports_3.md` + `Field_Reports_4.md` (Shipped 2026-07-16 — FR7–FR14 all in code with tests) |
| **Anything shipped & archived** (MCP, Pilot/Relay/Panel, Process Ownership, Pending, Stalled Watchdog, Try-Fix, Warm chat, Team/Model catalogs, Composer image, thread MLP/notifications/streaming/unread, Field Reports 1–4, Agent Dogfood Papercuts, GLM code-review logs) | [`docs/archive/phases/README.md`](../archive/phases/README.md) — code is SSOT |

## Retired Content

Old numbered roadmap docs and worktree-era plans were removed long ago. Do not
infer active product truth from missing `XX_*.md` links. The 2026-07-18 cleanup
also removed several already-dangling references from this board
(`Project_Spine_And_Project_Manager.md`, `Team_Configuration_UX_Rescue.md`) that
no longer exist in the repo. New forward phases are added explicitly here.
