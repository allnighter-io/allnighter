# Allnighter - Phases

Status: Active post-MVP planning and execution
Updated: 2026-06-15

## Purpose

The MVP team-run substrate has been built. Going forward,
`docs/phases/` is the active home for post-MVP product slices, mentor-review
notes, and implementation phase docs.

> **▶ [`setup/`](setup/README.md) — First-Run Setup ("assemble your team").**
> Phase 0 (packaging) and Phase 1 (detection engine: `CLIDetector` +
> `ShellResolver` + `SetupStore`, reachable headless via `alln detect`) are
> **built**; Phase 2 (app consumes the detector) is largely built. Remaining:
> Phase 4 auto-team (engine), the Phase 2 "health == runs" check, and the Setup UX
> (Phase 3, **blocked on designer mocks**). See `setup/README.md` for live status.

`docs/mvp/` remains the source of truth for what has already shipped and for the
foundation it created: workers, drivers, fan-out, synthesis, design boards, and
the Mac app substrate. New forward work starts here unless a routed doc says
otherwise.

## Current Phase Board

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Persistent_Work_Threads.md`](Persistent_Work_Threads.md) | MLP BUILT (S01–S06), PAUSED 2026-06-15; S07–S09 + fast-follows remain | Thread/chat phase router: async work-thread MLP first, then Mac notifications, streaming, and observed usage as fast follows. |
| [`Utilization_Admission_Control.md`](Utilization_Admission_Control.md) | Execution-ready for all slices | Admission control for selected workers, team runs, pending work, fallbacks, and floor visibility without quota accounting. |
| [`Pending_Work_And_Drain.md`](Pending_Work_And_Drain.md) | Draft founder packet; CLI-first naming approved | Public `alln pending`, Away Mode drain, cooldown resume, and Activity Summary as the brand-fit utilization unlock. |
| [`CLI_Product_Spine.md`](CLI_Product_Spine.md) | **CLI M1 BUILT** (2026-06-15) | `alln` is the first-class agent-ready contract; RB6 grammar retired. Still owns the forward spine + naming/agent-first laws. |
| [`CLI_Implementation_Contract.md`](CLI_Implementation_Contract.md) | **CLI M1 BUILT** (2026-06-15), full wall green | M1 shipped: `TeamRunJSON`/`DoctorResult`/`ErrorEnvelope`, Core registry + generated artifacts + drift gate, `team --json` + **live `--stream`**, `doctor --json/--full`, `docs`/`show`/`export`/`history`/`doctor explain`, MCP `serve --stdio` (registry-derived). Still owns: MCP advertising/async tools + Pending grammar (deferred). |
| [`Fanout_Team_Catalog.md`](Fanout_Team_Catalog.md) | Backend BUILT (S00-S05); GUI/iOS deferred | Lane-scoped custom teams and built-in Build/Design/Copy specialist teams for Fan out: team picker, Low/Med/High effort, and one-CLI multi-skill self-fusion. |
| [`Agent_First_MCP_And_Messaging_Workflows.md`](Agent_First_MCP_And_Messaging_Workflows.md) | PARTIAL: bootstrap/preflight/discovery + spec retrieval built; async/Pending deferred | Agent-first workflow layer for OpenClaw/Hermes-style messaging and voice agents: bootstrap/doctor recovery loop, MCP async team tools, Pending over MCP, full spec retrieval, provenance, approval handoffs, and entitlement hooks. |
| [`Mac_Standalone_App_And_Background_Coordinator.md`](Mac_Standalone_App_And_Background_Coordinator.md) | Draft forward phase | Convert the Mac shell from menu-bar-first to standalone Dock app plus explicit background coordinator/resident lifecycle. |
| [`Work_Order_Team_Model.md`](Work_Order_Team_Model.md) | Active language contract | Source, bench, model, skill, worker, team, lane, type, effort, and preset vocabulary for work-order specs. |
| [`copy/README.md`](copy/README.md) | Draft post-MVP lane | Copy work orders: prompt-first `/copy`, copy type, effort, copy board, and later specialized copy packs. |
| [`ios/README.md`](ios/README.md) | Active iOS spine | Remote floor manager: sign in, pick your Mac, control runs. |

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
- A work thread is the durable product unit. Chat is the default turn; team run,
  design board, work order, dispatch, and return review are stronger turn types
  inside the same thread.
- The user-facing words are: model, skill, worker, team, team run, worker answer,
  plan, work order, thread, floor manager.
- Do not add new public `team` language. `Work_Order_Team_Model.md`
  owns the active vocabulary contract (cleanup slice complete — see
  `docs/archive/phases/Team_First_Vocabulary_Cleanup.md`).
- Workers fail honestly. A failed worker is shown failed, never hidden or faked.
- Effort is a user instruction, not an estimate.
- Do not estimate future cost, quota burn, runtime, or task complexity.
- Utilization is admission control: can this model accept work now, and what
  should Allnighter do next?
- Capacity state is observed, sourced, timestamped, and local by default.
- Pending separates user intent from worker availability; queueing is internal
  scheduler machinery, and draining must obey admission, safety, and explicit
  policy.
- Pending is public CLI-first: `alln pending` plus `alln serve` must exist before
  the GUI promises app-closed execution.
- Forward Mac app work targets a standalone Dock app plus explicit background
  coordinator. The menu bar is status/quick controls, not the primary shell.
- iOS is a floor manager. The Mac remains the execution and run-truth owner.
- Work-order creation stays prompt-first. Build/Design/Copy and Effort route the
  work; they must not become an intake form.
- Build, Design, and Copy are the peer creation lanes. A fourth lane requires a
  new substrate or output class; otherwise it is a type or preset inside the
  existing lanes.
- Fan out never infers lane from prompt prose. The user chooses Build / Design /
  Copy. Fan out targets a lane-scoped team plus effort, not a bare model.
- Every built-in and custom team belongs to exactly one lane. There are no
  shared or multi-lane teams; duplicate and tune a lineup when it belongs in
  another lane.
- Team presets are reusable units. Built-in and custom teams may resolve to
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
| Public vocabulary, model/skill/worker/team language | `Work_Order_Team_Model.md` (historical cleanup: `docs/archive/phases/Team_First_Vocabulary_Cleanup.md`) |
| CLI-first product spine, `alln`, product grammar, agent-first posture | `CLI_Product_Spine.md` |
| CLI implementation detail, generated docs/doctor/errors/events, proof gates | `CLI_Implementation_Contract.md` |
| Team-run JSON/schema, MCP rename, RB6 CLI cutover | `CLI_Product_Spine.md` + `CLI_Implementation_Contract.md` |
| Fan out composer, lane-scoped custom teams, built-in Build/Design teams | `Fanout_Team_Catalog.md` + `Work_Order_Team_Model.md` |
| OpenClaw/Hermes, messaging agents, voice-to-text workflows, doctor recovery, Pending over MCP, full spec retrieval | `Agent_First_MCP_And_Messaging_Workflows.md` + `CLI_Product_Spine.md` + `CLI_Implementation_Contract.md` + `Pending_Work_And_Drain.md` |
| Standalone Mac app, Dock presence, menu-bar role, background coordinator, resident lifecycle | `Mac_Standalone_App_And_Background_Coordinator.md` |
| Built MVP behavior, worker drivers, team-run/design-board substrate | `docs/mvp/README.md` |
| Work-order vocabulary, model/skill/worker/team model | `Work_Order_Team_Model.md` |
| Persistent chat, routable turns, thread backend, run-to-thread linkage | `Persistent_Work_Threads.md` -> `threads/01_Work_Threads_MLP.md` **(BUILT S01–S06; S07–S09 remain)** |
| Mac notifications / mobile OneSignal push | `threads/02_Notifications.md` |
| Mac token streaming / live worker output | `threads/03_Mac_Streaming.md` |
| Source-labeled observed usage metadata | `threads/04_Observed_Usage.md` |
| Utilization, admission control, worker availability, pending dispatch | `Utilization_Admission_Control.md` |
| Pending, Away Mode, cooldown resume, Activity Summary, drain policy | `Pending_Work_And_Drain.md` + `Utilization_Admission_Control.md` + `Mac_Standalone_App_And_Background_Coordinator.md` |
| Copy lane, `/copy`, copy type packs, copy board | `copy/README.md` |
| iOS remote floor manager | `ios/README.md` |
| Feature semantics before implementation | `docs/workflows/SSOT_Feature_Workflow.md` |
| Sprint execution and closeout | `docs/operations/Execution-Playbook.md` |
| Stack and proof commands | `docs/operations/TechStack.md` |

## Retired Content

The old numbered roadmap docs that previously lived here were removed. Do not
infer active product truth from missing `XX_*.md` phase links or archived
worktree-era plans. New forward phases are added explicitly to this folder.
