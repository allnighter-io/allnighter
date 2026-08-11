# ASR-S03b — wake-safe park wake + deadline inventory

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §4.4
(vendor-backoff continuation is one of the obligations serve exists for; a due
obligation fires within 2 minutes of wake), §7 (`timer -> wake`), §10.1 R2.

**2 of N** in the ASR-S03 cut. S03a landed `WakeSafeWaiter` (`96b685a6`) and
converted `PendingWakeScheduler`. This slice applies it to the longest deadline
in the product and maps what is left.

## 1. Goal

`LoopCoordinator.sleepClampedToDeadline` — the wait behind a vendor-backoff /
session-cap park, which is routinely **hours** long — re-evaluates its deadline
against wall-clock time instead of computing one duration up front. Plus: an
honest inventory of every remaining deadline wait a daemon scheduler depends on.

## 2. Copy-paste prompt

> Convert `LoopCoordinator.sleepClampedToDeadline` to use `WakeSafeWaiter`, add
> the failing-first sleep-gap test, and produce the inventory in Step 4. Keep
> every clock/sleep seam injected. Do not change park/resume policy, vendor
> substitution, or any other LoopCoordinator behavior — this is a waiting
> mechanism change only.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/WakeSafeWaiter.swift` — the
  waiter from S03a and its injected `now` / `performSleep` seams.
- `Packages/AllnighterCore/Sources/AllnighterEngine/LoopCoordinator.swift` —
  **only** `sleepClampedToDeadline`, its callers, and the `now` seam near line
  184. Do not read the rest of the file.
- `Packages/AllnighterCore/Sources/AllnighterEngine/PendingWakeScheduler.swift`
  — how S03a wired the waiter in and recorded overshoot; copy that shape.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/LoopCoordinator.swift   (sleepClampedToDeadline + its seam only)
Packages/AllnighterCore/Tests/AllnighterEngineTests/WakeSafeWaiterTests.swift
docs/qa/alln-serve/ASR-S03b-deadline-inventory.md                        (new)
```
Plus the existing LoopCoordinator test file if its expectations change.

## 5. Do not read / do not touch

- Do not change park duration, resume policy, vendor substitution, session-cap
  logic, or anything else in `LoopCoordinator`. A behavior change here is a
  quota-spend change and is out of scope.
- Do not touch `ServeDaemon`, `ServeLifecycle`, `CapacityResidentService`
  (§2.4 deletes its periodic portion in ASR-S04 — do not fix what is being
  removed), any CLI file, any script, or `Apps/`.
- Do not add `IOKit`/`NSWorkspace` wake observers.

## 6. Steps

1. **Convert the wait.** `sleepClampedToDeadline` keeps its existing clamp to
   `config.until`, then waits via `WakeSafeWaiter` so the effective deadline is
   re-read on each nap boundary. Behavior when awake must be identical; only the
   sleeping-Mac case changes.

2. **Failing-first test, same discipline as S03a.** A 5-hour park (the real
   `agy`/Gemini reset interval), an injected sleep whose first invocation
   advances the fake clock past the deadline, asserting the wait returns within
   one nap. Run it against the pre-change code, **observe it fail**, and report
   the actual assertion message. A test that only ever passed proves nothing.

3. **Record overshoot** the way S03a does, so a real sleep gap is visible rather
   than silently absorbed.

4. **Inventory — this is half the slice.** Write
   `docs/qa/alln-serve/ASR-S03b-deadline-inventory.md` listing **every** wait in
   `Packages/AllnighterCore/Sources/AllnighterEngine/` that a background
   obligation depends on. One row per site: file:line, what it waits for, the
   typical duration, and a verdict of **wake-safe** (re-reads wall-clock at a
   bounded interval) / **not wake-safe** (computes one duration up front) /
   **not an obligation** (short poll, subprocess timeout, test seam).

   Rules for the inventory:
   - Judge each site by reading it, not by its name.
   - A loop that re-evaluates `now()` each iteration is wake-safe **only if**
     its inter-iteration wait is also bounded — check that, do not assume it.
   - Sites being deleted by a later slice (e.g. `CapacityResidentService`'s
     periodic portion, §2.4/ASR-S04) are listed and marked as such, not fixed.
   - If you cannot determine a verdict from the code, write **unknown** and say
     why. An honest unknown is worth more than a confident guess.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'WakeSafeWaiterTests|LoopCoordinator'
```

## 8. Done when

- [ ] The 5-hour park sleep-gap test was observed failing before the fix, with
      the failure message quoted in the report, and passes after.
- [ ] Awake behavior is unchanged: a short park still completes in one nap and
      the clamp to `config.until` still applies.
- [ ] Overshoot is recorded and non-zero after a simulated gap.
- [ ] No park/resume/substitution policy changed (diff is the wait mechanism
      plus tests).
- [ ] The inventory exists, covers every Engine wait an obligation depends on,
      and each row carries a verdict — including honest `unknown`s.
- [ ] No test sleeps in real time.
- [ ] Focused proof passes. One commit, explicit paths.

## 9. Host-state invariant

Changes only how a parked loop waits inside a running daemon. No install,
launchd, plist, or quota behavior changes.

## 10. What this slice does *not* prove

Same limit as S03a: a simulated clock jump is not a real lid close. **ASR-S06
gate 10** remains the only proof, and §10.1 R2 stays open until it is recorded.
