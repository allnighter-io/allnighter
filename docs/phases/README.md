# Allnighter — Phases

Status: Active post-MVP planning and execution
Updated: 2026-08-08

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

> **Trust rule:** verify against **code and git commits**, not a phase doc's own
> SHIPPED/DONE banner. A shipped banner in `phases/` means **promote + archive is
> overdue**.

## Current Phase Board

### Active priorities (founder-ordered)

> **Founder-ordered top four (2026-08-08)** — work them in this order:
> **1.** Scheduler 2.0 · **2.** Seat assignments · **3.** OpenCode attach · **4.** Ollama.
> Everything below the top four is unordered backlog.

| Doc | Status | Next action |
| --- | --- | --- |
| [`Probe_Freshness.md`](Probe_Freshness.md) | **1 · Scheduler 2.0 — v2, Ready for named slices** | `alln menu` hid Grok + Kimi as `notReady` while both answered live prompts. PF-S00 expire-at-projection + PF-S02 un-invent the verdict stop the lie; PF-S01 discloses age; **PF-S03 re-homes refresh into `alln serve`** — founder ruling §0.2 supersedes the CWB Dock-only host lock. Spec Review Min `FCF51DB2` Ready. |
| [`Crew_Understaffed_Signal.md`](Crew_Understaffed_Signal.md) | **2 · Seat assignments — Ready to code (S01/S02)** | Serialize-don't-drop: AgentOS gate timeout = seat invoke timeout; dry-run names serial drivers. Hardened by DeepSeek + Kimi K3. AI PMs only. |
| [`OpenCode_Serve_Attach.md`](OpenCode_Serve_Attach.md) | **3 · OpenCode attach — Ready, OSA-S00→S03** | Attach healthy leftover serve on `:4096`; do not tear down per run. All OpenCode seats. Live repro 2026-08-08: killed the Proof Auditor seat inside a Spec Review run (`pid 48831`). |
| [`OpenCode_Local_Ollama_Seats.md`](OpenCode_Local_Ollama_Seats.md) | **4 · Ollama — OCL-S00 pipe PASS; code unauthorized** | **Dev builds only until fully ready** (founder 2026-08-08) — no dev-build gate exists in the CLI today, so that mechanism precedes OCL-S01/S02/S04. Also blocked on doc v5 + `--no-commit` honesty + serve attach. |
| [`Ambient_Dirty_Run_Outcome.md`](Ambient_Dirty_Run_Outcome.md) | **OPEN — draft; after the top four** | S122.3 `incomplete_uncommitted` fires on ambient WIP; OpenCode can deliver a full answer with zero run-owned edits and still fail. ADR-S01 dirty-vs-start; ADR-S02 don't stamp `empty_output` on delivered text. Origin: `09E19604`. |
| [`Capacity_Warm_Bench.md`](Capacity_Warm_Bench.md) | **OPEN — S00a then scheduler** | One 30m freshness clock; scoped kill before timer. ⚠ Its **Dock-only host lock is superseded** by `Probe_Freshness.md` §0.2 — reconcile. |
| [`Codex_Alln_Run_Hot_Fix.md`](../archive/phases/Codex_Alln_Run_Hot_Fix.md) | **READY — T3 diagnosis complete** | Code red: prove Codex → LaunchServices authority, then make one `alln run` self-starting with no stale queued work. |
| [`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md) | **OPEN — code-complete; one dogfood proof remains** | Wall-crossing resume half blocked on Codex real reset (2026-08-04). Code SSOT: `CapacityDisplayAcquisition`, `MenuCatalog`, `LoopCoordinator`, `VendorBackoffReconciler`. |
| [`One_Paste_Cold_Start.md`](One_Paste_Cold_Start.md) | **OPEN — S05 in progress** | R2 + Worker deployed; founder: Porkbun CNAME `get` → Cloudflare + Developer ID sign/notarize. S00–S03/S06 shipped. |
| [`Receipt_Portability_And_Call_Sites.md`](Receipt_Portability_And_Call_Sites.md) | **⚠ FOUNDER DECISION** | RP-S00 room test is free; RP-S01 digest needs ruling vs TRR-S02 signing cut. |
| [`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md) | **OPEN — not started** | Incident-driven: `workRecovery` envelope, PM substitution, `work scan`. Origin: 2026-07-29 PM outage. |
| [`One_Run_Surface.md`](One_Run_Surface.md) | **IN FLIGHT — code/docs cutover shipped; ORS-S04 two-host Works Test remains** | One single-run read surface: `alln show --json|--stream`. Public `team status` / `team result`, old waiter, and parallel status schema deleted. |

### Forward feature packets

