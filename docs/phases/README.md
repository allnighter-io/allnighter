# Allnighter - Phases

Status: Active post-MVP planning and execution
Updated: 2026-06-15

## Purpose

The MVP Council and Design Council have been built. Going forward,
`docs/phases/` is the active home for post-MVP product slices, mentor-review
notes, and implementation phase docs.

`docs/mvp/` remains the source of truth for what has already shipped and for the
foundation it created: workers, drivers, fan-out, synthesis, design council, and
the Mac app substrate. New forward work starts here unless a routed doc says
otherwise.

## Current Phase Board

| Doc | Status | Purpose |
| --- | --- | --- |
| [`Utilization_Admission_Control.md`](Utilization_Admission_Control.md) | Draft for mentor review | Queue and dispatch work from observed worker availability, not quota accounting. |
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
- The user-facing words remain: worker, panel, council run, member answer,
  judge, master plan, work order, floor manager.
- Workers fail honestly. A failed worker is shown failed, never hidden or faked.
- Effort is a user instruction, not an estimate.
- Do not estimate future cost, quota burn, runtime, or task complexity.
- Utilization is admission control: can this worker accept work now, and what
  should Allnighter do next?
- Capacity state is observed, sourced, timestamped, and local by default.
- iOS is a floor manager. The Mac remains the execution and run-truth owner.

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
| Utilization, admission control, worker availability, queued dispatch | `Utilization_Admission_Control.md` |
| iOS remote floor manager | `ios/README.md` |
| Feature semantics before implementation | `docs/workflows/SSOT_Feature_Workflow.md` |
| Sprint execution and closeout | `docs/operations/Execution-Playbook.md` |
| Stack and proof commands | `docs/operations/TechStack.md` |

## Retired Content

The old numbered roadmap docs that previously lived here were removed. Do not
infer active product truth from missing `XX_*.md` phase links or archived
worktree-era plans. New forward phases are added explicitly to this folder.

