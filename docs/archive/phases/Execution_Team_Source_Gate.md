# Execution Team Source Gate

Archived: 2026-06-19
Status: **Complete** - ETS-S00 through ETS-S07 built and archived.
Owner: Founder + AllnighterCore + CLI/MCP + Mac app
Updated: 2026-06-19

Successor owners:

- `docs/phases/Work_Order_Team_Model.md` owns the durable product/model law.
- `docs/phases/Project_Spine_And_Project_Manager.md` owns mutating dispatch gates.
- `docs/phases/CLI_Implementation_Contract.md` owns shared error-contract shape.
- Core implementation owns `ExecutionTeamSourceGate`,
  `ProjectMutatingDispatchEvaluator`, and related tests.

## Archive Note

This phase is historical proof and implementation detail. Do not route new work
through this archived file. Use the successor owners above for active truth.

## Authority At Build Time

Read with:

- `docs/phases/Language_Cutover.md`
- `docs/phases/Work_Order_Team_Model.md`
- `docs/phases/Team_Delegation_Surface.md`
- `docs/phases/Project_Spine_And_Project_Manager.md`
- `docs/phases/CLI_Implementation_Contract.md`
- `docs/operations/Execution-Playbook.md`

`Language_Cutover.md` owns vocabulary. This doc owns the execution-team source
law: mixed-source teams are allowed for judgment; mutating or `execute` posture
teams must resolve to one source/driver before anything can write.

## Founder Intent

Allnighter's primary team value is heterogeneous judgment: different models,
skills, sources, blind spots, and tool affordances harden the spec before work is
made real.

Execution is different. When a team is allowed to mutate the Project, concurrent
execution across Claude Code, Codex, Grok, Gemini, Cursor, or another independent
CLI is where codebases can diverge quickly. Allnighter should not compete by
owning a hidden multi-workspace write orchestration problem.

Product law:

```text
Judgment can be mixed-source.
Execution is single-source.
```

The user may still get a rich multi-role execution team. The roles live inside
one coherent CLI/source: one permission model, one Project readiness contract,
one working directory, one driver, one return.

## Product Value

This preserves the sharp Allnighter wedge:

- Use multiple CLIs for review, proposal, option generation, design critique,
  copy alternatives, Signal interpretation, and spec hardening.
- Turn the chosen result into one work order.
- Execute through one selected source/driver that owns the mutating session.

Power users still get reusable execution teams, such as a Codex code team or a
Claude Code release team, with multiple skills and stages. They do not get
uncoordinated concurrent writes from unrelated agent runtimes.

## Trusted Workflow Slice

```text
open Project
-> Chat with Project Manager or Send to team
-> run a mixed-source Code review/proposal team
-> inspect the returned plan, risks, and work-order draft
-> choose Execute
-> pick or confirm one execution source
-> dispatch one source-owned execution team
-> receive one return
-> verify with proof
```

Direct execution teams are legal only when their resolved worker lineup is
already single-source:

```text
Code / Codex Implementation Team
  First Principles on GPT-5 via Codex
  Maintainer on GPT-5 via Codex
  Proof Skeptic on GPT-5 via Codex
```

## Non-Goals

- No hidden multi-workspace or multi-branch execution manager.
- No concurrent mutating writes by multiple independent CLIs against one Project.
- No silent fallback to "pick the first ready source."
- No automatic source reauthorizing, trust-prompt accepting, or permission setup.
- No new peer lane. Execution teams still belong to Code, Design, or Copy.
- No new `Execute` mode. Execute remains the user's approval action.
- No cost, runtime, quota, or task-complexity estimates.

## Current State

Exists:

- `TeamPreset`, `TeamCard`, `TeamRun`, and floor projections carry `posture` and
  `mutating`.
- Mutating teams require Execute approval at the product layer.
- Project dispatch gates check Project root, approval, dirty state, worker
  readiness, proof, and privacy posture.
- Execution lane serialization reduces directory-level collision risk.
- Work orders can reveal exact handoff text or dispatch to a target worker.

Missing:

- A first-class rule that execution teams must be single-source.
- Resolver/preflight validation that blocks mixed-source mutating teams.
- Team authoring guidance for source-scoped execution teams.
- CLI/MCP error contracts for mixed-source execution blockers.
- Mac UI treatment that distinguishes mixed-source judgment teams from
  source-scoped execution teams.

