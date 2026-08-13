# Allnighter — Phases

Status: Active post-MVP planning and execution
Updated: 2026-08-13

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

**No CODE RED is open.** Both closed 2026-08-12: First CLI Detection & Setup
(verified by running the product) and `alln serve` Recovery (2026-08-11). Nothing
in this board is currently top-priority — the next item should come from using
the product, not from picking the next row here.

> **Founder-ordered queue (re-ordered 2026-08-08 PM)** — work in this order:
> **QUEUE COMPLETE 2026-08-09.** ~~**1.** OpenCode attach~~ · ~~**2.** Seat
> assignments~~ (both closed + archived) · ~~**3.** Native capacity channels~~
> (4 shipped, kimi ruled out) · ~~**4.** PF-S01 freshness disclosure~~ ·
> ~~**5.** Shadow-mode the model reader~~ · ~~**6.** Probe Freshness (PF-S03b)~~.
> Stopped at 6 as instructed.
> Run-completion work outranks sensor work: capacity informs selection but never
> blocks a run, while `:4096` collisions stop the bench outright.
> ~~**0.** Run readout~~ · ~~**0.5** Ambient dirty~~ closed 2026-08-08.
> **Ollama seats (packet 1):** archived 2026-08-13 —
> [`OpenCode_Local_Ollama_Seats.md`](../archive/phases/OpenCode_Local_Ollama_Seats.md).
> Law: `docs/operations/Project_Laws.md` §Local Ollama seats. Remaining
> unproven: §11 B on Studio-class hardware; OCL-S05 (measured, not assumed).
> Packets 2–3 (Context Firewall, Second Mac) remain
> **document work / unauthorized for code** until a founder ruling.
> Everything below the queue is unordered backlog.

