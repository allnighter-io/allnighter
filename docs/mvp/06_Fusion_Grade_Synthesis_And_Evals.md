> **Vocabulary (2026-06-15).** Current product language lives in
> `docs/workflows/Product_Vocabulary.md`. This doc uses team/model/worker/plan
> terms only.

# 06 — Fusion-Grade Synthesis + Evals (the correct team foundation)

Status: **BUILT (S01–S10) — Core+Engine+Mac green (80 + 13 tests). On-device founder run + activation gate pending.**
Depends on: 00 (locked), 01–05
Owner: Shared Core + Mac
Created: 2026-06-14
Updated: 2026-06-14

> This phase makes the **synthesis step itself** dramatically better — the lever
> OpenRouter's Fusion result proves matters most — and lays the **correct, final
> team-run data model** before any review-board machinery is built on top of
> it. It is a deliberate foundation phase, not a feature sprint.

## Why now (Fusion validation, foundation timing)

OpenRouter's Fusion benchmark (DRACO, 100 deep-research tasks, rubric-graded 3×)
proved three things that map straight onto Allnighter:

1. **a team + a structured plan writer beats any solo frontier model** — and a *budget*
   team synthesized by a strong plan writer nearly matches a frontier team at ~half
   the cost. Allnighter's team is **zero marginal cost** (subscription CLIs), so
   this is pure upside.
2. **Self-fusion is real:** the same model run twice and synthesized beat itself
   solo by ~6.7 points. A big part of the lift is **the synthesis step**, not just
   model diversity — multiple independent runs explore different reasoning paths.
3. **The plan writer produces structured analysis first** (consensus, contradictions,
   partial coverage, unique insights, blind spots) and *then* grounds its answer
   in that analysis.

Allnighter already asks its plan writer for those exact categories
(`SynthesisInstructions.defaultText`), but only as **Markdown prose**. Phase 06
makes that analysis **structured truth** in `run.json`, makes **self-fusion** a
first-class team shape, and adds an **eval harness** so every change to the
review path is proven, not asserted.

## Foundation principle (founder directive)

There are **no users and no saved runs to migrate.** Build the correct shapes
now. This phase **changes** Phase 04/05 Core types to their final form (rewriting
fixtures and call sites) rather than layering compatibility optionals on top.
There are **no "decode old run.json" gates** in this phase. Design remains
extensible (future additions additive), but nothing here is a throwaway "fast
version we fix later."

## Goal

- The team run is modeled correctly **once**: workers, structured plan writer analysis,
  and a stage-output sequence — so RB0–RB5 add *kinds*, never restructure the run.
- The synthesis path produces a structured `PlanAnalysis` plus a plan
  grounded in it.
- **Self-fusion** works: one worker can occupy multiple independent workers.
- **Tiered presets** name the real tradeoffs (Fast / Quality / Diverse Team / Self-Double
  / Full), each with a live `WorkOrder.summary` shape string.
- An **eval harness** scores review quality against hidden weighted rubrics
  (with negative criteria) so improvements are measurable.

## Non-Goals

- **No OpenRouter / no API keys / no extra tokens.** Zero marginal cost is a hard
  product law (`00` §9). Fusion is the cloud version; Allnighter is the local one.
- No review board / final spec / dispatch (those are RB2–RB4, which *consume* this
  foundation).
