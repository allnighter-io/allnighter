# RB0 - Judgment Workflow Overview

Status: **Finalized — activate after Phase 06 lands and the RB0 gate passes.**
Owner: Founder + Shared Core + Mac
Created: 2026-06-14
Updated: 2026-06-14
Depends on: 05 (shipped), 06 (the council foundation: `PanelSeat`, `JudgeAnalysis`, `StageOutput`)

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

## What 05 + 06 Already Lay Down (build on, do not rebuild)

The review-board milestone starts from the **correct council foundation**, not
Phase 04. Phase 05 shipped presets + honesty; Phase 06 lays the final run model.

| Artifact | From | RB milestone reuses it as |
| --- | --- | --- |
| `SynthesisInstructionPreset` + `SynthesisInstructionStore` | 05 | The seed of `PromptProfile`. Phase 06 already evolves it into the structured judge profile; RB1 adds `purpose`. |
| honest `StageOutput.promptProfileId` (from `SynthesisInstructionChoice`) | 05→06 | RB1 keeps a regression test; the seam is already closed. |
| `PanelPreset` (+ `PanelPresetStore`) | 05 | The seed of `WorkflowPreset` (RB1 extends with `stages`). 06 ships tiered presets on it. |
| **`PanelSeat`** (panel is `[PanelSeat]`; self-fusion) | 06 | RB stages bind to seats; review/dispatch reference seat ids. |
| **`JudgeAnalysis`** (structured consensus/contradictions/unique/blind spots/coverage/failed seats) | 06 | RB2 lenses and RB3 finalizer consume it directly, not raw Markdown. |
| **`StageOutput` + `StagePurpose`** (the run is a stage sequence) | 06 | RB adds `StagePurpose` cases (`review`, `final_spec`, `dispatch`, `return_review`) — it does **not** restructure the run. |
| `reuseKey` on `StageOutput` | 06 (field) | RB1 turns reuse on (edit one lens → don't re-run the panel). |
| Eval harness (`Rubric`/`EvalScore`, negative criteria) | 06 | RB3 executability and RB5 outcome scoring reuse it. |
| `Doctor` / `WorkerDiagnosis` | 05 | RB4 gates dispatch on a healthy headless worker; reuses fix-hint vocabulary. |
| `AllnighterPaths`, `RunStore` / `RunMarkdown` | 05→06 | `run.json` is truth; RB adds derived sibling artifacts. |

> **No migration shims (pre-user).** There are no saved runs to preserve. RB
> evolves these types to their correct shape directly. `PromptProfile` subsumes
> `SynthesisInstructionPreset`; `WorkflowPreset` extends `PanelPreset`;
> `CouncilRun.presetId` is the preset slot. Do not add "decode old runs" gates.

## Core Vocabulary

| Term | Meaning |
| --- | --- |
| `Worker` | Executor endpoint: local CLI + model label + driver manifest. |
| `PanelSeat` | One independent panel slot (`{ id, workerId, seatIndex, label? }`). A worker can fill several seats — *self-fusion*. (Phase 06.) |
| `JudgeAnalysis` | Structured judge truth: consensus, contradictions, partial coverage, unique insights, blind spots, failed seats. Markdown is derived. (Phase 06.) |
| `PromptProfile` | Versioned, editable prompt template used by a stage. Review lenses and synthesis/judge instructions are all prompt profiles. Generalizes `SynthesisInstructionPreset`. |
| Review lens | User-facing name for a `PromptProfile` whose purpose is `review_lens`. |
| `WorkflowPreset` | A named binding of stage shape, seats, prompt profiles, and defaults. Extends `PanelPreset` with `stages`. |
| `WorkflowStage` | One ordered fanout or reduce unit inside the fixed chain. |
| `StageOutput` | Structured run truth for one stage (Phase 06); Markdown files are derived views. RB adds new `StagePurpose` cases. |
| `FinalizerPolicy` | Structured rule telling the final spec stage how to treat reviews. v1 ships `advisory` + `first_principles`. |
| `ImplementationBrief` | Handoff artifact created from a final spec before dispatch. |
| `CallPlan` | The previewed list of model calls a run will make (stage → seat → lens), with a rough quota/latency estimate, shown before the user commits. |

Keep `WorkerRole` narrow. It remains the existing structural capability:
`member`, `synthesizer`, or `both`. It is not a reviewer persona — a persona is a
`PromptProfile` (review lens) or an optional per-seat stance.

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

Phase 06 ships the **panel-tier** presets (Fast / Quality / Budget / Self-Double /
Full); the RB milestone adds the **workflow** presets that chain reviews + final
spec on top. Each `analysis → plan` pair is two stage outputs regardless of
call-count (06).

| Preset | Purpose | Calls after panel |
| --- | --- | --- |
| `synthesis_only` | Daily driver; the Phase 06 tiered panel presets with configurable judge. | 1–2 reduce (analysis + plan) |
| `light_review` | Common implementation planning. | analysis + plan + 3 review fanout + 1 final reduce |
| `full_review` | Architecture/product bets. | analysis + plan + full review fanout + 1 final reduce |

The composer shows the live `CallPlan` before a run. Full review is a deliberate
heavier mode, not the default daily path. A worker may fill **multiple seats**
(self-fusion) in any preset — the `CallPlan` counts seats, not workers.

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

All Markdown files are **derived from `run.json` stages** (Phase 06); `run.json`
is the only truth. Phase 06 establishes:

```text
run_<id>/
  run.json
  member_<seatId>.md     # by seatId, so self-fusion seats don't collide
  analysis.md            # derived from the JudgeAnalysis stage
  master_plan.md         # derived from the plan stage
  bundle.md
```

Review-board runs (RB) add derived artifacts, all from new `StageOutput`s:

```text
run_<id>/
  ... (above) ...
  review_<lensId>.md
  final_spec.md
  implementation_brief.md
  execution_prompt_<workerId>.md
  return_review.md       # RB5
```

`master_plan.md` is the plan-stage artifact. `bundle.md` is regenerated as the
composed view (prompt → members → analysis → plan → reviews → final spec → return)
of everything available so far. Since there are no users, artifact names take
their final form now — no rename migrations to worry about.

## North-Star Acceptance Demo

The milestone is done when this runs end to end with the founder's real workers:

```text
type ONE prompt
-> pick the light_review preset (composer shows the CallPlan: ~10 calls, est. quota)
-> panel answers in parallel  (reused if already run for this prompt)
-> structured JudgeAnalysis (verdict strip: consensus / conflicts / blind spots)
-> draft master_plan.md grounded in the analysis
-> 3 review lenses fan out in parallel over the analysis + draft
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
6. **Synthesis lift (Fusion criterion)**: a two-step analysis → plan (Phase 06)
   beats one-step synthesis on the same panel output — and the structured
   `JudgeAnalysis` made the decision faster to act on.

**The gate has two parts, both required before RB1 code:**

- **(a) Manual judgment** — the founder runs the three prompts and scores criteria
  1–6 above by hand. This is the human taste check.
- **(b) Automated eval** — the Phase 06 eval harness (`Fixtures/Evals/`) must show
  `separate` analysis→plan ≥ `combined` ≥ `solo` and **no regression** on the
  corpus. This requires Phase 06 (incl. P06-S10) shipped and the corpus authored.

(a) and (b) are different activities: (a) is taste on three live prompts; (b) is
the offline regression wall. Both must pass. Record the outcome below.

### Activation Gate Decision Log

| Date | Prompts (won / lost) | Manual verdict (1–6) | Eval result | Go / revise |
| --- | --- | --- | --- | --- |
| _pending_ | _e.g. arch bet ✓, feature ✓, refactor ✗_ | _filled at gate time_ | _eval scorecard ref_ | _pending_ |

The machinery only earns its complexity if both parts pass. If not, revise the
judge profiles (`judge_analysis` / `judge_plan`) and re-run — do not start RB1.

## Slice Map

> Phase **06 is a build-order phase** (a prerequisite, like 01–05), not an RB
> slice — RB work begins after 06 ships and the gate above passes. It is listed
> first for dependency clarity.

| Slice | Doc | Purpose |
| --- | --- | --- |
| 06 | `06_Fusion_Grade_Synthesis_And_Evals.md` | **Prerequisite phase.** The foundation RB consumes: seats, structured `JudgeAnalysis`, `StageOutput`, evals. Built first. |
| RB1 | `RB1_Workflow_Presets_And_Stage_Primitives.md` | Generalize presets + prompt profiles; add workflow stages over 06's `StageOutput`; `CallPlan`; reuse. |
| RB2 | `RB2_Review_Board.md` | Add optional advisory review fanout (lenses consume `JudgeAnalysis` + raw answers). |
| RB3 | `RB3_Final_Spec.md` | First-principles final reduce; resolve contradictions, preserve/reject unique insights. |
| RB4 | `RB4_Direct_Executor_Dispatch.md` | Send the final spec to a selected CLI without Allnighter-owned git rules. |
| RB5 | `RB5_Return_Review_And_Routing.md` | Close the loop: capture the return, score it, build worker scorecards, recommend rerun/remix/pick. |
| RB6 | `RB6_Council_As_Tool.md` | The moat: expose the council as a local tool (CLI/MCP/HTTP) any terminal agent can call — local Fusion at zero cost. Needs only `06`; judgment-only, recursion-guarded. |
