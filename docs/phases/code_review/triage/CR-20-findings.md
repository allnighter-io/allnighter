# CR-20 — Review SubprocessCommandRunner lifecycle

## Summary
The non-streaming `run` path (SubprocessCommandRunner.swift:85-143) has sound
process-lifecycle bones: `ResumeOnce` prevents double-resume, `EndReason`
encodes first-writer-wins for timeout/cancel, `terminationHandler` reaps the
child (no zombie leak), and argv-based launch closes the shell-injection vector.
Two real defects remain. (1) The timeout watchdog `Task { ... }` (lines 131-137)
is unstructured and never cancelled when the process exits normally — it sleeps
for the full `timeout` duration, retaining `ProcessBox` → `Process` → pipes and
`EndReason` until it wakes. For long timeouts under fan-out this is a measurable
memory leak. (2) The `terminationHandler` nils the readability handlers (lines
114-115) then immediately snapshots the buffers (lines 120-121), but a
readability-handler callback already in flight on Foundation's dispatch queue can
append to the buffer *after* `snapshot()` returns, silently dropping the final
stdout/stderr chunk from the `CommandResult`. `killGroup`, `configureProcess`,
and `launch` are referenced but not inlined, so process-group kill semantics and
stdin write behavior are not verifiable from this review.

## Findings

### P0 — None
No invariant or security issue found in the inlined sources. Shell injection is
closed (argv elements, no shell string — documented at lines 73-76). The
`@unchecked Sendable` assertions on `LockedBuffer`, `ResumeOnce`, `EndReason`,
and `ProcessBox` are justified by their lock discipline (or, for `ProcessBox`,
by restricting cross-thread access to `isRunning`/kill per the comment at lines
66-67).

### P1 — Timeout watchdog Task is never cancelled; leaks Task + retains Process
- **Invariant:** A watchdog task that outlives the operation it guards must be
  cancelled when the operation completes, or it retains captured state until it
  wakes.
- **Evidence:** The watchdog is an unstructured `Task { ... }` at
  SubprocessCommandRunner.swift:131-137:
  ```swift
  Task {
      try? await Task.sleep(for: timeout)
      if box.process.isRunning {
          endReason.set(.timeout)
          Self.killGroup(box.process)
      }
  }
  ```
  It captures `box` (ProcessBox → `Process` → `standardOutput`/`standardError`
  pipes and their readability-handler closures, which capture `outBuffer`/
  `errBuffer`) and `endReason`. When the process exits normally, the
  `terminationHandler` (lines 113-128) resumes the continuation and
  `withTaskCancellationHandler` returns — but the watchdog `Task` is never
  cancelled and is not a child task, so structured-concurrency cancellation does
  not propagate to it. It sleeps for the remaining `timeout` duration, retaining
  the `Process` and all pipe buffers. Under fan-out (many concurrent runs with
  long timeouts, e.g. 30 min), each completed run pins a `Process` + pipe
  buffers until its timeout elapses.
- **Suggested fix:** Capture the watchdog `Task` in a variable and call
  `.cancel()` on it inside the `terminationHandler` before resuming the
  continuation (after `resumer.claim()` succeeds). Alternatively, restructure as
  a `withTaskGroup` child task so cancellation propagates automatically when the
  parent returns. Either way, `Task.sleep` will throw `CancellationError`, the
  `try?` swallows it, and the `isRunning` check is never reached.
- **Suggested slice:** SubprocessCommandRunner: cancel timeout watchdog on exit

### P1 — stdout/stderr drain race: late readability-handler callback can miss final chunk
- **Invariant:** The `CommandResult.stdout`/`stderr` must contain *all* bytes the
  child wrote before terminating.
- **Evidence:** In `terminationHandler` (SubprocessCommandRunner.swift:113-128):
  ```swift
  process.terminationHandler = { proc in
      (proc.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
      (proc.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil

      guard resumer.claim() else { return }
      let reason = endReason.get()
      let result = CommandResult(
          stdout: String(decoding: outBuffer.snapshot(), as: UTF8.self),
          stderr: String(decoding: errBuffer.snapshot(), as: UTF8.self),
          ...
  ```
  Setting `readabilityHandler = nil` (lines 114-115) does not cancel a callback
  already scheduled on Foundation's dispatch queue — Foundation documents that a
  pending readability handler may still fire once after nil-ing. If such a
  callback fires *after* `outBuffer.snapshot()` / `errBuffer.snapshot()` (lines
  120-121), the appended bytes are absent from the returned `CommandResult`. The
  window is small (between snapshot and the late callback) but real, and most
  likely to bite on the final chunk written just before the child exits —
  exactly the chunk that matters (e.g. a trailing error line or JSON closing
  brace).
- **Suggested fix:** After nil-ing the readability handler, drain remaining pipe
  data synchronously before snapshotting:
  ```swift
  if let pipe = proc.standardOutput as? Pipe {
      let rest = pipe.fileHandleForReading.readDataToEndOfFile()
      outBuffer.append(rest)
  }
  // same for standardError
  ```
  `readDataToEndOfFile()` returns immediately at EOF (the child has terminated,
  so the write end is closed) and is the documented drain pattern after
  nil-ing a readability handler. Take the snapshot *after* the drain.
