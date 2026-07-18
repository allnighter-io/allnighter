# CR-24 — Review SubprocessCommandRunner resolution

## Summary
Read-only advisory review of `SubprocessCommandRunner.swift` (lines 160–336)
across executable resolution, PATH/env forwarding, and the streaming run loop.
No P0 (invariant/security) issues found: the token is scrubbed, depth is
incremented, no shell is involved, and the PATH fallback omits `.`. Two P1
reliability wins surface: a `setpgid` race that lets grandchildren escape
kill-on-timeout/cancel, and a deprecated non-throwing `FileHandle.write(_:)`
that can crash the host on a broken pipe. Several P2 nuts follow around
directory-as-executable acceptance, sub-second timeout truncation, a premature
idle-timer seed, and a blocking stdin write.

## Findings

### P0 — None
No invariant or security violations. `ALLNIGHTER_TOOL_TOKEN` is set to `nil`
in the child env (scrubbed), `ALLNIGHTER_TEAM_DEPTH` is incremented (recursion
guard), `process.executableURL` + `process.arguments` are used directly (no
shell, no command injection), and `String.split(separator:":")` defaults to
`omittingEmptySubsequences: true` so empty PATH components are dropped (no
implicit CWD execution from `::`).

### P1 — `setpgid` race leaves grandchildren outside the kill group
- **Invariant:** A timeout or cancel must reach the whole process tree, not
  just the direct child. Orphaned grandchildren keep consuming quota/CPU after
  the run is reported killed.
