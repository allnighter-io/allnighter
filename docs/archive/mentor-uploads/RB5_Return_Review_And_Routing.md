# RB5 - Return Review, Outcome Scoring, and Routing

Status: **Specced — the last RB milestone; closes the control loop.**
Owner: Shared Core + Mac
Created: 2026-06-14
Updated: 2026-06-14
Depends on: RB4 (dispatch), 06 (PlanAnalysis, StageOutput, eval harness)

## Why this exists (close the loop)

RB0–RB4 take one prompt to a pressure-tested spec and dispatch it to an executor.
But dispatch is currently **one-way**: Allnighter hands off and walks away, and
the vibe coder is back to reading transcripts by hand. The strategy doc
(`docs/strategy/Allnighter-Agent-Control-Loop-Strategy.md`) defines a Level 4 —
**Return Review and Output Comparison** — that closes the loop:

```text
... -> final spec -> dispatch -> [executor builds] -> capture return
   -> evaluate return vs spec + proofs + rubric
   -> worker scorecards -> recommended next action (rerun | remix | pick)
```

This is the difference between a planning tool and a **control loop**: the team
that plan writerd the plan also plan writers the result, learns which workers deliver, and
tells the founder what to do next — without leaving the app.

## What RB5 reuses (no new substrate)

- **06 `PlanAnalysis` + eval harness** — the return is scored with the same
  rubric machinery used to prove synthesis quality.
- **06 `StageOutput`** — return review and scoring are new `StagePurpose` cases
  (`return_review`, `outcome_score`), appended to the same run.
- **RB4 dispatch capture** — the executor's stdout/diff/exit is already captured.
- **Fan-out engine** — multi-executor compare is a fan-out over text returns
  (still no worktrees; that is deferred managed execution).
- **Phase 05 Doctor / `WorkerAnswer` timing+outcome** — feeds scorecards.

## Non-Goals

- No managed git: still no Allnighter-owned worktrees, branches, commits, landing,
  revert, or protected paths (the RB4 boundary holds).
- No auto-merge or auto-accept of executor output.
- No automatic re-dispatch — routing produces a **recommendation**; the user acts.
- Scorecards and scores are **estimates**, labeled as such (`00` §9 honesty).

## Design

### 1. Capture the return as structured truth

```text
ExecutionReturn
- id
- runId
- executionWorkerId
- workingDirectory
- exitCode?
- transcriptPath        // captured stdout/stderr in the run folder
- diffSummary?          // parsed files-touched / +adds / -dels, when derivable
- status: done|failed|timed_out|partial
- startedAt / finishedAt
```

