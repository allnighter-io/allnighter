# CR-05 — verified

## Summary
Both P0 findings are **upheld**. The inlined source confirms each failure
mechanism exactly as described: `spawnedPID` is set on a successful spawn and
cleared only on the two pre-spawn failure paths (no `terminationHandler`, no
liveness probe, no child-exit → `releaseSpawn` path), so a crashed child pins
the claim forever and every later caller times out with `healthCheckTimedOut`.
The health check is a bare 2xx probe on `:4096` with no ownership proof —
`spawnedPID` is stored but never compared to the port's actual listener — so a
stale or foreign process answering 2xx is a silent false positive. No
counter-evidence found in the inlined source for either P0. P1/P2 spot-checked;
none materially wrong.

## P0 adjudication

### P0 — Crashed child cannot be restarted; `spawnedPID` is never cleared on exit — Uphold
- **Original claim:** Once `setSpawnedPID` records a PID, it is never cleared on
  child exit, so `claimSpawn` returns false forever and a crashed serve process
  can never be restarted; every later caller throws `healthCheckTimedOut`.
- **Verdict:** Uphold
- **Evidence:** `setSpawnedPID` (`OpenCodeServeCoordinator.swift:84-85`) sets
  `spawnedPID = pid` and is the post-`process.run()` success recorder (`:63`).
  `releaseSpawn` (`:88-89`) is the only code that sets `spawnedPID = nil`, and
  it is called at exactly two sites: `:46` (executable-not-found) and `:61`
  (`process.run` throw) — both pre-spawn failure paths. There is no
  `terminationHandler` on the `Process`, no `kill(pid, 0)` liveness probe, and
  no code path from child-exit to `releaseSpawn` anywhere in the inlined source.
  `claimSpawn` (`:78-82`) guards `spawnedPID == nil` (`:79`); once a non-zero
  PID is set, it returns `false` for every subsequent caller. A second caller
  after the child has died therefore: `isHealthy()` → false (dead child,
  `:38`), `claimSpawn()` → false (non-nil dead PID, `:79`), skips the spawn
  block (`:41`), enters the wait loop (`:67-70`), `isHealthy()` stays false,
  the 10 s deadline elapses (`:66`), and `healthCheckTimedOut` is thrown
  (`:71`). The mechanism requires no actor suspension beyond the standard
  `await` on `claimSpawn`/`releaseSpawn`/`isHealthy` — all of which are present
  in source. The claim is confirmed exactly.

### P0 — No ownership proof on health; any 2xx on :4096 is a false positive — Uphold
- **Original claim:** `isHealthy()` returning true does not prove *this
  coordinator's* `opencode serve` is answering; any process returning 2xx on
  `:4096` is trusted, yielding silent false positives (stale serve, foreign dev
  server, or a replacement process after child death).
- **Verdict:** Uphold
- **Evidence:** The default `healthCheck` closure (`:14-26`) issues an HTTP GET
  to `defaultURL` (`:10`, `http://127.0.0.1:4096`) and returns `true` iff the
  status is in `200..<300` (`:21`). It performs no PID comparison, no response
  marker check, and no process-identity verification. `isHealthy()`
  (`:33-35`) delegates directly to `healthCheck`. `ensureRunning` returns
  immediately on `if await isHealthy() { return }` (`:38`) with no ownership
  proof. `spawnedPID` is recorded (`:63`, `:84-85`) but is never read back or
  compared to the PID owning `:4096` anywhere in the inlined source. The three
  false-positive paths are direct consequences: (1) cold start with a stale
  `opencode serve` — `spawnedPID == nil`, `isHealthy()` → true, `ensureRunning`
  returns without spawning, adopting, or restarting; (2) an unrelated dev server
  on `:4096` — `ensureRunning` is a silent no-op; (3) spawned child dies and a
  different process grabs `:4096` — in the wait loop `isHealthy()` flips to
  true (`:68`) and `ensureRunning` returns, so the dead child is never
  restarted (compounds the first P0, where `spawnedPID` is never cleared). The
  `healthCheck` closure is injectable via `init`, but the default ships with no
  ownership proof and `ensureRunning` does not require one — the defect is in
  the coordinator's contract, not merely the default closure. No
  counter-evidence in source.

## P1 notes
Spot-checked all three P1s against the inlined source; none materially wrong.

- **P1 (concurrent loser waits 10 s):** Confirmed. The wait loop (`:67-70`)
  calls only `isHealthy()` and `Task.sleep`; it never re-checks `claimSpawn` or
  re-reads `spawnedPID`. So if the winner fails and calls `releaseSpawn`
  (`:46`/`:61`), the loser still loops to the 10 s deadline and throws
  `healthCheckTimedOut` (`:71`) rather than the winner's
  `opencodeExecutableNotFound` / `spawnFailed`. The recorded spawn error is not
  stored in `SpawnState` for waiters to re-throw. Mechanism as described.
- **P1 (Process handle local and discarded):** Confirmed. `let process =
  Process()` (`:50`) is local to `ensureRunning`; only
  `process.processIdentifier` survives via `setSpawnedPID` (`:63`). No
  `terminationHandler` is installed, no `stop()`/`shutdown()` method exists on
  `OpenCodeServeCoordinator`, and `terminate()`/`isRunning` are unreachable
  after return. This also blocks the first P0's suggested `terminationHandler`
  fix.
- **P1 (Pipes never drained):** Confirmed. `process.standardOutput = Pipe()`
  (`:53`) and `process.standardError = Pipe()` (`:54`) create pipes that are
  never read by any code in the inlined source. `standardInput` is correctly
  `nullDevice` (`:55`), making the undrained output pipes the asymmetry. The
  64 KB buffer deadlock and lost-stderr-error consequences follow.

## Greps avoided
- Did not read or grep any file outside the inlined
  `OpenCodeServeCoordinator.swift` source. `SubprocessCommandRunner.resolveExecutable`
  was treated as an opaque resolved symbol per the review instructions; its
  behavior was not inspected. No repo exploration was performed. All line
  numbers are derived from the inlined source and the resolved-symbol anchors
  (`isHealthy` :33, `ensureRunning` :37, `claimSpawn` :78, `setSpawnedPID`
  :84, `releaseSpawn` :88).