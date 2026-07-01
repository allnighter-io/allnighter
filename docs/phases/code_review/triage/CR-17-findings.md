# CR-17 — Review runQueue until deadline mid-slice

## Summary

The `isPastDeadline(options)` deadline check in `runQueue` only fires inside the
`.compacting` branch of the terminal-state switch (PairCoordinator.swift:345).
All other terminal paths — including `.passed` (lines 330-334) — settle the entry
and continue to the next slice without checking the deadline. This means a queue
that is past its `options.until` deadline will still start new slice attempts as
long as those slices don't enter compaction, producing mid-slice and
between-slice overrun. The CR-06 P1 concern (deadline only at outer loop) is
only partially addressed: the compaction branch got a mid-slice check, but no
other branch or loop-top check was added.

## Findings

### P0 — (none)

No invariant or security violation found in the inlined sources.

### P1 — Deadline check only in compaction branch; other terminal paths and loop top unchecked

- **Invariant:** A queue run past its `options.until` deadline must stop starting
  new work. The deadline guard must be checked before beginning each new slice
  attempt and before transitioning to the next queue entry, not only when
  compaction retries occur.
- **Evidence:** `PairCoordinator.swift:345` — `isPastDeadline(options)` appears
  only inside `case .compacting` (line 335), after `executorAttempt -= 1`
  (line 344). The `.passed` case (lines 330-334) sets `settled = true` and
  increments `passed` with no deadline check. No `isPastDeadline` call is visible
  at the top of the queue-entry loop or before a new executor attempt outside the
  compaction branch. A slice that runs long but resolves without compaction
  (pass, fail, escalate) never triggers the deadline guard mid-slice; and after
  any settled entry the loop proceeds to the next entry without re-checking the
  deadline.
- **Suggested fix:** Hoist an `isPastDeadline(options)` check to the top of each
  queue-entry iteration (before dispatching a new slice) so that a past-deadline
  queue stops regardless of which terminal branch the previous entry took. If
  per-attempt granularity is desired, also check before each executor attempt,
  not only in the compaction retry path.
- **Suggested slice:** runQueue: hoist deadline check to loop top

### P2 — executorAttempt decremented before deadline check

- **Invariant:** State mutation should not occur when the run is about to stop
  for deadline.
- **Evidence:** `PairCoordinator.swift:344-345` — `executorAttempt -= 1` runs
  before `isPastDeadline(options)`. When past deadline, the entry is settled
  (line 348) and the loop breaks, so the decrement is moot for control flow, but
  the counter is still mutated and persisted on the entry.
- **Suggested fix:** Move the `isPastDeadline(options)` check before
  `executorAttempt -= 1` so the attempt counter is only decremented when a retry
  will actually occur.
- **Suggested slice:** runQueue: check deadline before mutating executorAttempt

## False alarms ruled out

- **parent.status = .complete set unconditionally (line 189):** The single-slice
  function marks the parent run `.complete` regardless of the terminal
  classification (lines 185-187), including when terminal is `.compacting`. This
  looks premature, but the terminal state is returned in the `Outcome` (line 200)
  and the caller (`runQueue`) decides whether to retry. `.complete` here means
  "this attempt finished executing," not "the slice succeeded." Ruled out
  without contradicting evidence from the inlined sources.
- **Sleep clamp:** No sleep/backoff logic (`Task.sleep`, `usleep`, throttle)
  appears in the inlined sources (lines 185-210, 325-350). Cannot confirm a
  sleep-clamp issue; not evidenced.
- **Planner takeover unbounded:** No planner-takeover logic appears in the
  inlined sources. Not evidenced.

## Greps avoided

Confirmed: no repo exploration performed. All evidence is drawn from the two
inlined source blocks (PairCoordinator.swift:185-210 and :325-350). No grep,
glob, read, or task tools were used on the repository.