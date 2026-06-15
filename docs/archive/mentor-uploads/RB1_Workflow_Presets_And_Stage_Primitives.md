# RB1 - Workflow Presets + Stage Primitives

Status: **Finalized — ready after Phase 06 + the RB0 activation gate.**
Owner: Shared Core + Mac
Created: 2026-06-14
Updated: 2026-06-14
Depends on: 06 (the run model: `Worker`, `PlanAnalysis`, `StageOutput`, tiered presets)

## Goal

Generalize the hardcoded team/synthesis presets into a fixed fanout/reduce
**workflow** over Phase 06's `StageOutput` sequence — so the same machinery can
chain reviews and a final spec. This is the preset + validation + reuse layer,
**not** a new run model (Phase 06 already laid that down) and not a general DAG.

## 05 + 06 Baseline (the foundation already exists)

RB1 is thin because Phase 06 did the heavy structural work:

- **`StageOutput` already exists** (06) and the run is already a stage sequence.
  RB1 does **not** restructure `TeamRun`; it adds new `StagePurpose` cases
  (`review`, `final_spec`, `dispatch`) and the preset machinery that schedules them.
- `PromptProfile` generalizes `SynthesisInstructionPreset` (06 already evolved it
  into the structured plan writer profile; RB1 adds the `purpose` field). There are **no
  users** — change the type to its final shape; do not keep a compatibility shim.
- `WorkflowPreset` extends `TeamPreset` with `stages`. 06's tiered team presets
  become one-/two-reduce `WorkflowPreset`s.
