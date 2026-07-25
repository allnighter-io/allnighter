# Allnighter — Phases

Status: Active post-MVP planning and execution
Updated: 2026-07-25

## Purpose

`docs/phases/` is the home for **live** post-MVP product slices and law SSOTs.
Finished phase docs move to [`docs/archive/phases/`](../archive/phases/README.md)
after their durable truth is promoted to code — **the code is the source of
truth, not the doc header.** A hard cleanup pass on 2026-07-18 archived ~40
delivered docs (verified against code); see the archive index for where each
one's truth now lives.

`docs/mvp/` remains the record of what shipped in the MVP substrate.

> **Trust rule:** a phase doc's own "SHIPPED/BUILT/DONE" banner is not evidence.
> Several archived docs had stale headers (`Worker_Session_Continuity` said "CODE
> RED" while SOLVED; `03_Mac_Streaming` said "Ready for implementation" while
> fully built). Verify in code before trusting any status line below.

## Current Phase Board

### Active priorities

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Seating_Tier_And_CLI_Diversity.md`](Seating_Tier_And_CLI_Diversity.md) | **Draft — REVIEW ONLY** (not authorized) | Haiku@100 + dead family-diversity: simplify to tier + prefer other CLI. Read before any fix; do not ship while panels are live. |
| [`CLI_Implementation_Contract.md`](CLI_Implementation_Contract.md) | **Forward work open** | SWW-S04/S05 attention commands, `pending stop`, safe followUp/returnReview Pending execution. |
| [`Signal_Scout_Triangulation_And_Graph.md`](Signal_Scout_Triangulation_And_Graph.md) | **⚠ FOUNDER DECISION** | Build the Scout → Triangulation → Graph backend, or archive the deep-build spec and keep only the shipped foundations. |

> Recently completed and archived — code is the SSOT, do not reopen:
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

### CLI spine & law SSOTs (living reference — keep, do not archive)

| Doc | Status | Purpose |
| --- | --- | --- |
| [`CLI_Product_Spine.md`](CLI_Product_Spine.md) | **Living spine SSOT** (M1 built) | `alln` as the first-class agent contract; owns forward naming/agent-first laws. Run-journal foundation work (`RunStore.swift`) currently in flight. |
| [`CLI_Implementation_Contract.md`](CLI_Implementation_Contract.md) | **Living implementation SSOT** (M1 built) | Generated docs/doctor/errors/events + proof gates. Forward CLI work: SWW-S04/S05 attention commands, `pending stop`, safe followUp/returnReview Pending execution. |
| [`Work_Order_Team_Model.md`](Work_Order_Team_Model.md) | **Living vocabulary contract** | Source/bench/model/skill/worker/team/lane/type/effort/preset word list for new phase docs and GUI briefs. Run-model vocabulary is code SSOT `RunService.swift` (archived `Unified_Run_Model.md` has the closed design record). |
| [`Language_Cutover.md`](Language_Cutover.md) | **DONE** (CUT-S00–S06) — kept as canonical word list | The locked vocabulary is codebase reality. Retained as the word-list SSOT other docs cite. |
| [`Team_Depth_Naming.md`](Team_Depth_Naming.md) | **DECIDED — convention SSOT** (partially applied) | Family = the job; depth = universal Min / (bare) / Max; bare = default send, never Min; no numbers. Stays until `Team_Catalog_Normalization` lands catalog-wide. |
| [`Spec_Review.md`](Spec_Review.md) | **Living hero-loop SSOT** (team built) | The multi-model spec-hardening hero loop: positioning, review-lens rubric, impact ledger. Backend team exists; this doc governs positioning/rubric. |
| [`GUI_Visual_Proof_Gate.md`](GUI_Visual_Proof_Gate.md) | **ENFORCED STANDING POLICY** (S00–S05 built) | Stops blind GUI "fixed" claims: render → separate layout-watcher looks at pixels → content-bound proof packet wall-enforced by `scripts/check_gui_proof.sh`. |

### Team catalog & delegation (forward)

Team Lab is **SHUT DOWN** (founder ruling 2026-07-24 — we have all the teams we
want/need for now). Its three specs are archived un-rebased (their scripts still
reference the dead `code_bug_hunt_lite` team); see
[`docs/archive/phases/README.md`](../archive/phases/README.md). Do not resume
without a new founder ruling.

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Team_Delegation_Surface.md`](Team_Delegation_Surface.md) | **Draft — needs re-base** against `Unified_Run_Model.md` (its Execute-approval mutating gate is retired ceremony); Core routing built, GUI browse surface unbuilt | Send-to-team as the discoverable delegation surface: Team Card projection, family map, direct team send. |
| [`Live_Team_Board.md`](Live_Team_Board.md) | **Draft feature packet** — no-theater contract | In-thread live board for running answer-team runs: sourced per-worker states + real deltas only when emitted. Forbids fake activity/progress. |

