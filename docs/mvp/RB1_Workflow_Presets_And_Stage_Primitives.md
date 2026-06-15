# RB1 - Workflow Presets + Stage Primitives

Status: **Finalized — ready after RB0 activation gate.**
Owner: Shared Core + Mac
Created: 2026-06-14
Updated: 2026-06-14
Depends on: 05 (shipped: presets, honest persistence, `panelPresetId`)

## Goal

Replace the hardcoded "panel then synthesis" orchestration with a fixed
fanout/reduce stage model that can still run today's synthesis-only workflow
unchanged. This is the foundation for review and final spec stages, not a
general workflow engine.

## Phase 05 Baseline (start here, don't restart)

This slice **extends** shipped types rather than inventing parallels:

- `PromptProfile` generalizes `SynthesisInstructionPreset` (add a `purpose`
  field; keep the old type as a typealias/shim and keep decoding old preset
  files). `SynthesisInstructionStore` becomes the profile registry.
- `WorkflowPreset` extends `PanelPreset` (add `stages`; a `PanelPreset` is a
  one-reduce `WorkflowPreset`). `PanelPresetStore` migrates to the preset store.
- **RB1-S02 is already implemented** in Phase 05 via `SynthesisInstructionChoice`:
  `Synthesis.instructions` records the chosen preset id or literal custom text.
  RB1 keeps a **regression test** for this and threads the same honesty through
  `StageOutput.promptProfileId`; it does not re-do the fix.
- `CouncilRun.panelPresetId` already exists and decodes old runs — reuse it as
  the `workflowPresetId` slot (rename via a coding-key alias, not a new field).

## Non-Goals

- No review board UI yet.
- No final spec stage yet.
- No execution handoff.
- No arbitrary DAG, conditionals, loops, or user-authored stage graph.
- No new on-disk path scheme — stages persist under the existing `Runs/` and
  `Config/` tree (`AllnighterPaths`).

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

## Inputs are explicit and content-addressed (cost defense)

Every stage declares what it consumes via an `InputSelector` set, drawn from a
**fixed enum** (no free-form graph):

```text
InputSelector: founder_prompt | member_answers | draft_plan | reviews | final_spec
```

