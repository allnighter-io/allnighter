# RB1 - Workflow Presets + Stage Primitives

Status: Draft
Owner: Shared Core + Mac
Depends on: 05

## Goal

Replace the hardcoded "panel then synthesis" orchestration with a fixed
fanout/reduce stage model that can still run today's synthesis-only workflow
unchanged. This is the foundation for review and final spec stages, not a
general workflow engine.

## Non-Goals

- No review board UI yet.
- No final spec stage yet.
- No execution handoff.
- No arbitrary DAG, conditionals, loops, or user-authored stage graph.

## Design

All stages are one of two kinds:

```text
fanout: run many workers in parallel with stage-specific prompt profiles
reduce: run one worker over assembled inputs with one prompt profile
```

The only valid v1 stage order is:

```text
panel_fanout -> draft_synthesis -> review_fanout? -> final_spec? -> handoff?
```

`WorkflowPreset` stores a named configuration of that shape. Validation rejects
unknown stage order or a review/final stage without its required prior output.

## Proposed Core Types

```text
PromptProfile
- id
- displayName
- purpose: draft_synthesis | review_lens | final_spec | execution_dispatch
- profileVersion
- template
- builtIn

WorkflowPreset
- id
- displayName
- description
- stages: [WorkflowStage]
- default

WorkflowStage
- id
- kind: fanout | reduce
- displayName
- inputSelector
- promptProfileBindings
- workerBindings
- optional
- finalizerPolicy?

StageOutput
- id
- stageId
- workerId?
- promptProfileId
- status
- markdown
- errorReason?
- startedAt
- finishedAt

FinalizerPolicy
- reviewWeight: advisory
- conflictResolution: first_principles
- requiredSections
```

`PromptProfile` is the generalized version of synthesis instructions. A review
lens is a prompt profile, not a second kind of worker role.

## Ordered Slices

- [ ] RB1-S01 - `PromptProfile` model + bundled registry. Migrate the built-in
  `default_master_plan_v1` synthesis instruction into a profile while keeping
  existing constants as compatibility shims if useful.
- [ ] RB1-S02 - Fix the synthesis instruction roundtrip: `run.json` records the
  chosen profile id or explicit custom instruction, not always
  `default_master_plan_v1`.
- [ ] RB1-S03 - `WorkflowPreset` model with a synthesis-only built-in preset and
  validation for the fixed v1 stage order.
- [ ] RB1-S04 - Extend `CouncilRun` with `workflowPresetId` and structured
  `StageOutput` storage while preserving old run decode.
- [ ] RB1-S05 - Add generic `stage.*` events (`stage.started`,
  `stage.output`, `stage.completed`, `stage.failed`) with `stageId` in payload.
- [ ] RB1-S06 - Decide the run-state extension before code: keep existing states
  and add only the high-level states needed for later slices (`reviewing`,
  `finalizing`), with exhaustive transition tests.
- [ ] RB1-S07 - Centralize input assembly with explicit input selectors:
  prompt, member answers, draft plan, reviews, final spec.
- [ ] RB1-S08 - Update `RunStore` / `RunMarkdown` so `run.json` is truth and
  derived artifacts remain backward-compatible (`master_plan.md`, `bundle.md`).

## Works Test

```text
Run the current synthesis-only workflow through a WorkflowPreset. It produces the
same visible result as Phase 04: panel answers, master_plan.md, bundle.md, and a
complete run. The saved run.json also records workflowPresetId, the draft
synthesis stage output, and the selected prompt profile. An old Phase 04 run
still opens.
```

## Exit Gates

- [ ] Existing synthesis-only behavior is unchanged.
- [ ] Custom synthesis instructions persist honestly.
- [ ] Stage events are generic and do not add review-specific event shapes.
- [ ] State-machine transition tests cover all new states and illegal edges.
- [ ] Old saved runs decode.
- [ ] `swift test` + app test wall green.

## Closeout

Activate RB2 only after the synthesis-only preset is proven. Review-board work
must reuse these stage primitives.