Execution lane serialization is useful lower-level safety. It is not the product
authorization model and must not be treated as permission to spawn a mixed-source
mutating team.

## Truth Owner

Core owns the policy and the resolved facts:

```text
AllnighterCore
  TeamCatalog / TeamPreset
  TeamResolver / TeamRequestResolver
  Team preflight projection
  Project dispatch gate evaluator
  TeamRunJSON / future team.run result warnings and blockers
```

Mac, CLI, MCP, and iOS render the Core decision. They must not invent their own
mixed-source execution policy.

## Lie-Prone Layers

| Layer | Tempting lie | Required truth |
| --- | --- | --- |
| Team catalog | A good team can always mix the best workers. | Mixed sources are for non-mutating judgment. Execution teams are source-scoped. |
| Team editor | Toggling `mutating` is just metadata. | Saving an execution-capable team with multiple sources is blocked. |
| Project Manager | A strong mixed review answer can become dispatch automatically. | Mixed review output becomes a work order; dispatch picks one source. |
| CLI/MCP | The caller asked to run, so run what was requested. | Preflight blocks mixed-source execution before spawn. |
| Mac UI | Hide source details to keep the surface clean. | Execution approval shows the source that will mutate the Project. |
| Execution lane | Serialization makes mixed execution safe. | Serialization is collision control, not a mixed-source execution contract. |

## New Semantic Rules

### 1. Gate Trigger

The source gate applies when any of these are true:

- resolved team `posture == execute`;
- resolved team `mutating == true`;
- Team Card `mutating == true`;
- Work Order mode is `dispatch` and can mutate Project files or external state;
- Pending, MCP, CLI, Mac, or iOS attempts to start a previously approved
  mutating team run;
- a next action would invoke a mutating target.

V1 implementation can start with the hard Core predicate:

```text
team.posture == .execute || team.mutating == true
```

Project dispatch then applies the same policy before invoking a worker.

### 2. Single-Source Invariant

After model and worker resolution, every active worker participating in a
mutating execution team must share the same `sourceId` and driver.

Allowed:

```text
Codex as Implementer
Codex as Maintainer
Codex as Proof Skeptic
```

Allowed when one driver exposes multiple model choices through the same source:

```text
Claude Code / Opus as Architect
Claude Code / Sonnet as Editor
Claude Code / Sonnet as Proof Skeptic
```

Blocked:

```text
Claude Code as Architect
Codex as Implementer
Grok as Reviewer
mutating: true
```

`modelId` is not enough. The gate is source/driver coherence: the same CLI
runtime boundary, Project readiness contract, permission posture, and mutating
execution owner.

If one vendor integration has multiple spawn modes that cannot share the same
working-directory and permission semantics, those modes are distinct sources for
this gate.

### 3. Judgment Teams Stay Mixed

Teams with non-mutating `scout`, `propose`, or `review` posture may resolve to
multiple sources. That is the point of Allnighter's judgment layer.

Mixed-source judgment teams may return:

- Insights;
- options;
- review findings;
- plans;
- design boards;
- copy alternatives;
- work-order drafts;
- risk lists;
- proof recommendations.

They must not write Project files, change external state, or dispatch mutating
subprocess work.

### 4. Execution Teams Are Source-Scoped

An execution team is not a new lane. It is a Code, Design, or Copy team whose
posture/mutating state allows make-real work after Execute approval.

Execution team authoring rules:

- choose lane first;
- choose execution source before worker rows;
- filter model choices to that source;
- allow multiple skills on one model;
- allow multiple models only when they are available through the same source;
- block save if `mutating == true` or `posture == execute` and resolved source
  count is greater than one.

Built-in execution teams should be source-scoped variants, not one mixed-source
team that sometimes happens to resolve safely:

```text
Code / Codex Implementation Team
Code / Claude Code Implementation Team
Code / Cursor Agent Implementation Team
```

The display can be friendlier, but the Core fact is `executionSourceId`.

### 5. Block, Do Not Degrade

A mixed-source execution team is rejected before any worker spawns.

The system must not:

- run the non-mutating workers and skip the rest;
- silently pick one source;
- silently flip the team to non-mutating;
- create hidden isolated workspaces to make it work;
- dispatch separate CLIs sequentially and call that one execution team.

Canonical blocker:

```text
Execution teams run on one CLI. This team resolves to Claude Code and Codex.
Pick one execution source, or run it as a non-mutating review/proposal team first.
```

