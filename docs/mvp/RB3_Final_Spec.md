# RB3 - Final Spec

Status: **BUILT — Core+Engine+Mac green. (orchestration run)**
Owner: Shared Core + Mac
Created: 2026-06-14
Updated: 2026-06-14
Depends on: RB2, 06 (`JudgeAnalysis`)

## Goal

Produce a decisive implementation spec after the advisory review board. This is
not another exploratory master plan. It is the artifact the founder can hand to
an executor or future lane system.

The final spec is the milestone's product: a **decision-grade, executable brief.**
"Executable" is a hard requirement, not a nicety — RB4 dispatches this file to a
coding agent, so it must carry everything the agent needs to start and to know
when it is done (scope, acceptance criteria, Works Test, proof commands). A final
spec a human still has to translate has failed its job.

## Non-Goals

- No automatic code execution.
- No majority voting.
- No assumption that reviewer feedback is correct.
- No hidden mutation of `master_plan.md`.
- No requirement that reviews succeeded: the finalizer runs even with zero
  completed reviews (labeled "finalized without review board").

## Design

Final spec is a reduce stage:

```text
input: founder prompt + raw member answers + JudgeAnalysis (06) + master_plan.md + labeled reviews
policy: advisory + first_principles
worker: configured final synthesizer
output: final_spec.md
```

The finalizer must think from first principles. It consumes the structured
**`JudgeAnalysis`** (Phase 06) directly, so it acts on the panel's actual
disagreements and unique signal rather than re-reading prose. It may adopt,
partially adopt, reject, or defer review feedback, but it must explain material
decisions — and it must **resolve every recorded contradiction** and rule on
**every unique insight** (preserve or reject, with a reason). Dissent and
minority signal are not averaged away; they are decided on, visibly.

## Finalizer Policy

`FinalizerPolicy` is stored in the preset and copied into the run:

```text
reviewWeight: advisory
conflictResolution: first_principles
requiredSections:
- Final Spec
- Scope
- Non-goals
- Architecture and state ownership
- UX / user-facing behavior, when relevant
- Acceptance criteria
- Works Test and proof wall
- Decisions on panel contradictions   # each JudgeAnalysis.contradictions item, resolved
- Decisions on unique insights        # each JudgeAnalysis.uniqueInsights item, preserved or rejected
- Decisions on review feedback
- Risks and open questions
```

The prompt profile reflects this policy, but the policy is not owned by prompt
prose alone.

## Output Contract

`final_spec.md` must include a decisions section like:

```text
## Decisions on review feedback
- Security & Privacy: ADOPTED - ...
- Code Maintainer: PARTIAL - ...
- Proof / QA: REJECTED - ...
- Dissent Preserver: DEFERRED - ...
```

This makes advisory treatment inspectable after the run. The finalizer is given
each review's verdict header (RB2) as a hint, but must read the body and decide
from first principles — a `blocker`-tagged review may still be rejected with a
reason, and an `ok` review may surface an item worth adopting.

The decisions are persisted **structurally** in the final `StageOutput`'s
`StagePayload.finalSpec(FinalSpecPayload)` (00 §4.1), so the UI renders chips and a
later audit reads them without parsing prose:

```text
FinalSpecPayload
- markdown: String                      # the human/agent final spec
- reviewDecisions:       [{ lensId, decision: adopted|partial|rejected|deferred, reason }]
- contradictionDecisions:[{ topic, resolution, reason }]          # one per JudgeAnalysis.contradiction
- insightDecisions:      [{ insight, decision: preserved|rejected, reason }]  # one per JudgeAnalysis.uniqueInsight
- reviewBoardRan: Bool                  # false => "finalized without review board" (zero-review path)
- decisionsStructured: Bool             # false => decisions couldn't be parsed; read the prose
- hasProofCommands: Bool                # executability gate result (see below)
```

Coverage: the finalizer must emit a decision for **every** contradiction and unique
insight in the `JudgeAnalysis`, and for every completed review — nothing silently
dropped. **Bounding (token safety):** when the analysis is large (say >12
contradictions or insights), the finalizer decides on the top items by
`AnalysisPoint.strength` individually and **rolls up** the long tail into one
grouped decision with a reason; the `CallPlan` notes the heavier token cost on
`full_review`. **Empty analysis:** zero contradictions/insights → the corresponding
decision arrays are empty and the spec notes "no contradictions to resolve"
(valid, not an error).

