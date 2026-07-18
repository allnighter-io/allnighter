# CR-08 — DriverConcurrencyGate spawn limits

## Summary

`DriverConcurrencyGate` is a process-wide, per-`driverId` actor limiter that
caps concurrent worker spawns for fragile CLIs (antigravity, cursor_agent at
`maxConcurrentSpawns=1`). The core handoff invariant — `active` counts holders,
`release` transfers a slot to the next waiter without double-counting — is
correct, and the value-type `Lane` copy is written back on every path before
yielding. The gate has **no P0 invariant/security violations**. It does have
several P1 liveness and forward-compatibility gaps: cancelled waiters are not
dropped (they wake and run `body`, holding a slot they no longer want), there is
no wait timeout (one hung holder permanently deadlocks a `limit=1` driver),
`withPermit`'s `release` is not guarded against a future `throws` on `body`, the
gate sits at the spawn chokepoint and will be bypassed by a future warm pool, and
FIFO ordering lets a team run starve an interactive chat on the same `limit=1`
driver. P2 nits: first-caller-wins limit, no holder-proof on `release`, and
`activeCount` hides queue depth.

## Findings

### P0 — No P0 findings

No invariant or security violation was found. The slot-transfer handoff
(`release` resumes a waiter without decrementing `active`; the woken `acquire`
took the queue path and did not increment `active`) preserves the
"active == number of holders" invariant. The `max(0, active-1)` clamp prevents
integer underflow. Actor isolation serializes `acquire`/`release`, and the
`withCheckedContinuation` closure runs synchronously before suspension, so the
`waiters.append` completes before any `release` can `removeFirst`.

### P1 — Cancelled waiters are not dropped; they wake and run `body`, holding a slot

- **Invariant:** A task cancelled while queued in `acquire` should release its
  slot (pass it to the next waiter) and bail out, not proceed to run `body`.
- **Evidence:** `acquire` uses `withCheckedContinuation` with a `Never` error
  type (DriverConcurrencyGate.swift:46). `Never`-typed continuations do **not**
  auto-resume on cancellation — the cancelled task stays in `waiters`
  (DriverConcurrencyGate.swift:47). When a holder calls `release`, the cancelled
  continuation is resumed (DriverConcurrencyGate.swift:55-57), the task returns
  from `acquire`, and `withPermit` proceeds to run `body`
  (DriverConcurrencyGate.swift:69) and only then calls `release`
  (DriverConcurrencyGate.swift:70). For `maxConcurrentSpawns=1` drivers
  (antigravity, cursor_agent), a cancelled task that wakes and runs a long
  `body` blocks every other waiter for the full duration. For a mutating
  execution run, a cancelled worker can still execute repo mutations before
  `body` gets a chance to check `Task.isCancelled`.
- **Suggested fix:** Switch to `withTaskCancellationHandler` +
  `withCheckedThrowingContinuation<Void, Error>`. On cancellation, remove the
  continuation from `waiters` (so the slot passes to the next waiter) and resume
  it with `CancellationError`. Have `acquire` `throw` and have `withPermit`
  treat `CancellationError` as "never acquired" (skip `release` and rethrow
  without running `body`).
- **Suggested slice:** `DriverConcurrencyGate: drop cancelled waiters`

### P1 — No wait timeout: one hung holder permanently deadlocks the driver

- **Invariant:** A waiter should not block indefinitely; a hung holder should
  not permanently disable a `limit=1` driver for the process lifetime.
- **Evidence:** `acquire` suspends in `withCheckedContinuation` with no timeout
  (DriverConcurrencyGate.swift:46). `release` is only called by the holder via
  `withPermit` after `body` returns (DriverConcurrencyGate.swift:70). If `body`
  hangs (worker process hangs, never returns), `release` is never called and
  every waiter blocks forever. For `limit=1` drivers, a single hung worker
  permanently deadlocks that driver for the entire process — no chat, no team
  seat, no recovery short of process restart.
- **Suggested fix:** Add a `timeout: Duration?` parameter to `acquire`/
  `withPermit` (defaulting to a per-driver manifest value). Race the
  continuation against a `Task` that sleeps for the timeout and resumes it with
  a `DriverConcurrencyGateError.timedOut`. On timeout, remove the waiter from
  `waiters` so the slot is not transferred to a dead task. Optionally pair with
  a force-release watchdog that decrements `active` if a holder exceeds a
  max-hold duration.
- **Suggested slice:** `DriverConcurrencyGate: acquire timeout + watchdog`

### P1 — `withPermit` release is not guarded; a future `throws` on `body` leaks the slot

- **Invariant:** `release` must run on every exit path from `withPermit`,
  including the error path.