- **Honest profile persistence already shipped** (`StageOutput.promptProfileId`,
  from Phase 05's `SynthesisInstructionChoice`). RB1 keeps a regression test only.
- `TeamRun.presetId` (06) is the preset slot. No alias, no migration.

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

The only valid v1 stage order is (Phase 06 owns `team_fanout` → `analysis` →
`plan`; RB adds the rest):

```text
team_fanout -> analysis -> plan -> review_fanout? -> final_spec? -> handoff?
```

`WorkflowPreset` stores a named configuration of that shape. Validation rejects
unknown stage order or a review/final stage without its required prior output.

## Inputs are explicit and content-addressed (cost defense)

Every stage declares what it consumes via an `InputSelector` set, drawn from a
**fixed enum** (no free-form graph):

```text
InputSelector (closed enum, extended additively): founder_prompt | member_answers
  | plan_analysis | draft_plan | reviews | final_spec
  (RB5 adds: execution_return | outcome_score)
```

`plan_analysis` exposes Phase 06's structured `PlanAnalysis` so reviewers and
the finalizer consume consensus/contradictions/unique-insights directly, not by
re-parsing prose. The enum is closed (exhaustive switches); RB5 adds cases as a
deliberate, compiler-guided change.

### reuseKey + the reuse matrix (precise so implementation isn't guesswork)

`reuseKey = hash(promptProfileId | customInstruction, profileVersion, the resolved
input bytes for this stage's `inputSelectors`, ordered workerId list + per-worker
stance, modelLabel set)`. Before running a stage the coordinator looks for a
matching `reuseKey` (in this run, or the most recent prior run for the **same
normalized prompt** when "reuse last run" is on) and reuses on a hit
(`status: .reused`). **`reuseKey` governs *automatic* reuse only.** An explicit
**"rerun this stage"** action is a deliberate *force-fresh*: it bypasses the
reuseKey check, spends the call, and **supersedes** the prior `StageOutput` (a new
output is appended; the latest of a given purpose/lens is the active one — outputs
are append-only history). This resolves the "rerun returns the cached answer"
trap: reuse is for unchanged inputs; rerun means "I want a fresh take."

| Change the user makes | team | analysis | plan | reviews | final |
| --- | --- | --- | --- | --- | --- |
| Edit one review lens profile | reuse | reuse | reuse | rerun **that** lens | rerun |
| Edit the founder prompt | rerun | rerun | rerun | rerun | rerun |
| Toggle/add a worker | rerun changed workers | rerun | rerun | reuse | rerun |
| Edit synthesis instructions | reuse | rerun | rerun | reuse | reuse |
| Click "rerun" on a stage | — | force-fresh that stage + everything downstream | | | |

## Proposed Core Types

```text
PromptProfile                         # generalizes SynthesisInstructionPreset (06's plan writer profiles)
- id
- displayName
- purpose: plan_analysis | plan_writer | review_lens | final_spec | execution_dispatch
- profileVersion                      # bumped on built-in template change; user edits create a NEW profile id
- template
- builtIn

WorkflowPreset                        # extends TeamPreset (which already has workers: [WorkerSpec] + synthesis)
- id
- displayName
- description
- stages: [WorkflowStage]
- executionWorkerId?                  # default RB4 dispatch target — validated at DISPATCH by Doctor, NOT at save
- isDefault

WorkflowStage
- id
- kind: fanout | reduce
- displayName
- inputSelectors: [InputSelector]
- bindings: [StageBinding]            # one per profile/lens this stage runs
- optional: Bool
- wallTimeoutSeconds?                 # optional cap for the whole fanout

StageBinding                          # a (profile -> worker) assignment with its own timeout
- id
- promptProfileId
- workerId                            # the worker that runs this binding (reduces/reviews are NOT workers)
- preferFastWorker: Bool = false      # RB2 budget routing: pick fastest healthy worker instead (see RB2)
- timeoutSeconds                      # PER-binding, so a slow lens can't kill the others
- finalizerPolicy?                    # only on the final_spec reduce binding

# StageOutput + StagePayload + reuseKey are defined in Phase 06 (00 §4 / §4.1).
# RB1 adds StagePurpose cases (review | final_spec | dispatch) and turns reuseKey matching ON.

FinalizerPolicy
- reviewWeight: advisory
- conflictResolution: first_principles
- requiredSections: [String]

CallPlan                              # previewed before a run commits
- entries: [{ stageId, workerId?, workerId, lens?, willReuse: Bool }]   # workerId for team/self-fusion
- estimatedCalls: Int                 # fresh (non-reused) calls
- estimatedSeconds: Int               # from history median durationMs
- estimateNote: String                # labeled an estimate, never exact
```

**Team vs reduce bindings (resolves the worker/worker conflation).** The *team*
fanout stage uses the preset's `seats: [WorkerSpec]` (Phase 06), which expand
into `TeamRun.workers` (`Worker`s) at run start. Every *reduce* and *review*
stage instead uses `StageBinding.workerId` — a fresh single-use worker invocation,
**not** a worker (recorded as `StageOutput.producedByWorkerId`). `Worker` is
reserved strictly for the team. So "a worker bound to a review lens" is a normal
call with the lens prompt, never a reused worker.

`PromptProfile` is the generalized version of synthesis instructions. A review
lens is a prompt profile, not a second kind of worker role. **Custom inline
instructions** persist via Phase 06's `StageOutput.customInstruction` (the
`promptProfileId` is nil for that stage); a named profile sets `promptProfileId`
and leaves `customInstruction` nil — exactly one, honest. The RB1-S02 regression
test asserts this. All new Core types ship with **fixtures + round-trip tests**
(`00` §8); there are no users, so types take their final shape — no old-run gates.

**Preset validation (Bug-proofing the save/run boundary).** `WorkflowPreset`
validation runs at **two points**: (1) at **save** — reject an unknown stage
order, or a review/final stage missing its required prior output, with an inline
UI error (the preset cannot be saved invalid); (2) at **run start** — re-validate
(profiles/workers may have changed since save) and refuse to start with a clear
message. `executionWorkerId` is *not* validated at save (the worker's health is a
dispatch-time concern); the UI may show a soft "dispatch target may be unhealthy"
hint sourced from the last Doctor run.

### Perspective diversity (optional per-worker `stanceModifier`)

Phase 06 self-fusion gets diversity for free from independent sampling. RB1 adds an
*optional* amplifier: a **per-worker** stance (it lives on `WorkerSpec.stance`,
Phase 06's worker-spec — **not** on the stage, so three workers can carry three
*different* stances). Built-in stances: `neutral`, `skeptic`, `first_principles`,
`minimalist`, `user_advocate`. So Self-Double becomes
`seats: [{opus, stance: neutral}, {opus, stance: skeptic}, {opus, stance: first_principles}]`
→ three genuinely divergent workers the plan writer reconciles. The stance is a prefix on
that worker's `MemberPrompt`; assembly order is **founder prompt → stance prefix →
optional bounded context (RB6)**. Stances are visible in `PlanAnalysis`
attribution (`Opus (A) skeptic`).

