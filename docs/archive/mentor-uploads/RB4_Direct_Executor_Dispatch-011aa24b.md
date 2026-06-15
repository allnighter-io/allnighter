# RB4 - Direct Executor Dispatch

Status: **Finalized — ready after RB3.**
Owner: Mac + Shared Core
Created: 2026-06-14
Updated: 2026-06-14
Depends on: RB3 (final spec + analysis decisions). Followed by: RB5 (return review)

## The payoff (why the whole milestone exists)

This is where the vibe coder's loop closes: **one prompt became a pressure-tested
spec, and one click hands that spec to the agent that builds it.** No clipboard,
no re-explaining context, no "let me paste the plan into Cursor." The review
work Allnighter just did is exactly the context the executor needs, so dispatch
is a self-contained handoff, not a fresh conversation.

Allnighter stays in its lane: it routes and observes. It does **not** become a
git tool. The boundary is stated honestly to the user at dispatch time.

## Goal

Let the founder choose a worker/model and have Allnighter immediately send the
final spec to that worker's configured CLI. The MVP must remove the copy/paste
step. It should not wait for Allnighter-owned worktrees, commit policy, landing,
or revert machinery.

## Non-Goals

- No git worktree creation.
- No Allnighter-owned git or commit rules.
- No branch naming, landing queue, merge, revert, or protected-path enforcement.
- No guarantee that the active repo is untouched.
- No landing, merge, preview, or test execution.
- No auto-fire: dispatch is an explicit user action with the boundary shown, and
  a **reveal-only** path always exists for users who want to inspect first.

## Design

`Implement This` on `final_spec.md` creates the handoff artifacts and dispatches
the execution prompt to the selected worker:

```text
implementation_brief.md
execution_prompt_<workerId>.md
```

If the worker has a healthy `headless_cli` driver, Allnighter invokes it through
the same runner substrate used for workers. If the worker is `manual_paste`
or unhealthy, Allnighter falls back to copy/reveal artifacts.

**Health gate (reuse Phase 05 Doctor).** Before auto-invoking, dispatch runs the
worker's `Doctor` diagnosis. Only a `healthy` headless worker is invoked
automatically; an unhealthy one shows the Doctor fix hint and drops to the manual
reveal path instead of failing opaquely. No new health logic — reuse
`Doctor`/`WorkerDiagnosis`.

**Reveal-only mode.** Every dispatch can be run as "reveal, don't invoke": write
the brief + execution prompt and open/copy them without spawning the CLI. This is
the default for unhealthy/manual workers and an explicit option for any worker, so
a cautious user can read the exact prompt before it runs.

Direct dispatch runs in the configured execution working directory. That may be
the user's active repo. Git behavior is controlled by the selected CLI, its
normal configuration, and the execution prompt. Allnighter v1 observes and
captures what it can; it does not impose commit policy.