| Doc | Status | Notes |
| --- | --- | --- |
| [`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) | **Live — 3 of 5 slices shipped** | Capacity signals must be owned per source. S01/S02 + S03-AgentOS shipped (AgentOS `6f66bdd`, `1d0f64f`); S05 shipped (`bc2311ea`). Open: label separation, S04 manifest signals, S06 AGY scoping. S03 persisted parks blocked on a founder ruling (§10.1). |
| [`Agent_Teaching_Surface.md`](Agent_Teaching_Surface.md) | Open — sequenced after Vendor Signal Isolation | `alln bootstrap` teaching block ships retired vocabulary; narrow the paste, gate the block, add a delegation help topic. |
| [`OpenCode_Long_Run_Continuity.md`](OpenCode_Long_Run_Continuity.md) | **ARCHIVE READY** | Dogfood + CT-08 coded; archive + promote next. |
| [`OpenCode_Completion_Truth_Followup.md`](OpenCode_Completion_Truth_Followup.md) | **COMPLETE** | CT-10 deferred; archive with S123. |
| [`OpenCode_Go_Capacity.md`](OpenCode_Go_Capacity.md) | **Ready for Implementation — not started** | Browser `/go` HTTP scrape (not PTY); separate `OpenCodeGoCapacity*` modules; encrypted credential file (no Keychain). v1: capacity strip only. |
| [`Composer_File_References.md`](Composer_File_References.md) | Backend built; Mac `@` palette forward | FR-S04 palette + GUI proof remain. |
| [`CLI_Product_Spine.md`](CLI_Product_Spine.md) | Open naming spine | Archive when no forward CLI naming work remains. |
| [`Team_Delegation_Surface.md`](Team_Delegation_Surface.md) | Draft — needs re-base | Core routing built; GUI browse unbuilt. |
| [`Live_Team_Board.md`](Live_Team_Board.md) | Draft | Honest in-thread team-run progress only. |
| [`Persistent_Work_Threads.md`](Persistent_Work_Threads.md) | Parent/router | MLP core delivered; open child: [`threads/09_Thread_Forking.md`](threads/09_Thread_Forking.md). |
| [`Keyboard_Shortcuts.md`](Keyboard_Shortcuts.md) | KBD-S00/S01 done | S02–S06 forward; re-base KBD-S05 away from retired approve ceremony. |
| [`Folder_Native_Memory.md`](Folder_Native_Memory.md) | Pointer only shipped | Consolidation engine unbuilt. |
| [`Chat_Module_Extraction.md`](Chat_Module_Extraction.md) | Plan — not started | AgentOS chat package extraction. |
| [`Share_To_Research.md`](Share_To_Research.md) | Draft — not started | iOS share sheet → Mac Research run. |
| [`Buzz_Harness_Spike.md`](Buzz_Harness_Spike.md) | SPIKE — deferred | Receipt prerequisite met; strategy in `docs/strategy/`. |
| [`Contradiction_Pass.md`](Contradiction_Pass.md) | **NOT AUTHORIZED** | Extends `docs/operations/Spec_Review.md`; do not start without founder ruling. |
| [`Pricing_Change_Process.md`](Pricing_Change_Process.md) | Standing process | Offer SSOT: `docs/marketing/Pricing_Recommendation.md`. |

### Subdirectories

| Dir | Status | Purpose |
| --- | --- | --- |
| [`setup/`](setup/README.md) | Detection engine built; WOW UX forward | First-run setup, per-CLI support docs. OpenCode driver **built** (HTTP serve path). |
| [`copy/`](copy/README.md) | Draft — unbuilt | Copy lane work orders. |
| [`ios/`](ios/README.md) | **Parked** | Future remote PM; must not block Mac delivery. |
| [`parked/`](parked/README.md) | **Parked** | Premature scheduler ideas (e.g. utilization admission). |
| [`sprint/`](sprint/README.md) | **No active work orders** | All sprint docs archived; open new ones here when slicing. |
| `wiring/`, `mockups/` | Design-handoff assets | Pixel reference for composer/setup/send-to-team surfaces. |

## Recently archived

Verified against code/commits; full index:
[`docs/archive/phases/README.md`](../archive/phases/README.md).

| Packet | Why archived | Successor |
| --- | --- | --- |
| [`Allnighter_Qwen_Driver_Bug_Report.md`](../archive/phases/Allnighter_Qwen_Driver_Bug_Report.md) | **QDR-S01 Complete (2026-08-07)** — headless write grant + answer retrieval; intake closed | AgentOS `catalog.json` (qwen/kimi `--yolo`); `TeamRunJSONMapper` / `alln show --answer` / contract 9.10.0 |
| [`Mac_Studio_LAN_Bench.md`](../archive/phases/Mac_Studio_LAN_Bench.md) | **SHELVED / NO BUILD (2026-08-06)** — streamed-diffs + iOS-pairing-as-execution fabric rejected; wrong ICP hero (Studio farm vs one-floor multi-CLI). Do not resume. | None — optional future: remote inference URL / research-only remote seats as separate packets. Active attention: capacity truth, park/substitute, teaching (`Vendor_Signal_Isolation`, `Quota_Aware_Bench_Continuity`, `Agent_Teaching_Surface`). |
| [`CLI_Park.md`](../archive/phases/CLI_Park.md) | `alln drivers park\|unpark` shipped `073522c7` | `SetupStore.parkedDriverIds`, `DriversCLI`, `Product_Vocabulary.md` |
| [`Worker_To_Agent_Migration.md`](../archive/phases/Worker_To_Agent_Migration.md) | Ship line complete 2026-07-29 | `Product_Vocabulary.md`; optional hygiene backlog in archive doc |
| [`threads/04_Observed_Usage.md`](../archive/phases/threads/04_Observed_Usage.md) | Superseded by OUR packet | `ObservedUsagePresentation`, archived `Observed_Usage_On_Receipts_And_Live_Status.md` |
| `sprint/team-run-receipt/TRR-S00*` | Founder disposition only; TRR product shipped | `ArtifactProjector` / `ArtifactCLI` |
| `sprint/opencode/OC-S01b–d` | Superseded by AgentOS HTTP driver | AgentOS `OpenCodeServeClient`, archived blocker resolution |
| [`Agent_Facing_Run_Observability.md`](../archive/phases/Agent_Facing_Run_Observability.md) | Superseded before implementation | [`One_Run_Surface.md`](One_Run_Surface.md) consolidates snapshot, activity, reattachment, and terminal delivery under `alln show`. |

Earlier 2026-07-31 cleanup archived Loop Verb Cutover, Menu Envelope Compression,
Worker/Skill Sharing, Capacity Hardening, and orphaned sprint work orders — see
archive index (do not reopen).

## Operating Rules

- Founder input is intent. Durable semantics land in **code** and/or **standing
  docs outside phases** — never as a permanent resident of `docs/phases/`.
- New phase docs must name one trusted workflow slice, one truth owner, and one
  Works Test or proof waiver.
- Closeout = **promote keepable law**, then **archive**. Skipping promotion dumps
  truth into the archive where agents stop reading it.
- Check one level below the phase packet (sprint work orders, execution briefs)
  when auditing — parent archived while children left behind is a recurring failure
  mode (fixed again 2026-08-01).

## Post-MVP Product Laws

- Allnighter coordinates the agents the user already pays for. It is not a model
  provider, IDE, chat aggregator, cloud coding service, or terminal viewer.
- Allnighter uses the user's existing CLI subscriptions/logins, **never** API
  keys / BYOK.
- Allnighter has nothing to do with git. Safety = one mutating agent + write
  lock + bounded order + proof surface.
- The agent-facing contract is CLI-only. **MCP was retired 2026-07-16**.
- Execution lane serialization is INVIOLABLE: one mutating run per repo root.
- Agents fail honestly. A failed agent is shown failed, never hidden or faked.

Full laws: prior README sections and `docs/workflows/Product_Vocabulary.md`.

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

Works Test:
Proof command:
Missing proof / waiver:

Done when:
Open questions:
```

## Routing (active work)

| Work | Read first |
| --- | --- |
| Capacity strip, `alln capacity`, warm pool, stale % | [`Capacity_Warm_Bench.md`](Capacity_Warm_Bench.md) — Spec Review Min Ready; S00a scoped kill → Dock 30m silent schedule |
| `alln run` fails from Codex, handoff host missing, stale handoff work | [`Codex_Alln_Run_Hot_Fix.md`](../archive/phases/Codex_Alln_Run_Hot_Fix.md) |
| Plan-time quota routing, loop park-yield, cross-vendor arbitrage | [`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md) |
| OpenCode local / Ollama seats (pipe on mini, sell to Studio; Idle/Busy readiness) | [`OpenCode_Local_Ollama_Seats.md`](OpenCode_Local_Ollama_Seats.md) — founder rulings locked; Spec Review next; ignore Ollama Cloud |
| OpenCode serve busy / leftover :4096 after `alln run` | [`OpenCode_Serve_Attach.md`](OpenCode_Serve_Attach.md) — attach healthy serve; do not tear down per run |
| Core execution broken, team research/execution lies | Code SSOT: `RunService.swift`, `TeamCatalog`, `RunWriteLockRegistry` |
| Cold start — no `alln` on PATH | [`One_Paste_Cold_Start.md`](One_Paste_Cold_Start.md) |
| Composer `@` file references | [`Composer_File_References.md`](Composer_File_References.md) |
| PM continuity after seat death | [`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md) |
| Agent needs status, activity, reattachment, or result for one delegated run | [`One_Run_Surface.md`](One_Run_Surface.md) |
| Send to team / delegation surface | [`Team_Delegation_Surface.md`](Team_Delegation_Surface.md) + `docs/gui/surfaces/send-to-team/brief.md` |
| Persistent chat / thread backend | [`Persistent_Work_Threads.md`](Persistent_Work_Threads.md) |
| First-run setup, CLI detection | [`setup/README.md`](setup/README.md) |
| Sprint work orders (one-slice agents) | [`sprint/README.md`](sprint/README.md) — none active; create new when slicing |
| Built MVP / run model law | `docs/mvp/README.md` + code `RunService.swift` |
| Sprint execution and closeout | `docs/operations/Execution-Playbook.md` |
| **Anything shipped & archived** | [`docs/archive/phases/README.md`](../archive/phases/README.md) |

## Retired Content

Old numbered roadmap docs and worktree-era plans were removed long ago. Do not
infer active product truth from missing `XX_*.md` links. New forward phases are
added explicitly to this board.