- **Evidence:** `withPermit` calls `release` as a plain statement after `body`
  (DriverConcurrencyGate.swift:70), not in `defer` or a `do/catch`. `body` is
  currently `() async -> T` (non-throwing, DriverConcurrencyGate.swift:66), so
  today the only skip is a trap — which aborts the process, making the leak
  moot. But worker spawns fail, so the obvious next change is `body: () async
  throws -> T`. The moment `throws` is added, a thrown error skips
  `DriverConcurrencyGate.swift:70` and the slot leaks permanently — for
  `limit=1`, that is a permanent driver deadlock after the first failed spawn.
  `defer` cannot `await release(...)` (actor method), so the fix is structural.
- **Suggested fix:** When adding `throws`, restructure to
  `await acquire(...); do { let r = try await body(); release(...); return r }
  catch { release(...); throw error }` — or, better, make `release` synchronous
  (e.g., a nonisolated `@discardableResult` permit-token release that the actor
  processes) so `defer { release(...) }` works. At minimum, add a comment at
  DriverConcurrencyGate.swift:66 flagging the non-throwing contract as
  load-bearing for slot accounting.
- **Suggested slice:** `DriverConcurrencyGate: throwing withPermit + safe release`

### P1 — Warm-pool interaction: gate is at spawn, not use; a warm pool bypasses it

- **Invariant:** The gate must limit concurrent *use* of a fragile driver, not
  only concurrent *spawn*.
- **Evidence:** The gate is explicitly at the "WORKER-SPAWN chokepoint"
  (DriverConcurrencyGate.swift:10). `withPermit` wraps `body`, which is the
  spawn call (DriverConcurrencyGate.swift:66-71). The protected fragilities —
  antigravity's singleton brain dir, cursor_agent's `~/.cursor/cli-config.json`
  race (DriverConcurrencyGate.swift:17-19) — are triggered by concurrent
  *invocation* of the CLI, not by the spawn syscall itself. If a future warm-pool
  feature keeps a worker process alive and hands it to a second seat without a
  new spawn, the second seat never enters `withPermit`, so two seats can
  concurrently use the same warm process for a `limit=1` driver — re-introducing
  exactly the deadlock/config-race the gate exists to prevent.
- **Suggested fix:** When warm pooling is introduced, either (a) move the gate
  to the use-site (wrap the "hand process to seat" call, not the spawn call), or
  (b) gate both spawn and use, or (c) document that warm-pooled drivers must
  reinterpret `maxConcurrentSpawns` as `maxConcurrentUses` and have the pool
  itself enforce it. Add a forward-compat note at
  DriverConcurrencyGate.swift:10-11.
- **Suggested slice:** `DriverConcurrencyGate: gate use, not just spawn (warm-pool prep)`

### P1 — FIFO + process-wide: a team run starves an interactive chat on a `limit=1` driver

- **Invariant:** Interactive/foreground work should not queue behind a full team
  run on the same fragile driver.
- **Evidence:** `release` hands the slot to `waiters.removeFirst()`
  (DriverConcurrencyGate.swift:55) — strict FIFO. The limit is "global to the
  process" (DriverConcurrencyGate.swift:14), so a team seat and a single-lane
  chat on the same driver share one queue. A 10-seat team run on `cursor_agent`
  (`limit=1`) fills the queue; a user's interactive chat that hits the same
  driver waits for all 10 serial spawns ahead of it. There is no priority field
  on `acquire`/`withPermit` (DriverConcurrencyGate.swift:35, 66) and no reserved
  foreground slot.
- **Suggested fix:** Add a `priority: DispatchQoS` or `.userInitiated`/`.utility`
  enum to `acquire`/`withPermit`. Replace `waiters: [CheckedContinuation...]` with
  a priority-ordered structure (heap or `[priority: [cont]]`). On `release`,
  resume the highest-priority waiter first. Alternatively, reserve one slot of
  `limit` for foreground work when `limit > 1` (does not help `limit=1`, where
  preemption is the only option — likely a "skip the queue" flag that resumes the
  foreground waiter and re-queues the current holder, which is complex; a
  priority queue is the simpler win).
- **Suggested slice:** `DriverConcurrencyGate: priority queue for foreground work`

### P2 — First-caller-wins `limit`: divergent callers silently ignored

- **Invariant:** A driver's lane limit should reflect the current
  `DriverManifest.maxConcurrentSpawns`, not whichever caller happened to acquire
  first.
- **Evidence:** `var lane = lanes[driverId] ?? Lane(limit: cap)`
  (DriverConcurrencyGate.swift:37). If the lane exists, the passed `limit`
  (clamped to `cap` at DriverConcurrencyGate.swift:36) is discarded. The comment
  at DriverConcurrencyGate.swift:34 documents "the first acquire for a driver
  fixes its lane limit." If two call paths disagree (e.g., chat reads a stale
  manifest value of 2, team reads the current 1), the first call wins for the
  process lifetime and a runtime manifest update is ignored.
- **Suggested fix:** `precondition(lane.limit == cap, ...)` on subsequent
  acquires, or key the lane by `(driverId, limit)` and treat a limit change as a
  new lane. At minimum, log a warning when a divergent `limit` is observed.
- **Suggested slice:** `DriverConcurrencyGate: assert limit stability`

