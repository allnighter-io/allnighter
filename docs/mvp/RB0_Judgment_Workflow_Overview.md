# RB0 - Judgment Workflow Overview

Status: **Finalized — ready to activate after the RB0 activation gate passes.**
Owner: Founder + Shared Core + Mac
Created: 2026-06-14
Updated: 2026-06-14
Depends on: 05 (shipped: S01–S05)

## Who This Is For (the 10x thesis)

The user is a **vibe coder**: someone who ships by directing AI agents, not by
hand-writing most lines. Their bottleneck is no longer typing — it is **deciding
correctly and handing the agent an unambiguous, pressure-tested brief.** A vague
prompt to a coding agent yields confident, wrong code fast.

Allnighter's judgment workflow is the 10x lever: it turns **one prompt** into a
**decision-grade implementation spec** that has already survived a panel of
strong models and a board of adversarial review lenses — then routes that spec
straight into the executor CLI. The vibe coder presses go *once* and trusts the
output because they can see what was challenged, adopted, and rejected, and why.

> One prompt in. A pressure-tested spec out, then into the agent that builds it.
> Zero copy/paste. Nothing hidden.

## Founder Intent

The founder wants Allnighter to automate the whole judgment ritual, not only the
first synthesis:

```text
one prompt
-> independent panel answers
-> configurable draft synthesis
-> configurable advisory review from named lenses
-> first-principles final implementation spec
-> optional handoff to a chosen executor
```

Mentor feedback is advisory input. This doc is the product decision.

## Product Value

Allnighter should turn one prompt into a pressure-tested implementation spec
without copy/paste, while avoiding hidden product truth such as "Opus always
synthesizes" or "security feedback is binding."

The daily preset remains today's fast loop. Review and finalization are opt-in
workflow presets for higher-stakes decisions. The win is measured, not asserted:

| Signal | Synthesis-only (today) | Review-board target |
| --- | --- | --- |
| Copy/paste actions | 0 | 0 |
| Clicks: prompt → executable spec | 1 (master plan) | 1 (final spec) |
| Decision confidence | "one model's read" | "survived N lenses; decisions visible" |
| Spec is executable | Sometimes | Always (carries Works Test + proof commands) |
| Hidden product truth | None | None (advisory ≠ binding; synthesizer explicit) |

## CTO Decision

Build a fixed v1 judgment chain from two primitives:

```text
Fanout: run N workers in parallel over one assembled prompt.
Reduce: run 1 worker over assembled inputs and produce one canonical artifact.
```

The v1 chain is fixed:

```text
panel_fanout -> draft_synthesis -> optional_review_fanout
-> optional_final_spec -> optional_direct_dispatch
```

Do not build a general DAG engine in v1. Configure the participants,
instructions, review lenses, and worker bindings inside this shape.

## What Phase 05 Already Shipped (build on, do not rebuild)

The review-board milestone is **not** starting from Phase 04. Phase 05 landed the
preset and honesty substrate the RB chain extends:

| Phase 05 artifact | RB milestone reuses it as |
| --- | --- |
| `SynthesisInstructionPreset` + `SynthesisInstructionStore` | The seed of `PromptProfile` (RB1 generalizes it; keep a compatibility shim). |
| `SynthesisInstructionChoice` (honest `Synthesis.instructions`) | RB1-S02 is **already done** — `run.json` records the chosen preset id or literal custom text, never always `default_master_plan_v1`. RB1 verifies, not re-implements. |
| `PanelPreset` (+ `PanelPresetStore`) | The seed of `WorkflowPreset` (RB1 extends it with `stages`). |
| `CouncilRun.panelPresetId` (optional, decodes old runs) | The forward-compatible slot for `workflowPresetId`. |
| `Doctor` / `WorkerDiagnosis` | RB4 gates dispatch on a healthy headless worker and reuses the fix-hint vocabulary. |
| `AllnighterPaths` (`Runs/`, `Config/`) | RB stores land under the same tree; no new path scheme. |
| `RunStore` / `RunMarkdown` artifact contract | RB adds sibling artifacts; `run.json` stays truth, `master_plan.md`/`bundle.md` stay backward-compatible. |

> Migration rule: `PromptProfile` **subsumes** `SynthesisInstructionPreset` and
> `WorkflowPreset` **subsumes** `PanelPreset`. Prefer evolving these types (add
> fields, keep decoding old files) over introducing parallel duplicates.

## Core Vocabulary

| Term | Meaning |
| --- | --- |
| `Worker` | Existing executor endpoint: local CLI + model label + driver manifest. |
| `PromptProfile` | Versioned, editable prompt template used by a stage. Review lenses and synthesis instructions are both prompt profiles. Generalizes Phase 05's `SynthesisInstructionPreset`. |
| Review lens | User-facing name for a `PromptProfile` whose purpose is `review_lens`. |
| `WorkflowPreset` | A named binding of stage shape, workers, prompt profiles, and defaults. Extends Phase 05's `PanelPreset` with `stages`. |
| `WorkflowStage` | One ordered fanout or reduce unit inside the fixed chain. |
| `StageOutput` | Structured run truth for one stage output; Markdown files are derived views. |
| `FinalizerPolicy` | Structured rule telling the final spec stage how to treat reviews. v1 ships `advisory` + `first_principles`. |
| `ImplementationBrief` | Handoff artifact created from a final spec or master plan before dispatch. |
| `CallPlan` | The previewed list of model calls a run will make (stage → worker → lens), with a rough quota/latency estimate, shown before the user commits. |

Keep `WorkerRole` narrow. It remains the existing structural capability:
`member`, `synthesizer`, or `both`. It is not a reviewer persona.

