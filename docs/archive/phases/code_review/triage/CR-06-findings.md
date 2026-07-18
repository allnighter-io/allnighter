# CR-06 — PairCoordinator.runQueue loop

## Summary
`runQueue` correctly preserves the three named invariants for the happy and
failure paths: compaction grace does not escalate (`executorAttempt -= 1` at
`:284` keeps compaction out of the failure budget), the executor attempt budget
is honored for `.failure`/`.stalled`/`.failed` (`:221`, `:294`), and planner
takeover is invoked exactly when the budget is exhausted (`:231`, `:304`). The
state machine terminates on every *bounded* path. The real defects are on the
two unbounded paths: `.compacting` and `.infraBackoff` decrement `executorAttempt`
back and never set `settled`, so a slice that keeps returning either terminal
loops forever — and because the `options.until` deadline is checked only at the
top of the outer loop (`:188-191`), that stuck slice also ignores the deadline
and the planner-takeover call is not deadline-aware either. Secondary issues:
gate-blocked escalations can record no reason and no run IDs, `store.save`
errors are swallowed, zero-second compaction grace can spin, and there is no
`Task` cancellation handling. `applyPlannerTakeover` and `reconcileStaleRunning`
are not inlined; the takeover counting depends on their exact post-conditions,
which should be verified.

## Findings

### P0 — None confirmed
No P0 (invariant/security) violation is confirmable from the inlined sources.
The three named invariants hold on every bounded path:
- **Compaction grace must not escalate** — `.compacting` (`:283-287`) and
  `.infraBackoff` (`:288-291`) do not touch `entry.status` and never set
  `settled = true` via an escalate branch; they retry with `nudge = nil`. The
  invariant is preserved. (The *liveness* flip-side — that grace must also
  eventually terminate — is filed as P1 below, not an invariant violation.)
- **Executor attempt budget** — `attemptBudget = options.executorAttemptsBeforePlanner`
  (`:185`); the `executorAttempt < attemptBudget` guard (`:221`, `:294`) yields
  exactly `attemptBudget` executor attempts before planner takeover, then
  takeover. Compaction/infraBackoff intentionally do not consume budget, which
  is the point of the grace invariant.
- **Planner takeover** — invoked on budget exhaustion for both the `.failure`
  (`:231-244`) and `.stalled`/`.failed` (`:304-318`) paths, with a correctly
  populated `PlannerTakeoverPrompt.Context`.

### P1 — `.compacting` / `.infraBackoff` retries are unbounded (infinite retry, grace blocks the queue)
- **Invariant:** liveness — a slice must eventually settle (pass, escalate, or
  hand to planner) so the outer loop can advance. The grace invariant says
  compaction must not *escalate*; it does not license compaction to *never
  terminate*.
- **Evidence:** the inner loop increments `executorAttempt` at the top
  (`PairCoordinator.swift:207`) then, for `.compacting` (`:283-287`) and
  `.infraBackoff` (`:288-291`), decrements it back (`executorAttempt -= 1` at
  `:284` and `:289`) and leaves `settled = false`. Net change per iteration is
  zero, so `executorAttempt` never reaches `attemptBudget` via these branches.
  There is no `maxCompactionRetries` / `maxInfraBackoffRetries` counter. If
  `runSlice` keeps returning `.compacting` (or `.infraBackoff`), the inner
  `while !settled` loop (`:206`) never exits, the slice is never written back
  (`queue.entries[idx] = entry` at `:331` is unreachable), and the outer loop
  never advances to the next pending entry. The queue is hung on one slice
  indefinitely.
- **Suggested fix:** add per-terminal retry caps to `QueueOptions` (e.g.
  `maxCompactionRetries`, `maxInfraBackoffRetries`). Track a separate counter
  that is *not* decremented, and when exceeded either escalate with a distinct
  `escalatedReason` (e.g. "compaction budget exhausted") or hand to planner.
  Do **not** fold compaction into `executorAttempt` — that would re-introduce
  the escalation the grace invariant forbids.
- **Suggested slice:** "runQueue: bound compaction/infraBackoff retries"

### P1 — `options.until` deadline is not honored mid-slice
- **Invariant:** a caller-supplied `until` deadline should stop the queue. The
  contract is "stop near the deadline," not "stop only between slices."
