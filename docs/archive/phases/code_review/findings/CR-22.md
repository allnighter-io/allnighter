# CR-22 — Review RunService OpenCode execution branch

## Summary
The OpenCode streaming branch (RunService.swift:551-615) acquires a per-driver
spawn gate, starts a warm `opencode serve` via `OpenCodeServeCoordinator`,
streams answer/reasoning deltas with time-and-byte throttling, and falls back to
a non-streaming `runner.invoke` when the stream ends non-`.done` with empty
output. The structure is sound, but the spawn gate is released only on the
fallback path — the success and failed-with-output paths show no release in the
inlined scope, which is a gate-leak risk. Secondary issues: `reasoning` is an
unbounded `String` (unlike the bounded `StreamingPartialBuffer` used for
`answer`), `ensureRunning()` has no timeout and its failures are misclassified as
`missingCLI`, and the fallback invoke's own gate handling is not verifiable from
the inlined scope.

## Findings

### P0 — Spawn gate released only on fallback path; success / failed-with-output paths leak
- **Invariant:** Every `acquireDriverSpawnGate` must be paired with a
  `releaseDriverSpawnGate` on every exit path. A leaked gate permanently
  consumes one slot of the per-driver concurrency limit; enough leaks and no
  further OpenCode spawns can acquire the gate.
- **Evidence:**
  - Acquire: RunService.swift:554 `if let gateLimit, let gateFailure = await acquireDriverSpawnGate(driverId: driverId, limit: gateLimit)`.
  - `gateHeld = gateLimit != nil` at RunService.swift:557.
  - The only release in the inlined scope is at RunService.swift:611-613,
    guarded by the condition at RunService.swift:609:
    `if outcome.status != .done, (outcome.output ?? "").isEmpty`.
  - On a `.done` terminal (RunService.swift:593-594) the condition at 609 is
    false → no release. On a `.failed` terminal with non-empty output the
    condition is also false → no release. `gateHeld` stays `true` and no other
    release is visible in the inlined scope (the snippet ends at RunService.swift:615).
- **Contingency:** If a `defer { if gateHeld { release } }` or equivalent release
  exists after line 615 (not inlined), the success path is covered and the
  manual release at 611-613 exists only to drop the streaming gate before the
  fallback invoke acquires its own. That is consistent and correct. If no such
  release exists, this is a real leak. The manual-release-only-in-one-branch
  pattern is the smell; confirm by inlining the lines after 615.
- **Suggested fix:** Release the gate once, immediately after the streaming
  do/catch completes and before the fallback decision, so all paths are covered
  and the fallback invoke runs without the streaming gate:
  ```swift
  } catch { ... }
  if gateHeld { await releaseDriverSpawnGate(driverId: driverId); gateHeld = false }
  emitAnswer()
  if !reasoning.isEmpty { emitReasoning() }
  outcome = terminal ?? WorkerRunOutcome(status: .failed, ...)
  if outcome.status != .done, (outcome.output ?? "").isEmpty {
      // fallback invoke — streaming gate already released
      outcome = await runner.invoke(...)
  }
  ```
  This removes the inline release at 611-613 and covers the success path.
- **Suggested slice:** opencode: release spawn gate on all streaming exit paths

### P1 — `reasoning` is an unbounded String; `answer` is bounded
- **Invariant:** Streaming buffers should be bounded. `answer` uses
  `StreamingPartialBuffer` (with `isTruncated` / `byteDue`); `reasoning` uses a
  raw `String` with no cap.
- **Evidence:**
  - RunService.swift:559 `var answer = StreamingPartialBuffer()` — bounded
    (see `answer.isTruncated` at 567, `byteDue` at 588).
  - RunService.swift:560 `var reasoning = ""`; RunService.swift:591
    `reasoning += text` — append-only, no length check, no truncation, no clear.
  - A long reasoning stream (e.g., a stuck model emitting reasoning tokens) grows
    `reasoning` without bound for the life of the run, and the final
    `emitReasoning()` at RunService.swift:605 emits the entire accumulated string
    in one event.
- **Suggested fix:** Cap `reasoning` length (truncate with a marker past N bytes)
  or stream-and-clear it in chunks like `answer` does, rather than accumulating
  the whole reasoning transcript.
- **Suggested slice:** opencode: bound reasoning buffer in streaming branch

### P1 — `ensureRunning()` has no timeout; can hold the gate indefinitely
- **Invariant:** A spawn-gate-held region must not contain an unbounded await.
  The stream itself has a `timeout` (RunService.swift:577, passed at 584); serve
  startup does not.
- **Evidence:** RunService.swift:579
  `try await OpenCodeServeCoordinator().ensureRunning()` is awaited with no
  deadline. If serve startup hangs (subprocess that doesn't exit, port wait,
  handshake stall), the gate is held forever and the run never reaches the
  `for try await` loop or the catch.
- **Suggested fix:** Wrap `ensureRunning()` in a `withTimeout` (shorter than the
  stream timeout — e.g., 30s) or have it accept a deadline; map a startup
  timeout to a distinct failure outcome.
- **Suggested slice:** opencode: timeout ensureRunning in streaming branch