## Run-State Extension (decide before code, per S06)

Keep the existing machine (`00` §4). Add only two high-level states, slotted as:

```text
draft -> fanning_out -> answers_in -> synthesizing -> complete | partial
                                                    \-> reviewing -> finalizing -> complete | partial
reviewing/finalizing -> cancelled (user stop) ; any active -> failed
```

`synthesizing` spans **both** Phase 06 reduces (analysis then plan): the run is in
`synthesizing` from analysis start until the plan stage settles. Analysis-done /
plan-failed → `partial` (the `PlanAnalysis` is usable). `reviewing` and
`finalizing` are entered only by presets that include those stages; synthesis-only
runs use the unchanged path. Dispatch (RB4) + return review (RB5) are stages on a
`complete` run, not new `RunStatus` values (`00` §4). Every new legal/illegal edge
gets an exhaustive `canTransition` test (Phase 01 style).

## Ordered Slices

- [ ] RB1-S01 - `PromptProfile` (add `purpose`/`profileVersion` to Phase 06's plan writer
  profile type) + bundled registry over `SynthesisInstructionStore`. Fixtures +
  round-trip tests. (No shim — change the type to its final shape.)
- [ ] RB1-S02 - **Verify, don't rebuild:** regression test that
  `StageOutput.promptProfileId` records the chosen profile id or explicit custom
  text. (Honesty shipped in 05/06.)
- [ ] RB1-S03 - `WorkflowPreset` (extend `TeamPreset` with `stages`) + validation
  for the fixed v1 stage order (reject unknown order or a stage missing its
  required prior output). 06's tiered presets become `WorkflowPreset`s.
- [ ] RB1-S04 - Add `StagePurpose` cases `review`/`final_spec`/`dispatch` and the
  `WorkflowStage` scheduler over Phase 06's `StageOutput`. (No `TeamRun`
  restructure — the container already exists.)
- [ ] RB1-S05 - Generic `stage.*` events (`stage.started`, `stage.output`,
  `stage.completed`, `stage.failed`, `stage.reused`) with `stageId`. No
  review-specific event family.
- [ ] RB1-S06 - Run-state extension (`reviewing`, `finalizing`) with exhaustive
  legal/illegal transition tests.
- [ ] RB1-S07 - Input assembly behind the `InputSelector` enum (incl.
  `plan_analysis`) + `reuseKey` compute/match (formula above) + the **rerun
  force-fresh** path that bypasses reuse and supersedes the prior stage output.
- [ ] RB1-S08 - `CallPlan` builder (full workflow chain; entries keyed by `workerId`
  where applicable) + live composer preview, updating as workers/depth/lenses toggle.
- [ ] RB1-S09 - Optional per-worker `WorkerSpec.stance` (built-in stances) threaded
  into `MemberPrompt` (which gains `workerId`); assembly order founder prompt → stance
  → context; attribution preserved in `PlanAnalysis`.
- [ ] RB1-S10 - `StageBinding` (per-binding worker + timeout) + two-point
  `WorkflowPreset` validation (save + run start). `executionWorkerId` validated at
  dispatch, not save.

## Works Test

```text
Run a synthesis-only WorkflowPreset. It produces the Phase 06 result: team
answers (by worker), a PlanAnalysis, master_plan.md, bundle.md, complete run. The
run.json records presetId, the analysis + plan StageOutputs, and the selected
prompt profile (id or honest custom text). Re-run the same prompt: the CallPlan
shows the team REUSED (0 fresh team calls) and only the synthesis re-runs.
Add a stanced Self-Double preset (Opus × 3 stances): three distinct workers,
attributed independently.
```

## Exit Gates

- [ ] Synthesis-only behavior matches Phase 06.
- [ ] Custom instructions persist honestly (regression test green).
- [ ] Stage events are generic; no review-specific event shapes.
- [ ] State-machine transition tests cover all new states and illegal edges.
- [ ] `reuseKey` reuse demonstrably avoids re-running unchanged stages.
- [ ] `CallPlan` shows an estimated call count before a run commits.
- [ ] New Core types have fixtures + round-trip tests (final shapes; no shims).
- [ ] `swift test` + app test wall green.

## Closeout

Activate RB2 only after the synthesis-only preset is proven. Review-board work
must reuse these stage primitives.
