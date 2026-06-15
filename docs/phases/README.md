# Allnighter - Phases

Status: Active post-MVP planning and execution
Updated: 2026-06-15

## Purpose

The MVP Council and Design Council have been built. Going forward,
`docs/phases/` is the active home for post-MVP product slices, mentor-review
notes, and implementation phase docs.

> **▶ [`setup/`](setup/README.md) — First-Run Setup ("assemble your council").**
> Specs finalized; design + build pending. **Phase 0 is a confirmed prerequisite
> bug:** the bundled driver manifests don't ship as a `Drivers/` folder, so first
> run shows a broken "0/1 healthy" council. Fix packaging first, then the
> CLI-detection engine, then the Setup UX. See `setup/README.md` for the build
> order.

`docs/mvp/` remains the source of truth for what has already shipped and for the
foundation it created: workers, drivers, fan-out, synthesis, design council, and
the Mac app substrate. New forward work starts here unless a routed doc says
otherwise.

## Current Phase Board

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Persistent_Work_Threads.md`](Persistent_Work_Threads.md) | MLP BUILT (S01–S06), PAUSED 2026-06-15; S07–S09 + fast-follows remain | Thread/chat phase router: async work-thread MLP first, then Mac notifications, streaming, and observed usage as fast follows. |
| [`Utilization_Admission_Control.md`](Utilization_Admission_Control.md) | Finalized for implementation | Admission control for selected workers, panels, queued turns, fallbacks, and floor visibility without quota accounting. |
| [`Work_Order_Team_Model.md`](Work_Order_Team_Model.md) | Draft language contract | Bench, skill, seat, team, lane, type, effort, and preset vocabulary for work-order specs. |
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
- A work thread is the durable product unit. Chat is the default turn; council,
  design, work order, dispatch, and return review are stronger turn types inside
  the same thread.
- The user-facing words remain: worker, panel, council run, member answer,
  judge, master plan, work order, thread, floor manager.
- Workers fail honestly. A failed worker is shown failed, never hidden or faked.
- Effort is a user instruction, not an estimate.
- Do not estimate future cost, quota burn, runtime, or task complexity.
- Utilization is admission control: can this worker accept work now, and what
  should Allnighter do next?
- Capacity state is observed, sourced, timestamped, and local by default.
- iOS is a floor manager. The Mac remains the execution and run-truth owner.
- Work-order creation stays prompt-first. Build/Design/Copy and Effort route the
  work; they must not become an intake form.
- Build, Design, and Copy are the peer creation lanes. A fourth lane requires a
  new substrate or output class; otherwise it is a type or preset inside the
  existing lanes.
- A seat is one worker wearing one skill. Lanes ship default teams, but advanced
  users can customize the worker-skill lineup one level below the main composer.

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
| Built MVP behavior, worker drivers, council/design council substrate | `docs/mvp/README.md` |
| Work-order vocabulary, bench/skill/seat/team model | `Work_Order_Team_Model.md` |
| Persistent chat, routable turns, thread backend, run-to-thread linkage | `Persistent_Work_Threads.md` -> `threads/01_Work_Threads_MLP.md` **(BUILT S01–S06; S07–S09 remain)** |
| Mac notifications / mobile OneSignal push | `threads/02_Notifications.md` |
| Mac token streaming / live worker output | `threads/03_Mac_Streaming.md` |
| Source-labeled observed usage metadata | `threads/04_Observed_Usage.md` |
| Utilization, admission control, worker availability, queued dispatch | `Utilization_Admission_Control.md` |
| Copy lane, `/copy`, copy type packs, copy board | `copy/README.md` |
| iOS remote floor manager | `ios/README.md` |
| Feature semantics before implementation | `docs/workflows/SSOT_Feature_Workflow.md` |
| Sprint execution and closeout | `docs/operations/Execution-Playbook.md` |
| Stack and proof commands | `docs/operations/TechStack.md` |

## Retired Content

The old numbered roadmap docs that previously lived here were removed. Do not
infer active product truth from missing `XX_*.md` phase links or archived
worktree-era plans. New forward phases are added explicitly to this folder.