`ExecutionReturn` is **the embedded payload of the RB4 dispatch
`StageOutput(purpose: .dispatch)`** — the single source of truth, not a duplicate
loose file. `diffSummary` is observational only: at dispatch start Allnighter
records `git rev-parse HEAD` (if the working dir is a git repo); at return it runs
`git diff --stat <saved-HEAD>`. It is best-effort, may include unrelated changes,
and is labeled as such — Allnighter computes nothing about *landing*. (Captured per
RB4's size cap; reveal-only dispatches have a user-pasted return.)

### 2. Return review (reduce, advisory)

A reduce stage — run by a **configurable worker** (`returnReviewWorkerId`, default
the run's plan writer/plan writer) — that reads the final spec (acceptance criteria +
Works Test + proof commands) and the `ExecutionReturn`, then writes
`return_review.md`:

```text
input: final spec (acceptance criteria, Works Test, proof commands) + execution return
output: did the result meet each acceptance criterion? which proof commands pass?
        what is missing, risky, or wrong? what is the single best next action?
```

**Proof execution is OFF by default (safety).** The return review **reveals** the
proof commands for the user to run and paste back (manual path). Auto-execution is
strictly **opt-in** and constrained: only commands matching a **user-editable
allowlist** of safe prefixes (e.g. `swift test`, `xcodebuild test`, `npm test`,
repo-relative `./scripts/*`), each requiring **explicit per-command approval** shown
prominently, run in the execution working directory with a timeout, and fully
logged. Anything else is refused and falls back to manual. The review reports
**which proofs Allnighter executed vs which the user reported.** Advisory only —
never edits the executor's output. (See `00` §12 decision log.)

A return review is available even for a **reveal-only** dispatch: the user pastes
the result the executor produced, and the review proceeds over that.

### 3. Outcome scoring (eval harness, reused)

Score the return against the final spec's acceptance criteria. RB3 emits acceptance
criteria as a **structured list** (one item each) in the `FinalSpecPayload`; RB5
maps each criterion to a `RubricCriterion` (weight defaulting to 1, the user may
adjust) to form a `Rubric`, then scores with the 06 `EvalScore` machinery — same
engine that proves synthesis quality, pointed at execution results. Scores are
estimates and labeled.

### 4. Worker scorecards (learning)

Aggregate outcomes per worker across runs (reusing `WorkerAnswer` timing +
status and `ExecutionReturn` outcomes):

```text
WorkerScorecard
- workerId
- sampleSize             // runs this worker participated in (drives confidence)
- teamAnswerRate        // answered vs failed/timed-out as a worker
- plan writerSuccessRate       // when this worker was the plan writer, it produced a usable plan/spec
- executionSuccessRate   // dispatched returns that met acceptance criteria
- medianLatencyMs
- updatedAt
```

(`planWriterSuccessRate` replaces the earlier "synthesisSelectedRate" — the plan writer is
chosen by the preset, not selected from candidates, so "selected rate" was
meaningless; "did it succeed when it plan writerd" is the informative metric.)

Scorecards are **aggregates over the local run history** (`Runs/`, excluding the
`Evals/` corpus), computed **on demand** — no new telemetry, no upload, no persisted
snapshot to drift. **Small-sample honesty:** a rate from < 5 samples is labeled
"insufficient data"; routing then defers to Doctor health + median latency rather
than a confident-but-empty rate. They seed the deferred scorecards/routing roadmap
(`00` §10) and the eventual preference ledger.

### 5. Routing recommendation (rerun | remix | pick)

From the return review + outcome score + scorecards, recommend one next action:

- **Rerun** — re-dispatch the same brief to a different (healthier / historically
  stronger) worker; or re-run the team at higher depth if the spec itself was
  weak.
- **Remix** — when multiple executors ran (§6), a **reduce over the N returns**:
  input = the final spec + each return's transcript/diff summary + outcome scores;
  output = a new `ImplementationBrief` that names the best parts of each to combine,
  for one more pass. Advisory; the user dispatches it explicitly.
- **Pick** — choose the single best return and stop.

Routing is a labeled suggestion with its reasoning, never an automatic action.
**One-tap setup** hands the chosen action straight into a configured run: Rerun
pre-fills the prior preset + working dir (reusing `reuseKey` so the team isn't
re-run when the spec is unchanged); Remix opens the remix brief; Pick just marks
the winner.

### 6. Multi-executor compare (directory safety is mandatory)

Comparing N executors must **never** run concurrent code-writing agents in one
working directory — they would corrupt each other (no worktrees here). So:

- **Default: sequential.** Dispatch executor A, capture its return, then B, then C
  — each in the **same** working dir is fine because only one runs at a time, and
  the user resets between if they wish. The compare view scores the captured returns
  side by side afterward.
- **Parallel only with distinct dirs.** Parallel dispatch is allowed **only** when
  the user assigns each executor a **separate working directory** (e.g. distinct
  clones). Allnighter never shares one CWD across concurrent executors and never
  creates the dirs itself.
- **Pure-review briefs** (text-out, no file writes) may always run parallel.

This is the text-level precursor to the deferred "races" capability (`00` §10).

## Ordered Slices

- [ ] RB5-S01 - `ExecutionReturn` model + capture into the run folder; transcript
  persisted; `diffSummary` parsed when a git repo is detected. Fixtures + tests.
- [ ] RB5-S02 - Return-review reduce (worker = `returnReviewWorkerId`, default the
  plan writer) + `return_review.md`; **manual proof reveal by default**, opt-in allowlist
  execution with per-command approval + timeout + logging.
- [ ] RB5-S03 - Acceptance criteria → `Rubric` mapping (from RB3's structured
  criteria) + outcome scoring via the 06 `EvalScore` machinery; persisted.
- [ ] RB5-S04 - `WorkerScorecard` on-demand aggregation over `Runs/` (excluding
  `Evals/`); small-sample "insufficient data" labeling; scorecard UI.
- [ ] RB5-S05 - Routing recommendation (rerun | remix | pick) with reasoning;
  one-tap setup (preset + working dir + `reuseKey` handoff).
- [ ] RB5-S06 - Multi-executor compare: **sequential by default**; parallel only
  with distinct per-executor working dirs; side-by-side scored comparison. Remix =
  a reduce over returns producing a new `ImplementationBrief`.
- [ ] RB5-S07 - `bundle.md` extends to include execution return, return review,
  outcome score, and the routing recommendation.

## Works Test

```text
Dispatch a final spec to a healthy worker (RB4). After it returns, RB5 captures
the transcript, runs the return review against the spec's acceptance criteria +
proof commands (running the proofs with consent), produces an outcome score, and
recommends rerun/remix/pick with reasoning. Dispatch the same brief to a second
worker; the compare view scores both returns side by side. Worker scorecards
update from local history. No worktree, branch, commit, landing, or revert rule
is created.
```

## Exit Gates

- [ ] Execution return is captured as structured truth with a persisted transcript.
- [ ] Return review evaluates each acceptance criterion + proof command, advisory,
  never mutating the executor's output.
- [ ] Outcome scores reuse the 06 eval harness and are labeled estimates.
- [ ] Worker scorecards aggregate from local history only — no upload, no telemetry;
  rates from < 5 samples are labeled "insufficient data."
- [ ] Proof commands default to manual reveal; auto-execution is allowlist + per-
  command approval only, and the review records executed-vs-reported.
- [ ] Multi-executor compare is sequential by default; parallel only with distinct
  working dirs; still no worktrees/git rules.
- [ ] Routing produces a recommendation with reasoning; it never auto-acts.
- [ ] `swift test` + app test wall green.

## Closeout

The control loop is closed: plan writer → plan → review → final spec → dispatch →
**evaluate → route**. Allnighter now learns which workers deliver and tells the
founder what to do next. This is the substrate the deferred roadmap (managed lanes,
races, preference ledger) builds on — and it composes with the **Team-as-Tool**
surface (`RB6`, specced) — none of which requires reworking the team run model
established in Phase 06.
