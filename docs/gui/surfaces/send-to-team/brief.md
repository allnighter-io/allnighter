# Send To Team - Brief

**Tier:** D
**Visual kit:** `docs/gui/surfaces/send-to-team/mockups/`
**Behavioral owner:** `docs/phases/Team_Delegation_Surface.md`

## Purpose

The Send to team surface is the discoverable delegation map for Allnighter. It
lets the user browse or accept recommended teams, then send one team with Project
context and a prompt. It may lead to mutating work, so Execute approval remains a
separate gate owned by the Project/Work Order contract.

## States

loading - Team Card projection is being loaded.

empty - No Team Cards are available; show a catalog/contract blocker, not a blank
surface.

ready - Cards are grouped by Signal, Code, Design, Copy and can be searched,
filtered, or recommended by the Project Manager.

blocked - Cards are visible, but preflight says no ready worker or missing Project
root prevents sending.

running - A non-mutating team run has started and the surface links to the live
thread/run.

done - Team returned an Insight, board, proposal, draft, or work order draft.

failed - Team run failed; failed worker/run state is visible and recoverable.

approvalRequired - The chosen team/card is mutating and must route to Execute
approval before it can make real changes.

## Intents

- Open Send to team -> load Team Card projection for current Project.
- Change family -> filter cards by `family`.
- Search -> filter card title, promise, starter prompts, and recommendations.
- Pick Team Card -> show card detail, requirements, lineup summary, and starter
  prompts.
- Ask Project Manager to choose -> create a recommendation turn; do not run.
- Send team -> preflight, then start non-mutating `team.run`.
- Save Pending -> create Project-scoped Pending item for the selected card/prompt.
- Execute -> route mutating proposal/work order to approval; never bypass.
- Recheck workers -> run declared safe readiness probes only.

## Field Ownership Ledger

| GUI field | Core model field | Source | States it appears in | Test owner |
| --- | --- | --- | --- | --- |
| Family tabs | `TeamCard.family` | `AllnighterCore.TeamCard` projection | ready, blocked | Core projection test |
| Card title | `TeamCard.displayName` | `TeamCatalog` via `TeamCard` | ready, blocked, detail | Core projection test |
| Card promise | `TeamCard.promise` | `TeamCard` | ready, detail | Core projection test |
| Pinned flag | `TeamCard.pinned` + `pinnedReason` | `TeamCard` | ready | Core projection test |
| Recommended reason | `projectFitReason` | Project Manager recommendation receipt | ready, detail | Project Manager tests |
| Output label | `TeamCard.outputKind` | `TeamCard` / team definition | ready, detail | Core projection test |
| Posture label | `TeamCard.posture` | `TeamCard` | detail, approvalRequired | Core projection test |
| Mutating label | `TeamCard.mutating` | `TeamCard` | detail, approvalRequired | Core + GUI presenter test |
| Requirements | `TeamCard.requirements[]` | `TeamCard` + Project worker readiness | detail, blocked | Readiness/preflight tests |
| Starter prompts | `TeamCard.starterPrompts[]` | `TeamCard` | detail | Core projection test |
| Worker count | Derived from Team definition worker rows | `TeamCatalog` / resolved preflight | ready, detail | Presenter test |
| Ready worker status | `ProjectWorkerReadiness.status` | Project readiness contract | blocked, ready | Project readiness tests |
| Last run | `TeamCard.lastRunAt` | Team run history projection | ready, detail | History projection test |
| Next actions | `TeamCard.nextActions[]` or result next actions | Core result contract | done, detail | Contract schema test |
| Live run status | `TeamRunJSON.teamRun.status` | `TeamRunJSON` | running, done, failed | Team run tests |
| Failure | `TeamRunJSON.errors[]` / `workerAnswers[].error` | `TeamRunJSON` | failed | Team run tests |

Rule: if `TeamCard` does not exist yet, the GUI implementation must stop at the
contract gap. Do not hard-code the mockup card data in SwiftUI.

## Layout Notes

- Use sentence case in production labels.
- Use `Signal`, `Code`, `Design`, `Copy` as the public family names.
- Use `Send to team` for the primary non-mutating action.
- Use `Execute` only for approval of mutating work.
- Do not use `Workflow`, `Template`, `Fan out`, or `Build` as public labels.
- Cards are repeated items. Do not nest cards inside cards.
- Amber is reserved for the selected/recommended team and the primary action.

## Mockups

Static HTML variants live in `mockups/`:

- `variant-a-pm-recommended.html`
- `variant-b-team-map.html`
- `variant-c-composer-sheet.html`

These are visual/product exploration artifacts. They are not implementation
truth. SwiftUI must bind to the Core contracts above.

