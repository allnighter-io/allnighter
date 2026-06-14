# 02 — Worker Drivers + Parallel Fan-Out Engine

Status: Draft — **the heart of the product**
Depends on: 01
Owner: Mac (engine layer)
Created: 2026-06-14

## Goal

Build the engine that turns one prompt into N parallel CLI invocations and
collects normalized results: a subprocess `WorkerRunner`, a manifest-driven
driver layer, worker detection + smoke tests (Doctor data), and the
`CouncilRunCoordinator` that fans out via a `TaskGroup`, enforces per-worker
timeouts, supports cancellation, and emits the `RunEvent` stream. No synthesis
yet, no UI — this is the reusable execution substrate (it is what the full
factory's agent runtime grows from).

## Non-Goals

- Synthesis / master plan (Phase 04). UI (Phase 03). Persistence beyond what a
  test harness needs. Lanes/worktrees (Growth Seam).

## Approach (per `00`)

- **`WorkerRunner`** (`actor`): given a `DriverManifest.invoke` + a resolved
  prompt + model, spawns the CLI via `Foundation.Process` in **its own process
  group**, passes the prompt as a single `argv` element or via stdin (never
  shell-concatenated, `00` §9), captures stdout/stderr, strips ANSI, enforces
  `timeoutSeconds`, and returns a `MemberResponse`. Completion via `doneSignal`
  (exit_code first; idle_timeout backstop).
- **Driver layer**: a manifest loader (bundled defaults in
  `Apps/AllnighterMac/Drivers/*.json` + user overrides in Config), template
  substitution (`{{prompt}}`, `{{model}}`, `{{workingDir}}`), and a
  `MockDriver` for tests.
- **Detection + smoke test**: run `detectCommand` (presence/version) and
  `smokeTestCommand` (expects `smokeTestExpect`) to mark each worker
  healthy/unhealthy with a reason. This is the churn defense and feeds Doctor
  (Phase 05).
- **`CouncilRunCoordinator`** (`actor`): builds `MemberPrompt`s (MVP: identical
  text for all), fans out enabled members concurrently with a `TaskGroup`,
  updates `CouncilRun`/`MemberResponse`, emits `RunEvent`s, and resolves the run
  to `answers_in` / `partial` (when some failed). A global **cancel** tears down
  all child process groups.
- **Manual-paste workers**: `manual_paste` members are emitted as `skipped` with
  the resolved prompt attached so the UI can collect a pasted answer later.
- **Error taxonomy**: `missing_cli`, `auth_required`, `timed_out`,
  `nonzero_exit`, `empty_output`, `cancelled` — each a clear `errorReason`.

## Ordered Slices

- [ ] P02-S01 — `WorkerRunner`: process-group spawn, argv/stdin prompt passing,
  stdout/stderr capture, ANSI strip, exit-code completion.
- [ ] P02-S02 — Per-worker timeout + idle backstop + clean kill of the process group.
- [ ] P02-S03 — Manifest loader (bundled + user override) + template substitution
  (injection-safe) + `MockDriver`.
- [ ] P02-S04 — Worker detection + smoke test → health + reason (Doctor data).
- [ ] P02-S05 — `CouncilRunCoordinator` fan-out via `TaskGroup`; build identical
  member prompts; collect `MemberResponse`s; resolve `answers_in` / `partial`.
- [ ] P02-S06 — `RunEvent` emission (`run.*`, `member.*`) as an `AsyncStream`.
- [ ] P02-S07 — Global cancel (stop all children) + error taxonomy + `manual_paste`
  members emitted as `skipped` with prompt attached.

## Works Test

```text
Headless harness: configure the panel with at least two REAL workers
(e.g. Opus 4.8 and Sonnet 4.6 via `claude -p --model`). Fan out one prompt.
Both run in parallel, each returns a captured answer with status `done`,
timing, and exit code. Force one worker to a bad command and confirm it resolves
`failed` with a reason while the run still reaches `partial`. Set a tiny timeout
and confirm `timed_out` + the child process is actually killed. Re-run with the
MockDriver in `swift test` for deterministic CI.
```

## Exit Gates

- [ ] Works Test passes with real CLIs and with the MockDriver (CI).
- [ ] Parallelism verified: total wall time ≈ slowest worker, not the sum.
- [ ] No shell injection path (prompts never concatenated into a shell string).
- [ ] Timeouts kill the whole process group; global cancel leaves no orphans.
- [ ] A failed/missing worker never blocks the run (`partial`).
- [ ] `swift test` green.

## Closeout

Activate Phase 03 (Mac App + Run Loop), which drives this engine from the UI.