### Forward feature packets

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Share_To_Research.md`](Share_To_Research.md) | **Draft feature packet — not started**; pre-launch, not urgent | Share an X post / video / article from the iOS share sheet, confirm once, and the Mac's Research team returns a project-aware read. Mostly wiring: typed `startRun`, the cloud relay drain loop, the Research team, and `SignalSourceRouter` all exist — new work is the iOS Share Extension + confirm sheet. The iOS app's first defensible feature (needs the user's own multi-CLI bench; no vendor can copy it). |
| [`Composer_File_References.md`](Composer_File_References.md) | **Backend built** (FR-S00–S03 + picker); FR-S04 `@`-palette + FR-S05/06/07 forward | `@` file references. Remaining: Mac `@` palette (ranking/highlight/paste/DnD/persistence), pending/work-order revalidation, context reveal, GUI proof seal. |
| [`Persistent_Work_Threads.md`](Persistent_Work_Threads.md) | **Parent/router** — MLP core delivered | Work-thread lane router; index for still-open children below. |
| [`threads/04_Observed_Usage.md`](threads/04_Observed_Usage.md) | **Unbuilt** (USG-S01–S07) | Source-labeled observed usage: `ObservedUsage` model, driver parsers, attach-to-chat, scorecard, UI display. Engine token capture exists; the model/UI do not. |
| [`threads/09_Thread_Forking.md`](threads/09_Thread_Forking.md) | **Draft — unbuilt** (needs CLI-only reframe) | Fork a thread from a terminal turn prefix into a new child thread. No code yet. |
| [`Keyboard_Shortcuts.md`](Keyboard_Shortcuts.md) | **KBD-S00/S01 done**; S02–S06 forward | Tier-2 list nav (j/k), ⌘P quick-switcher, output/manage keys, PM/pending keys, settings override page. |
| [`Folder_Native_Memory.md`](Folder_Native_Memory.md) | **Pointer only shipped** — consolidation engine unbuilt | Only the memory pointer line ships (referenced by relay/pilot scaffolds); the consolidation round, seat-line loop, and second-run works-test are unbuilt. |
| [`Signal_Scout_Triangulation_And_Graph.md`](Signal_Scout_Triangulation_And_Graph.md) | **Draft — ⚠ FOUNDER DECISION** | Signal foundations exist (`SignalInsight.swift` struct + parser only); the whole Scout → Triangulation → Graph backend is unbuilt. Decide: build it out, or archive the deep-build spec and keep only the shipped foundations. |
| [`Chat_Module_Extraction.md`](Chat_Module_Extraction.md) | **Plan — not started** | Consolidate Allnighter's two chat substrates and extract into the shared AgentOS `AgentOSChatCore`/`AgentOSChatUI` packages. |
| [`Contradiction_Pass.md`](Contradiction_Pass.md) | **Draft — NOT AUTHORIZED**; queued behind Code Red + Menu Relations | Give Max a structural difference instead of more bodies: mechanical contradiction/co-attribution detection from anchored findings (all tiers, zero model cost), false/factual/judgment classification, and one bounded Max-only resolution seat. Default escalates via `escalationRecommended`, never silently spends. Extends `Spec_Review.md`. |

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

- Founder input is intent. Durable semantics go through a phase doc or routed
  SSOT before implementation.
- New phase docs must name one trusted workflow slice, one truth owner, and one
  Works Test or proof waiver. Use the template in **Adding a Phase Doc** below.
- Product truth belongs in `AllnighterCore`, protocol docs, or the owning phase
  doc. SwiftUI may render truth; it must not invent it.
- Generated output is derived. Change the source contract, then regenerate.
- Finished phase docs are archived only after their durable truth has been
  promoted to the owning source. **Archive aggressively** — a shipped feature's
  spec is clutter once the code owns the truth.

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
- Healthy model substitution is same-shelf only (user-governed Flagship /
  Balanced / Fast tiers); it may cross CLIs inside a shelf, never silently
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
| GUI visual bugs, SwiftUI "fixed" claims, screenshot/proof gates | `GUI_Visual_Proof_Gate.md` + `docs/gui/GUI_Workflow.md` |
| Agent front door — findable/suggested/selection, catalog normalization | Front door V1 Complete — archived `Agent_Front_Door.md` (gate 1) → archived `Agent_Onboarding.md` (gate 2) → archived `Menu_Not_Router.md` (selection; gate 3 router tombstone: `Agent_Intent_Router.md`); catalog: archived `Team_Catalog_Normalization.md` |
| Stale MCP/help language, empty help search, invented flags, dead `pair slice` in living docs, version freshness | archived `CLI_Agent_Surface_Fidelity.md` (Complete; code SSOT `RetiredVocabulary` + HelpTopicRegistry) |
| CLI-first product spine, `alln`, product grammar, agent-first posture | `CLI_Product_Spine.md` + `CLI_Implementation_Contract.md` |
| Team authoring shape (`teams duplicate`/`new`/`edit` JSON), model-catalog quick fixes | archived [`Model_Catalog_Quick_Fixes.md`](../archive/phases/Model_Catalog_Quick_Fixes.md) — MCV-S03 shipped (code SSOT: `AllnighterCLI` authoring printers + `ContractRegistry` `teamPreset`/`teamShowJSON`); remaining ledger items unauthorized |
| Run model, answer vs execution teams, dispatch/source safety | Code SSOT: `RunService.swift`, `RunWriteLockRegistry` + `Work_Order_Team_Model.md` |
| Public vocabulary, model/skill/worker/team language | `Work_Order_Team_Model.md` + `Language_Cutover.md` |
| Send to team, delegation surface, Team Cards | `Team_Delegation_Surface.md` + `docs/gui/surfaces/send-to-team/brief.md` |
| Live in-thread team run progress, honest streaming excerpts | `Live_Team_Board.md` |
| Team naming, depth tiers (Min/Default/Max), family names | `Team_Depth_Naming.md` (applied by `Team_Catalog_Normalization.md`) |
| Team lab — benchmarking, seat economics, roster ablation, calibration | Team Lab is SHUT DOWN (founder, 2026-07-24) — do not resume; archived `Team_Lab_Run_Factory.md` + `Team_Lab_Composition_And_Seat_Economics.md` + `Team_Lab_Slice_1_Full_Package.md` (un-rebased) |
| Spec Review hero loop, review lenses, positioning | `Spec_Review.md` |
| Team seating, Haiku/custom rank inheritance, CLI/family diversity that never fires | `Seating_Tier_And_CLI_Diversity.md` (Draft — review only; not authorized) |
| Menu byte budget, cold-agent selection and composition | Code SSOT: `MenuCatalog.swift`, `MenuSelectionCopy.swift`; gate `scripts/verify_menu_contract.py`; matrix `scripts/agent_eval.sh --suite menu-not-router`. The relations phase was killed by its own measurement — do not reopen. |
| Panel disagreement, contradiction detection, what Max does beyond more seats, anchored findings | `Contradiction_Pass.md` (extends `Spec_Review.md`) |
| Share a link from the phone into a Research run, iOS share sheet intake | `Share_To_Research.md` (reuses `RemoteCommandRouter` `startRun` + `SignalSourceRouter`; no new protocol operation) |
| Composer `@` file references, file chips, prompt file-read blocks | `Composer_File_References.md` |
| Persistent chat, routable turns, thread backend | `Persistent_Work_Threads.md` → `threads/04_Observed_Usage.md`, `threads/09_Thread_Forking.md` |
| Keyboard shortcuts, quick-switcher, list nav | `Keyboard_Shortcuts.md` |
| Folder-native memory / seat-line consolidation | `Folder_Native_Memory.md` |
| Signal craft — Scout / Triangulation / Graph | `Signal_Scout_Triangulation_And_Graph.md` (⚠ founder decision) |
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
