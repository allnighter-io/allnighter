# Allnighter — Phases

Status: Active post-MVP planning and execution
Updated: 2026-07-19

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
| [`Concurrent_Invocation_Isolation.md`](../archive/phases/Concurrent_Invocation_Isolation.md) | **SHIPPED 2026-07-19, archived** — F1–F5b + two-process gates (mutation/context + same-key idempotency). Mutation receipts deferred. | Two `alln`s on different projects isolate like two `claude`s. Code SSOT: scoped reconcile/kill, stage-lease, context provenance, `IdempotencyStore.claim`. |
| [`Team_Run_Load_Performance.md`](Team_Run_Load_Performance.md) | **TOP PERF PRIORITY** — S01–S03, S04a, and RunStore progress fast path landed; S00 proof incomplete. Next: S04b off-main generation-safe reads and S06 hard timing gates. | Team-run open stall fixed; Team/execution and default-chat streaming use live overlay (no per-token reload). Remaining: MainActor store scans + unproved paint/Floor gates. |
| [`Field_Reports_3.md`](Field_Reports_3.md) | **In progress** — piloted delivery #10 | Lane-label truth, JSON stream discipline, retry idempotency from live dogfood. |
| [`Field_Reports_4.md`](Field_Reports_4.md) | **In progress** — piloted delivery #11 | Commit fidelity, proof surfacing, token truth from live dogfood. |

### Agent front door (gates 2 & 3 + the keystone)

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Team_Catalog_Normalization.md`](../archive/Team_Catalog_Normalization.md) | **SHIPPED 2026-07-19, archived** (founder-approved; CN-S01–S06 + Law 4 guards landed) | Decisive normalized family list: obvious job names, optional Min/Default/Max tiers (Spec Review, Bug Hunt, Growth, Design), Law 3 caliber+capability staffing, Law 4 unique typeTags. The catalog in `BuiltInTeams.swift` now matches this doc. |
| [`Agent_Intent_Router.md`](Agent_Intent_Router.md) | **Specced v2** (gate 3) — **UNBLOCKED**, IR-S00 done | `alln team hello --for "<intent>"` as a local solutions engineer over the normalized catalog. Today `AgentHello.swift` is a static readiness report; the `--for` matcher (IR-S01) is next. |
| [`Agent_Onboarding.md`](Agent_Onboarding.md) | **Specced v3** (gate 2) — V1 three slices unbuilt | From findable to suggested: the app teaches every CLI session about `alln` (recipe cards, CLAUDE.md/AGENTS.md seeding, app missionary surface). |

### CLI spine & law SSOTs (living reference — keep, do not archive)

| Doc | Status | Purpose |
| --- | --- | --- |
| [`CLI_Product_Spine.md`](CLI_Product_Spine.md) | **Living spine SSOT** (M1 built) | `alln` as the first-class agent contract; owns forward naming/agent-first laws. Run-journal foundation work (`RunStore.swift`) currently in flight. |
| [`CLI_Implementation_Contract.md`](CLI_Implementation_Contract.md) | **Living implementation SSOT** (M1 built) | Generated docs/doctor/errors/events + proof gates. Forward CLI work: SWW-S04/S05 attention commands, `pending stop`, safe followUp/returnReview Pending execution. |
| [`Unified_Run_Model.md`](Unified_Run_Model.md) | **Root run-model law** (Core + CLI built) | A run = message + optional preset + worker, in the repo root. Answer teams (parallel, read-only) vs execution teams (one worker, mutating, write-locked). Kept as the conceptual root; truth in `TeamRun.swift`/`TeamRunCoordinator`. |
| [`Work_Order_Team_Model.md`](Work_Order_Team_Model.md) | **Living vocabulary contract** | Source/bench/model/skill/worker/team/lane/type/effort/preset word list for new phase docs and GUI briefs. |
| [`Language_Cutover.md`](Language_Cutover.md) | **DONE** (CUT-S00–S06) — kept as canonical word list | The locked vocabulary is codebase reality. Retained as the word-list SSOT other docs cite. |
| [`Team_Depth_Naming.md`](Team_Depth_Naming.md) | **DECIDED — convention SSOT** (partially applied) | Family = the job; depth = universal Min / (bare) / Max; bare = default send, never Min; no numbers. Stays until `Team_Catalog_Normalization` lands catalog-wide. |
| [`Spec_Review.md`](Spec_Review.md) | **Living hero-loop SSOT** (team built) | The multi-model spec-hardening hero loop: positioning, review-lens rubric, impact ledger. Backend team exists; this doc governs positioning/rubric. |
| [`GUI_Visual_Proof_Gate.md`](GUI_Visual_Proof_Gate.md) | **ENFORCED STANDING POLICY** (S00–S05 built) | Stops blind GUI "fixed" claims: render → separate layout-watcher looks at pixels → content-bound proof packet wall-enforced by `scripts/check_gui_proof.sh`. |

### Team catalog, delegation & lab (forward)

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Team_Delegation_Surface.md`](Team_Delegation_Surface.md) | **Draft** — Core routing built; GUI browse surface unbuilt | Send-to-team as the discoverable delegation surface: Team Card projection, family map, direct team send, Execute approval for mutating work. |
| [`Live_Team_Board.md`](Live_Team_Board.md) | **Draft feature packet** — no-theater contract | In-thread live board for running answer-team runs: sourced per-worker states + real deltas only when emitted. Forbids fake activity/progress. |
| [`Team_Lab_Run_Factory.md`](Team_Lab_Run_Factory.md) | **Draft** — CLI-native; harness re-base next | Run factory for making default Teams excellent: benchmark suites, per-worker/writer scoring, run-contract scoring. Scripts still reference dead `code_bug_hunt_lite` — re-base is the next code slice. |
| [`Team_Lab_Composition_And_Seat_Economics.md`](Team_Lab_Composition_And_Seat_Economics.md) | **Active spec** — forward LAB-C slices | Post–Slice 1 macro loop: seat economics, VNRC, forward selection, necessity suite. |
| [`Team_Lab_Slice_1_Full_Package.md`](Team_Lab_Slice_1_Full_Package.md) | **Active spec** — dependency of the two Lab docs | PRE-S0 + LAB-S00–S05 + Judge Loop v2 for Bug Hunt calibration. (MCP wire framing is dead — MCP retired.) |