### P1 — `ensureRunning()` failure misclassified as `missingCLI`
- **Invariant:** `errorKind` must describe the actual failure class.
  `missingCLI` asserts the CLI binary is absent; `ensureRunning()` can fail for
  many other reasons (serve port conflict, auth/handshake failure, serve crash,
  version mismatch).
- **Evidence:** RunService.swift:579 `try await OpenCodeServeCoordinator().ensureRunning()`;
  catch at RunService.swift:599-603 sets `errorKind: .missingCLI` (line 601) with
  reason `"opencode serve: \(error)"` (line 602) for any throw out of the `do`.
  A downstream consumer that reads `errorKind == .missingCLI` to prompt "install
  opencode" would misfire when the CLI is present but serve failed to start.
- **Suggested fix:** Distinguish serve-start failures from a missing binary —
  probe CLI presence explicitly, or use a more accurate `errorKind` (e.g.,
  `.spawnFailed` or a new `.serveStartFailed`). Reserve `missingCLI` for the
  "binary not on PATH" case.
- **Suggested slice:** opencode: classify serve-start failures separately from missingCLI

### P1 — Fallback invoke gate handling not verifiable from inlined scope
- **Invariant:** The fallback `runner.invoke` must respect the OpenCode driver
  spawn concurrency limit, or the limit is bypassed exactly when the streaming
  path is already flaky.
- **Evidence:** RunService.swift:611-614 releases the streaming gate, then
  RunService.swift:615 `outcome = await runner.invoke(` — signature truncated.
  The non-streaming branch above (RunService.swift:548-549) passes
  `spawnConcurrencyLimit` explicitly, suggesting gate handling is the caller's
  job. Whether `runner.invoke` acquires the OpenCode driver gate itself cannot
  be confirmed from the inlined lines (the call is cut off at the `(`).
- **Suggested fix:** Confirm `runner.invoke` acquires the OpenCode driver gate
  (or receives `spawnConcurrencyLimit`) before the fallback is trusted as
  gated. If it does not, acquire the gate around the fallback invoke.
- **Suggested slice:** (verification, not an edit until confirmed)

### P2 — Unconditional final `emitAnswer()` may emit an empty delta
- **Invariant:** A terminal flush should not emit a no-content event.
- **Evidence:** RunService.swift:604 `emitAnswer()` runs unconditionally after
  the do/catch. If no answer text arrived (e.g., immediate `ensureRunning`
  failure → catch at 599 → empty `answer`), this emits a `workerAnswerDelta`
  with `text: ""` and `truncated: false`.
- **Suggested fix:** Guard with `if !answer.visibleText.isEmpty { emitAnswer() }`,
  or document that the empty emit is an intentional flush signal. Likely a nit,
  but it can render a spurious empty bubble in the UI.
- **Suggested slice:** (nit)

### P2 — First answer delta may be delayed up to 100ms
- **Invariant:** (latency, not correctness)
- **Evidence:** `lastAnswerEmit = now()` at RunService.swift:561; the emit guard
  at RunService.swift:589 is `byteDue || now().timeIntervalSince(lastAnswerEmit) >= 0.1`.
  The first small answer chunk that doesn't trip `byteDue` waits up to 100ms
  before the first emit. Reasoning has the same shape (RunService.swift:562, 592).
- **Suggested fix:** Initialize `lastAnswerEmit`/`lastReasoningEmit` to a sentinel
  (e.g., `nil` or `.distantPast`) so the first delta emits immediately, or
  special-case the first chunk. Minor; only affects first-token latency.

## False alarms ruled out
- **`gateHeld` race** — `gateHeld` is a local `var` in a single async context;
  no concurrent access. Not a race.
- **Closure capture of mutable locals** — `emitAnswer`/`emitReasoning`
  (RunService.swift:564, 571) capture `answer`, `reasoning`, `lastAnswerEmit`,
  `lastReasoningEmit` by reference. Standard Swift local-closure capture; works
  for both struct and class backing. Not a defect.
- **Reasoning uses time-only throttle, answer uses byte-or-time** —
  RunService.swift:589 vs 592. The asymmetry is intentional (reasoning is lower
  priority / less frequent). Not a bug.
- **`.completed` and `.failed` both assign `terminal`** — RunService.swift:594.
  In a well-formed stream these are mutually exclusive; if both arrive, last wins.
  Acceptable.
- **`gateHeld = false` after manual release** — RunService.swift:613. Makes the
  release idempotent within this scope and prevents a double-release if a later
  release exists. Correct guard, not a defect.

## Greps avoided
Confirmed: no repo exploration performed. This review used only the inlined
source (RunService.swift:548-615) and the two resolved-symbol notes
(`emitAnswer` at 564, `emitReasoning` at 571). No `grep`, `glob`, `read`, or
`task` tool calls were made against the repository. The body of `runner.invoke`,
`acquireDriverSpawnGate`/`releaseDriverSpawnGate`, `StreamingPartialBuffer`,
`OpenCodeServeCoordinator.ensureRunning`, and any code after RunService.swift:615
were not inlined and are explicitly marked unreviewable above (see P0
contingency and the P1 fallback-invoke finding).