# CR-16 — Review runQueue compaction and infraBackoff bounds

## Summary
CR-06 P1 flagged unbounded compaction/infraBackoff in the runQueue. The single
inlined source (PairCoordinator.swift:280-295) does **not** contain either the
compaction logic or any `infraBackoff` symbol — it shows only the failure
escalation path: a deadline stop (`stoppedForDeadline`) and, in the `else`
branch, a call to `runPlannerTakeover` with the current `executorAttempt` and a
`.failed` terminal. Against the four requested lenses (executorAttempt
decrement, max retries, queue hang, escalate path), the inlined code shows a
time-based bound (deadline) but **no retry-count bound** and **no decrement** of
`executorAttempt` in this span. The escalate path exists but appears to be the
only recovery action before the deadline fires. The core compaction/infraBackoff
claim cannot be confirmed or refuted from this snippet and should be re-scoped
with that code inlined.

## Findings

### P0 — None
No invariant/security issue can be established from the 16 inlined lines. The
compaction/infraBackoff code that CR-06 P1 refers to is not present in the
inlined source, so no P0 can be asserted without reading outside the allowlist.

### P1 — No retry-count bound visible in the takeover path; only a deadline bound
- **Invariant:** A failing queue entry must be bounded by both a deadline **and**
  a retry count so it cannot spin in `runPlannerTakeover` until the deadline
  expires.
- **Evidence:** PairCoordinator.swift:280 (only `stoppedForDeadline` guard shown),
  PairCoordinator.swift:282-283 (`else` → `runPlannerTakeover` on failure with no
  visible `maxAttempts` / retry-count check before the call).
- **Suggested fix:** Add an explicit retry-count ceiling before the `else`
  (e.g., `if executorAttempt >= maxExecutorAttempts { surfaceToUser(); settled = true }`)
  so an entry that keeps failing is surfaced to the user instead of looping
  through takeover until the deadline.
- **Suggested slice:** Bound executor takeover retries in PairCoordinator

### P1 — `executorAttempt` is read but not decremented in this span
- **Invariant:** If `executorAttempt` is a monotonic counter that gates
  escalation, it must be incremented and/or decremented at a visible, bounded
  site; an unbounded counter paired with no max-retries guard (see above) is the
  queue-hang risk.
- **Evidence:** PairCoordinator.swift:290 (`executorAttempts: executorAttempt` is
  passed read-only into the takeover context); no `executorAttempt -=` or
  `executorAttempt +=` appears in lines 280-295.
- **Suggested fix:** Confirm the increment/decrement site is bounded and covered
  by a test; if `executorAttempt` is meant to reset on a successful takeover, that
  reset must be visible and tested. Re-scope this review with the loop body that
  mutates `executorAttempt` inlined.
- **Suggested slice:** (covered by the slice above)

### P2 — Escalate path is the only recovery; no non-deadline "give up" terminal
- **Invariant:** Beyond the deadline, a repeatedly failing entry should have a
  terminal "surface to user" path so the queue is not held hostage to a distant
  deadline.
- **Evidence:** PairCoordinator.swift:280-281 (deadline → `settled = true`),
  PairCoordinator.swift:282-283 (else → `runPlannerTakeover`); no third branch
  surfacing a persistent failure to the user is visible in this span.
- **Suggested fix:** Add a terminal "give up and surface" branch distinct from
  the deadline stop, triggered by the retry ceiling from the P1 above.
- **Suggested slice:** (covered by the slice above)

## False alarms ruled out
- **"Completely unbounded queue."** Not quite — `stoppedForDeadline = true;
  settled = true` (PairCoordinator.swift:280-281) provides a time-based bound.
  The real concern is the *absence of a count-based bound*, not total absence of
  any bound.
- **"`executorAttempts: executorAttempt` is a bug."** No — passing the current
  attempt count into the takeover context (PairCoordinator.swift:290) is correct
  and necessary for the planner to know prior attempts. The issue is the absence
  of a bound/decrement, not the read itself.
- **"`lastTerminal: .failed` hardcodes the outcome."** This is the failure branch
  (the `else` after the deadline check), so recording `.failed` as the last
  terminal here is expected, not a defect (PairCoordinator.swift:291).

## Greps avoided
Confirmed: no repo exploration, no `grep`, no `glob`, no reads outside the
inlined PairCoordinator.swift:280-295 snippet. The compaction/infraBackoff code
was not read; the recommendation above is to re-scope with that code inlined
rather than to infer its behavior from this snippet.