### 6. Legal Repairs

When the gate blocks, Core should offer typed repair paths:

- switch to non-mutating review/propose posture;
- choose one execution source and remap worker rows to that source;
- split into a two-step flow: mixed-source judgment team, then single-source
  execution team;
- reveal the work order without dispatching.

Repair suggestions are options. They do not auto-run.

### 7. Project Readiness Is Per Source

After the single-source gate passes, Project dispatch still requires that source
to be ready in the selected Project root.

The readiness rule from `Project_Spine_And_Project_Manager.md` remains:

```text
A ready worker from one CLI does not authorize or configure another CLI.
```

This doc adds:

```text
A ready worker from one CLI cannot carry a mixed-source execution team.
```

### 8. Work Orders Target One Execution Owner

Mutating Work Orders must identify one execution owner:

```text
targetSourceId
targetAgent?
targetWorkerId?
executionTeamId?
```

The handoff prompt may include multiple roles, stages, and skill instructions,
but dispatch invokes one source/driver. The worker return is one return from that
execution owner, later verified by Allnighter.

### 9. Agent-Originated Runs Follow The Same Gate

MCP, CLI, local API, and future iOS clients cannot bypass this policy. External
agents may request a mutating team run, but Core preflight returns the same
blocker and repair options when the resolved team is mixed-source.

Agent-originated approval still follows the Project approval policy. This source
gate is additional, not a replacement.

## Duplicate Truth To Delete

Do not add independent mixed-execution rules in:

- SwiftUI Team Card rendering;
- generated CLI help prose;
- MCP tool descriptions;
- Project Manager prompts;
- built-in team copy.

Those surfaces should link to or project Core policy. If they need user-facing
copy, generate it from the preflight blocker or a shared error descriptor.

## Implementation Impact

Core:

- Ensure resolved workers expose `sourceId`, `sourceDisplayName`, and `driverId`.
- Add an `ExecutionTeamSourceGate` or equivalent pure policy evaluator.
- Add preflight output fields:

```text
executionSourcePolicy: mixedAllowed | singleSourceRequired
resolvedSourceIds[]
executionSourceId?
sourceGateStatus: pass | blocked
sourceGateBlocker?
repairOptions[]
```

- Add structured error/blocker code, e.g. `EXECUTION_TEAM_MIXED_SOURCES`.
- Run the policy in `TeamResolver`/`TeamRequestResolver` after worker resolution
  and before any `WorkerRunner` spawn.
- Run the same policy in Project dispatch gates before worker readiness is treated
  as sufficient.
- Keep run snapshots honest: if a mutating run starts, its `executionSourceId`
  is present and its worker source set has one value.

Team catalog:

- Mark execution-capable built-ins as source-scoped.
- Block custom execution team saves when rows resolve to multiple sources.
- Keep mixed-source built-ins non-mutating unless they are split into
  source-scoped variants.

CLI/MCP:

- `team preflight`, `team run`, Project dispatch, Pending run, and MCP team tools
  return the same structured blocker.
- Machine modes return JSON errors/warnings only on the correct streams.
- Generated docs mention the source gate only through registry-owned command
  descriptors and error descriptors.

Mac:

- Team editor chooses/locks execution source before worker rows for execution
  teams.
- Execute approval shows the source that will mutate the Project.
- Mixed-source review/proposal teams remain normal and valuable.
- Blocked execution teams show repair options instead of a dead end.

iOS:

- Future iOS renders the same preflight and approval facts from the Mac/Core
  contract. It does not add a mobile-only execution policy.

## Ordered Slices

- [x] **ETS-S00 - Spec routing (DONE 2026-06-19).** Added this doc to
  `docs/phases/README.md` and `AGENTS.md` as the top active gate. No code.
- [x] **ETS-S01 - Core source facts (DONE 2026-06-19).** Resolved team workers
  and run snapshots expose `resolvedSourceIds`, `executionSourceId`, and per-worker
  `sourceId` in preflight.
- [x] **ETS-S02 - Core preflight gate (DONE 2026-06-19).** `ExecutionTeamSourceGate`
  evaluator, structured blocker/repairs, and WT-ETS01–03 tests.
- [x] **ETS-S03 - Catalog authoring (DONE 2026-06-19).** Source-scoped execution
  built-ins; `TeamCatalog.validateExecutionSourceGate` blocks mixed custom saves.
