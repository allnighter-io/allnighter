# CR-05 — OpenCodeServeCoordinator lifecycle

## Summary
`ensureRunning` is idempotent on the happy path and the `SpawnState` actor
correctly serializes the spawn claim so two concurrent callers do not double-spawn.
But the coordinator has no liveness tracking for the child it spawns: once
`setSpawnedPID` records a PID, it is never cleared on child exit, so `claimSpawn`
returns false forever and a crashed serve process can never be restarted — every
later caller throws `healthCheckTimedOut` instead. The health check also has no
ownership proof: any process answering 2xx on :4096 is trusted as "our opencode,"
so a port collision or stale foreign process is a silent false positive. Two
further real wins: the spawned `Process` handle is local and discarded (no
`stop()`/shutdown path, no `terminationHandler`), and the stdout/stderr `Pipe`s
are never drained — so the real spawn error (e.g. "port already in use") is
trapped in an unreadable 64 KB pipe buffer that can also deadlock the child.

## Findings

### P0 — Crashed child cannot be restarted; `spawnedPID` is never cleared on exit
- **Invariant:** `ensureRunning` must be able to establish a healthy serve process
  when none is running. A coordinator that spawned once must remain able to spawn
  again after its child exits.
- **Evidence:** `setSpawnedPID` (`OpenCodeServeCoordinator.swift:84-85`) sets
  `spawnedPID` to the real PID after a successful `process.run()`
  (`OpenCodeServeCoordinator.swift:63`). `releaseSpawn`
  (`OpenCodeServeCoordinator.swift:88-89`) is the only code that clears
  `spawnedPID` back to `nil`, and it is called *only* on the two pre-spawn failure
  paths (`:46` executable-not-found, `:60` `process.run` throw). There is no
  `terminationHandler`, no `kill(pid, 0)` liveness probe, and no code path that
  calls `releaseSpawn` when an already-spawned child exits. `claimSpawn`
  (`OpenCodeServeCoordinator.swift:78-82`) guards on `spawnedPID == nil`
  (`:79`), so once a non-zero PID is set, every subsequent caller gets
  `shouldSpawn == false` (`:40-41`) and falls into the wait loop
  (`:67-70`). If the child has died, health never returns, the loop times out,
  and `healthCheckTimedOut` (`:71`) is thrown — forever, for every caller. The
  coordinator cannot recover a crashed child, which breaks "restart mid-slice"
  and the core `ensureRunning` contract under a normal failure mode.
- **Suggested fix:** retain the `Process` handle in `SpawnState` (not just the
  `Int32` PID) and install `process.terminationHandler = { [state] _ in Task
  { await state.releaseSpawn() } }` so a child exit frees the claim. Optionally,
  in the wait loop, probe `kill(spawnedPID, 0)` and if it is dead, `releaseSpawn`
  and re-claim. Either way, `releaseSpawn` must be reachable from the
  child-exit path, not only the spawn-failure paths.
- **Suggested slice:** "ServeCoordinator: child-exit detection + respawn"

### P0 — No ownership proof on health; any 2xx on :4096 is a false positive
- **Invariant:** `isHealthy()` returning true must mean *this coordinator's*
  `opencode serve` is answering — not an arbitrary process that happens to listen
  on :4096.
- **Evidence:** `isHealthy` (`OpenCodeServeCoordinator.swift:33-35`) only checks
  an HTTP 2xx on `defaultURL` (`:10`, used at `:17`). `ensureRunning` returns
  immediately on `isHealthy()` (`:38`) without verifying the responder is the
  process it spawned. `spawnedPID` (`:84`) is stored but never compared to the
  PID actually owning :4096. Three concrete false-positive paths: (1) a stale
  `opencode serve` from a previous app run that the new `SpawnState` does not
  know about is trusted as healthy and never adopted or restarted; (2) an
  unrelated dev server on :4096 makes `ensureRunning` a no-op — the coordinator
  believes it is serving when it is not; (3) if the spawned child dies and a
  different process grabs :4096, `isHealthy` flips back to true and the dead
  child is never restarted (compounds the first P0).
- **Suggested fix:** after spawning, verify the :4096 listener PID matches
  `spawnedPID` (e.g. `lsof -iTCP:4096 -sTCP:LISTEN -t` or a `libproc` call). On
  cold start where `spawnedPID == nil` but the port is live, either adopt (after
  proving it is `opencode`) or fail loud rather than silently trusting. A
  opencode-specific health endpoint or response body marker is stronger than a
  bare 2xx.
- **Suggested slice:** "ServeCoordinator: port-ownership proof on health"