- **Suggested slice:** SubprocessCommandRunner: drain pipes before snapshot in terminationHandler

### P2 — `EndReason.set` uses manual `lock.unlock()` without `defer`
- **Invariant:** Lock release should be robust to future edits that add a
  throwing or early-return path inside the critical section.
- **Evidence:** SubprocessCommandRunner.swift:53-57:
  ```swift
  func set(_ value: Reason) {
      lock.lock()
      if reason == .normal { reason = value }
      lock.unlock()
  }
  ```
  Every other locked method in this file uses `defer { lock.unlock() }`
  (`LockedBuffer.snapshot` at line 16, `LockedDate.get` at line 28,
  `ResumeOnce.claim` at line 39, `EndReason.get` at line 61). `set` is the lone
  exception. Not a live bug (enum assignment cannot throw), but inconsistent and
  fragile if the body ever grows.
- **Suggested fix:** Replace with `lock.lock(); defer { lock.unlock() }`.

### P2 — Timeout measured from watchdog Task start, not from process launch
- **Invariant:** The `timeout` parameter is the maximum wall-clock duration the
  child may run.
- **Evidence:** `Self.launch` runs at SubprocessCommandRunner.swift:102. The
  watchdog `Task.sleep(for: timeout)` starts at line 132, *after* the
  continuation closure sets up `terminationHandler` (line 113) and the `Task` is
  scheduled on the cooperative pool. The effective timeout is `timeout + Δ`,
  where `Δ` covers continuation setup + Task scheduling latency. Negligible for
  long timeouts; relevant for short ones in tests.
- **Suggested fix:** Record `Date()` before `launch` and sleep for
  `timeout - elapsed` in the watchdog, or start the watchdog before `launch`.

## False alarms ruled out
- **Zombie leak (CR-04 follow-up lens):** Not present. Foundation's `Process`
  reaps the direct child when `terminationHandler` fires (set at line 113).
  Grandchildren killed by `killGroup` are reparented to launchd (PID 1) on macOS
  and reaped there. No `waitpid` call is needed in user code — Foundation owns
  it. The only way to leak a zombie would be to never set `terminationHandler`,
  which does not happen here.
- **Double-resume:** `ResumeOnce.claim()` (lines 36-43) returns `true` exactly
  once; the `terminationHandler` guards on it (line 117). `onCancel` (lines
  139-142) does not resume directly — it kills, which triggers
  `terminationHandler`, which resumes. `withCheckedContinuation` will not
  double-resume.
- **`timedOut` propagation (review lens):** Correct. `EndReason.set(.timeout)`
  (line 134) is called only when `box.process.isRunning` is true (line 133).
  `terminationHandler` reads `endReason.get()` (line 118) and sets
  `timedOut: reason == .timeout` (line 123). The first-writer-wins semantics in
  `EndReason.set` (line 55: `if reason == .normal`) ensure cancel-vs-timeout is
  resolved deterministically.
- **Cancel-then-hang:** `onCancel` (lines 139-142) calls `killGroup`, which
  terminates the process, which fires `terminationHandler`, which resumes the
  continuation. No hang path — unless SIGKILL is ineffective (uninterruptible
  disk sleep), which is not reachable for normal CLI tools on macOS.
- **Process terminates before `terminationHandler` is set:** Foundation calls
  `terminationHandler` immediately if the process has already terminated when the
  handler is assigned. The window between `launch` (line 102) and handler
  assignment (line 113) is safe.
- **Shell injection:** Closed by design — argv elements / stdin, no shell string
  (documented at lines 73-76).
- **`@unchecked Sendable` on `ProcessBox`:** Justified — the only cross-thread
  access is `isRunning` (read) and `killGroup` (kill), both OS-safe per the
  comment at lines 66-67.

## Verification gaps (not inlined — not findings, just scope)
- **`killGroup`** (called at lines 135, 141) — implementation not inlined. The
  comment at lines 73-74 claims "its own process group so the whole tree can be
  killed," but whether `configureProcess` calls `setpgid` and whether
  `killGroup` uses `kill(-pgid, SIGKILL)` cannot be verified. If the child is
  *not* in its own group, `kill(-pgid, SIGKILL)` would target the parent's group
  (the Allnighter app). This is a P0 if the setup is missing, but the comment
  asserts it is present — flag for a follow-up review that inlines
  `configureProcess` and `killGroup`.
- **`configureProcess` / `launch`** (lines 95-97, 102) — not inlined. Executable
  resolution, env scrubbing, stdin write policy, and process-group setup are not
  verifiable.
- **`runStreaming`** (starts at line 147, cut off at line 160) — the streaming
  path uses the same `LockedBuffer` + readability-handler pattern (lines 148-152),
  so both P1 findings (watchdog leak, drain race) likely apply there too, but the
  body is truncated and cannot be confirmed.

## Greps avoided
Confirmed: no repo exploration performed. This review used only the inlined
source (SubprocessCommandRunner.swift:1-160) and the resolved-symbols list. No
`grep`, `glob`, `read`, or `task` tool calls were made against the repository.
`killGroup`, `configureProcess`, `launch`, and the `runStreaming` body were not
inlined and are explicitly marked unreviewable above.