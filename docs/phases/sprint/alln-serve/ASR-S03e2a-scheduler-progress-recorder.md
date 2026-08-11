# ASR-S03e2a — serialized scheduler progress recorder

Status: **done** — `69a52bbd` (Cursor Grok 4.5)
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §6
(each row records attempt / success / error / next wake), §7 (`daemon ->
scheduler` inference ban).

**6 of N** in the ASR-S03 cut. Follows ASR-S03e, which built
`ServeRuntimeReceipts` and made the daemon register rows.

Two deliverables:

1. `ServeSchedulerProgress` — the single serialized writer of `runtime.json`,
   plus the narrow reporting interface a scheduler depends on.
2. `ServeDaemon` registers through it, and **exactly one** scheduler
   (`PendingWakeScheduler`) reports real progress through it.

Wiring the other six schedulers is **S03e2b** — do not attempt it here.

## 1. Goal

Today every row in the live receipt says `registered` forever:

```json
{"id":"pendingWake","state":"registered"}
{"id":"capacityRefresh","state":"registered"}
```

That proves the daemon *started* a loop. It cannot distinguish a scheduler that
is working from one that has been wedged for six hours. This slice builds the
mechanism that makes a row move, and proves it on one scheduler.

## 2. The race this slice exists to prevent

`ServeRuntimeReceipts.register` (line 173) is a read-modify-write of the whole
file: it reads all rows, replaces one, writes all rows back. That is survivable
today because registration happens once per scheduler during a single
`withTaskGroup` body.

It is **not** survivable once eight concurrent scheduler loops report at tick
rate. Two interleaved read-modify-writes drop a row: A reads, B reads, A writes,
B writes B's view — and A's row is gone. A receipt that silently loses rows would
make `ServeStatusJSON` v2 (S03f) report a required scheduler as missing, i.e.
`degraded`, on a perfectly healthy host. That is a false alarm manufactured by
our own writer.

So the recorder must be the **only** writer, must hold the row set in memory,
and must serialize every mutation.

## 3. Copy-paste prompt

> Add `ServeSchedulerProgress`: a single serialized owner of the scheduler row
> set that writes `runtime.json` through the existing `ServeRuntimeReceipts`
> atomic writer, and a narrow `SchedulerProgressReporting` protocol that
> schedulers depend on instead of the file. Move `ServeDaemon`'s eight
> `receipts.register(...)` calls onto it, and wire `PendingWakeScheduler` to
> report attempt / success / failure / next wake. Do not modify any other
> scheduler. Do not add a status command or touch any CLI file.

## 4. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeRuntimeReceipts.swift`
  — the full file. `write(...)` is the atomic primitive to keep; `register(...)`
  is the read-modify-write to replace.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift` lines
  120–200 — the eight registration call sites and the task group they sit in.
- `Packages/AllnighterCore/Sources/AllnighterEngine/PendingWakeScheduler.swift`
  — the whole file (116 lines). Note `OvershootBox` (line 38): a
  lock-guarded `final class ... @unchecked Sendable` is this file's existing
  idiom for shared mutable state.

## 5. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeSchedulerProgress.swift          (new)
Packages/AllnighterCore/Sources/AllnighterEngine/ServeRuntimeReceipts.swift
Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift
Packages/AllnighterCore/Sources/AllnighterEngine/PendingWakeScheduler.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeSchedulerProgressTests.swift  (new)
Packages/AllnighterCore/Tests/AllnighterEngineTests/PendingWakeSchedulerTests.swift
```

## 6. Do not read / do not touch

- Do **not** modify `BoostSeedScheduler`, `CapacityRefreshScheduler`,
  `ProbeRecordRefreshScheduler`, `NotificationScheduler`, `PMTurnWakeScheduler`,
  `VendorBackoffReconciler`, or the cloud relay coordinator. They keep
  registering and stay at `registered`. That is correct for this slice.
- Do **not** touch `CoordinatorHealth`, `ServeDaemonProbe`, `ServeLifecycle`,
  `ServeHealthClient`, any file under `Sources/AllnighterCLI`, any script, or
  `Apps/`. The status contract is S03f.
- Do not add log rotation, and do not add a `runtime.json` schema version bump
  unless the row shape actually changes — it should not; `SchedulerRow` already
  carries all four progress fields.

## 7. Steps

1. **`SchedulerProgressReporting`** — a `Sendable` protocol with the smallest
   verb set that covers §6: `registered(id:)`, `attempting(id:)`,
   `succeeded(id:)`, `failed(id:error:)`, `waiting(id:until:)`. Timestamps come
   from an injected clock, not `Date()` at the call site. Ship a no-op
   conforming type so every existing scheduler construction site and test
   compiles unchanged and writes nothing.

