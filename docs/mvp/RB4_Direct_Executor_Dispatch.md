# RB4 - Direct Executor Dispatch

Status: **Finalized — ready after RB3.**
Owner: Mac + Shared Core
Created: 2026-06-14
Updated: 2026-06-14
Depends on: RB3

## The payoff (why the whole milestone exists)

This is where the vibe coder's loop closes: **one prompt became a pressure-tested
spec, and one click hands that spec to the agent that builds it.** No clipboard,
no re-explaining context, no "let me paste the plan into Cursor." The judgment
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
the same runner substrate used for panel members. If the worker is `manual_paste`
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
known non-goals
risks and open questions
explicit direct-dispatch boundary
```

The brief carries RB3's Works Test + proof commands verbatim so the executing
agent knows the done-condition without re-deriving it. If the final spec lacked
them (RB3 disclosed this), the brief surfaces that gap rather than implying the
work is verifiable.

If no final spec exists, the action may create a brief from `master_plan.md`, but
the UI must label that as less reviewed.

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

- [ ] RB4-S01 - `ImplementationBrief` model and Markdown renderer.
- [ ] RB4-S02 - Worker picker for handoff target; default comes from
  `WorkflowPreset.executionWorkerId` when present.
- [ ] RB4-S03 - Execution working-directory picker/default. Store the path in
  the run/brief; do not create a worktree.
- [ ] RB4-S04 - Execution prompt builder that assembles a self-contained prompt
  for the selected worker and names the CLI/git boundary explicitly.
- [ ] RB4-S05 - Write `implementation_brief.md` and
  `execution_prompt_<workerId>.md` to the run folder before dispatch.
- [ ] RB4-S06 - Direct dispatch: gate on a `Doctor` healthy check, then invoke
  healthy `headless_cli` workers with the execution prompt in the configured
  working directory; capture stdout/stderr or output file per the driver manifest.
- [ ] RB4-S07 - Manual + reveal-only fallback: for `manual_paste`, unhealthy
  workers, or an explicit user choice, reveal/copy the exact prompt without
  invoking and mark the dispatch as manual.
- [ ] RB4-S08 - Dispatch status UI: queued/running/done/failed/timed out plus
  transcript/output when available, written to the run folder.
- [ ] RB4-S09 - Forward-compatibility note in Phase 12: managed lane execution
  consumes `ImplementationBrief` unchanged.

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
- [ ] Transcript/output is captured when the driver supports capture.
- [ ] The brief can become managed Phase 12 input without changing its core
  shape.
- [ ] `swift test` + app test wall green.

## Closeout

MVP execution is useful: Allnighter routes the final spec into the chosen CLI and
saves the operator time. Future managed execution adds worktrees, branch policy,
protected paths, landing, and revert on top of this brief/dispatch shape.
