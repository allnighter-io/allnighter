# RB0 - Judgment Workflow Overview

Status: Draft - activate after Phase 05 is dogfooded
Owner: Founder + Shared Core + Mac
Created: 2026-06-14
Depends on: 05

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
workflow presets for higher-stakes decisions.

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

## Core Vocabulary

| Term | Meaning |
| --- | --- |
| `Worker` | Existing executor endpoint: local CLI + model label + driver manifest. |
| `PromptProfile` | Versioned, editable prompt template used by a stage. Review lenses and synthesis instructions are both prompt profiles. |
| Review lens | User-facing name for a `PromptProfile` whose purpose is `review_lens`. |
| `WorkflowPreset` | A named binding of stage shape, workers, prompt profiles, and defaults. |
| `WorkflowStage` | One ordered fanout or reduce unit inside the fixed chain. |
| `StageOutput` | Structured run truth for one stage output; Markdown files are derived views. |
| `FinalizerPolicy` | Structured rule telling the final spec stage how to treat reviews. v1 ships `advisory` + `first_principles`. |
| `ImplementationBrief` | Handoff artifact created from a final spec or master plan before dispatch. |

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

## Activation Gate

Before RB1 starts, run the workflow manually on three real prompts:

```text
existing panel -> master_plan.md
manual light review prompts over the master plan
manual finalizer prompt over prompt + raw answers + master plan + reviews
```

The founder must see materially better final specs than synthesis-only. If not,
stop and revise the prompts before building machinery.

## Slice Map

| Slice | Doc | Purpose |
| --- | --- | --- |
| RB1 | `RB1_Workflow_Presets_And_Stage_Primitives.md` | Generalize presets, prompt profiles, stage outputs, and events. |
| RB2 | `RB2_Review_Board.md` | Add optional advisory review fanout. |
| RB3 | `RB3_Final_Spec.md` | Add first-principles final reduce stage. |
| RB4 | `RB4_Direct_Executor_Dispatch.md` | Send the final spec to a selected CLI without Allnighter-owned git rules. |