### P1 — Concurrent loser waits 10 s for a spawn that already failed (wrong error)
- **Invariant:** a caller that did not win the spawn claim must not be made to
  wait for a process that was never spawned, and must surface the real spawn
  error rather than a timeout.
- **Evidence:** Caller A wins `claimSpawn` (`:40`, sets `spawnedPID = 0` at
  `:80`), fails to resolve the executable, calls `releaseSpawn` (`:46`), and
  throws `opencodeExecutableNotFound` (`:47`). Caller B had `claimSpawn` return
  false (because `spawnedPID` was momentarily `0`, non-nil), so B skips the spawn
  block (`:41`) and enters the wait loop (`:67-70`). B waits the full 10 s
  deadline (`:66`) then throws `healthCheckTimedOut` (`:71`) — even though no
  process was ever spawned and the real failure was `opencodeExecutableNotFound`.
  The error is misleading and 10 s is wasted. The same applies to the
  `spawnFailed` path at `:60-61`.
- **Suggested fix:** in the wait loop, re-check spawn state: if `spawnedPID` is
  `nil` (spawn was released), re-attempt `claimSpawn` or re-throw the recorded
  spawn error. Store the spawn failure error in `SpawnState` and have waiters
  re-throw it rather than timing out.
- **Suggested slice:** "ServeCoordinator: propagate spawn failure to waiting callers"

### P1 — `Process` handle is local and discarded; no `stop()`/shutdown path
- **Invariant:** a coordinator that starts a long-lived child must own its full
  lifecycle — including clean termination — and must retain the handle needed to
  monitor and stop it.
- **Evidence:** `let process = Process()` (`OpenCodeServeCoordinator.swift:50`)
  is local to `ensureRunning`. After the function returns, only
  `process.processIdentifier` (an `Int32`) survives in `SpawnState` (`:63`). The
  `Process` object — and with it `terminationHandler`, `isRunning`, and
  `terminate()` — is lost. There is no public `stop()`/`shutdown()` method on
  `OpenCodeServeCoordinator`. The coordinator can start a serve but never stop
  it: the child outlives the coordinator, there is no clean teardown for app
  exit or "restart mid-slice," and the only way to kill a tracked PID would be a
  raw `kill(pid, SIGTERM)` syscall that is not implemented. This also blocks the
  first P0's `terminationHandler` fix.
- **Suggested fix:** store the `Process` (or a small `Sendable` wrapper) in
  `SpawnState` alongside the PID. Add `func stop() async` that sends `SIGTERM`,
  waits a grace period, then `SIGKILL`, and calls `releaseSpawn`. Call it from
  app teardown and before any re-spawn.
- **Suggested slice:** "ServeCoordinator: retain Process + add stop()"

### P1 — stdout/stderr `Pipe`s are never drained; real error is lost and child can deadlock
- **Invariant:** a spawned long-lived process's stdout/stderr must either be
  drained, redirected to a file/null, or captured into the error path — never
  left in an unread `Pipe` whose 64 KB buffer blocks the child.
- **Evidence:** `process.standardOutput = Pipe()` (`OpenCodeServeCoordinator.swift:53`)
  and `process.standardError = Pipe()` (`:54`) create pipes that are never read
  by anyone. Two consequences: (1) if `opencode serve` logs enough to fill the
  pipe buffer (typically 64 KB), the child blocks on `write` and silently hangs
  — `ensureRunning` then times out (`:71`) with no clue why; (2) the real reason
  for a fast spawn-then-die (e.g. "port already in use", bad config, missing
  subcommand) is in the unread stderr buffer and is discarded, so the caller
  sees only `healthCheckTimedOut`. `standardInput` is correctly set to
  `nullDevice` (`:55`), which makes the undrained output pipes the more glaring
  asymmetry.
- **Suggested fix:** either drain both pipes on a background `Task` into a ring
  buffer, redirect to a log file under the app's logs dir, or set both to
  `FileHandle.nullDevice` if logging is unwanted. On timeout/spawn-failure,
  surface captured stderr in the thrown error (e.g. add an associated `diagnostics:
  String` to `healthCheckTimedOut`).
- **Suggested slice:** "ServeCoordinator: capture child stderr into errors"

### P2 — `defaultPort` and the port inside `defaultURL` can drift
- **Invariant (clarity):** the port used to spawn and the port used to health-check
  must be derived from one source of truth.
- **Evidence:** `defaultURL` (`OpenCodeServeCoordinator.swift:10`) hardcodes
  `:4096` as a string literal; `defaultPort` (`:11`) is a separate `Int`. The
  spawn args use `String(Self.defaultPort)` (`:52`), but the health check uses
  `defaultURL` (`:17`). Changing `defaultPort` does not update `defaultURL`'s
  port — the coordinator would spawn on the new port and health-check the old
  one, timing out forever.