### P2 — `release` has no holder proof: double-release or release-without-acquire corrupts the count

- **Invariant:** `release` should only succeed for a caller that holds a permit.
- **Evidence:** `release` (DriverConcurrencyGate.swift:52-62) takes only
  `driverId` — no token, no holder id. A spurious `release` with waiters
  present (DriverConcurrencyGate.swift:54-57) resumes a waiter without
  decrementing `active`, admitting an extra concurrent holder (limit violation).
  A spurious `release` with no waiters (DriverConcurrencyGate.swift:59)
  under-counts `active`, admitting an extra holder on the next `acquire`. The
  `max(0, active-1)` clamp prevents underflow but not the count corruption.
  `acquire`/`release` are `public` (DriverConcurrencyGate.swift:35, 52), so
  callers outside `withPermit` can misuse them.
- **Suggested fix:** Have `acquire` return an opaque `Permit` token (carrying
  `driverId` and a unique id); have `release(_ permit: Permit)` require it and
  assert the holder is in the active set. Or make `acquire`/`release` `internal`
  and force all external callers through `withPermit`.
- **Suggested slice:** `DriverConcurrencyGate: permit-token release`

### P2 — `activeCount` hides queue depth: diagnostics blind to a stuck queue

- **Invariant:** A diagnostic should distinguish "idle" from "blocked behind
  holders."
- **Evidence:** `activeCount` returns only `lanes[driverId]?.active`
  (DriverConcurrencyGate.swift:75). A lane with `active=1, limit=1, waiters=12`
  (a stuck queue) reports `1`; a lane with `active=1, limit=1, waiters=0`
  (healthy, one holder) also reports `1`. There is no way to observe queue
  depth, so a deadlock looks like normal operation.
- **Suggested fix:** Add `waiterCount(driverId: String) -> Int` returning
  `lanes[driverId]?.waiters.count ?? 0`, or change `activeCount` to return a
  struct `{ active, limit, waiters }`.
- **Suggested slice:** `DriverConcurrencyGate: expose waiter count`

### P2 — Non-`shared` instance deinit leaks continuations

- **Invariant:** Dropping a gate with suspended waiters must resume them.
- **Evidence:** `init()` is `public` (DriverConcurrencyGate.swift:30), so a
  caller can construct a non-`shared` gate. If it is dropped while waiters are
  suspended, the `CheckedContinuation`s in `Lane.waiters` are never resumed —
  the tasks hang forever, and `CheckedContinuation` asserts in debug builds.
  `Lane` is a value type with no `deinit`, and the actor has no `deinit`.
- **Suggested fix:** Make `init` `internal` (force `shared`), or add a
  `cancelAll()` that resumes every waiter with an error, and document that
  callers must invoke it before dropping a non-`shared` instance.
- **Suggested slice:** `DriverConcurrencyGate: scope init or add cancelAll`

## False alarms ruled out

- **Actor reentrancy between `waiters.append` and `release.removeFirst`:** The
  closure passed to `withCheckedContinuation` (DriverConcurrencyGate.swift:46-48)
  runs synchronously before the task suspends, so the `append` completes while
  the actor is still executing `acquire`. `release` cannot interleave. Not a
  race.
- **Value-type `Lane` copy loses mutations:** `Lane` is a struct; `var lane =
  lanes[driverId] ?? ...` (DriverConcurrencyGate.swift:37) copies. But every
  mutating path writes back (`lanes[driverId] = lane` at
  DriverConcurrencyGate.swift:40, 45, 56, 60), and the continuation closure
  appends to `lanes[driverId]` (the stored copy), not the local `lane`
  (DriverConcurrencyGate.swift:47). No lost mutation.
- **Slot double-count on handoff:** `release` resumes a waiter without
  decrementing `active` (DriverConcurrencyGate.swift:55-57), and the woken
  `acquire` took the queue path (it did not execute `lane.active += 1` at
  DriverConcurrencyGate.swift:39). So `active` stays at "number of holders"
  across the handoff. The comment at DriverConcurrencyGate.swift:43-44 is
  accurate. Not a double-count.
- **Integer underflow on `active - 1`:** `max(0, lane.active - 1)` at
  DriverConcurrencyGate.swift:59 clamps to zero. No underflow crash. (The
  *count* is still wrong on a spurious release — see P2 "no holder proof" — but
  there is no crash.)
- **`limit ≤ 0` from a misconfigured manifest:** `let cap = max(1, limit)` at
  DriverConcurrencyGate.swift:36 clamps to 1, so a manifest typo of 0 or
  negative does not create a zero-capacity lane that deadlocks on the first
  acquire. Not a bug.

## Greps avoided

Confirmed: this review used only the inlined `DriverConcurrencyGate.swift`
source and the resolved-symbol line numbers provided in the task. No `grep`,
`glob`, `read`, or `task` calls were made against the repository to inform the
review. The only filesystem write was this findings file
(`docs/phases/code_review/findings/CR-08.md`).