**Context-exclusion (Fusion's contamination lesson, localized).** Allnighter's
own run artifacts (`~/Library/Application Support/Allnighter/Runs/`) must **not**
leak into the executor's context — a coding agent that scans the working directory
and reads stale drafts/reviews/answers gets contaminated and confused. Because
`Runs/` lives in Application Support (never inside the working dir), it is already
out of repo scope; RB4 additionally never copies run artifacts into the working
directory and the execution prompt points only to the brief. If a future option
stages artifacts into the repo, it must add them to a local ignore.

When lane/worktree safety lands, this same brief becomes the input to managed
execution. No redesign should be required.

## Implementation Brief Contract

The brief includes:

```text
source run id
selected source artifact: final_spec.md or master_plan.md
selected execution worker id
execution working directory
original prompt
final spec
acceptance criteria
proof commands / Works Test          # copied from RB3's executability gate
team review summary               # PlanAnalysis: key consensus + resolved contradictions
analysis decisions                   # adopted / rejected / deferred contradictions + unique insights (RB3)
known non-goals
risks and open questions
explicit direct-dispatch boundary
```

The brief carries RB3's Works Test + proof commands verbatim so the executing
agent knows the done-condition without re-deriving it, **plus the structured
analysis decisions** (which contradictions were resolved how, which unique
insights were adopted or rejected) so the executor inherits the pressure-testing
context instead of re-litigating it. If the final spec lacked proof commands (RB3
disclosed this), the brief surfaces that gap rather than implying the work is
verifiable.

If no final spec exists, the action may create a brief from `master_plan.md`. In
that path the **analysis-decision fields are absent** (there were no review
decisions / contradiction resolutions to carry), the `PlanAnalysis` summary is
still included, and the UI + the brief header label it **"less reviewed — built
from the plan, not a final spec."** The execution-prompt builder omits the
decision sections cleanly rather than emitting empty headers.

## Boundary Label

Before dispatch, the UI shows a concise truth label:

```text
Direct dispatch will run <worker> in <working directory>.
Allnighter is not creating a worktree or managing commits.
File edits and git behavior are controlled by the selected CLI and prompt.
```

This is not an approval system. It is an honesty label for the MVP's execution
boundary.

## Ordered Slices

- [ ] RB4-S01 - `ImplementationBrief` model (incl. the team review summary +
  structured analysis decisions from RB3's `PlanAnalysis`) and Markdown renderer.
- [ ] RB4-S02 - Worker picker for handoff target; default comes from
  `WorkflowPreset.executionWorkerId` when present.
- [ ] RB4-S03 - Execution working-directory picker/default. Store the path in
  the run/brief; do not create a worktree. Confirm `Runs/` stays out of the
  executor's context (context-exclusion).
- [ ] RB4-S04 - Execution prompt builder that assembles a self-contained prompt
  for the selected worker, includes the analysis decisions, and names the CLI/git
  boundary explicitly.
- [ ] RB4-S05 - Each dispatch is a `StageOutput(purpose: .dispatch)` with an
  embedded `ExecutionReturn` (RB5 owns the type) — **the single source of truth**;
  no loose duplicate state. The run stays `complete` (dispatch is post-review,
  `00` §4). Multiple dispatches per run are supported (RB5 compares them).
- [ ] RB4-S06 - Artifact naming versions per dispatch to avoid collision:
  `implementation_brief.md` (shared) + `execution_prompt_<workerId>_<NN>.md` and a
  `dispatch_<NN>/` transcript subfolder, `NN` = dispatch index. Validate the working
  directory **exists + is writable** before dispatch.
- [ ] RB4-S07 - Direct dispatch: gate on a `Doctor` healthy check, then invoke
  healthy `headless_cli` workers with the execution prompt in the configured
  working directory; capture stdout/stderr or output file per the driver manifest.
  Use a **separate `dispatchTimeoutSeconds`** (default 600, configurable) — NOT the
  team `invoke.timeoutSeconds` — plus a user **cancel**; on timeout, status
  `timed_out` with the partial transcript kept.
- [ ] RB4-S08 - Manual + reveal-only fallback: for `manual_paste`, unhealthy
  workers, or an explicit user choice, reveal/copy the exact prompt without invoking
  and mark the dispatch manual.
- [ ] RB4-S09 - Transcript capture with a **size cap** (default: first N KB + last N
  KB with a "[… truncated M bytes …]" marker) so a long coding session doesn't
  bloat the run or RB5's return-review input; full transcript streamed to the
  dispatch subfolder file.
- [ ] RB4-S10 - Dispatch status UI: queued/running/done/failed/timed_out + live
  transcript tail; forward-compat note: managed lane execution (Phase 12) consumes
  `ImplementationBrief` unchanged.

## Works Test

```text
Open a run with final_spec.md. Click Implement This, choose a healthy headless
worker and a working directory. Allnighter shows the boundary label, writes
implementation_brief.md plus execution_prompt_<workerId>.md, invokes the worker
CLI with that prompt, shows live status, and captures the transcript to the run
folder. Repeat with an unhealthy worker: dispatch shows the Doctor fix hint and
falls back to reveal-only (artifacts written, CLI not invoked). No Allnighter
worktree, branch, commit, landing, or revert rule is created in either case.
```

## Exit Gates

- [ ] Dispatch artifacts are written and included in `bundle.md`.
- [ ] Selected worker id is persisted as provenance.
- [ ] Execution working directory is explicit and persisted.
- [ ] Dispatch gates on a `Doctor` healthy check; healthy headless workers are
  invoked automatically; manual/unhealthy workers fall back to reveal-only with
  the fix hint.
- [ ] Reveal-only mode writes artifacts without invoking the CLI.
- [ ] The boundary label is shown before any invocation.
- [ ] Allnighter creates no worktree, branch, commit, landing, or revert rule.
- [ ] **Context-exclusion verified:** after a dispatch, **no Allnighter run
  artifact appears in the execution working directory** (explicit test).
- [ ] Each dispatch is a `StageOutput(purpose: .dispatch)`; multiple dispatches per
  run don't collide (versioned artifact names).
- [ ] Dispatch uses `dispatchTimeoutSeconds` (not the team timeout) and is
  cancelable; transcript is size-capped.
- [ ] A brief built from `master_plan.md` (no final spec) omits the analysis-decision
  sections and is labeled "less reviewed — no final spec."
- [ ] The brief can become managed Phase 12 input without changing its core shape.
- [ ] `swift test` + app test wall green.

## Closeout

MVP execution is useful: Allnighter routes the final spec into the chosen CLI and
saves the operator time. **RB5** then closes the loop — capturing the executor's
return, scoring it against this brief's acceptance criteria + proof commands, and
recommending the next move. Far-future managed execution adds worktrees, branch
policy, protected paths, landing, and revert on top of this same brief/dispatch
shape.