## Product Laws For This Milestone

- Workers execute; prompt profiles shape judgment; presets bind them.
- Review feedback is advisory by default and must not mutate the draft artifact.
- The finalizer owns the final spec and must decide from first principles.
- `run.json` owns truth; Markdown artifacts are generated for humans and agents.
- Every stage degrades gracefully. Partial review beats a blocked run.
- The review board is optional per preset. Synthesis-only remains supported.
- The UI renders and edits presets; it must not invent workflow semantics.
- Direct executor dispatch is in scope: Allnighter may invoke the selected CLI in
  the configured working directory.
- Managed execution safety is out of scope: no Allnighter-owned worktrees,
  branch policy, commit rules, landing, revert, or protected-path enforcement.
- **Cost is never silent.** A heavier preset can fan out a dozen+ model calls.
  The composer must show the `CallPlan` (count + rough quota/latency estimate,
  labeled an estimate per `00` §9) *before* the run commits. No surprise burn.
- **Reuse over re-run.** A stage's inputs are content-addressed: editing one
  review lens or re-running the finalizer must **not** re-run the panel or other
  unchanged stages. Panel answers are durable inputs, not throwaway.
- **Resumable.** A run that fails or is stopped mid-chain keeps its completed
  stage outputs; re-running continues from the first incomplete stage.

## Built-In Presets

| Preset | Purpose | Calls after panel |
| --- | --- | --- |
| `synthesis_only` | Daily driver; current behavior with configurable synthesizer. | 1 reduce |
| `light_review` | Common implementation planning. | 1 draft reduce + 3 review fanout + 1 final reduce |
| `full_review` | Architecture/product bets. | 1 draft reduce + full review fanout + 1 final reduce |

The composer should show the rough call count before a run. Full review is a
deliberate heavier mode, not the default daily path.

## Built-In Review Lenses

Ship these as editable prompt profiles:

| Lens id | Job |
| --- | --- |
| `security_privacy` | Find obvious security, privacy, permission, and data-leak gaps. |
| `code_maintainer` | Keep the diff, architecture, and state ownership simple. |
| `proof_qa` | Define the Works Test, proof wall, and likely failure cases. |
| `ui_ux` | Pressure-test interaction model, empty/error states, and visual simplicity. |
| `customer_advocate` | Ask whether a paying user cares and whether the workflow solves the real pain. |
| `dissent_preserver` | Recover dissent or nuance the draft synthesis may have flattened. |
| `cost_latency_quota` | Challenge cost, latency, quota burn, and unnecessary model calls. |
| `writer_editor` | Improve spec clarity, product language, and user-facing copy. |

`light_review` starts with:

```text
security_privacy
code_maintainer
proof_qa
```

`full_review` includes all built-ins. Users can bind any lens to any healthy
worker; one worker may wear multiple lenses.

## Artifact Contract

Current Phase 04 artifacts stay backward-compatible:

```text
run_<id>/
  run.json
  master_plan.md
  bundle.md
```

Review-board runs add derived artifacts:

```text
run_<id>/
  prompt.md
  member_<workerId>.md
  master_plan.md
  review_<lensId>.md
  final_spec.md
  implementation_brief.md
  execution_prompt_<workerId>.md
  bundle.md
  run.json
```

`master_plan.md` remains the draft plan artifact for compatibility. Do not
rename it to `master_plan_draft.md` without a migration.

`bundle.md` is regenerated as the composed view of everything available so far.

## North-Star Acceptance Demo

The milestone is done when this runs end to end with the founder's real workers:

```text
type ONE prompt
-> pick the light_review preset (composer shows the CallPlan: ~10 calls, est. quota)
-> panel answers in parallel  (reused if already run for this prompt)
-> draft master_plan.md
-> 3 review lenses fan out in parallel over the draft
-> finalizer writes final_spec.md with a visible "Decisions on review feedback"
   section AND a runnable Works Test + proof commands
-> click "Implement This" -> pick a healthy headless worker + working dir
-> Allnighter writes the brief + execution prompt and invokes the CLI
-> live dispatch status; transcript captured to the run folder
No copy/paste anywhere. master_plan.md is never overwritten by reviews.
```

## Activation Gate

Before RB1 code starts, run the workflow **manually** on three real, materially
different prompts (e.g. one architecture bet, one feature plan, one refactor):

```text
existing panel -> master_plan.md
manual light review prompts over the master plan (security, maintainer, proof/QA)
manual finalizer prompt over prompt + raw answers + master plan + reviews
```

Judge each with this rubric — the final spec must win on a majority, on a
majority of the three prompts, or **stop and revise the prompt profiles before
building machinery**:

1. **Caught a real gap** the draft synthesis missed (named, not vague).
2. **Resolved a real conflict** between panel answers instead of averaging them.
3. **More executable**: a coding agent could start from it with fewer questions.
4. **Honest**: visibly adopted *and* rejected review items with reasons.
5. **Worth the extra calls**: the quality gain justifies the added quota/latency.

Record the verdict (and the winning/ losing prompts) in this doc's decision log
before RB1. The machinery only earns its complexity if the manual run already
produces materially better specs.

## Slice Map

| Slice | Doc | Purpose |
| --- | --- | --- |
| RB1 | `RB1_Workflow_Presets_And_Stage_Primitives.md` | Generalize presets, prompt profiles, stage outputs, and events. |
| RB2 | `RB2_Review_Board.md` | Add optional advisory review fanout. |
| RB3 | `RB3_Final_Spec.md` | Add first-principles final reduce stage. |
| RB4 | `RB4_Direct_Executor_Dispatch.md` | Send the final spec to a selected CLI without Allnighter-owned git rules. |
