# RB2 - Review Board

Status: Draft
Owner: Shared Core + Mac
Depends on: RB1

## Goal

After a draft `master_plan.md` exists, fan it out to configurable advisory
review lenses in parallel. Each review lands as structured stage output plus a
derived Markdown file. The founder can read the reviews even before RB3 exists.

## Non-Goals

- No final spec synthesis yet.
- No generic model-vs-model cross-critique.
- No auto execution.
- No requirement that every reviewer succeed.

## Design

Review is a fanout stage:

```text
input: founder prompt + master_plan.md + lens-specific extras
binding: one review lens -> one worker
output: review_<lensId>.md
```

The same worker can run multiple lenses. Lenses bind to workers inside the
workflow preset or through per-run override. No lens is inherently tied to one
model.

Review outputs are advisory. They never overwrite `master_plan.md`; they append
sibling artifacts for the finalizer or founder to consider.

## Inputs

Default review input:

```text
founder prompt
draft master plan
review lens instructions
```

Lens-specific input selectors may add raw member answers when needed. The
`dissent_preserver` lens should receive raw member answers by default so it can
find what the draft synthesis flattened.

## Built-In Lenses

Ship all built-ins from RB0 as prompt profiles. The initial UI should expose:

```text
synthesis_only: no reviews
light_review: security_privacy, code_maintainer, proof_qa
full_review: all built-in lenses
```

`writer_editor` is optional for non-user-facing implementation plans.

## Ordered Slices

- [ ] RB2-S01 - Bundled review-lens prompt profiles and fixtures.
- [ ] RB2-S02 - Workflow preset review bindings: lens id, worker id, input
  selector, timeout, enabled.
- [ ] RB2-S03 - Review prompt builder with explicit advisory language and
  lens-specific input selectors.
- [ ] RB2-S04 - Review fanout coordinator reusing the existing worker runner and
  `TaskGroup` behavior.
- [ ] RB2-S05 - `Review` / `StageOutput` persistence in `run.json` and derived
  `review_<lensId>.md` artifacts.
- [ ] RB2-S06 - UI review board panel: per-lens status, output, copy, rerun
  affordance if cheap to include.
- [ ] RB2-S07 - Partial behavior: failed/timed-out reviews are surfaced and do
  not block the run.
- [ ] RB2-S08 - `bundle.md` includes prompt, member answers, master plan, and
  all completed reviews.

## Works Test

```text
Run the light_review preset. After master_plan.md lands, three reviewers run in
parallel. The run folder contains review_security_privacy.md,
review_code_maintainer.md, and review_proof_qa.md. Force one reviewer to time
out; the other reviews remain visible, the failure is explicit, and the run is
still usable.
```

## Exit Gates

- [ ] Review fanout is parallel and bounded by per-worker timeouts.
- [ ] Reviews are marked advisory in structured run truth.
- [ ] Review Markdown files are derived from `run.json`.
- [ ] One failed review does not erase successful reviews or block inspection.
- [ ] Stage events are emitted via `stage.*`.
- [ ] `swift test` + app test wall green.

## Closeout

Activate RB3. RB3 consumes review outputs, but RB2 must be valuable on its own.

