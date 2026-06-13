# 04 — Agent Driver Framework

Status: Draft
Milestone: A (Substrate)
Depends on: 01, 03
Owner: Mac
Created: 2026-06-13

## Goal

Build the thin, versioned **driver layer** that turns a normalized work order into
an agent-specific launch command and turns the agent's output back into
normalized lane events. Ship the first drivers — **shell**, **Claude Code**,
**Codex CLI** — with detection, smoke tests, and completion detection. This is
the churn-resistant integration boundary (`00` §9.8, Principle 9).

## Non-Goals

- Multi-lane races (Phase 11), council (Phase 13), local models (Phase 19).
- IDE handoff (post-MVP). PTY/interactive flows (post-v1 per `00` §9.3).

## Approach (per `00` §9.3, §9.6, §9.8)

- A `Driver` is a JSON **manifest** (`00` §9.8 schema) + a small Swift adapter
  conforming to a `Driver` protocol: `detect()`, `smokeTest()`,
  `launch(workOrder, in: laneWorktree) -> AsyncStream<NormalizedEvent>`,
  `completionSignals`.
- **Headless-first** (`00` §9.3): use `claude -p`, `codex` non-interactive, etc.
  Drivers declaring `needs_pty: true` are refused in v1 with a clear message.
- **Normalization:** raw stdout/stderr lines → `NormalizedEvent`s (output chunk,
  status, artifact-detected, done, error). Stub parsers per driver; full parsing
  is incremental.
- **Completion detection** is layered (exit code → sentinel → JSON done → idle
  timeout) per the manifest's `completion_signals`.
- **Smoke-test gate:** workers run their smoke test on launch/on demand; failures
  mark the worker unhealthy and drop it from routing with a visible reason.
- Manifests are **versioned** (`manifest_version`) and updateable without app
  release where feasible.

## Ordered Slices

- [ ] P04-S01 — `Driver` protocol + manifest loader/validator; worker health model.
- [ ] P04-S02 — Shell driver (runs an arbitrary command in a lane; reference implementation).
- [ ] P04-S03 — Claude Code driver (`detect`, `smoke_test`, `launch` headless, completion via exit/idle).
- [ ] P04-S04 — Codex CLI driver (same surface).
- [ ] P04-S05 — Normalized event stream + per-driver stub parser → `lane.*`/`worker.*` events.
- [ ] P04-S06 — Smoke-test gate wired into worker health + Diagnostics; unhealthy workers excluded from routing.
- [ ] P04-S07 — `MockDriver` parity (scripted output + completion) for tests.

## Works Test

```text
Run a trivial prompt ("create a file FOO.txt with the text BAR") in a lane via
the Claude Code driver:
- the agent runs with cwd = the lane worktree (never the active repo);
- output is captured as normalized lane events;
- completion is detected and the lane transitions to a terminal/ready state;
- the file appears only in the lane worktree.
Detection + smoke test for an unavailable agent marks it unhealthy with a reason.
```

## Exit Gates

- [ ] Works Test passes with at least the shell + Claude Code drivers.
- [ ] Smoke-test gate demonstrably removes an unhealthy worker from routing.
- [ ] MAC-4, MAC-5, MAC-16 satisfied; `00` §9.3 headless rule honored.
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 05. Record any manifest-schema changes in `00` §9.8.