- [x] **ETS-S04 - Dispatch and agent surfaces (DONE 2026-06-19).** Preflight,
  `AsyncTeamService`, `TeamService`, and contract error `EXECUTION_TEAM_MIXED_SOURCES`.
- [x] **ETS-S05 - Mac treatment (DONE 2026-06-19).** Team editor mutating toggle,
  source conflict messaging, execution source on mutating cards.
- [x] **ETS-S06 - Proof wall (DONE 2026-06-19).** `ExecutionTeamSourceGateTests`,
  contract export, `swift test --package-path Packages/AllnighterCore`.
- [x] **ETS-S07 - Project dispatch substrate (DONE 2026-06-19).**
  `ProjectMutatingDispatchEvaluator` composes source gate, dirty-state gate, and
  per-Project worker readiness for PRJ-S11; `WorkOrderBuilder` stamps execution
  targets; Pending and Mac Execute refuse mixed-source mutating dispatch.

## Closeout

The execution source gate is built and no longer a live phase:

- mixed-source judgment teams still pass;
- mutating/`execute` teams resolve to exactly one source/driver or block before
  spawn;
- source-scoped execution built-ins and custom-team save validation are in Core;
- Project mutating dispatch composes the source gate before dirty-state and
  worker-readiness gates;
- Pending run, CLI/MCP, and Mac Execute paths surface the same blocker.

Focused proof:

```bash
swift test --package-path Packages/AllnighterCore --disable-sandbox --filter 'ExecutionTeamSourceGateTests|ProjectMutatingDispatchGateTests|WorkOrderBuilderTests'
```

Result on archive closeout: 16 tests passed, 0 failures.

## Works Tests

### WT-ETS01 - Mixed-source judgment team is allowed

Setup:

```text
Team resolves to Claude Code + Codex.
posture: review
mutating: false
```

Gesture:

```text
Run preflight and then run the team.
```

Assertions:

- Source gate status is `pass`.
- Run starts as non-mutating.
- Result contains worker answers and no mutating next action starts
  automatically.

### WT-ETS02 - Mixed-source execution team is blocked

Setup:

```text
Team resolves to Claude Code + Codex.
posture: execute
mutating: true
```

Gesture:

```text
Run preflight or attempt dispatch.
```

Assertions:

- No worker process spawns.
- Blocker code is `EXECUTION_TEAM_MIXED_SOURCES`.
- Blocker names both resolved sources.
- Repair options include single-source selection and non-mutating review/propose.

### WT-ETS03 - Single-source execution team can proceed to normal gates

Setup:

```text
Team resolves to Codex only.
posture: execute
mutating: true
Project root is available.
Codex readiness is ready for the Project.
Approval and proof are present.
```

Gesture:

```text
Dispatch approved work order.
```

Assertions:

- Source gate passes with `executionSourceId == codex` or equivalent.
- Project dispatch continues to dirty-state, readiness, proof, and privacy gates.
- Exactly one source/driver is invoked.

### WT-ETS04 - Team editor blocks unsafe save

Gesture:

```text
Create a custom team with Claude Code and Codex worker rows.
Toggle mutating true or posture execute.
Save.
```

Assertions:

- Save is blocked.
- UI names the source conflict.
- User can pick one source or keep the team non-mutating.

### WT-ETS05 - MCP and CLI agree

Gesture:

```text
Call CLI preflight and MCP preflight for the same mixed-source execution team.
```

Assertions:

- Both return the same blocker code.
- Both return the same resolved source list.
- Neither starts a run.

## Proof Command

Archive closeout proof:

```bash
swift test --package-path Packages/AllnighterCore --disable-sandbox --filter 'ExecutionTeamSourceGateTests|ProjectMutatingDispatchGateTests|WorkOrderBuilderTests'
git diff --check -- AGENTS.md docs/phases/README.md docs/phases/Work_Order_Team_Model.md docs/phases/Project_Spine_And_Project_Manager.md docs/phases/CLI_Implementation_Contract.md docs/archive/phases/README.md docs/archive/phases/Execution_Team_Source_Gate.md
```

The focused test command passed with 16 tests and 0 failures during archive
closeout. The first attempt without `--disable-sandbox` failed before test
execution because SwiftPM's own `sandbox-exec` was not permitted in this Codex
sandbox.