**Decision-parse fallback (mirror RB2's header degradation).** If the finalizer's
prose can't be parsed into the structured decision arrays, the stage is still
`done`: `markdown` is populated, the decision arrays are empty, and
`decisionsStructured = false` — the UI shows "decisions could not be structured —
read the prose." Never fail a usable spec over a parse miss.

### Executability gate

`final_spec.md` is only valid if it contains a concrete **Works Test** and the
**proof commands** an agent/CI would run to verify the change. "Present" =
`hasProofCommands` is set when the spec has a fenced command block under the "Works
Test and proof wall" section. If the finalizer cannot produce them, it sets
`hasProofCommands = false` and says so under "Risks and open questions" rather than
emit a spec that looks done but cannot be verified. RB4's brief copies these
forward.

**`requiredSections` validation scope.** RB3-S08 checks **only** the executability
criteria (Works Test + proof commands). Presence of the *other* `requiredSections`
(Scope, Architecture, …) is a **separate structural check** that flags missing
sections in the UI as a soft warning — it does not fail the stage (a spec missing
"UX/user-facing behavior" on a pure-refactor task is legitimate; the finalizer marks
non-applicable sections "n/a" per the `FinalizerPolicy`).

## Ordered Slices

- [ ] RB3-S01 - Built-in final-spec prompt profile and `FinalizerPolicy` model
  (+ fixtures/round-trip tests).
- [ ] RB3-S02 - Finalizer input builder (`InputSelector` set: prompt + raw member
  answers + `judge_analysis` + draft plan + reviews) so dissent is not flattened
  twice and every contradiction/insight is on the table.
- [ ] RB3-S03 - Final reduce coordinator reusing the same `Synthesizer`/
  `WorkerRunner` path as draft synthesis; inputs are reused (no fresh panel).
- [ ] RB3-S04 - Manual-paste finalizer path using Phase 06's manual-reduce pattern
  (reveal the assembled finalizer prompt → paste → settle the `final_spec`
  `StageOutput`), same as a manual analysis/plan reduce. (The Phase 04 `Synthesis`/
  `manualSynthesisPrompt` shapes are gone.)
- [ ] RB3-S05 - Persist the final `StageOutput` with `StagePayload.finalSpec`
  (markdown + structured decisions + `reviewBoardRan`/`decisionsStructured`/
  `hasProofCommands` flags) in `run.json`; derive `final_spec.md`.
- [ ] RB3-S06 - UI final spec panel with copy/export, adopt/reject decision chips,
  and an "Implement This" entry point (handed to RB4).
- [ ] RB3-S07 - `bundle.md` canonical order: prompt → member answers → **analysis**
  → master plan → reviews → final spec (matches `00` §7 / RB0; analysis is included).
- [ ] RB3-S08 - Executability check sets `hasProofCommands`; UI flags a spec that
  lacks them. (Separate soft-warning check for other `requiredSections`.)
- [ ] RB3-S09 - Zero-review path: finalizer runs and sets `reviewBoardRan = false`
  ("finalized without review board") when no review completed — persisted on
  `FinalSpecPayload`, not re-derived by the UI.

## Works Test

```text
Run a light_review preset where one review includes a deliberately bad security
suggestion. The final spec completes, explicitly REJECTS that suggestion with a
reason, ADOPTS at least one useful review item, includes a runnable Works Test +
proof commands, writes final_spec.md, and keeps master_plan.md unchanged.
Re-running the finalizer alone reuses the panel + reviews (CallPlan shows 1 call).
```

## Exit Gates

- [ ] Finalizer policy is stored structurally in `run.json`.
- [ ] Review decisions are stored structurally (adopt/partial/reject/defer +
  reason), not only in prose.
- [ ] Every `JudgeAnalysis` contradiction is resolved and every unique insight is
  preserved/rejected, with reasons, structurally — none silently dropped.
- [ ] Final spec includes a Works Test + proof commands, or explicitly states it
  could not produce them.
- [ ] Raw member answers + `JudgeAnalysis` are available to the finalizer by input
  selector.
- [ ] Failed/zero reviews are disclosed and do not block finalization.
- [ ] `master_plan.md` remains unchanged after finalization.
- [ ] `swift test` + app test wall green.

## Closeout

Activate RB4. The final spec is now the canonical implementation artifact for
direct executor dispatch.