- **Evidence:** the deadline is checked exclusively at the top of the outer
  loop (`PairCoordinator.swift:188-191`). Once a slice starts, the inner retry
  loop (`:206-329`) has no `until` check. Every mid-slice path can overrun by
  an unbounded amount: each `.compacting` sleeps `compactionGraceSeconds`
  (`:285-286`) and repeats indefinitely (see P1 above); each `.infraBackoff`
  sleeps 5 s (`:290`) and repeats indefinitely; failure retries run
  `attemptBudget` more `runSlice` calls; and `runPlannerTakeover`
  (`:231-244`, `:304-318`) is a full `runService.run` + `checkRunner.run`
  (`:382`, `:390`) with no deadline clamp. A single stuck slice can therefore
  miss the deadline by minutes-to-forever, and `stoppedReason` is never set to
  reflect it.
- **Suggested fix:** check `options.until` inside the inner loop — at minimum
  before each compaction/infraBackoff sleep and before invoking
  `runPlannerTakeover` — and break out with `stoppedReason = "until deadline
  (mid-slice)"`, writing the entry back as `.running`/`.escalated` as
  appropriate. Also clamp each `Task.sleep` to the remaining deadline so a
  long `compactionGraceSeconds` cannot overshoot.
- **Suggested slice:** "runQueue: honor queue deadline inside slice retry loop"

### P1 — No `Task` cancellation handling; cancelled parent cannot stop a stuck slice
- **Invariant:** a long-running `async` queue should observe `Task` cancellation
  so the caller can abort (distinct from the `until` deadline).
- **Evidence:** `runQueue` has no `try Task.checkCancellation()` anywhere
  (`:171-350`). The only stop is the inter-slice `until` check (`:188-191`),
  which (per the P1 above) is not reached while a slice is stuck. A cancelled
  parent `Task` is ignored until the slice settles on its own. Combined with
  the unbounded compaction path, cancellation is effectively unobservable.
- **Suggested fix:** `try Task.checkCancellation()` at the top of the outer
  loop and before each `runSlice` / `runPlannerTakeover` call; convert to a
  `stoppedReason = "cancelled"` rather than throwing, so the partial `QueueOutcome`
  is still returned.
- **Suggested slice:** "runQueue: observe Task cancellation"

### P2 — Gate-blocked escalation can record no reason and no run IDs
- **Invariant (traceability):** an escalated slice should carry a reason and,
  if a run happened, its run IDs.
- **Evidence:** on `!outcome.gate.isAllowed` (`PairCoordinator.swift:254`),
  `entry.escalatedReason` is set only `if case .blocked(_, let reason)`
  (`:256-258`). Any other disallowed-gate case leaves `escalatedReason == nil`.
  Run IDs (`entry.parentRunId`/`childRunId`, `:272-273`) and check fields
  (`:274-275`) are assigned only *after* the gate check passes, so a
  gate-blocked escalation records no run IDs even though `outcome.parentRun`/
  `childRun` may be non-nil. The slice is escalated with no traceability.
- **Suggested fix:** set a default `escalatedReason` (e.g. "gate disallowed")
  in the else branch, and record `parentRunId`/`childRunId` before the gate
  check.
- **Suggested slice:** (nit, fold into the next touch of this file)

### P2 — `store.save` errors are silently swallowed
- **Invariant (durability):** a failed persistence write should at least be
  observable, so the operator knows on-disk queue state is stale.
- **Evidence:** both saves use `try? store.save(queue)`
  (`PairCoordinator.swift:194`, `:332`). If the write fails, the queue
  continues in-memory but the persisted state is stale; on crash,
  `reconcileStaleRunning` (`:179`) will recover from a state that does not
  reflect the in-flight slice. There is no log, no `stoppedReason`, no signal.
- **Suggested fix:** at minimum `appendVerbose` the save failure; consider
  surfacing a non-fatal `persistenceError` on `QueueOutcome` if saves keep
  failing.
- **Suggested slice:** (nit, optional)

### P2 — Zero-second compaction grace can hot-loop
- **Invariant (liveness/clarity):** a grace sleep should always yield for at
  least some minimum interval.
- **Evidence:** `let grace = UInt64(entry.packet.compactionGraceSeconds) *
  1_000_000_000` (`PairCoordinator.swift:285`) then `try? await Task.sleep(
  nanoseconds: grace)` (`:286`). If `compactionGraceSeconds` is 0, the sleep
  is 0 ns — `Task.sleep(0)` yields the executor but does not introduce wall
  time. Combined with the unbounded compaction path (P1 above), a
  synchronously-returning `.compacting` becomes a tight CPU loop.
