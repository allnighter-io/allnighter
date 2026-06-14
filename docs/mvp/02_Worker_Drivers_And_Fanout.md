# 02 — Worker Drivers + Parallel Fan-Out Engine

Status: **Complete (engine + MockDriver)** — real-CLI verification deferred to a
separate on-device probe (founder chose mock-first). `swift test`: 51 passing.
Depends on: 01
Owner: Mac (engine layer)
Created: 2026-06-14
Completed: 2026-06-14

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

- [x] P02-S01 — `WorkerRunner`: argv/stdin prompt passing, stdout/stderr capture,
  ANSI strip, exit-code completion. (`SubprocessCommandRunner` + `WorkerRunner`.)
- [x] P02-S02 — Per-worker timeout + clean kill of the process group
  (`setpgid` + negative-pid `SIGTERM`; cancel honored via task cancellation).
- [x] P02-S03 — Manifest store + user override (`DriverRegistry`) + injection-safe
  template substitution (reused from Core) + `MockCommandRunner`.
- [x] P02-S04 — Worker detection + smoke test → health + reason
  (`WorkerHealthChecker`; `ShellWords` tokenizes trusted manifest commands).
- [x] P02-S05 — `CouncilRunCoordinator` fan-out via `TaskGroup`; identical
  member prompts; collect `MemberResponse`s; resolve `answers_in`.
- [x] P02-S06 — `RunEvent` emission (`run.*`, `member.*`) as an `AsyncStream`
  with monotonic, gap-free `seq`.
- [x] P02-S07 — Global cancel (cancel the fan-out task → children terminated) +
  error taxonomy + `manual_paste` members resolved as `skipped`.

> **State-model clarification:** the Phase 02 run resolves to **`answers_in`**
> (or `cancelled`), never `partial`. A failed/missing/timed-out member does
> **not** block the run — it simply lands in `failedMembers` while the run still
> reaches `answers_in`. `partial` is a *synthesis-stage* terminal (Phase 04:
> members readable but no master plan), per the Core state machine which is the
> truth owner.

## Works Test

```text
Deterministic CI (no cost): MockCommandRunner + real /bin tools.
- Fan out one prompt to 3 workers; all run IN PARALLEL (3x 400ms ≈ <1s, not 1.2s)
  and resolve `done`; run reaches `answers_in`.
- One worker scripted to exit 1 and one to time out: run still reaches
  `answers_in` with answeredMembers=1, failedMembers=2 (no blocking).
- Cancel the fan-out task mid-run: run resolves `cancelled`.
- RunEvents emitted for run + member transitions with gap-free seq.
SubprocessCommandRunner proven against /bin/echo (capture), /bin/cat (stdin),
/bin/sleep (timeout kill < 5s), a missing binary (launchError), and Task cancel.
```

**Result (2026-06-14):** `swift test` → 51 passing (24 Core + 27 Engine), clean
build, no warnings.

## Exit Gates

- [x] Works Test passes with the MockDriver (CI) + real `/bin` tools.
- [ ] **Deferred:** verified against the founder's real AI CLIs (separate
  on-device probe — see below).
- [x] Parallelism verified (3 concurrent ≈ slowest, not the sum).
- [x] No shell injection path (prompt is a single argv element; proven with a
  `a; echo PWNED` payload that stays one line).
- [x] Timeouts kill the process; global cancel leaves no orphan (verified with
  `/bin/sleep`).
- [x] A failed/missing worker never blocks the run (resolves `answers_in`).
- [x] `swift test` green.

## Closeout

**Complete (engine).** The execution substrate lives in
`Packages/AllnighterCore` target **`AllnighterEngine`** (kept separate so
`AllnighterCore` stays pure of I/O). Activate **Phase 03 (Mac App + Run Loop)**,
which drives this engine from the UI.

### Deferred: on-device CLI verification (do before/with Phase 03 real use)

Run each real CLI once to confirm the headless invocation + capture, then commit
corrected bundled manifests:

- `claude -p "..." --model claude-opus-4.8` / `--model claude-sonnet-4.6`
- `grok` headless flag for `--model "Grok Build"` and `"Grok Composer 2.5 Fast"`
  (verify `-p`/headless exists; else mark `manual_paste`)
- ChatGPT 5.5 CLI (`codex`?) headless flag
- Gemini Flash (Antigravity/Gemini CLI) headless flag

The engine needs **no code change** for these — only manifest JSON. Anything not
yet scriptable stays `manual_paste` and still appears in the panel.
