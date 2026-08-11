# ASR-S03e2b — wire the four simple schedulers to progress

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §6, §7
(`daemon -> scheduler` inference ban).

**7 of N** in the ASR-S03 cut. Follows ASR-S03e2a (`69a52bbd`), which built
`ServeSchedulerProgress` and proved the pattern on `PendingWakeScheduler`.

Mechanical repetition of one already-proven pattern across four schedulers.
`PMTurnWakeScheduler`, `NotificationScheduler`, and the cloud relay are
**S03e2c** — do not touch them here.

## 1. Goal

Four more receipt rows stop lying. Today `boostSeed`, `vendorBackoff`,
`capacityRefresh`, and `probeRecordRefresh` read `registered` forever on the live
host, whether they are working or wedged.

## 2. Copy-paste prompt

> Wire `BoostSeedScheduler`, `VendorBackoffReconciler`, `CapacityRefreshScheduler`,
> and `ProbeRecordRefreshScheduler` to `SchedulerProgressReporting` exactly the way
> `PendingWakeScheduler` was wired in commit `69a52bbd`. Read that commit's diff
> first and copy its shape. Do not change any scheduler's timing, sleep
> arithmetic, or control flow. Do not touch PMTurnWakeScheduler,
> NotificationScheduler, the cloud relay, any CLI file, or any script.

## 3. Read only

- `git show 69a52bbd -- Packages/AllnighterCore/Sources/AllnighterEngine/PendingWakeScheduler.swift`
  — **the** reference. Copy this shape; do not invent a second one.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeSchedulerProgress.swift`
  — the protocol and the no-op default.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift` lines
  120–200 — the eight registration sites.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/BoostSeedScheduler.swift
Packages/AllnighterCore/Sources/AllnighterEngine/VendorBackoffReconciler.swift
Packages/AllnighterCore/Sources/AllnighterEngine/CapacityRefreshScheduler.swift
Packages/AllnighterCore/Sources/AllnighterEngine/ProbeRecordRefreshScheduler.swift
Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeSchedulerProgressWiringTests.swift  (new)
```

## 5. Do not touch

`PMTurnWakeScheduler`, `NotificationScheduler`, `RemoteMacAgentCoordinating` /
cloud relay, `ServeRuntimeReceipts`, `ServeSchedulerProgress`,
`CoordinatorHealth`, `ServeDaemonProbe`, `ServeLifecycle`, anything under
`Sources/AllnighterCLI`, any script, `Apps/`.

## 6. Steps

Per scheduler, identically:

1. Add a `progress: SchedulerProgressReporting = NoOpSchedulerProgress()` init
   parameter and a matching stored property. Default keeps every existing
   construction site and test compiling unchanged.
2. Add an `id: String` the scheduler reports under — the same id `ServeDaemon`
   already registers (`boostSeed`, `vendorBackoff`, `capacityRefresh`,
   `probeRecordRefresh`). It is a constant on the scheduler, not a caller
   argument, so the daemon and the scheduler cannot drift apart.
3. Report around the **existing** loop: `attempting` when a pass begins,
   `succeeded` when it completes, `failed(error:)` in the existing catch,
   `waiting(until:)` with the deadline it is about to sleep to — the deadline it
   already computes, never a recomputed one.
4. `ServeDaemon` passes the shared `ServeSchedulerProgress` into each.

Do **not** change any sleep interval, jitter, cancellation check, ordering, or
early-exit. This slice adds reporting to loops that already work. If a
scheduler's control flow makes an honest report awkward, report less rather than
restructure the loop, and say so in the commit message.

`failed(error:)` carries the scheduler's own error description only — never
vendor stdout, prompt text, source excerpt, credential, or environment (§6).

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'ServeSchedulerProgressWiringTests|ServeSchedulerProgressTests|BoostSeed|VendorBackoff|CapacityRefresh|ProbeRecordRefresh|ServeDaemon'
```

## 8. Done when

- [ ] Each of the four reports at least one non-`registered` state under a
      recording reporter driven through one loop iteration, asserted per
      scheduler — four separate assertions, not one loop over a table.
- [ ] Each reports under the same id `ServeDaemon` registers it with. A test
      compares the daemon's id set against the schedulers' own constants and
      fails on any mismatch.
- [ ] A failing/throwing reporter does not stop or delay any of the four.
- [ ] No sleep interval, jitter value, or cancellation check changed — prove by
      reading the diff, and state it in the commit message.
- [ ] `PMTurnWakeScheduler`, `NotificationScheduler`, and the cloud relay are
      unmodified and still read `registered`. That is correct for this slice.
- [ ] No test writes outside a temp directory. One commit, explicit paths.

## 9. Host-state invariant

Additive. Four rows in `runtime.json` gain movement; nothing reads them yet
(`ServeStatusJSON` v2 is S03f), so no command's output changes. Scheduler timing
is untouched, so the live daemon behaves identically.
