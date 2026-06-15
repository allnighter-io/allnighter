# RB2 - Review Board

Status: **Finalized — ready after RB1.**
Owner: Shared Core + Mac
Created: 2026-06-14
Updated: 2026-06-14
Depends on: RB1

## Why this is the trust layer (vibe-coder value)

A vibe coder's risk is shipping a confident-but-wrong plan to an agent. The
review board is the cheap insurance: before any code is written, adversarial
lenses (security, maintainer, proof/QA, cost, dissent…) attack the draft in
parallel. The payoff is **trust to press go** — and it costs minutes of model
time, not a day of debugging generated code. The board is opt-in per preset so
the daily fast loop stays one call.

## Goal

After a draft `master_plan.md` exists, fan it out to configurable advisory
review lenses in parallel. Each review lands as structured stage output plus a
derived Markdown file. The founder can read the reviews even before RB3 exists.

## Non-Goals

- No final spec synthesis yet.
- No generic model-vs-model cross-critique.
- No auto execution.
- No requirement that every reviewer succeed.
- No re-running the panel: review consumes the existing draft plan as a reused
  input (RB1 `reuseKey`), it never triggers a fresh fan-out.

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

### Reviews are markdown, with a small machine-readable header

So RB3's finalizer can consume reviews reliably (and the UI can render chips),
each `review_<lensId>.md` begins with a tiny, optional front-matter block — the
prose below it stays the real, human review:

```text
---
lens: security_privacy
verdict: concerns            # ok | concerns | blocker
top_concerns:
  - "Token stored in plaintext in run folder"
---
<the full advisory review in Markdown>
```

The header is a convenience, never authority: a missing/malformed header degrades
to "treat the whole file as advisory prose." The finalizer must still read the
body and decide from first principles (RB3).

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

- [ ] RB2-S01 - Bundled review-lens prompt profiles (all RB0 lenses) + fixtures
  with round-trip tests.
- [ ] RB2-S02 - Workflow preset review bindings: lens id, worker id, input
  selectors, timeout, `enabled` (per-lens toggle so the user can trim the board
  and the cost).
- [ ] RB2-S03 - Review prompt builder with explicit advisory language and
  lens-specific input selectors (`dissent_preserver` gets raw member answers).
- [ ] RB2-S04 - Review fanout coordinator reusing the existing `WorkerRunner` +
  `TaskGroup`; the draft plan is supplied as a **reused** input (no re-fan-out).
- [ ] RB2-S05 - `StageOutput` persistence in `run.json` and derived
  `review_<lensId>.md` artifacts with the optional machine-readable header.
- [ ] RB2-S06 - UI review board panel: per-lens status, verdict chip, output,
  copy, and a per-lens rerun that reuses the unchanged draft.
- [ ] RB2-S07 - Partial behavior: failed/timed-out reviews are surfaced and do
  not block the run; a healthy-worker check (Doctor) warns before binding a lens
  to an unhealthy worker.
- [ ] RB2-S08 - `bundle.md` includes prompt, member answers, master plan, and
  all completed reviews. `CallPlan` counts the enabled lenses before the run.

## Works Test

```text
Run the light_review preset. After master_plan.md lands (reused if already
present for this prompt), three reviewers run in parallel. The run folder
contains review_security_privacy.md, review_code_maintainer.md, and
review_proof_qa.md, each with a verdict header. Disable one lens and rerun: the
CallPlan shows one fewer call and the panel/draft are reused. Force one reviewer
to time out; the other reviews remain visible, the failure is explicit, and the
run is still usable.
```

## Exit Gates

- [ ] Review fanout is parallel and bounded by per-worker timeouts.
- [ ] Reviews are marked advisory in structured run truth; never overwrite the
  draft plan.
- [ ] Review Markdown files are derived from `run.json`; header degrades safely.
- [ ] Per-lens enable/disable is reflected in the `CallPlan` before the run.
- [ ] Reviews consume the draft plan as a reused input (no fresh panel fan-out).
- [ ] One failed review does not erase successful reviews or block inspection.
- [ ] Stage events are emitted via `stage.*`.
- [ ] `swift test` + app test wall green.

## Closeout

Activate RB3. RB3 consumes review outputs, but RB2 must be valuable on its own.