### Forward feature packets

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Composer_File_References.md`](Composer_File_References.md) | **Backend built** (FR-S00–S03 + picker); FR-S04 `@`-palette + FR-S05/06/07 forward | `@` file references. Remaining: Mac `@` palette (ranking/highlight/paste/DnD/persistence), pending/work-order revalidation, context reveal, GUI proof seal. |
| [`Persistent_Work_Threads.md`](Persistent_Work_Threads.md) | **Parent/router** — MLP core delivered | Work-thread lane router; index for still-open children below. |
| [`threads/04_Observed_Usage.md`](threads/04_Observed_Usage.md) | **Unbuilt** (USG-S01–S07) | Source-labeled observed usage: `ObservedUsage` model, driver parsers, attach-to-chat, scorecard, UI display. Engine token capture exists; the model/UI do not. |
| [`threads/09_Thread_Forking.md`](threads/09_Thread_Forking.md) | **Draft — unbuilt** (needs CLI-only reframe) | Fork a thread from a terminal turn prefix into a new child thread. No code yet. |
| [`Keyboard_Shortcuts.md`](Keyboard_Shortcuts.md) | **KBD-S00/S01 done**; S02–S06 forward | Tier-2 list nav (j/k), ⌘P quick-switcher, output/manage keys, PM/pending keys, settings override page. |
| [`Folder_Native_Memory.md`](Folder_Native_Memory.md) | **Pointer only shipped** — consolidation engine unbuilt | Only the memory pointer line ships (referenced by relay/pilot scaffolds); the consolidation round, seat-line loop, and second-run works-test are unbuilt. |
| [`Signal_Scout_Triangulation_And_Graph.md`](Signal_Scout_Triangulation_And_Graph.md) | **Draft — ⚠ FOUNDER DECISION** | Signal foundations exist (`SignalInsight.swift` struct + parser only); the whole Scout → Triangulation → Graph backend is unbuilt. Decide: build it out, or archive the deep-build spec and keep only the shipped foundations. |
| [`Chat_Module_Extraction.md`](Chat_Module_Extraction.md) | **Plan — not started** | Consolidate Allnighter's two chat substrates and extract into the shared AgentOS `AgentOSChatCore`/`AgentOSChatUI` packages. |

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
| Two `alln`s on different projects colliding, scoped reconcile/kill, per-invocation isolation | archived `Concurrent_Invocation_Isolation.md` (code SSOT; extends archived `Process_Ownership.md`) |
| Default-chat / team-run latency, streaming throughput, rail click stalls, scroll jank | `Team_Run_Load_Performance.md` (warm path shipped: archived `Warm_Single_Lane_Chat.md`) |
| GUI visual bugs, SwiftUI "fixed" claims, screenshot/proof gates | `GUI_Visual_Proof_Gate.md` + `docs/gui/GUI_Workflow.md` |
| Agent front door — findable/suggested/routed, `team hello --for`, catalog normalization | `Team_Catalog_Normalization.md` → `Agent_Intent_Router.md` → `Agent_Onboarding.md` (gate 1 shipped: archived `Agent_Front_Door.md`) |
| CLI-first product spine, `alln`, product grammar, agent-first posture | `CLI_Product_Spine.md` + `CLI_Implementation_Contract.md` |
| Run model, answer vs execution teams, dispatch/source safety | `Unified_Run_Model.md` + `Work_Order_Team_Model.md` |
| Public vocabulary, model/skill/worker/team language | `Work_Order_Team_Model.md` + `Language_Cutover.md` |
| Send to team, delegation surface, Team Cards | `Team_Delegation_Surface.md` + `docs/gui/surfaces/send-to-team/brief.md` |
| Live in-thread team run progress, honest streaming excerpts | `Live_Team_Board.md` |
| Team naming, depth tiers (Min/Default/Max), family names | `Team_Depth_Naming.md` (applied by `Team_Catalog_Normalization.md`) |
| Team lab — benchmarking, seat economics, roster ablation, calibration | `Team_Lab_Run_Factory.md` + `Team_Lab_Composition_And_Seat_Economics.md` + `Team_Lab_Slice_1_Full_Package.md` |
| Spec Review hero loop, review lenses, positioning | `Spec_Review.md` |
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
| **Anything shipped & archived** (MCP, Pilot/Relay/Panel, Process Ownership, Pending, Stalled Watchdog, Try-Fix, Warm chat, Team/Model catalogs, Composer image, thread MLP/notifications/streaming/unread, Field Reports 1–2, GLM code-review logs) | [`docs/archive/phases/README.md`](../archive/phases/README.md) — code is SSOT |

## Retired Content

Old numbered roadmap docs and worktree-era plans were removed long ago. Do not
infer active product truth from missing `XX_*.md` links. The 2026-07-18 cleanup
also removed several already-dangling references from this board
(`Project_Spine_And_Project_Manager.md`, `Team_Configuration_UX_Rescue.md`) that
no longer exist in the repo. New forward phases are added explicitly here.
