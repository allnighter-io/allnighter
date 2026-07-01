# CR-11 — Review WorkerRunner.runOpenCode

## Summary
`runOpenCode` (WorkerRunner.swift:257-331) dispatches an OpenCode serve run
either via SSE streaming or a sync POST, after ensuring the serve process is
alive and acquiring an optional spawn gate. The structure is sound and the
gate acquire/release pairing is correct. The main concerns are: (1) the spawn
gate is released via a fire-and-forget unstructured `Task` in a `defer`, which
can leak the gate if the task never runs; (2) all streaming errors are mapped
to `.nonzeroExit` regardless of cause; (3) the stream-without-terminal
fallback uses `.emptyOutput` even though the stream may have produced deltas;
and (4) `NSTemporaryDirectory()` in the cwd fallback chain is dead code.

## Findings

### P1 — Fire-and-forget spawn gate release can leak

- **Invariant:** Every acquired spawn gate must be released exactly once.
- **Evidence:** WorkerRunner.swift:269 —
  `defer { if gateLimit != nil { Task { await DriverConcurrencyGate.shared.release(driverId: manifest.id) } } }`
- **Suggested fix:** `defer` cannot `await` in Swift, which motivates the
  `Task` workaround. Restructure to release the gate on every return path
  before returning (e.g., a `releaseGateThenReturn(_:)` helper that awaits
  release then returns the outcome). Alternatively, make `release`
  non-async/synchronous so it can be called directly in `defer`. As written,
  if the unstructured `Task` is never scheduled (e.g., process tear-down) the
  gate is never released, permanently blocking that driver's concurrency slot.
  Even in normal operation the async release creates a false-contention window
  where the gate appears held after the run is complete.
- **Suggested slice:** opencode-gate-release-on-return

### P1 — Streaming error kind is always `.nonzeroExit`

- **Invariant:** `errorKind` should categorize the failure for downstream retry
  and user-facing logic.
- **Evidence:** WorkerRunner.swift:295-300 —
  `errorKind: .nonzeroExit, errorReason: "opencode stream: \(error)"`
- **Suggested fix:** A streaming failure can be a connection refusal (should be
  `.missingCLI` or a connection error), a timeout (should be `.timeout`), an
  SSE parse failure, or a server-side error. Mapping all to `.nonzeroExit`
  misleads retry logic. Inspect the thrown error type and map accordingly, or
  introduce a `.streamError` / `.connectionError` kind. At minimum, distinguish
  connection errors (`.missingCLI`) from stream-protocol errors.
- **Suggested slice:** opencode-stream-error-kind-mapping

### P2 — Stream-without-terminal uses `.emptyOutput` despite possible deltas

- **Invariant:** `errorKind` should reflect the actual failure mode.
- **Evidence:** WorkerRunner.swift:302-306 —
  `errorKind: .emptyOutput, errorReason: "opencode stream ended without terminal"`
- **Suggested fix:** The stream may have emitted `.answerDelta` /
  `.reasoningDelta` events before ending without a terminal event. This is a
  protocol or timeout failure, not empty output. Consider `.timeout` or a new
  `.incompleteStream` kind. The `errorReason` string is descriptive, but the
  programmatic `errorKind` is what drives retry logic.

### P2 — `NSTemporaryDirectory()` is dead code in cwd fallback

- **Invariant:** No unreachable code in fallback chains.
- **Evidence:** WorkerRunner.swift:281-283 —
  `?? FileManager.default.temporaryDirectory.path ?? NSTemporaryDirectory()`
- **Suggested fix:** `FileManager.default.temporaryDirectory.path` is a
  non-optional `String` that always returns a valid path (e.g.
  `/var/folders/.../T/`). The `??` operator checks for nil, not empty, so
  `NSTemporaryDirectory()` is never reached. Remove the dead `??
  NSTemporaryDirectory()` term.

### P2 — Stream vs sync `durationMs` parity

- **Invariant:** Streaming and sync paths should produce structurally
  equivalent outcomes.
- **Evidence:** Sync path explicitly computes `durationMs` at
  WorkerRunner.swift:326 —
  `durationMs: Int(finishedAt.timeIntervalSince(startedAt) * 1000)`.
  Streaming path (WorkerRunner.swift:290-298) returns the terminal outcome
  from stream events (`.completed(let o)`, `.failed(let o)`) with no explicit
  `durationMs` computation visible.
- **Suggested fix:** If the terminal outcomes constructed inside
  `invokeOpenCodeStreaming` do not set `durationMs`, streaming runs will lack
  duration data that sync runs provide. Verify the stream-event outcomes
  include `durationMs`; if not, compute it from `startedAt`/`now()` before
  returning the terminal outcome.

### P2 — `autoApprove` parity between stream and sync paths

- **Invariant:** Both paths should auto-approve tool permissions identically
  (docstring at WorkerRunner.swift:258-259 says "tool permissions
  auto-approved").
- **Evidence:** Sync path passes `autoApprove: true` at WorkerRunner.swift:319.
  Streaming path calls `invokeOpenCodeStreaming(prompt:modelLabel:directory:
  timeout:)` at WorkerRunner.swift:291-293 with no `autoApprove` argument
  visible.
- **Suggested fix:** Confirm `invokeOpenCodeStreaming` hardcodes or defaults
  `autoApprove` to `true`. If it does not, tool calls in the streaming path
  will hang waiting for interactive approval, which never comes in a
  headless worker context.

### P2 — Fresh `OpenCodeServeCoordinator` per call

- **Invariant:** `ensureRunning` should be cheap and idempotent.
- **Evidence:** WorkerRunner.swift:272 —
  `try await OpenCodeServeCoordinator().ensureRunning()`
- **Suggested fix:** A new `OpenCodeServeCoordinator()` is constructed on every
  `runOpenCode` call. If the coordinator holds no persistent state (e.g., a
  cached process handle), each `ensureRunning` must re-discover the running
  serve process. Consider injecting a shared coordinator or making
  `ensureRunning` a static/class method that caches the liveness check.

## False alarms ruled out

- **Gate released without acquisition:** The early return at WorkerRunner.swift:267
  fires before the `defer` at line 269 is registered, so a failed gate
  acquisition never triggers a spurious release. Not a bug.
- **`startedAt` excludes gate-wait time:** `acquireDriverSpawnGate` returns a
  failure immediately (non-blocking), so `startedAt` at line 271 correctly
  measures the run duration, not the gate wait. Not a bug.
- **`AllnighterPaths.ensuredProbeScratchPath()` side effect in `??` chain:**
  Short-circuit evaluation means the side effect only fires when
  `workingDirectoryOverride` and `defaultWorkingDirectory` are both nil — the
  intended fallback. Not a bug, though embedding side effects in `??` is a
  style concern.
- **`ensureRunning` called once per run:** Only one `ensureRunning` call is
  visible in `runOpenCode` itself. Whether `OpenCodeServeClient().run()` or
  `invokeOpenCodeStreaming` also calls it internally cannot be confirmed from
  the inlined sources, so no redundancy is claimed.

## Greps avoided
Review based solely on the inlined source (WorkerRunner.swift:251-331) and
resolved symbol signature. No repo exploration, file reads, or greps were
performed outside the provided inlined sources.