- **Evidence:** `SubprocessCommandRunner.swift:297` — `setpgid` is called in
  the PARENT after `process.run()`. If the child has already `execve`'d,
  `setpgid` fails with `EACCES` (POSIX: a parent may not move a child that has
  exec'd into a new group). The return value is ignored. `killGroup`
  (`SubprocessCommandRunner.swift:330`) then calls `kill(-pid, SIGTERM)`,
  which fails with `ESRCH` (`pid` is not a group leader), and falls back to
  `process.terminate()` — killing only the direct child. Any grandchildren the
  CLI spawned (e.g. `git`, `node`, a model server) survive as orphans.
- **Suggested fix:** Use `posix_spawn` with `POSIX_SPAWN_SETGROUP` +
  `POSIX_SPAWN_SETEXGROUP` so the child enters its own group before exec, with
  no parent/child race. If that is too large a change, at minimum have the
  child call `setpgid(0, 0)` early via a shim and keep the parent's best-effort
  `setpgid(pid, pid)` (both calls are idempotent; whichever wins first is
  fine). Pair with the P2 below to surface the failure in debug builds.
- **Suggested slice:** `setpgid-before-exec via posix_spawn`

### P1 — Deprecated `FileHandle.write(_:)` can crash on broken pipe
- **Invariant:** A fast-exiting child must not take the host down with it.
- **Evidence:** `SubprocessCommandRunner.swift:302` —
  `handle.write(Data(stdin.utf8))` uses the deprecated non-throwing
  `FileHandle.write(_:)`. On a broken pipe (child exited before reading stdin,
  e.g. a bad-flag CLI that fails in <1ms), the underlying `write(2)` returns
  `EPIPE` and Foundation raises `NSFileHandleOperationException` — an
  `NSException` that Swift `do/catch` cannot intercept, crashing the process.
  The adjacent `try? handle.close()` shows the throwing style is available but
  unused for the write.
- **Suggested fix:** `try? handle.write(contentsOf: Data(stdin.utf8))` (the
  throwing, non-deprecated replacement). Optionally surface a non-fatal error
  instead of swallowing, but the crash must go.
- **Suggested slice:** `stdin write uses throwing write(contentsOf:)`

### P2 — `resolveExecutable` accepts directories as executables
- **Invariant:** A resolved URL should point to an executable file, not a
  directory.
- **Evidence:** `SubprocessCommandRunner.swift:316` and `:321` —
  `FileManager.default.isExecutableFile(atPath:)` returns `true` for any path
  with an execute bit, including directories (which always have `x` for
  traversal). If a PATH component contains a subdirectory named the same as
  the command, it is returned as the executable URL; `process.run()` then
  fails with `EISDIR`/`EACCES` and `launch` surfaces a generic "failed to
  launch" message that hides the real cause.
- **Suggested fix:** Use `var isDir: ObjCBool = false;
  FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir)`
  and require `!isDir.boolValue` alongside `isExecutableFile`.

### P2 — `setpgid` return value silently ignored
- **Evidence:** `SubprocessCommandRunner.swift:297` — the return of `setpgid`
  is discarded. On `EACCES` (child already exec'd) this is the root cause of
  the P1 above; logging or asserting would have surfaced it in testing.
- **Suggested fix:** At minimum `assert(setpgid(...) == 0 || errno == EACCES)`
  in debug builds; pair with the P1 fix.

### P2 — Idle timeout truncates to whole seconds
- **Evidence:** `SubprocessCommandRunner.swift:236` —
  `let idleSeconds = max(Double(timeout.components.seconds), 1)`.
  `components.seconds` drops any sub-second part of `timeout`, and the
  `max(..., 1)` floor rounds any sub-second timeout up to 1s. A 500ms idle
  budget becomes 1s.
- **Suggested fix:** If `timeout` is a `Duration`, fold in the attoseconds
  component, or use `Double(timeout.in(.seconds))`-style conversion.

### P2 — `lastActivity` seeded before launch → premature timeout on slow spawn
- **Evidence:** `SubprocessCommandRunner.swift:161` —
  `let lastActivity = LockedDate(Date())` is set before `configureProcess` and
  `launch`. The watchdog Task (`SubprocessCommandRunner.swift:230`) starts
  after launch but measures idle from the pre-configure timestamp, so
  configure+launch time is counted against the idle budget. With the 1s floor
  this can eat a large fraction of the budget on a slow spawn.
- **Suggested fix:** Re-seed `lastActivity.set(Date())` right before starting
  the watchdog Task (after `continuation.yield(.started)`).

### P2 — Blocking stdin write can deadlock on large input
- **Evidence:** `SubprocessCommandRunner.swift:302` —
  `handle.write(Data(stdin.utf8))` is synchronous. If `stdin` exceeds the pipe
  buffer (typically 64KB on macOS) and the child doesn't drain stdin until
  after producing output, the write blocks forever while the child blocks on a
  full stdout pipe — classic pipe deadlock.
- **Suggested fix:** Write stdin on a background thread/Task, or use
  `writeabilityHandler` with chunked writes, concurrent with stdout reading.

### P2 — TOCTOU between resolve and launch
- **Evidence:** `resolveExecutable` (`SubprocessCommandRunner.swift:313`)
  checks `isExecutableFile` at configure time; `process.run()`
  (`SubprocessCommandRunner.swift:296`) execs later. If the file is
  replaced/removed in between, behavior differs from the resolve result. Low
  impact for trusted local execution; noted for completeness.

## False alarms ruled out
- **`kill(-pid, SIGTERM)` killing the parent's group when `setpgid` fails:**
  ruled out. If `setpgid` failed, `pid` is not a process-group leader, so
  `kill(-pid, ...)` returns `ESRCH` (no such group) and the code falls back to
  `process.terminate()`. The parent's group is never targeted because its PGID
  ≠ the child's PID.
- **PATH containing `.` / empty components → CWD execution:**
  ruled out. `String.split(separator:)` defaults to
  `omittingEmptySubsequences: true`, so `::` in PATH is dropped and `.` is
  only reached if explicitly listed (caller's choice; the default fallback has
  no `.`).
- **Token leak to child:** ruled out.
  `environment["ALLNIGHTER_TOOL_TOKEN"] = nil` removes the key from the child
  env before launch.
- **Command injection via shell:** ruled out. `process.executableURL` +
  `process.arguments` are used directly; no `/bin/sh -c` interpolation.
- **Termination handler racing the watchdog:** ruled out. `ResumeOnce.claim()`
  serializes the terminal emit, and the watchdog's `isRunning` check before
  `endReason.set(.timeout)` ensures a normal exit between the check and the set
  is reported as `.completed` (the claim is already taken).
- **`ALLNIGHTER_TEAM_DEPTH` override by caller:** not a finding — the caller
  is the trusted engine; the depth is incremented, not trusted as-is.
- **`resolveExecutable` uses `env["PATH"]` while child gets merged env:**
  ruled out. Both paths are consistent — if the caller passes `PATH`, both
  resolution and the child use it; if not, both use the parent's PATH.

## Greps avoided
Confirmed: no repo exploration performed. All evidence is from the inlined
`SubprocessCommandRunner.swift` source and the resolved-symbols list. No
`grep`, `glob`, `read`, or `task` calls were issued against the repository.
The only filesystem touch was creating this findings file.