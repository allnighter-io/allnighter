# 02 — Model Drivers + Parallel Fan-Out Engine

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
`TeamRunCoordinator` that fans out via a `TaskGroup`, enforces per-worker
timeouts, supports cancellation, and emits the `RunEvent` stream. No synthesis
yet, no UI — this is the reusable execution substrate (it is what the full
factory's agent runtime grows from).

## Non-Goals

- Synthesis / plan (Phase 04). UI (Phase 03). Persistence beyond what a
  test harness needs. Lanes/worktrees (Growth Seam).

## Approach (per `00`)

- **`WorkerRunner`** (`actor`): given a `DriverManifest.invoke` + a resolved
  prompt + model, spawns the CLI via `Foundation.Process` in **its own process
  group**, passes the prompt as a single `argv` element or via stdin (never
  shell-concatenated, `00` §9), captures stdout/stderr, strips ANSI, enforces
  `timeoutSeconds`, and returns a `WorkerAnswer`. Completion via `doneSignal`
  (exit_code first; idle_timeout backstop).
- **Driver layer**: a manifest loader (bundled defaults in
  `Apps/AllnighterMac/Drivers/*.json` + user overrides in Config), template
  substitution (`{{prompt}}`, `{{model}}`, `{{workingDir}}`), and a
  `MockDriver` for tests.
- **Detection + smoke test**: run `detectCommand` (presence/version) and
  `smokeTestCommand` (expects `smokeTestExpect`) to mark each worker
  healthy/unhealthy with a reason. This is the churn defense and feeds Doctor
  (Phase 05).
- **`TeamRunCoordinator`** (`actor`): builds `WorkerPrompt`s (MVP: identical
  text for all), fans out enabled members concurrently with a `TaskGroup`,
  updates `TeamRun`/`WorkerAnswer`, emits `RunEvent`s, and resolves the run
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
- [x] P02-S04 — Model detection + smoke test → health + reason
  (`ModelHealthChecker`; `ShellWords` tokenizes trusted manifest commands).
- [x] P02-S05 — `TeamRunCoordinator` fan-out via `TaskGroup`; identical
  member prompts; collect `WorkerAnswer`s; resolve `answers_in`.
- [x] P02-S06 — `RunEvent` emission (`run.*`, `member.*`) as an `AsyncStream`
  with monotonic, gap-free `seq`.
- [x] P02-S07 — Global cancel (cancel the fan-out task → children terminated) +
  error taxonomy + `manual_paste` members resolved as `skipped`.

> **State-model clarification:** the Phase 02 run resolves to **`answers_in`**
> (or `cancelled`), never `partial`. A failed/missing/timed-out member does
> **not** block the run — it simply lands in `failedWorkerAnswers` while the run still
> reaches `answers_in`. `partial` is a *synthesis-stage* terminal (Phase 04:
> members readable but no plan), per the Core state machine which is the
> truth owner.

## Works Test

```text
Deterministic CI (no cost): MockCommandRunner + real /bin tools.
- Fan out one prompt to 3 workers; all run IN PARALLEL (3x 400ms ≈ <1s, not 1.2s)
  and resolve `done`; run reaches `answers_in`.
- One worker scripted to exit 1 and one to time out: run still reaches
  `answers_in` with answeredWorkers=1, failedWorkerAnswers=2 (no blocking).
- Cancel the fan-out task mid-run: run resolves `cancelled`.
- RunEvents emitted for run + member transitions with gap-free seq.
SubprocessCommandRunner proven against /bin/echo (capture), /bin/cat (stdin),
/bin/sleep (timeout kill < 5s), a missing binary (launchError), and Task cancel.
```

**Result (2026-06-14):** `swift test` → 51 passing (24 Core + 27 Engine), clean
build, no warnings.

## Exit Gates

- [x] Works Test passes with the MockDriver (CI) + real `/bin` tools.
- [x] **Verified against the founder's real AI CLIs** (on-device probe, 2026-06-14
  — see below).
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

### On-device CLI verification — DONE (2026-06-14)

Probed the founder's machine and confirmed each headless invocation returns a
clean answer; the bundled manifests in `Apps/AllnighterMac/Resources/Drivers/`
now encode these exact commands:

| Model | CLI | Verified command | Capture |
| --- | --- | --- | --- |
| Opus 4.8 / Sonnet 4.6 | `claude` 2.1.177 | `claude -p "<prompt>" --model opus`/`sonnet` | stdout |
| Grok Build | `grok` 0.2.51 | `grok -p "<prompt>" -m grok-build --output-format plain` | stdout |
| Composer 2.5 | `grok` (same CLI) | `grok -p "<prompt>" -m grok-composer-2.5-fast --output-format plain` | stdout |
| ChatGPT 5.5 | `codex` 0.130.0 | `codex exec --skip-git-repo-check --color never -o <file> "<prompt>"` (default model **gpt-5.5**) | **file** |
| Gemini (Antigravity) | `agy` 1.0.8 (Antigravity CLI) | `agy --print "<prompt>" --model "Gemini 3.5 Flash (Medium)" --dangerously-skip-permissions` | stdout |

> **Gemini graduated from `manual_paste` → headless (verified on-device 2026-06-15).**
> Google's **Antigravity CLI** (`agy` 1.0.8, successor to the legacy gemini-cli;
> install `curl -fsSL https://antigravity.google/cli/install.sh | bash`) drives
> Gemini headlessly via `--print` + `--dangerously-skip-permissions` (auto-approves
> tool permissions for unattended runs). `--model` takes the **display-name** form
> from `agy models` (e.g. `"Gemini 3.5 Flash (Medium)"`) — confirmed by a live
> `agy --print … --model …` call. `agy --version` is the detect probe. Driver
> `antigravity` replaces the old `gemini` manual manifest (the generic `manual_paste`
> driver remains for any other un-scriptable CLI). This `agy` capability also powers
> the design lane's image gen (`docs/mvp/Design0`).

Two engine changes came out of the probe (both unit-tested):

1. **stdin = `/dev/null`** when no input is piped — without it `claude -p` waits
   3s and `codex exec` **hangs forever** reading stdin.
2. **File capture** (`output.capture: "file"` + `{{outputFile}}` token) — codex's
   stdout is noisy (preamble + token count); `-o <file>` yields just the answer.

`grok models` is the source of truth for grok model ids. `grok` emits unrelated
MCP-config errors on **stderr** that do not pollute the captured stdout answer.
Anything not scriptable stays `manual_paste` and still appears in the panel.