| Doc | Status | Next action |
| --- | --- | --- |
| [`Handover_Capacity_2026-08-08.md`](Handover_Capacity_2026-08-08.md) | **START HERE — PM handover** | State of capacity/serve after 51 commits, decisions already ruled (do not relitigate), landmines, and the next work in order. Read before picking anything up. |
| [`Capacity_Native_Channels.md`](Capacity_Native_Channels.md) | **v6 — 4 credential-free channels SHIPPED. §4 credential posture: RULED NO (2026-08-12)** | Every one of the six PTY-scraped sources has a VERIFIED better channel; four need no credentials at all. `agy --print "/usage" --output-format json` returns structured JSON in ~1s with zero model tokens; codex `app-server` exposes typed `account/rateLimits/read`. Deletes the whole 2026-08-08 bug class (generic markers, misspelled guards, repaint races, load sensitivity) by construction. §4 is **answered by the 2026-08-12 capacity ruling: no vendor-stored tokens for a dashboard.** The 4 credential-free channels stand because they are strictly cheaper and more reliable than PTY scraping — that is maintenance of a shipped surface, not new capability. The 2 credential-requiring channels are not authorized. |
| [`Context_Firewall.md`](Context_Firewall.md) | **SPEC — packet 2 of 3; no code authorized** | Per-root `egress: open\|abstracted\|local_only` + verbatim egress ledger. Claim is **auditable, never sanitised** (§4.1) — copy review is a blocking test. Blocked on root-less dispatch design (§6). Packet 1 archived; outcome honesty landed `7a7f8117`. Regulated tier is bottom-up optionality, not roadmap (§3.3). |
| [`Second_Mac_Bench.md`](Second_Mac_Bench.md) | **V2 STUB — packet 3 of 3; not started** | Scope fence for the two-machine problem. Shelved LAN architecture stays shelved; three narrow doors recorded (D1 remote inference URL only). Cannot open until packets 1 and 2 land + a founder ruling names the door. |
| [`One_Paste_Cold_Start.md`](One_Paste_Cold_Start.md) | **OPEN — S05 CLI + DMG live** | `curl -fsSL https://get.allnighter.io \| sh` + `/Allnighter.dmg`. Repeatable ship: `docs/operations/Public_Release.md`. |
| [`Receipt_Portability_And_Call_Sites.md`](Receipt_Portability_And_Call_Sites.md) | **⚠ FOUNDER DECISION** | RP-S00 room test is free; RP-S01 digest needs ruling vs TRR-S02 signing cut. |
| [`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md) | **OPEN — not started** | Incident-driven: `workRecovery` envelope, PM substitution, `work scan`. Origin: 2026-07-29 PM outage. |

### Forward feature packets

| Doc | Status | Notes |
| --- | --- | --- |
| [`Agent_Teaching_Surface.md`](Agent_Teaching_Surface.md) | Open — sequenced after Vendor Signal Isolation | `alln bootstrap` teaching block ships retired vocabulary; narrow the paste, gate the block, add a delegation help topic. |
| [`OpenCode_Go_Capacity.md`](OpenCode_Go_Capacity.md) | **CLI beta SHIPPED (2026-08-06) — metering LIVE; Mac GUI deferred** | Browser `/go` HTTP scrape (not PTY); `OpenCodeGoCapacity*` modules; encrypted credential file. Live on the founder's machine — `alln doctor` reports `source.opencode.goConnected`. **Wrongly archived 2026-08-12 by an agent extending a founder ruling that did not cover it; restored same day.** The board had also mislabelled this "Ready for Implementation — not started" while it was shipped. |
| [`Bailian_Token_Plan_Capacity.md`](Bailian_Token_Plan_Capacity.md) | **SPIKE — dogfood only (`--dogfood --source bailian_token_plan`)** | Alibaba Token Plan Personal quota via JSON API. **Wrongly archived 2026-08-12 by the same over-extended ruling; restored same day.** |
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
| [`Scarcity_Aware_Routing.md`](Scarcity_Aware_Routing.md) | **Brainstorm — NO slice authorized** | Read §3 rejected list first. Was orphaned off this board until 2026-08-12. |
| [`Pricing_Change_Process.md`](Pricing_Change_Process.md) | Standing process | Offer SSOT: `docs/marketing/Pricing_Recommendation.md`. |

### Subdirectories

| Dir | Status | Purpose |
| --- | --- | --- |
| [`setup/`](setup/README.md) | Detection engine built; WOW UX forward | First-run setup, per-CLI support docs. OpenCode driver **built** (HTTP serve path). |
| [`copy/`](copy/README.md) | Draft — unbuilt | Copy lane work orders. |
| [`ios/`](ios/README.md) | **Parked** | Future remote PM; must not block Mac delivery. |
| [`parked/`](parked/README.md) | **Parked** | Premature scheduler ideas (e.g. utilization admission). |
| [`sprint/`](sprint/README.md) | **No active queue** | ASR complete and archived (2026-08-11); SC orders are superseded historical evidence — do not resume either. Cut a new order from whichever packet you are actually working. |
| `wiring/` | Design-handoff assets | Pixel reference for composer/setup/send-to-team surfaces. (`mockups/` was listed here until 2026-08-12 and does not exist.) |

## Recently archived

Verified against code/commits; full index:
[`docs/archive/phases/README.md`](../archive/phases/README.md).

| Packet | Why archived | Successor |
| --- | --- | --- |
| [`OpenCode_Local_Ollama_Seats.md`](../archive/phases/OpenCode_Local_Ollama_Seats.md) | **CLOSED (2026-08-13)** — packet 1 of 3. Works Test **A** for both bodies. **B** unproven on Studio-class hardware. OCL-S05 unbuilt (20.9s cold vs 120s on this host). `check.sh` green wall not run: red on GUI visual proof debt (`CapacityStripView`, `RootView`) belonging to capacity work — not waived. | Law in `docs/operations/Project_Laws.md` §Local Ollama seats; vocab `Product_Vocabulary.md` §Local Ollama readiness; code `ModelCatalog` / `ModelDiscoveryProvider` / `OllamaLocalDoctorReport` / `ClaudeLocalIsolation` |
| [`Capacity_Warm_Bench.md`](../archive/phases/Capacity_Warm_Bench.md) | **KILLED (2026-08-12) — founder: feature creep.** The resident trust gate certified numbers that changed no decision: `TeamResolver` has zero capacity references and `alln menu --json` emits no `capacity` key. The two cases that could justify prediction — long fan-outs, unattended loops — are not how this founder works. | Reactive park/substitute stands (`CapacityClassifier` → `VendorBackoffPolicy` → substitute); honest "unknown — never sampled" display stands |
| [`First_CLI_Detection_And_Setup_Code_Red.md`](../archive/phases/First_CLI_Detection_And_Setup_Code_Red.md) | **CLOSED (2026-08-12) — CODE RED cleared.** S01–S07 shipped; S08 closed. Verified by RUNNING the product, not by reading the packet: a virgin store yields `neverScanned` (never `0/9`) with `nextAction: alln detect`; bootstrap teaches find-CLIs via the live nextAction; Cursor IDE ≠ Agent CLI teaching present. Cold-install dogfood gate WAIVED — its substance is proven, and the faucet belongs to One_Paste_Cold_Start. | Code SSOT: `BenchTallyProjector`, `MenuCatalog`, `DoctorReport`, `SourceProbeService`, `ProbeRecordMerge`; law in `docs/operations/Project_Laws.md` §Bench tally |
| [`Vendor_Signal_Isolation.md`](../archive/phases/Vendor_Signal_Isolation.md) | **CLOSED (2026-08-12).** S01/S02, S03-AgentOS, S05, S06, S07 shipped. **S06's prescribed exit-code gate was NOT built — it is redundant** (`DefaultWorkerRunner.swift:279` already classifies on nonzero exit only). **S04 manifest signals KILLED** (unbuilt, nothing depends on it; scoping a matcher costs a two-line guard, a declaration framework adds a second place to be wrong). **S03 persisted parks KILLED** — a sensor may not become a durable veto; durable parks stay user intent. | Code SSOT: AgentOS `CapacityClassifier`, `VendorBackoffPolicy`, `CapacityPaintGate`, `SeatReseat`; law in `docs/operations/Project_Laws.md` §Vendor signals |
| [`Alln_Serve_Hotfixes.md`](../archive/phases/Alln_Serve_Hotfixes.md) | **CLOSED (2026-08-11)** — 15/15 done-when; one canonical binary, one launchd agent, verified install/update/repair, no detached auto-launch. **§10.1 R1 did NOT close**: the 2026-08-09 LWCR root cause is still unidentified and was re-homed to the debug log. | Code SSOT: `ServeLifecycle`, `ServeDaemon`, `ServeStatusJSON`, `CanonicalCLIInstall`; vocabulary `Product_Vocabulary.md` §Background scheduler; open risk in `docs/operations/debugger/DEBUGLOG.md` |
| [`CLI_Install_Documents_TCC_Adhoc_Waive.md`](../archive/phases/CLI_Install_Documents_TCC_Adhoc_Waive.md) | **CLOSED — WAIVED (2026-08-11)** — the residual Documents prompt on CLI reinstall is ad-hoc CDHash dogfood, not a signed first-user install bug. No further escape layers. | Code SSOT: `ProtectedCWDEscape` (`b65a2ea2`) |
| [`First_Launch_CLI_Strip.md`](../archive/phases/First_Launch_CLI_Strip.md) | **CLOSED (2026-08-10)** — FLCS-S01: home marketing chips use `setupCards` (not `composeBench` models); Find-my-team suppresses gray wall; green/amber/gray via `StatusDot`; tap → `openCLISetup`. Not capacity. | Code SSOT: `HomeMarketingCLIStrip`, `HomeMarketingEmptyState` / `HomeView`, `RootView.openCLISetup`; proof `HomeMarketingCLIStripTests` |
| [`Probe_Freshness.md`](../archive/phases/Probe_Freshness.md) | **CLOSED (2026-08-09)** — PF-S00…S03b: expire-at-projection, disclosure, vendor-signal sibling, serve capacity refresh, `lastDetectedAt` split + run capability clock, founder B periodic full probe smoke (`ProbeRecordRefreshScheduler`). | Code SSOT: `ProbeFreshnessGate`, `ProbeFreshnessDisclosure`, `SourceProbeService`, `CensusIngest`, `ProbeRecordRefreshScheduler`, `RunService`; vocabulary: `Product_Vocabulary.md` §Probe freshness |
| [`OpenCode_Long_Run_Continuity.md`](../archive/phases/OpenCode_Long_Run_Continuity.md) | **CLOSED (2026-08-09)** — S123 long-run/concurrent continuity; CT follow-up archived with parent. CT-10 deferred. | Help `opencode_headless_completion`; code SSOT AgentOS `OpenCodeServeClient` / `OpenCodeSSEParser` / `OpenCodeRoutingWorkerRunner` |
| [`OpenCode_Turn_Capture_Hardening.md`](../archive/phases/OpenCode_Turn_Capture_Hardening.md) | **CLOSED (2026-08-09)** — OCH-S01…S04: actor parser last-assistant-only, harden post-idle reconcile, busy/idle-defer + clock injection, shared seat timeout budget. AgentOS `65da768`. | Help `opencode_headless_completion`; code SSOT AgentOS `OpenCodeSSEParser` / `OpenCodeServeClient` / `OpenCodeRoutingWorkerRunner` |
| [`Ambient_Dirty_Run_Outcome.md`](../archive/phases/Ambient_Dirty_Run_Outcome.md) | **CLOSED (2026-08-08)** — S122.3 blamed the seat for the user's pre-existing WIP, failing honest zero-edit answers as `incomplete_uncommitted`, and stamped `empty_output` on delivered text. S01 dirty-vs-start, S02 delivered≠empty, S03 help. | Help `opencode_headless_completion`; code SSOT `RunService` (`startDirtyPaths`, S122.3 gate, `applyIncompleteUncommitted`) |
| [`Run_Readout_Truth.md`](../archive/phases/Run_Readout_Truth.md) | **CLOSED (2026-08-08)** — a completed Spec Review carrying a Ready verdict read as a crashed run. S02 teaching v11, S03 honest `outcome.headline`, S04 wired `errors` (was a hardcoded `[]`). S01 dropped: `outcome.status` already answers did-it-work, and nothing was affordable to delete for a new field. Cold-agent gate passed on three real runs. | `../archive/phases/One_Run_Surface.md` §"What the terminal snapshot must say"; code SSOT `TeamRunJSONMapper` (`runErrors`, `outcomeHeadline`), `LeadCallParser`, `TeachingSnippet` |
| [`Allnighter_Qwen_Driver_Bug_Report.md`](../archive/phases/Allnighter_Qwen_Driver_Bug_Report.md) | **QDR-S01 Complete (2026-08-07)** — headless write grant + answer retrieval; intake closed | AgentOS `catalog.json` (qwen/kimi `--yolo`); `TeamRunJSONMapper` / `alln show --answer` / contract 9.10.0 |
| [`Mac_Studio_LAN_Bench.md`](../archive/phases/Mac_Studio_LAN_Bench.md) | **SHELVED / NO BUILD (2026-08-06)** — streamed-diffs + iOS-pairing-as-execution fabric rejected; wrong ICP hero (Studio farm vs one-floor multi-CLI). Do not resume. | None — optional future: remote inference URL / research-only remote seats as separate packets. Active attention: capacity truth, park/substitute, teaching (`Vendor_Signal_Isolation`, `Agent_Teaching_Surface`). |
| [`CLI_Park.md`](../archive/phases/CLI_Park.md) | `alln drivers park\|unpark` shipped `073522c7` | `SetupStore.parkedDriverIds`, `DriversCLI`, `Product_Vocabulary.md` |
| [`Worker_To_Agent_Migration.md`](../archive/phases/Worker_To_Agent_Migration.md) | Ship line complete 2026-07-29 | `Product_Vocabulary.md`; optional hygiene backlog in archive doc |
| [`threads/04_Observed_Usage.md`](../archive/phases/threads/04_Observed_Usage.md) | Superseded by OUR packet | `ObservedUsagePresentation`, archived `Observed_Usage_On_Receipts_And_Live_Status.md` |
| `sprint/team-run-receipt/TRR-S00*` | Founder disposition only; TRR product shipped | `ArtifactProjector` / `ArtifactCLI` |
| `sprint/opencode/OC-S01b–d` | Superseded by AgentOS HTTP driver | AgentOS `OpenCodeServeClient`, archived blocker resolution |
| [`Agent_Facing_Run_Observability.md`](../archive/phases/Agent_Facing_Run_Observability.md) | Superseded before implementation | [One_Run_Surface.md](../archive/phases/One_Run_Surface.md) consolidates snapshot, activity, reattachment, and terminal delivery under `alln show`. |

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
| Capacity strip, `alln capacity`, warm pool, stale % | Bench tally / never-scanned host / a seat wrongly shown missing | Archived [`First_CLI_Detection_And_Setup_Code_Red.md`](../archive/phases/First_CLI_Detection_And_Setup_Code_Red.md); law in [`docs/operations/Project_Laws.md`](../operations/Project_Laws.md) §Bench tally; code SSOT `BenchTallyProjector`, `ProbeRecordMerge` |
| `alln menu` hides seats / stale readiness / probe freshness | Archived [`Probe_Freshness.md`](../archive/phases/Probe_Freshness.md); code SSOT `ProbeFreshnessGate`, `ProbeRecordRefreshScheduler` |
| `alln run` fails from Codex, handoff host missing, stale handoff work | [`Codex_Alln_Run_Hot_Fix.md`](../archive/phases/Codex_Alln_Run_Hot_Fix.md) |
| Plan-time quota routing, loop park-yield, cross-vendor arbitrage | Archived [`Quota_Aware_Bench_Continuity.md`](../archive/phases/Quota_Aware_Bench_Continuity.md); vocabulary `Product_Vocabulary.md` §Quota-aware bench; code SSOT `LoopCoordinator.resolveCapacityPark`, `VendorBackoffReconciler` |
| Ollama local seats (Claude Code and/or OpenCode; Available/Unavailable per seat) | Archived [`OpenCode_Local_Ollama_Seats.md`](../archive/phases/OpenCode_Local_Ollama_Seats.md); law in [`docs/operations/Project_Laws.md`](../operations/Project_Laws.md) §Local Ollama seats; vocab `Product_Vocabulary.md` §Local Ollama readiness; code `ModelCatalog` / `ModelDiscoveryProvider` |
| Context firewall / egress policy / "keep the frontier model away from my source" | [`Context_Firewall.md`](Context_Firewall.md) — packet 2 of 3; *auditable, never sanitised*; root-less dispatch undesigned |
| Second Mac, Studio in the office, LAN, remote `OLLAMA_HOST` | [`Second_Mac_Bench.md`](Second_Mac_Bench.md) — packet 3 of 3; fence, not a plan |
| OpenCode serve busy / leftover :4096 after `alln run` | Core execution broken, team research/execution lies | Code SSOT: `RunService.swift`, `TeamCatalog`, `RunWriteLockRegistry` |
| Cold start — no `alln` on PATH | [`One_Paste_Cold_Start.md`](One_Paste_Cold_Start.md) |
| Composer `@` file references | [`Composer_File_References.md`](Composer_File_References.md) |
| PM continuity after seat death | [`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md) |
| Agent needs status, activity, reattachment, or result for one delegated run | Archived [`One_Run_Surface.md`](../archive/phases/One_Run_Surface.md); code SSOT `RunService` / `TeamRunJSONMapper` |
| Send to team / delegation surface | [`Team_Delegation_Surface.md`](Team_Delegation_Surface.md) + `docs/gui/surfaces/send-to-team/brief.md` |
| Persistent chat / thread backend | [`Persistent_Work_Threads.md`](Persistent_Work_Threads.md) |
| First-run setup, CLI detection | [`setup/README.md`](setup/README.md) |
| `alln serve` dead / orphan LaunchAgent / capacity stale with app closed / app launch storm | Code SSOT `ServeLifecycle`, `ServeDaemon`, `ServeStatusJSON`, `CanonicalCLIInstall`; vocabulary `Product_Vocabulary.md` §Background scheduler. Archived [`Alln_Serve_Hotfixes.md`](../archive/phases/Alln_Serve_Hotfixes.md). **Silent disables / unexplained unloads are NOT closed** — see `docs/operations/debugger/DEBUGLOG.md` 2026-08-11 (R1) |
| Sprint work orders (one-slice agents) | [`sprint/README.md`](sprint/README.md) — no active queue; ASR archived, SC superseded |
| Built MVP / run model law | `docs/mvp/README.md` + code `RunService.swift` |
| Sprint execution and closeout | `docs/operations/Execution-Playbook.md` |
| **Anything shipped & archived** | [`docs/archive/phases/README.md`](../archive/phases/README.md) |

## Retired Content

Old numbered roadmap docs and worktree-era plans were removed long ago. Do not
infer active product truth from missing `XX_*.md` links. New forward phases are
added explicitly to this board.