- No general DAG, conditionals, or user-authored stage graph.
- No recursive synthesis (a plan writer never fans out another team — mirrors
  Fusion's recursion guard).
- The eval harness is a **developer/founder tool**, not a shipped product surface;
  it never auto-grades a user's run by default.

## The correct team-run data model (Core, contract-first)

All new/changed types live in `AllnighterCore`, each with a JSON fixture and a
round-trip test (`00` §8), and replace the prior shapes outright.

### Worker — the self-fusion foundation

Today `WorkerAnswer.id == workerId`, so two runs of the same worker collide. A
**worker slot** is one independent slot in the team; a worker can fill several.

```text
Worker
- id: String            // stable worker id, e.g. "model_opus#1", "model_opus#2"
- workerId: String      // which configured worker runs this worker
- instanceIndex: Int        // 0-based index among workers sharing a workerId
- label: String?        // display override, e.g. "Opus (A)"
```

`TeamRun.workers` becomes `[Worker]` (was `[String]`). `WorkerAnswer` gains
a stored **`workerId`** field (the stable identity) and retains `workerId`
(provenance: which worker ran); its `Identifiable.id` is a **computed** property
returning `workerId` (not encoded — `workerId` and `workerId` are the only encoded
keys). Two workers of Opus produce two distinct members, attributable independently.

> A normal six-model team is six workers, each `instanceIndex == 0`. Self-fusion is
> just multiple workers sharing a `workerId`. One shape covers both.

**Presets request workers, not worker ids.** A preset stores `seats: [WorkerSpec]`
where `WorkerSpec = { workerId, count = 1, stance? }`; at run start the engine
**expands** it into `Worker`s (`model_opus#0`, `model_opus#1`, …). This is the
*only* shape that can express the Self-Double preset (`{ workerId: opus, count: 3 }`)
and, once RB1 lands `stance`, perspective diversity. Phase 06 evolves `TeamPreset`
from `panelWorkerIds: [String]` to `seats: [WorkerSpec]` (no shim — final shape).

### PlanAnalysis — structured review truth

The plan writer's analysis is **data**, not only Markdown. `analysis.md` is a
derived view.

```text
PlanAnalysis
- consensus: [AnalysisPoint]        // points most/all workers agree on
- contradictions: [Contradiction]   // genuine disagreements + recommended resolution
- partialCoverage: [CoverageNote]   // who addressed what; who was silent
- uniqueInsights: [AnalysisPoint]   // raised by only one/few workers, attributed
- blindSpots: [String]              // angles NO worker addressed (team-wide gaps)
- failedWorkers: [WorkerFailure]        // workers that did not answer (honest, never hidden)
- confidenceNote: String?           // plan writer's own calibration, labeled

AnalysisPoint   = { statement: String, sourceWorkerIds: [String], strength: Strength? }   // Strength: strong|moderate|weak
Contradiction   = { topic: String, positions: [{ workerId, summary }], recommendedResolution: String }
CoverageNote    = { workerId: String, addressed: [String], silentOn: [String] }
WorkerFailure     = { workerId: String, reason: String }
```

The `blindSpots` field is the team-wide gap (distinct from one model's miss); it
is the highest-value signal for architecture decisions and feeds RB2's
`coverage_audit` lens.

### StageOutput — the run becomes a sequence of stage outputs

This container lands **here**, not in RB1, so the run model is correct once. The
team fan-out produces `members`; everything after is a `StageOutput`.

```text
StageOutput
- id: String
- purpose: StagePurpose          // analysis | plan  (RB extends: review | final_spec | dispatch | return_review | outcome_score)
- producedByWorkerId: String?    // the worker invocation that produced this reduce (reduces are NOT workers)
- producedByWorkerId: String?      // set only when the producer is a worker (rare)
- promptProfileId: String?       // the named profile used  — exactly one of these two is set
- customInstruction: String?     // OR one-off custom text   (honest record; the Phase 05 choice, generalized)
- status: StageStatus            // queued|running|done|failed|timed_out|skipped|reused
- payload: StagePayload?         // typed structured truth (00 §4.1): .analysis(PlanAnalysis) | .plan(markdown) | ...
- reuseKey: String?              // content address (06 leaves it nil; RB1 computes + matches — formula in RB1)
- errorReason: String?           // on failure, the raw producer output is preserved here
- startedAt / finishedAt
```

`StagePurpose` is a **closed enum** (00 §4.1): exhaustive `switch`es force every new
purpose to be handled — a feature, not a trap. `StageStatus` likewise. **`reuseKey`
is left `nil` in Phase 06** (the field exists for shape stability); RB1 owns the
hash formula, computation, and matching — Phase 06 never reuses.

### TeamRun — final shape

```text
TeamRun
- id
- prompt
- status: RunStatus
- origin: RunOrigin              // gui | cli | mcp | http (default gui) — Phase 06 owns this field
- originAgent: String?           // best-effort caller label (e.g. "claude-code") for tool runs
- presetId: String?              // the TeamPreset/WorkflowPreset launched from (replaces teamPresetId)
- workers: [Worker]             // was [String]
- workerAnswers: [WorkerAnswer]      // keyed by workerId
- stages: [StageOutput]          // analysis, then plan (RB appends review/final/dispatch/return)
- createdAt
```

The Phase 04/05 `Synthesis` struct is **removed**; the plan is the
`StageOutput` with `purpose == .plan`. The honest instruction record (Phase 05
`SynthesisInstructionChoice`) becomes `StageOutput.promptProfileId` **or**
`customInstruction` (exactly one set). **`RunOrigin` + `TeamRun.origin`/
`originAgent` are defined here** (default `gui`) so RB6 only *sets* them — it adds
no field to a shipped type. `RunMarkdown` derives `master_plan.md` from the plan
stage, `analysis.md` from the analysis stage, and `bundle.md` in the canonical
order **prompt → members → analysis → plan** (RB appends → reviews → final → return;
this ordering is fixed and every milestone matches it).

## Two-stage synthesis (analysis → plan)

Synthesis is two reduces over the team:

```text
team fan-out (seats) -> analysis_reduce -> plan_reduce
```

- **analysis_reduce**: the plan writer worker reads the prompt + every worker's answer
  (with the honest "these workers did not answer" note) and emits a `PlanAnalysis`.
- **plan_reduce**: reads the prompt + raw worker answers + the `PlanAnalysis` and
  writes `master_plan.md`, grounded in the analysis ("decide, don't average;
  attribute; resolve each contradiction explicitly").

**Call-count is a preset choice, never a data shortcut.** The run always carries
both an analysis `StageOutput` and a plan `StageOutput`. The synthesis config is an
explicit owned type on the preset (not floating):

```text
SynthesisConfig                        // TeamPreset.synthesis (and later WorkflowPreset)
- analysisDepth: combined | separate
- planWriterModelId: String?               // the worker that plan writers; nil = first enabled canWritePlan
- analysisProfileId: String            // built-in plan_analysis profile
- planProfileId: String                // built-in plan_writer profile
```

- `analysisDepth: combined` — one plan writer call emits the structured analysis **and**
  the plan; the engine splits it into the two stage outputs. (Fast presets.)
- `analysisDepth: separate` — two plan writer calls (more rigor; the analysis is a clean
  standalone reduce the plan then consumes). (Quality/Full presets.)

Either way `run.json` is identical in shape: an `analysis` stage
(`promptProfileId = analysisProfileId`) and a `plan` stage
(`promptProfileId = planProfileId`). Two distinct built-in profiles drive the two
reduces (`plan_analysis` asks for structured analysis; `plan_writer` asks for a
decisive plan grounded in it) — they are not the same template, so attribution
stays honest.

### Plan writer Output Contract (the combined path is the daily driver — make it precise)

The `combined` plan writer prompt requires a **strict, delimited** output so parsing is
deterministic, not prose-scraping:

```text
<a single fenced json code block conforming exactly to the PlanAnalysis schema>
===PLAN===
<the plan, as Markdown, after the sentinel>
```

The first block is a `json`-tagged fenced code block; the parser splits on the
`===PLAN===` sentinel, decodes the JSON block into
`PlanAnalysis`, and takes the remainder as the plan Markdown. **Failure
granularity — never lose a recoverable half:**

| Outcome | analysis `StageOutput` | plan `StageOutput` | run |
| --- | --- | --- | --- |
| both parse | `done`, `.analysis(...)` | `done`, `.plan(md)` | `complete` |
| JSON missing/invalid, plan present | `failed` (raw in `errorReason`) | `done`, `.plan(md)` | `partial` |
| sentinel/plan missing, JSON valid | `done`, `.analysis(...)` | `failed` | `partial` |
| neither parses | `failed` (raw preserved) | `failed` | `partial`/`failed` |

The engine may do **one** bounded retry with a "emit valid JSON + `===PLAN===`"
reminder before recording a failure. `separate` mode has no parse ambiguity (the
analysis reduce emits only the JSON block; the plan reduce emits only Markdown).
Fixtures cover *perfect / analysis-only / plan-only / garbage* plan writer responses.

## Tiered built-in presets (name the tradeoffs)

Shipped as `TeamPreset`s (Phase 05 substrate), each surfacing a live
`WorkOrder.summary` (worker count, plan writer, analysis depth — structural facts only):

| Preset | Team | Synthesis | For |
| --- | --- | --- | --- |
| **Fast Team** | 3 fast workers | `combined` | the daily driver; snappy |
| **Quality Team** | the six | `separate`, strong plan writer | important decisions |
| **Diverse Team** | diverse workers (plan writer excluded from team) | `separate`, strong plan writer | breadth without repeating the plan writer on the team |
| **Self-Double** | 1 strong worker × 2–3 workers | same-model plan writer | one-subscription users; the self-fusion lift |
| **Full Deliberation** | the six (+ later RB review board) | `separate` | architecture/product bets |

Self-Double is `seats: [{ workerId: opus, count: 3 }]`; the other tiers are
distinct workers. `WorkOrder.summary` updates live as the user toggles workers or
depth. No pre-run time/quota/call forecasts.

**Manual-paste per worker.** When a worker's worker is `manual_paste`, the app shows
**one labeled paste box per worker** (`Opus (A)`, `Opus (B)`, …) — self-fusion workers
are independent, so each is pasted separately (with a "use this answer for the
other empty workers of this worker" convenience). The two synthesis reduces
(analysis, plan) also support manual paste: if the plan writer worker is `manual_paste`,
the app reveals the assembled reduce prompt and accepts a pasted result, exactly
like a worker. This manual matrix (workers · analysis · plan, and later
reviews/finalizer/return) is one consistent "reveal prompt → paste → settle stage"
pattern.

## Eval harness (the discipline gate)

A local, offline harness that proves a review change actually helps before it
becomes a default. **Dev tool, not product UI; scores are estimates.**

Core types (Core, with fixtures + tests):

```text
EvalCase   = { id, prompt, rubric: Rubric, notes? }
Rubric     = { criteria: [RubricCriterion], passMark: Double }   // passMark = min totalWeighted to "pass"
RubricCriterion = { id, description, weight }   // weight may be NEGATIVE (punish confident-wrong / verbosity)
EvalScore  = { caseId, mode, totalWeighted, perCriterion: [{ criterionId, score, note }], planWriterModelId, pass }
EvalConfig = { planWriterModelId, passes = 3 }      // who grades; how many passes to average
```

- A corpus of **10–20 founder prompts** with weighted rubrics (positive *and*
  negative criteria — mirroring DRACO's punishment of confident errors), location
  **`Fixtures/Evals/`** (one canonical path; not `docs/`).
- **Plan writer identity is explicit:** `EvalConfig.planWriterModelId` names the scoring
  worker (default: the strongest healthy worker), blind to the rubric source;
  `passes` (default 3) averages to reduce plan writer variance. `EvalScore.pass` =
  `totalWeighted >= rubric.passMark`.
- **Comparison runner**: scores the same case across modes — `solo` vs `combined`
  vs `separate` vs (later) review-board final — and prints a per-criterion
  scorecard so lifts are visible.
- **Contamination guard is structural, not conventional:** (1) the eval corpus path
  is **never** passed to any prompt builder or member/reduce assembly — enforced by
  a build/test assertion that the worker-invocation chain cannot read
  `Fixtures/Evals/`; (2) eval *runs* are written to a **separate `Evals/` run dir,
  not `Runs/`**, so `team_recall` (RB6) and history never surface them. Mirrors
  Fusion's excluded-domains lesson, localized and enforced.

The harness is the proof wall for this phase and for RB: a synthesis/profile
change ships as a default only if it does not regress the corpus. It runs as a
`swift test`-able target / script so the **RB0 activation gate** can cite its
output (see RB0).

## Team Analysis UI

Render `PlanAnalysis` as scannable review, not a wall of prose:

- A **verdict strip** on every completed run: `Team 5/6 · Consensus: strong on X
  · Conflict: Y · Gap: Z`.
- Tabs/sections: **Consensus · Contradictions · Unique insights · Blind spots ·
  Coverage map · Failed workers**, each linking back to the **exact worker answers**
  behind it ("replay the disagreement").
- Self-fusion workers are labeled (`Opus (A)`, `Opus (B)`).
- "Show plan writer reasoning" reveals the analysis behind the plan, so synthesis feels
  like a visible deliberation, not magic.

## Ordered Slices

- [ ] P06-S01 — `Worker` + `WorkerSpec`; `TeamRun.workers: [Worker]`;
  `WorkerAnswer` stored `workerId` (+ computed `id`). Evolve `TeamPreset` to
  `seats: [WorkerSpec]` + worker expansion at run start. Rewrite fixtures + Phase
  02/03/05 call sites. Round-trip tests.
- [ ] P06-S02 — `PlanAnalysis` (+ `AnalysisPoint`/`Contradiction`/`CoverageNote`/
  `WorkerFailure`) model + fixtures + round-trip tests.
- [ ] P06-S03 — `StageOutput` + `StagePayload` union + `StagePurpose`/`StageStatus`;
  `TeamRun.stages` + `origin`/`originAgent` + `presetId` (delete `panelPresetId`);
  **remove** `Synthesis`. `RunMarkdown`/`RunStore` derive `analysis.md`,
  `master_plan.md`, `bundle.md` from stages. Derivation tests.
- [ ] P06-S04 — `RunOrigin` enum + `TeamRun.origin` (default gui) + round-trip;
  the coordinator stamps `origin: .gui` (RB6 sets cli/mcp/http later).
- [ ] P06-S05 — Built-in `plan_analysis` + `plan_writer` profiles + the **Plan writer
  Output Contract** parser (`===PLAN===` split, JSON decode, per-half failure
  granularity, one bounded retry). Fixtures: perfect / analysis-only / plan-only /
  garbage. `combined` path.
- [ ] P06-S06 — `separate` path: `analysis_reduce` then `plan_reduce`, reusing
  `PlanWriter`/`WorkerRunner`. `SynthesisConfig.analysisDepth` on the preset.
- [ ] P06-S07 — Self-fusion: coordinator runs multiple workers per worker in parallel
  (keyed by `workerId`); per-worker manual-paste boxes + Doctor; analysis attributes by
  `workerId`. Member events carry `workerId`.
- [ ] P06-S08 — Tiered built-in presets (Fast / Quality / Diverse Team / Self-Double /
  Full) via `seats` + `SynthesisConfig` + live `WorkOrder.summary`. No estimates.
- [ ] P06-S09 — Team Analysis UI (verdict strip, analysis sections, worker
  back-links, "show plan writer reasoning").
- [ ] P06-S10 — Eval harness: `EvalCase`/`Rubric`/`EvalScore`/`EvalConfig` models +
  corpus under `Fixtures/Evals/` (hidden, negative criteria) + scoring runner + mode
  comparison + 3-pass plan writer + structural contamination guard (corpus unreadable by
  the worker chain; eval runs in `Evals/`, not `Runs/`).

## Works Test

```text
Run three materially different real prompts (an architecture bet, a feature plan,
a refactor) through (a) the old single-shot synthesis and (b) the new structured
analysis + plan. Confirm:
- run.json contains a PlanAnalysis (consensus/contradictions/uniqueInsights/
  blindSpots/coverage/failedWorkers) and a plan stage grounded in it.
- A Self-Double preset (one worker × 3 workers) produces three distinct members and
  a synthesis that reconciles them — no worker-id collisions.
- The eval harness scores (b) >= (a) on the hidden-rubric corpus, and the founder
  plan writers the structured analysis materially faster to act on.
- The daily Fast Team preset is still one click and feels fast.
```

## Exit Gates

- [ ] `TeamRun` uses `[Worker]` + `[StageOutput]` (+ `origin`, `presetId`);
  `Synthesis` and `panelPresetId` removed; fixtures rewritten; `Runs/` wiped at
  cutover (no shims, no decode-old-runs).
- [ ] `PlanAnalysis` is structured truth (`StagePayload.analysis`); `analysis.md`
  derived; `bundle.md` follows the canonical order.
- [ ] The Plan writer Output Contract parser passes the perfect/partial/garbage fixtures
  and never loses a recoverable half (analysis or plan).
- [ ] Self-fusion workers never collide; each is independently attributable; member
  events carry `workerId`.
- [ ] Each stage's `promptProfileId` **or** `customInstruction` records honestly
  what ran (exactly one set).
- [ ] `WorkOrder.summary` shows the selected work shape before any preset runs.
- [ ] Eval harness runs `Fixtures/Evals/` and reports a per-criterion mode
  comparison; the corpus is unreadable by the worker chain; the new synthesis does
  not regress it.
- [ ] `AllnighterEngine` imports no UI (SwiftUI/AppKit) — asserted by test/lint.
- [ ] Zero network egress beyond the CLIs' own; no API keys introduced.
- [ ] `swift test` + `xcodebuild test -scheme AllnighterMac` green; Code Audit CLEAN.

## Closeout

The team run is now modeled correctly and the synthesis is Fusion-grade and
proven. RB0–RB5 build **on** these types: `PromptProfile` generalizes the plan writer
profile, `WorkflowPreset` extends `TeamPreset`, `StageOutput` already carries
every stage, reviews/finals/dispatch/return-review are new `StagePurpose` cases —
no run-model restructuring. Run the RB0 activation gate (now including the
synthesis-lift criterion) before RB1 code starts.