Each stage output carries a `reuseKey` = hash of (promptProfileId + profileVersion
+ resolved input bytes + workerId + modelLabel). Before running a stage the
coordinator checks the current run (and an explicit "reuse last run for this
prompt" option) for a matching `reuseKey`; on a hit it reuses the output instead
of spending a call. This is what makes editing one lens cheap and re-running the
finalizer free of a fresh panel fan-out (RB0 "Reuse over re-run" law).

## Proposed Core Types

```text
PromptProfile                         # generalizes SynthesisInstructionPreset
- id
- displayName
- purpose: draft_synthesis | review_lens | final_spec | execution_dispatch
- profileVersion
- template
- builtIn

WorkflowPreset                        # extends PanelPreset
- id
- displayName
- description
- stages: [WorkflowStage]
- executionWorkerId?                  # default RB4 dispatch target
- isDefault

WorkflowStage
- id
- kind: fanout | reduce
- displayName
- inputSelectors: [InputSelector]
- promptProfileBindings               # lensId/profileId -> binding
- workerBindings                      # bindingId -> workerId
- optional: Bool
- timeoutSeconds
- finalizerPolicy?

StageOutput
- id
- stageId
- workerId?
- promptProfileId
- reuseKey                            # content address for reuse/resume
- status: queued|running|done|failed|timed_out|skipped|reused
- markdown
- errorReason?
- startedAt / finishedAt

FinalizerPolicy
- reviewWeight: advisory
- conflictResolution: first_principles
- requiredSections: [String]

CallPlan                              # previewed before a run commits
- entries: [{ stageId, workerId, lens?, willReuse: Bool }]
- estimatedCalls: Int                 # fresh (non-reused) calls
- estimateNote: String                # labeled an estimate, never exact
```

`PromptProfile` is the generalized version of synthesis instructions. A review
lens is a prompt profile, not a second kind of worker role. All new Core types
ship with JSON **fixtures + round-trip tests** and an **old-run decode test**
(contract-first, per `00` §7–8), exactly as Phase 05 did for `PanelPreset`.

## Run-State Extension (decide before code, per S06)

Keep the existing machine (`00` §4). Add only two high-level states, slotted as:

```text
draft -> fanning_out -> answers_in -> synthesizing -> complete | partial
                                                    \-> reviewing -> finalizing -> complete | partial
reviewing/finalizing -> cancelled (user stop) ; any active -> failed
```

`reviewing` and `finalizing` are entered only by presets that include those
stages; synthesis-only runs use the unchanged path and terminal states. Every
new legal and illegal edge gets an exhaustive `canTransition` test (Phase 01
style). `partial` still means "usable despite a dead stage" — a finalizer that
fails leaves the draft plan + reviews intact.

## Ordered Slices

- [ ] RB1-S01 - `PromptProfile` model + bundled registry by generalizing
  `SynthesisInstructionPreset` (add `purpose`/`profileVersion`; keep the old type
  as a shim and keep decoding existing preset files). Ship fixtures + round-trip
  tests.
- [ ] RB1-S02 - **Verify, don't rebuild:** add a regression test that
  `Synthesis.instructions` / `StageOutput.promptProfileId` records the chosen
  profile id or explicit custom text. (Honest roundtrip shipped in Phase 05 via
  `SynthesisInstructionChoice`.)
- [ ] RB1-S03 - `WorkflowPreset` by extending `PanelPreset` with `stages`; ship a
  synthesis-only built-in preset and validation for the fixed v1 stage order
  (reject unknown order or a stage missing its required prior output).
- [ ] RB1-S04 - Extend `CouncilRun` with structured `StageOutput` storage and
  reuse `panelPresetId` as `workflowPresetId` (coding-key alias), preserving old
  run decode (explicit test).
- [ ] RB1-S05 - Add generic `stage.*` events (`stage.started`, `stage.output`,
  `stage.completed`, `stage.failed`, `stage.reused`) with `stageId` in payload.
  No review-specific event family.
- [ ] RB1-S06 - Land the run-state extension above (`reviewing`, `finalizing`)
  with exhaustive legal/illegal transition tests.
- [ ] RB1-S07 - Centralize input assembly behind the `InputSelector` enum and
  compute each stage's `reuseKey`; the coordinator reuses a matching output
  instead of spending a call.
- [ ] RB1-S08 - `CallPlan` builder + composer preview (count + estimate, labeled)
  so a run's cost is visible before it commits.
- [ ] RB1-S09 - Update `RunStore` / `RunMarkdown` so `run.json` is truth and
  derived artifacts remain backward-compatible (`master_plan.md`, `bundle.md`).

## Works Test

```text
Run the current synthesis-only workflow through a WorkflowPreset. It produces the
same visible result as Phase 04: panel answers, master_plan.md, bundle.md, and a
complete run. The saved run.json records workflowPresetId, the draft synthesis
StageOutput, and the selected prompt profile (id or honest custom text). Re-run
the same prompt: the composer's CallPlan shows the panel will be REUSED (0 fresh
panel calls) and only the synthesis re-runs. An old Phase 04 run still opens.
```

## Exit Gates

- [ ] Existing synthesis-only behavior is unchanged.
- [ ] Custom synthesis instructions persist honestly (regression test green).
- [ ] Stage events are generic and do not add review-specific event shapes.
- [ ] State-machine transition tests cover all new states and illegal edges.
- [ ] `reuseKey` reuse demonstrably avoids re-running unchanged stages.
- [ ] `CallPlan` shows an estimated call count before a run commits.
- [ ] New Core types have fixtures + round-trip tests; old saved runs decode.
- [ ] `swift test` + app test wall green.

## Closeout

Activate RB2 only after the synthesis-only preset is proven. Review-board work
must reuse these stage primitives.