- **Suggested fix:** clamp grace to a floor (e.g. `max(1, grace)`) or assert
  `compactionGraceSeconds >= 1` at packet construction.
- **Suggested slice:** (nit, fold into the compaction-cap slice)

### P2 — `UInt64(entry.packet.compactionGraceSeconds)` can trap on overflow
- **Invariant (robustness):** a malformed packet should not trap the queue.
- **Evidence:** `UInt64(entry.packet.compactionGraceSeconds) * 1_000_000_000`
  (`PairCoordinator.swift:285`) will trap on arithmetic overflow if
  `compactionGraceSeconds` is large (>= ~1.84e10 s). Unlikely in practice but
  unvalidated.
- **Suggested fix:** cap `compactionGraceSeconds` to a sane maximum before
  conversion, or use a checked multiply.
- **Suggested slice:** (nit, optional)

## Assumptions to verify (symbols not inlined)
- **`applyPlannerTakeover`** — the counting at `PairCoordinator.swift:246-250`
  and `:320-324` assumes it sets `entry.status = .passed` (with
  `entry.resolvedBy = "planner"`) iff `takeover.passed`, and otherwise sets
  `entry.status = .escalated`. If it ever leaves `entry.status` as `.running`
  or sets a status other than `.passed`/`.escalated`, the `passed`/`escalated`
  counters mis-count and — worse — a `.running` entry would be skipped by the
  outer `firstIndex(where: { $0.status == .pending })` selector (`:187`) and
  silently dropped from the run. Verify `applyPlannerTakeover` sets status to
  exactly `.passed` or `.escalated`.
- **`reconcileStaleRunning`** — called once at entry (`:179`). Within a single
  `runQueue` invocation, entries move `.pending → .running → .passed`/`.escalated`
  atomically per entry, so there is no intra-invocation stale state. Cross-
  invocation recovery depends on `reconcileStaleRunning`'s logic: confirm it
  resets stale `.running` entries to `.pending` (re-run) or `.escalated`
  (give up), and never leaves a `.running` entry that the `.pending` selector
  would skip forever.
- **`runSlice`** — assumed to return `.compacting`/`.infraBackoff` only
  transiently. The P1 above assumes the worst case (persistent return); if
  `runSlice` itself bounds these, the liveness risk is mitigated upstream.

## False alarms ruled out
- **`executorAttempt` goes negative on compaction/infraBackoff.** No. It is
  incremented to >= 1 at the top of the inner loop (`:207`) before the
  decrement (`:284`/`:289`), so the floor is 0. Next iteration bumps it back
  to 1. No negative.
- **Budget bypassed by compaction.** No. Compaction does not escalate, so
  there is no bypass — it simply does not consume the failure budget, which is
  exactly the grace invariant. The defect is unbounded *retry*, not budget
  evasion.
- **`idx` invalidated during the inner loop.** No. `entry` is a value copy
  (`:201`); the `entries` array is not mutated inside the inner loop, so `idx`
  stays valid until the write-back at `:331`.
- **Double-save race between `:194` and `:332`.** No. The two saves are
  sequential within one slice on the same `async` frame; there is no
  concurrency inside `runQueue`.
- **`attemptBudget == 0` mis-handled.** No. With budget 0, the first failure
  hits `executorAttempt = 1`, `1 < 0` is false, so planner takeover runs
  immediately. That is a valid (if aggressive) configuration.
- **`.success` with `gate.isAllowed` but no terminal escalates correctly.**
  Yes — `guard let terminal` (`:264-270`) sets `.escalated` with reason "no
  terminal outcome". Sound, not a finding.
- **Takeover `passed`/`errorReason` inconsistency.** No.
  `runPlannerTakeover` (`:368-392`) returns `passed` and `errorReason` as
  strict complements on every path (serve error `:371`, run failure `:387`,
  check failure `:392`). Internally consistent.

## Greps avoided
- Did not read or grep any file outside the inlined
  `PairCoordinator.swift:169-400` source. `applyPlannerTakeover`,
  `reconcileStaleRunning`, `runSlice`, `NudgePrompt.failureRetry`,
  `PlannerTakeoverPrompt.assemble`, `SliceQueueStore.save`, `QueueOptions`,
  and `SliceTerminalOutcome` were treated as opaque resolved symbols per the
  review instructions; their behavior was not inspected. No repo exploration
  was performed. All line numbers are derived from the inlined source and the
  resolved-symbol anchors (`runQueue` :171, `runPlannerTakeover` :359,
  `failureReason` :395).