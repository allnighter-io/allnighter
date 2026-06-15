# RB2 - Review Board

Status: **BUILT — Core+Engine+Mac green. (orchestration run)**
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
the daily fast loop stays **one click** (the composer shows the selected work shape;
the daily loop is never literally "one call" after Phase 06).

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
to "treat the whole file as advisory prose." The **`lensId` is never taken from
the header** — it is known structurally from the `StageBinding`/stage output that
produced the review (the filename `review_<lensId>.md` is derived from it). So RB3
always has a `lensId` for every review decision even when the header is garbage;
only `verdict`/`top_concerns` are lost on a bad header. The engine (not the
finalizer) parses the header into the `ReviewResult` payload; the finalizer
consumes the structured form and still reads the body to decide from first
principles (RB3).

**Per-lens rerun + output identity.** Each review is a `StageOutput`
(`purpose: review`) tagged with its `lensId`. A "rerun this lens" is a force-fresh
(RB1) that **appends** a new review output and supersedes the prior one for that
`lensId` (outputs are append-only history; the latest per lens is active). So
`run.json` may hold two `review_security_privacy` outputs; `review_security_privacy.md`
renders the latest. This avoids the "rerun returns the cached result" trap.

## Inputs

Default review input:

```text
founder prompt
judge analysis (Phase 06 JudgeAnalysis: consensus/contradictions/unique/blind spots)
draft master plan
review lens instructions
```

Reviewers consume the **structured `JudgeAnalysis`** (`judge_analysis` input
selector, RB1), not only `master_plan.md` — so a lens can challenge a specific
contradiction or an unsupported consensus point directly. Lens-specific selectors
add raw member answers when needed; the `dissent_preserver` lens receives raw
member answers by default to find what the synthesis flattened.

### Anti-echo: reviewers challenge, they do not agree

Every built-in lens profile carries an explicit anti-echo instruction: "Do not
restate or endorse the draft. Surface what is wrong, missing, or risky from your
lens; if you find nothing, say so briefly." Diversity of *output* is the value
(the Fusion self-fusion lesson); a reviewer that parrots the plan is wasted quota.

## Built-In Lenses

Ship all built-ins from RB0 as prompt profiles, plus **`coverage_audit`** (new).
Its job is **meta-coverage**, sharply distinct from `JudgeAnalysis.blindSpots` and
from `dissent_preserver` (do not restate either): given the founder prompt + the
draft plan, judge whether **the original question is actually, fully answered** and
name domain risks/edge cases the whole exercise (panel *and* judge) could have
missed — e.g. "no rollback path", "i18n unaddressed", "abuse/rate-limit not
considered". `blindSpots` is what the panel missed; `coverage_audit` is whether the
*plan answers the prompt* and what neither panel nor judge could know.

```text
synthesis_only: no reviews
light_review:   security_privacy, code_maintainer, proof_qa
full_review:    all built-in lenses + coverage_audit
```

`writer_editor` is optional for non-user-facing implementation plans.

### Budget routing (the Fusion budget-panel lesson)

Review lenses are mostly structured checklist work, so they do not need a frontier
worker. `StageBinding.preferFastWorker` (RB1), when set, resolves the lens to the
**fastest healthy** worker. "Fastest" is **defined deterministically**: the lowest
**median `durationMs`** for that worker across local run history (`Runs/`); ties and
no-history fall back to a static per-driver tier hint, then to the first healthy
worker by Doctor. (This is a cheap local-history lookup, *not* the RB5 scorecard
system — it predates it and needs no new infrastructure.) Reserve the strong worker
for the analysis/finalizer reduces. This keeps `full_review` fast and easy on quota
while losing little review quality, and the work-shape summary shows which worker each lens
routed to.

## Ordered Slices

- [ ] RB2-S01 - Bundled review-lens prompt profiles (all RB0 lenses + new
  `coverage_audit`) with the anti-echo instruction baked in. Fixtures + round-trip.
- [ ] RB2-S02 - Workflow preset review bindings: lens id, seat/worker, input
  selectors, timeout, `enabled` (per-lens toggle), `preferFastWorker` (budget
  routing via Doctor).
- [ ] RB2-S03 - Review prompt builder with explicit advisory + anti-echo language
  and lens-specific input selectors (`judge_analysis` for all; raw member answers
  for `dissent_preserver`; `JudgeAnalysis.blindSpots` for `coverage_audit`).
- [ ] RB2-S04 - Review fanout coordinator reusing `WorkerRunner` + `TaskGroup`; the
  `JudgeAnalysis` + draft plan are supplied as **reused** inputs (no re-fan-out).
- [ ] RB2-S05 - Review `StageOutput`s (`purpose: review`) in `run.json` + derived
  `review_<lensId>.md` with the optional machine-readable header.
- [ ] RB2-S06 - UI review board: per-lens status, verdict chip, output, copy, and a
  per-lens rerun that reuses the unchanged analysis/draft.
- [ ] RB2-S07 - Partial behavior: failed/timed-out reviews are surfaced and do not
  block the run; Doctor warns before binding a lens to an unhealthy worker.
- [ ] RB2-S08 - `bundle.md` includes prompt, member answers, analysis, plan, and
  all completed reviews. The shape summary reflects enabled lenses (and their routed
  seats) before the run.

## Works Test

```text
Run the light_review preset. After master_plan.md lands (reused if already
present for this prompt), three reviewers run in parallel. The run folder
contains review_security_privacy.md, review_code_maintainer.md, and
review_proof_qa.md, each with a verdict header. Disable one lens and rerun: the
Reuse shows in run state; the panel/draft are reused. Force one reviewer
to time out; the other reviews remain visible, the failure is explicit, and the
run is still usable.
```

## Exit Gates

- [ ] Review fanout is parallel and bounded by per-worker timeouts.
- [ ] Reviews are marked advisory in structured run truth; never overwrite the
  draft plan.
- [ ] Review Markdown files are derived from `run.json`; header degrades safely.
- [ ] Per-lens enable/disable is reflected in the live work-shape summary before the run.
- [ ] Reviews consume the draft plan as a reused input (no fresh panel fan-out).
- [ ] One failed review does not erase successful reviews or block inspection.
- [ ] Stage events are emitted via `stage.*`.
- [ ] `swift test` + app test wall green.

## Closeout

Activate RB3. RB3 consumes review outputs, but RB2 must be valuable on its own.

