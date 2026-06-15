# RB3 - Final Spec

Status: **Finalized — ready after RB2.**
Owner: Shared Core + Mac
Created: 2026-06-14
Updated: 2026-06-14
Depends on: RB2

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
input: founder prompt + raw member answers + master_plan.md + labeled reviews
policy: advisory + first_principles
worker: configured final synthesizer
output: final_spec.md
```

The finalizer must think from first principles. It may adopt, partially adopt,
reject, or defer review feedback, but it must explain material decisions.

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
- Risks and open questions
- Decisions on review feedback
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

The decisions are also persisted **structurally** (one
`{ lensId, decision: adopted|partial|rejected|deferred, reason }` per review) in
the final `StageOutput`, so the UI can render adopt/reject chips and a later
audit can read decisions without parsing prose.

### Executability gate

`final_spec.md` is only valid if it contains a concrete **Works Test** and the
**proof commands** an agent/CI would run to verify the change (e.g. `swift test`,
a script, an acceptance check). If the finalizer cannot produce them, it must say
so explicitly under "Risks and open questions" rather than emit a spec that looks
done but cannot be verified. RB4's brief copies these forward.

## Ordered Slices

- [ ] RB3-S01 - Built-in final-spec prompt profile and `FinalizerPolicy` model
  (+ fixtures/round-trip tests).
- [ ] RB3-S02 - Finalizer input builder (`InputSelector` set: prompt + raw member
  answers + draft plan + reviews) so dissent is not flattened twice.
- [ ] RB3-S03 - Final reduce coordinator reusing the same `Synthesizer`/
  `WorkerRunner` path as draft synthesis; inputs are reused (no fresh panel).
- [ ] RB3-S04 - Manual-paste finalizer path matching the current manual synthesis
  flow (reuse Phase 04 `manualSynthesisPrompt` shape).
- [ ] RB3-S05 - Persist final `StageOutput` (incl. structured review decisions)
  in `run.json` and write `final_spec.md`.
- [ ] RB3-S06 - UI final spec panel with copy/export, adopt/reject decision chips,
  and an "Implement This" entry point (handed to RB4).
- [ ] RB3-S07 - `bundle.md` ordering: prompt, member answers, master plan,
  reviews, final spec.
- [ ] RB3-S08 - Executability check: final spec parsing surfaces whether a Works
  Test + proof commands are present; the UI flags a spec that lacks them.
- [ ] RB3-S09 - Zero-review path: finalizer runs and labels the spec "finalized
  without review board" when no review completed.

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
- [ ] Final spec includes a Works Test + proof commands, or explicitly states it
  could not produce them.
- [ ] Raw member answers are available to the finalizer by input selector.
- [ ] Failed/zero reviews are disclosed and do not block finalization.
- [ ] `master_plan.md` remains unchanged after finalization.
- [ ] `swift test` + app test wall green.

## Closeout

Activate RB4. The final spec is now the canonical implementation artifact for
direct executor dispatch.