- **Suggested fix:** construct `defaultURL` from `defaultPort`:
  `URL(string: "http://127.0.0.1:\(defaultPort)")!`, or make `defaultURL` a
  computed property.
- **Suggested slice:** (nit, fold into the next touch of this file)

### P2 — Per-poll 2 s timeout makes the 250 ms poll cadence misleading and can overshoot the deadline
- **Invariant (clarity):** the wait loop's effective poll interval and wall-clock
  budget should match what the code appears to express.
- **Evidence:** each `isHealthy()` in the wait loop (`OpenCodeServeCoordinator.swift:68`)
  can take up to the 2 s `timeoutInterval` (`:19`) when the server is slow to
  respond or the connection hangs. With a 250 ms sleep (`:69`), the *effective*
  poll interval is ≥2 s, so the 10 s deadline (`:66`) allows only ~5 attempts,
  not the ~40 implied by the 250 ms sleep. The deadline check (`:67`) only runs
  at the top of the loop, so a single 2 s poll can also overshoot the 10 s
  budget by up to ~2 s.
- **Suggested fix:** lower the per-poll timeout (e.g. 500 ms) inside the wait
  loop, or compute the remaining time to the deadline and clamp both the poll
  timeout and the sleep.
- **Suggested slice:** (nit, optional)

### P2 — `Task.sleep` cancellation surfaces as `CancellationError`, not a coordinator error
- **Invariant (clarity):** `ensureRunning`'s thrown error set should be enumerable
  from its signature/enum; an unadvertised `CancellationError` leak is a footgun.
- **Evidence:** `try await Task.sleep(nanoseconds: 250_000_000)`
  (`OpenCodeServeCoordinator.swift:69`) throws `CancellationError` if the owning
  `Task` is cancelled. This propagates out of `ensureRunning` as a
  non-`OpenCodeServeCoordinatorError`. Callers that `catch` only the
  coordinator's error enum will miss it.
- **Suggested fix:** either document that `ensureRunning` can throw
  `CancellationError`, or catch it and convert to a new `.cancelled` case (or
  rethrow as `healthCheckTimedOut` if cancellation should be treated as a
  timeout).
- **Suggested slice:** (nit, optional)

## False alarms ruled out
- **Force-unwrap of `defaultURL` (`:10`).** `URL(string:
  "http://127.0.0.1:4096")!` is a valid constant URL; the force-unwrap is safe.
  Not a finding. (The *drift* between this literal and `defaultPort` is filed as
  a P2.)
- **`@Sendable` health-check closure capturing `URLSession.shared`.**
  `URLSession.shared` is sendable and thread-safe; the closure is correctly
  marked `@escaping @Sendable`. Sound.
- **Double-spawn race between `isHealthy` and `claimSpawn`.** `claimSpawn`
  (`:78-82`) atomically sets `spawnedPID = 0` (`:80`) under the actor lock, so
  exactly one concurrent caller gets `true`. No double-spawn. (The *converse*
  issue — a loser waiting on a failed spawn — is real and filed as P1.)
- **`ProcessInfo.processInfo.environment` captured in `ensureRunning`.** This is
  a read-only snapshot used for PATH resolution of `opencode`; idiomatic and
  safe. (Forwarding the *full* env to a `/bin/sh -c` would be a secret surface,
  as in CR-04, but here the child is `opencode serve` directly, not a shell, and
  the env is used for resolution, not forwarded as a shell env.)
- **Child inheriting the parent environment.** `process.environment` is unset, so
  `Process` inherits the parent env by default — correct for a `opencode serve`
  that may itself spawn subprocesses needing `PATH`/`HOME`.
- **`Sendable` soundness of `OpenCodeServeCoordinator`.** Holds: the struct holds
  a `@Sendable` closure and a `Sendable` `actor` (`SpawnState`). No mutable
  non-Sendable state.
- **10 s deadline being too short.** That is a tunable, not a defect; the
  deadline logic itself (`:66-71`) is correct for a healthy spawn. The defect is
  what it *masks* (P0/P1 above), not the duration.

## Greps avoided
- Did not read or grep any file outside the inlined
  `OpenCodeServeCoordinator.swift` source. `SubprocessCommandRunner.resolveExecutable`
  was treated as an opaque resolved symbol per the review instructions; its
  behavior was not inspected. No repo exploration was performed. All line
  numbers are derived from the inlined source and the resolved-symbol anchors
  (`isHealthy` :33, `ensureRunning` :37, `claimSpawn` :78, `setSpawnedPID` :84,
  `releaseSpawn` :88).