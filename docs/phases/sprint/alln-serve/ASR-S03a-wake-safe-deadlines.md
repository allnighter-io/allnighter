# ASR-S03a — wake-safe deadline evaluation

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §4.4
(`ServeDaemon` owns wake; a due obligation fires within 2 minutes of system
wake), §7 (`timer -> wake` inference ban), §10.1 R2.

**1 of N** in the ASR-S03 cut, deliberately isolated. §10.1 R2 names this as the
easiest place in the packet to write a proof that cannot fail: a test that
advances a fake clock proves arithmetic, not that a sleeping Mac wakes and
fires. This slice exists so the wake bound is one reviewable mechanism with one
failing-first test, instead of arithmetic buried inside a larger status slice.

## 1. Goal

A scheduler waiting on a deadline re-evaluates that deadline against
**wall-clock time** at a bounded interval, so an obligation that came due while
the Mac was asleep fires within 2 minutes of wake instead of waiting out the
original interval.

## 2. Copy-paste prompt

> Add a `WakeSafeWaiter` that naps in bounded chunks and re-reads the wall clock
> after each nap, then make `PendingWakeScheduler` use it. Every clock and sleep
> seam stays injected. Do not touch the other schedulers, `ServeDaemon`, or any
> launchd code — a follow-up slice applies the same waiter to them.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/PendingWakeScheduler.swift`
  — `PendingWakeSleeper`, `DefaultPendingWakeSleeper`, the `now` seam, and the
  jitter behavior that must be preserved.
- `Packages/AllnighterCore/Sources/AllnighterEngine/PendingWakePlanner.swift` —
  how a due deadline is computed today.
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/` — pick the existing
  pending-wake test file and follow its fake-clock style.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/WakeSafeWaiter.swift            (new)
Packages/AllnighterCore/Sources/AllnighterEngine/PendingWakeScheduler.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/WakeSafeWaiterTests.swift    (new)
```
Plus the existing pending-wake test file if its expectations change.

## 5. Do not read / do not touch

- Do not modify `CapacityRefreshScheduler`, `ProbeRecordRefreshScheduler`,
  `BoostSeedScheduler`, `PMTurnWakeScheduler`, or `NotificationScheduler` —
  a follow-up slice converts them once this waiter is proven.
- Do not touch `ServeDaemon`, `ServeLifecycle`, any launchd code, any CLI file,
  any script, or `Apps/`.
- Do not add `IOKit` or `NSWorkspace` wake observers. §4.4 leaves the mechanism
  open and the bounded re-read is the simpler, testable choice; an observer is
  an optimization that can come later if measurement demands it.

## 6. Steps

1. **`WakeSafeWaiter`.** `wait(until deadline: Date) async throws` naps in
   chunks of at most `maxNapSeconds` (default `60`), and **after every nap
   re-reads `now()`** and recomputes the remaining interval. It returns as soon
   as `now() >= deadline`. Both `now` and the underlying sleep are injected
   closures.

2. **Why the re-read is the whole point.** A single
   `Task.sleep(nanoseconds: deadline - now)` computes its duration **once**, up
   front. If the Mac sleeps for six hours in the middle of that nap, the
   scheduler resumes late by however much the platform deferred it — and it
   cannot notice, because it never looks at the clock again. Capping each nap at
   60 s means the loop re-reads the wall clock at least once a minute of
   *awake* time, so a deadline that passed during system sleep is detected on
   the first post-wake nap boundary. That is what makes the §4.4 bound hold
   without a wake observer.

3. **Preserve jitter.** `PendingWakeScheduler`'s existing jitter is applied to
   the deadline **once**, before waiting — never re-rolled per nap, which would
   change the effective deadline on every iteration.

4. **Overshoot is reported, not hidden.** The waiter returns how late it was
   (`now() - deadline`). `PendingWakeScheduler` records that overshoot so a real
   sleep gap is observable in the receipt rather than silently absorbed. A
   scheduler that fires 90 minutes late and looks identical to one that fired on
   time is how R2 stays invisible.

5. **Keep `PendingWakeSleeper` as the seam.** Implement the waiter behind the
   existing protocol so `PendingWakeScheduler`'s call site changes minimally and
   existing tests keep their injection point.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'WakeSafeWaiterTests|PendingWake'
```

## 8. Done when

- [ ] **The sleep-gap test is the point of this slice, and it must fail against
      a single up-front `Task.sleep`.** Simulate a system sleep: a deadline 4
      hours out, an injected sleep closure whose first invocation advances the
      fake clock by 6 hours (the Mac was asleep), and assert the waiter returns
      **within one nap** of that advance rather than continuing to wait out the
      original 4 hours. Write this test first, watch it fail against the current
      `DefaultPendingWakeSleeper`, then make it pass — and say in the report that
      you observed it fail.
- [ ] A deadline already in the past returns immediately without napping.
- [ ] A deadline 10 s out completes in one nap, not 60 s.
- [ ] The number of naps for a long deadline is bounded by
      `ceil(interval / maxNapSeconds)` — asserted, so the chunking is real.
- [ ] Jitter is applied once, not per nap (assert the deadline is stable across
      iterations).
- [ ] Reported overshoot is non-zero after a simulated sleep gap and ~zero on a
      normal wait.
- [ ] No test sleeps in real time; the suite stays sub-second.
- [ ] Focused proof passes. One commit, explicit paths.

## 9. Host-state invariant

Committing this slice changes only how the pending-wake loop waits inside a
running daemon. Nothing about installation, launchd, or the plist changes, and
the founder's frozen daemon keeps running its current bytes until an
`install-cli` triggers the S02d migration.

## 10. What this slice does *not* prove

It proves the mechanism under a simulated clock jump. It does **not** prove the
platform behaves that way on a real lid close — only **ASR-S06 gate 10** does,
and R2 stays open until that gate is recorded under `docs/qa/alln-serve/`.
