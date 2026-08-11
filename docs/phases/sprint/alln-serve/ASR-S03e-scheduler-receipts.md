# ASR-S03e — scheduler receipt store

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §6
(`runtime.json`, one row per registered scheduler), §7 (`daemon -> scheduler`
inference ban: a process answering does not mean schedulers work).

**5 of N** in the ASR-S03 cut. Two deliverables: the receipt store, and the
daemon registering into it. Per-scheduler attempt/success/error reporting is
**S03e2** — do not attempt it here.

## 1. Goal

`~/Library/Application Support/Allnighter/Coordinator/runtime.json` exists and
records daemon identity plus one row per scheduler the daemon actually
registered, so status can answer "is scheduling alive?" instead of "does a pid
exist?"

## 2. Copy-paste prompt

> Add `ServeRuntimeReceipts` (atomic writer + reader for `runtime.json`) and
> have `ServeDaemon` register each scheduler it starts. Do not modify any
> scheduler, do not add per-attempt reporting, and do not touch
> `ServeStatusJSON` — those are later slices.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift` lines
  60–200 only — how the daemon constructs its schedulers and its task group,
  and where daemon identity (id, pid, startedAt) already lives.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeDesiredState.swift` —
  the atomic-write pattern to copy (`replaceItem`, injected clock, injected
  home). Use the same shape; do not reintroduce remove-then-move.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemonStore.swift` —
  where the durable coordinator record lives, so `runtime.json` sits beside it.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeRuntimeReceipts.swift        (new)
Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeRuntimeReceiptsTests.swift (new)
```

## 5. Do not read / do not touch

- Do **not** modify `PendingWakeScheduler`, `BoostSeedScheduler`,
  `CapacityRefreshScheduler`, `ProbeRecordRefreshScheduler`,
  `NotificationScheduler`, `PMTurnWakeScheduler`, or `VendorBackoffReconciler`.
  Registration is recorded by the daemon at the point it starts each one.
- Do not touch `ServeStatusJSON`, `ServeDaemonProbe`, `CoordinatorHealth`,
  `ServeLifecycle`, any CLI file, any script, or `Apps/`.
- Do not add log rotation — §6's bounded log is a separate concern.

## 6. Steps

1. **`ServeRuntimeReceipts`.** Path
   `<home>/Library/Application Support/Allnighter/Coordinator/runtime.json`,
   home injected. Shape: `schemaVersion`, daemon identity (`daemonId`, `pid`,
   `startedAt`), and `schedulers: [Row]` where `Row` is
   `{ id, state, lastAttemptAt?, lastSuccessAt?, lastError?, nextWakeAt? }` and
   `state ∈ registered | running | waiting | failed`.

2. **Write atomically**, same as `ServeDesiredState`: temp file in the same
   directory then `replaceItem`. A crash mid-write must leave the previous
   receipt readable, never a truncated or absent file.

3. **The id set is `ServeRuntimeReceipts`' own constant**, from §6:
   `pendingWake`, `pmTurnWake`, `boostSeed`, `vendorBackoff`, `notifications`,
   `capacityRefresh`, `probeRecordRefresh`, and `cloudRelay`. Mark `cloudRelay`
   **optional** — §6 says an absent optional scheduler is omitted, never painted
   failed, while an absent *required* one is a degradation. Expose which ids are
   required; do not encode that judgement at the call site.

4. **Daemon registers what it actually starts.** In `ServeDaemon`, as each
   scheduler is started, record a row with state `registered`. Register from the
   real start site — not from a hard-coded list written to look complete. If a
   scheduler is conditionally started, its row appears only when it is.

5. **Reader tolerates absence and corruption.** `read(homeDirectory:)`
   distinguishes absent (no daemon has written yet) from unreadable (corrupt /
   future schema), the way `ServeDesiredState.Reading` does. Neither is silently
   reported as a healthy set of rows.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'ServeRuntimeReceiptsTests|ServeDaemon'
```

## 8. Done when

- [ ] A written receipt round-trips: daemon identity plus one row per registered
      scheduler.
- [ ] The write is atomic — a failed write leaves the prior receipt intact and
      readable (assert it, do not assume `replaceItem`).
- [ ] Absent and corrupt receipts are distinguishable, and neither reads as a
      populated set of rows.
- [ ] `cloudRelay` absent is omitted, not `failed`; a missing **required** id is
      reported as missing by the reader.
- [ ] The daemon's registration is driven by the actual start sites — a test
      proves a scheduler that is not started has no row.
- [ ] No scheduler file was modified.
- [ ] No test writes outside a temp directory.
- [ ] Focused proof passes. One commit, explicit paths.

## 9. Host-state invariant

Additive: the running daemon starts writing a receipt file it did not write
before. Nothing reads it yet (`ServeStatusJSON` v2 is S03f), so no command's
output changes. The supervised agent, plist, and canonical binary are untouched.
