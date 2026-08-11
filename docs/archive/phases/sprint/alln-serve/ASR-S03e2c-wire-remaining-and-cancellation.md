# ASR-S03e2c — wire the last two schedulers; cancellation is not failure

Status: **done** — `e99cb778` (Cursor Grok 4.5)
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §6, §7,
and the project law *"Absence of a declared signal yields no observation, never
an inferred one."*

**8 of N** in the ASR-S03 cut. Closes the S03e2 wiring. Follows S03e2a
(`69a52bbd`) and S03e2b (`e1e7448d`).

## 1. The defect this slice fixes first

S03e2b's wiring is correct except for one thing, found in PM audit of
`e1e7448d`: every wired scheduler treats a **thrown sleep** as `failed`.

```swift
} catch {
    progress.failed(id: Self.progressId, error: "boostSeed sleep failed: ...")
    break
}
```

The overwhelmingly common way that sleep throws is **daemon shutdown** —
`isCancelled` fires, the task is cancelled, `sleep` throws `CancellationError`.
So a clean `alln serve` shutdown writes `failed` into four rows and leaves them
there: `ServeDaemon`'s `defer` clears `coordinator.json` via `store.clear()` but
does **not** clear `runtime.json`.

Consequence once S03f lands: a normally-stopped daemon leaves a receipt claiming
four required schedulers failed, and status reports `degraded` on a host where
nothing went wrong. That is a false alarm manufactured by our own writer — the
same class of bug S03e2a existed to prevent, arriving through a different door.

Cancellation is the daemon being told to stop. It is not a scheduler failure.

## 2. Copy-paste prompt

> First: make cancellation stop being reported as failure across every wired
> scheduler, and make the daemon leave an honest receipt at shutdown. Then wire
> `PMTurnWakeScheduler` and `NotificationScheduler` to `SchedulerProgressReporting`
> the same way `e1e7448d` wired the other four. Leave the cloud relay at
> `registered` and record why. Do not change any sleep interval, jitter value, or
> cancellation check.

## 3. Read only

- `git show e1e7448d` — the reference wiring, and the catch blocks this slice
  corrects.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeSchedulerProgress.swift`
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift` — the
  `defer { server.stop(); store.clear() }` in `run(...)`, and the registration
  sites.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeSchedulerProgress.swift
Packages/AllnighterCore/Sources/AllnighterEngine/BoostSeedScheduler.swift
Packages/AllnighterCore/Sources/AllnighterEngine/VendorBackoffReconciler.swift
Packages/AllnighterCore/Sources/AllnighterEngine/CapacityRefreshScheduler.swift
Packages/AllnighterCore/Sources/AllnighterEngine/ProbeRecordRefreshScheduler.swift
Packages/AllnighterCore/Sources/AllnighterEngine/PendingWakeScheduler.swift
Packages/AllnighterCore/Sources/AllnighterEngine/PMTurnWakeScheduler.swift
Packages/AllnighterCore/Sources/AllnighterEngine/NotificationScheduler.swift
Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeSchedulerProgressWiringTests.swift
```

## 5. Do not touch

`RemoteMacAgentCoordinating` / cloud relay, `ServeRuntimeReceipts`,
`CoordinatorHealth`, `ServeDaemonProbe`, `ServeLifecycle`, anything under
`Sources/AllnighterCLI`, any script, `Apps/`.

## 6. Steps

1. **Add `stopped(id:)` to `SchedulerProgressReporting`** (and the no-op). It
   records the loop as deliberately stopped — not `failed`, not `running`. Reuse
   an existing `SchedulerState` if one fits honestly; add a case only if none
   does, and if you add one, say so in the commit message because the receipt
   shape is read by S03f.

2. **Every wired scheduler distinguishes cancellation from failure.** In each
   catch, if the error is a cancellation *or* `isCancelled()` is now true, report
   `stopped` and break. Only a genuine error reports `failed`. Apply to all six
   wired schedulers including `PendingWakeScheduler` from S03e2a.

3. **Shutdown leaves an honest receipt.** `ServeDaemon`'s exit path must not
   leave rows that imply a live, working daemon. Decide between clearing
   `runtime.json` alongside `store.clear()` and marking every row `stopped`, and
   state which you chose and why in the commit message. Either is defensible;
   silently leaving stale `running`/`failed` rows is not.

4. **Wire `PMTurnWakeScheduler` and `NotificationScheduler`** exactly as
   `e1e7448d` wired the other four: `static let progressId` matching the id
   `ServeDaemon` registers, a `progress:` init parameter defaulting to the no-op,
   reporting around the existing loop. These two are larger (289 and 282 lines)
   and own nested types — report around the outer loop only. Do not restructure.

5. **cloudRelay stays `registered`.** It runs behind
   `RemoteMacAgentCoordinating`, so the daemon cannot see its passes and any
   progress the daemon invented would be a locally computed value dressed as an
   observation. Leave it registered and add one comment at the registration site
   saying so. It is optional in §6, so an unmoving row is not a degradation.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'ServeSchedulerProgressWiringTests|ServeSchedulerProgressTests|PendingWakeSchedulerTests|PMTurnWake|Notification|ServeDaemon'
```

## 8. Done when

- [ ] Kill test, written first and watched to fail against `e1e7448d`'s current
      behavior: cancelling a running scheduler leaves its row **not** `failed`.
- [ ] A genuine (non-cancellation) sleep error still reports `failed` with its
      bounded description. Both directions asserted.
- [ ] After `ServeDaemon` exits normally, `runtime.json` does not claim a live
      working daemon — asserted against the real exit path, not a hand-built row.
- [ ] `PMTurnWakeScheduler` and `NotificationScheduler` each report at least one
      non-`registered` state, under the same id `ServeDaemon` registers them with.
- [ ] The id-mismatch test from S03e2b still covers all seven wired ids.
- [ ] `cloudRelay` still reads `registered`, with the comment explaining why.
- [ ] No sleep interval, jitter value, or cancellation check changed.
- [ ] No test writes outside a temp directory. One commit, explicit paths.

## 9. Host-state invariant

Corrective and additive. The live daemon stops writing `failed` on clean
shutdown — strictly more honest than today. Two more rows gain movement. Nothing
reads the receipt yet (`ServeStatusJSON` v2 is S03f), so no command's output
changes and scheduler timing is untouched.

## 10. Closeout — 2026-08-11

Landed `e99cb778`. Re-verified outside the seat: 77 tests green under the §7
filter.

Rulings the seat made, both sound:

- **Shutdown marks rows `stopped` rather than clearing `runtime.json`.** Existing
  registration proofs read the receipt after exit, so deleting it would break
  them, and `stopped` is a truthful "daemon stood down" signal for S03f.
- **`cloudRelay` stays `registered`**, with the comment at the registration site
  explaining that the daemon cannot observe passes behind
  `RemoteMacAgentCoordinating` without inventing them.

A new `stopped` case was added to `SchedulerState`. S03f must treat it as a
stand-down paired with the supervisor observation, never as a failure.

**Carried note, deliberately not a slice.** `PMTurnWakeScheduler` previously
used `try?` around its sleep — swallow and keep polling — and now breaks out of
the loop on a sleep error. On the production path this is unreachable and
correct: `DefaultPendingWakeSleeper` bottoms out in `Task.sleep`, which throws
only `CancellationError`, and breaking on cancellation is right. It matters only
for an injected sleeper that throws something else, which exists only in tests.
Flagged here so a future reader does not rediscover it as a mystery.