2. **`ServeSchedulerProgress`** — conforms to the protocol. Holds daemon
   identity (`daemonId`, `pid`, `startedAt`) and the row set in memory, guarded
   by one lock. Every mutation updates memory, then persists the **whole** row
   set through `ServeRuntimeReceipts.write(...)`. It is the only writer.

3. **Delete `ServeRuntimeReceipts.register`.** Its read-modify-write is the bug
   in §2; leaving it available invites a second writer. Move its callers to the
   recorder. `read` and `write` stay as they are.

4. **State transitions must be honest.** `attempting` records `lastAttemptAt`
   and leaves `lastSuccessAt` alone. `succeeded` records `lastSuccessAt` and
   **clears** `lastError` — a scheduler that recovered is not still failed.
   `failed` records `lastError` and leaves `lastSuccessAt` alone, so status can
   show "last worked 09:14, failing since 11:02". `waiting` records
   `nextWakeAt`. Never infer one field from another.

5. **`lastError` is bounded and non-leaking.** Truncate to 200 characters. It
   carries the failure's own description only — never a prompt, source excerpt,
   vendor stdout, credential, or environment dump (§6 log rule). If a caller can
   only supply a raw vendor string, the caller is wrong; take a `String` that the
   scheduler composes from its own control-flow, not from worker output.

6. **`ServeDaemon` registers through the recorder.** Construct one
   `ServeSchedulerProgress` in `run(...)` after the daemon record is saved, and
   replace all eight `_ = receipts.register(...)` calls with it. Keep the
   existing rule from S03e: a row appears only when that scheduler is actually
   started. `ServeDaemon` keeps injecting a receipts store so tests can redirect
   `$HOME`.

7. **Wire `PendingWakeScheduler` only.** It takes a
   `SchedulerProgressReporting` (defaulting to the no-op) and reports around its
   existing loop: `attempting` when it begins a wake pass, `succeeded` when the
   pass completes, `failed` on the `catch` at line 84, and `waiting(until:)` with
   the deadline it is about to sleep to — the same `nextWake` it already
   computes at line 83. Do not restructure the loop, do not change its sleep
   arithmetic, and do not change `DefaultPendingWakeSleeper` — ASR-S03c made it
   wake-safe and that behavior is settled.

8. **Failure to persist never breaks a scheduler.** If a write fails, the
   scheduler keeps scheduling. A recording error is not a scheduling error.
   Prove it with a test whose writer always fails.

## 8. Works Test

```bash
scripts/swift-test.sh --filter 'ServeSchedulerProgressTests|ServeRuntimeReceiptsTests|PendingWakeSchedulerTests|ServeDaemon'
```

## 9. Done when

- [ ] Concurrency kill test: N reporters mutating **different** ids
      concurrently, and the final file contains every id. This must fail against
      the old `register` read-modify-write — write it first and watch it fail.
- [ ] `succeeded` after `failed` clears `lastError` and keeps `lastAttemptAt`;
      `failed` after `succeeded` keeps `lastSuccessAt`. Asserted, both ways.
- [ ] `lastError` is truncated at 200 characters.
- [ ] A failing writer leaves `PendingWakeScheduler` still looping and still
      sleeping to the same deadline.
- [ ] `PendingWakeScheduler`'s row reaches `waiting` with a `nextWakeAt` equal to
      the deadline it actually sleeps to — not a recomputed one.
- [ ] `ServeRuntimeReceipts.register` no longer exists and nothing calls it.
- [ ] The six unwired schedulers still register, still read `registered`, and
      none of their files changed.
- [ ] No test writes outside a temp directory. One commit, explicit paths.

## 10. Host-state invariant

Additive. `runtime.json` gains movement in one row; nothing reads it yet
(`ServeStatusJSON` v2 is S03f), so no command's output changes. The supervised
agent, plist, canonical binary, and every scheduler's timing are untouched. If
this slice were reverted, the receipt returns to eight static `registered` rows —
exactly today's state.

## 11. Closeout — 2026-08-11

Landed `69a52bbd`. Independently re-verified by the PM outside the seat's own
report: 35 tests pass under the §8 filter.

**The kill test can fail.** §9 asked for failing-first proof, which the seat
could not literally give because it deleted `register` in the same commit. So
the negative proof was taken the other way: removing the `NSLock` from
`ServeSchedulerProgress.mutate` makes
`testConcurrentRegisterOfDifferentIdsKeepsEveryId` terminate with an uncaught
NSException rather than pass. The lock was restored; the tree is clean. A gate
that has been made to fail on demand counts as the §7 negative proof.

Carried forward, not blocking: `succeeded` leaves the row in `running`, so a
scheduler that succeeds and never wakes again reads `running` indefinitely.
`lastSuccessAt` still tells the truth, and S03f decides how status renders it.
