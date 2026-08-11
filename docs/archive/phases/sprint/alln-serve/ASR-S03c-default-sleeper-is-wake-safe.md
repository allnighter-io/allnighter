# ASR-S03c — make the default sleeper wake-safe

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §4.4,
§7 (`timer -> wake`), §10.1 R2.
Evidence: [`docs/qa/alln-serve/ASR-S03b-deadline-inventory.md`](../../qa/alln-serve/ASR-S03b-deadline-inventory.md).

**3 of N** in the ASR-S03 cut. S03a built `WakeSafeWaiter` and converted
`PendingWakeScheduler`; S03b converted `LoopCoordinator` and produced the
inventory. The inventory found **seven** remaining obligation-bearing waits that
still compute one duration up front — including `VendorBackoffReconciler`
(hours) and `BoostSeedScheduler` (calendar hours), both obligations §4.4 names.

## 1. Goal

Fix all seven with **one symbol**: make `DefaultPendingWakeSleeper` — the shared
default every one of them already injects — nap in bounded chunks and re-read
the wall clock, instead of converting seven call sites independently.

## 2. Copy-paste prompt

> Reimplement `DefaultPendingWakeSleeper.sleep(until:jitterSeconds:)` on top of
> `WakeSafeWaiter` so every scheduler that takes the default becomes wake-safe,
> add the failing-first test, and update the S03b inventory verdicts to match
> reality. Change no scheduler's own logic, intervals, or jitter policy.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/PendingWakeScheduler.swift`
  — `PendingWakeSleeper` and `DefaultPendingWakeSleeper`, including the existing
  jitter behavior that must be preserved exactly.
- `Packages/AllnighterCore/Sources/AllnighterEngine/WakeSafeWaiter.swift` — the
  waiter and its injected `now` / `performSleep` seams.
- `docs/qa/alln-serve/ASR-S03b-deadline-inventory.md` — the seven rows this
  slice flips, and the rows it must **not** touch.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/PendingWakeScheduler.swift   (DefaultPendingWakeSleeper only)
Packages/AllnighterCore/Tests/AllnighterEngineTests/WakeSafeWaiterTests.swift
docs/qa/alln-serve/ASR-S03b-deadline-inventory.md                            (verdict column only)
```

## 5. Do not read / do not touch

- Do **not** edit `VendorBackoffReconciler`, `BoostSeedScheduler`,
  `CapacityRefreshScheduler`, `ProbeRecordRefreshScheduler`,
  `NotificationScheduler`, or `PMTurnWakeScheduler`. The whole point is that
  they need no edit — they already inject the default. If any of them turns out
  **not** to use `DefaultPendingWakeSleeper`, stop and report it rather than
  editing it; that is a different slice.
- Do not touch `CapacityResidentService` (ASR-S04 deletes its periodic portion),
  `RemoteMacAgentCoordinator` (separate sleeper protocol, out of scope),
  `ServeDaemon`, `ServeLifecycle`, any CLI file, any script, or `Apps/`.
- Do not change any scheduler's interval, backoff, or jitter policy.
- Do not add `IOKit`/`NSWorkspace` observers.

## 6. Steps

1. **Reimplement the default.** `DefaultPendingWakeSleeper.sleep(until:jitterSeconds:)`
   applies jitter to the deadline **once** (unchanged), then delegates the wait
   to `WakeSafeWaiter`. Behavior while awake is identical; only the
   sleeping-Mac case changes.

2. **Keep the seam and the type name.** Every scheduler already names
   `DefaultPendingWakeSleeper` as its default and injects fakes in tests. Do not
   rename it, do not change the protocol, and do not alter any scheduler's
   initializer signature — a rename here would touch seven files and defeat the
   point of the slice.

3. **Failing-first test, same discipline as S03a/S03b.** Drive
   `DefaultPendingWakeSleeper` through an injected sleep seam: a deadline hours
   out, first nap advances the fake clock past it, assert return within one nap.
   Observe it fail against the current implementation, quote the failure
   message, then make it pass. If `DefaultPendingWakeSleeper` has no injectable
   sleep seam today, add one — that is in scope and is the minimum needed to
   make the behavior testable at all.

4. **Prove the blast radius.** Add one test per *high-duration* consumer —
   `VendorBackoffReconciler` and `BoostSeedScheduler` — showing that a scheduler
   constructed with its **default** sleeper survives a simulated sleep gap.
   Constructing them with the default is the assertion: it proves the fix
   reaches real call sites and not just the type in isolation.

5. **Update the inventory honestly.** Flip only the rows this change actually
   fixes. Leave `CapacityResidentService` and `RemoteMacAgentCoordinator` as
   they are, with their existing notes. Add a line recording that S03c flipped
   them and how it was verified. Do not mark a row wake-safe that you did not
   test or read.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'WakeSafeWaiterTests|PendingWake|VendorBackoff|BoostSeed'
```

## 8. Done when

- [ ] The failing-first test was observed failing, with the message quoted.
- [ ] `DefaultPendingWakeSleeper` naps in bounded chunks and re-reads the clock;
      jitter is still applied once, not per nap.
- [ ] `VendorBackoffReconciler` and `BoostSeedScheduler`, each built with its
      **default** sleeper, return within one nap after a simulated gap.
- [ ] No scheduler file was edited; no initializer signature changed.
- [ ] No interval, backoff, or jitter policy changed.
- [ ] The inventory reflects reality, with untouched rows left untouched.
- [ ] No test sleeps in real time.
- [ ] Focused proof passes. One commit, explicit paths.

## 9. Host-state invariant

Changes only how already-running daemon schedulers wait. No install, launchd,
plist, or quota behavior changes.

## 10. What this slice does *not* prove

Unchanged from S03a/S03b: simulated clock jumps are not a real lid close.
**ASR-S06 gate 10** is the only proof, and §10.1 R2 stays open until it is
recorded under `docs/qa/alln-serve/`.
