# RB3 - Final Spec

Status: Draft
Owner: Shared Core + Mac
Depends on: RB2

## Goal

Produce a decisive implementation spec after the advisory review board. This is
not another exploratory master plan. It is the artifact the founder can hand to
an executor or future lane system.

## Non-Goals

- No automatic code execution.
- No majority voting.
- No assumption that reviewer feedback is correct.
- No hidden mutation of `master_plan.md`.

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

This makes advisory treatment inspectable after the run.

## Ordered Slices

- [ ] RB3-S01 - Built-in final-spec prompt profile and `FinalizerPolicy` model.
- [ ] RB3-S02 - Finalizer input builder that includes raw member answers to
  avoid flattening dissent twice.
- [ ] RB3-S03 - Final reduce coordinator reusing the same synthesizer/worker
  runner path as draft synthesis.
- [ ] RB3-S04 - Manual-paste finalizer path matching the current manual
  synthesis flow.
- [ ] RB3-S05 - Persist final stage output in `run.json` and write
  `final_spec.md`.
- [ ] RB3-S06 - UI final spec panel with copy/export and visible review-decision
  section.
- [ ] RB3-S07 - `bundle.md` ordering: prompt, member answers, master plan,
  reviews, final spec.

## Works Test

```text
Run a light_review preset where one review includes a deliberately bad security
suggestion. The final spec completes, explicitly rejects that suggestion with a
reason, adopts at least one useful review item, writes final_spec.md, and keeps
master_plan.md unchanged.
```

## Exit Gates

- [ ] Finalizer policy is stored structurally in `run.json`.
- [ ] Final spec includes adopt/partial/reject/defer decisions.
- [ ] Raw member answers are available to the finalizer by input selector.
- [ ] Failed reviews are disclosed and do not block finalization.
- [ ] `master_plan.md` remains unchanged after finalization.
- [ ] `swift test` + app test wall green.

## Closeout

Activate RB4. The final spec is now the canonical implementation artifact for
direct executor dispatch.
