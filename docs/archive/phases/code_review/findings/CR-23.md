# CR-23 — Review PendingRunExecutor queue drain

## Summary
`PendingRunExecutor` settles one Pending item (workerChat or non-mutating
teamRun) through `WorkerRunner` / `CatalogRunCoordinator`. The dispatch shape is
sound — `beginRun` → kind switch → settle — and the teamRun path correctly
checks `team.mutating`, `resolved.isRunnable`, and the source gate before
dispatch. Four real issues surface under the requested lenses: the mutation
guard checks the preset flag but stamps the run with the resolver's flag
(possible bypass), a transcript-write throw after a completed worker run leaves
the item stuck in "running", there is no per-id double-dispatch guard, and the
workerChat path does not filter disabled models (unlike teamRun). Several lower-
severity provenance and durability gaps follow.

## Findings

### P1 — Mutation guard checks `team.mutating` but stamps `resolved.mutating`
- **Invariant:** Mutating/execution teams must be deferred from this executor
  (one worker under the per-root write lock). The executor is the dispatch gate
  and must not emit a run stamped `mutating == true`.
- **Evidence:** The guard throws `mutationDeferred` only on `team.mutating`
  (`PendingRunExecutor.swift:99-101`). Resolution happens after
  (`PendingRunExecutor.swift:104-109`), and the run is stamped
  `copy.mutating = resolved.mutating` (`PendingRunExecutor.swift:131`). If
  `TeamResolver.resolve` can produce `resolved.mutating == true` from a preset
  where `team.mutating == false` (e.g. lane/effort-driven mutation), the guard
  passes, the source gate evaluates a mutating run, and a mutating run is
  dispatched and persisted. The check and the stamp read different fields.
- **Suggested fix:** After `resolved` is computed, re-check
  `resolved.mutating` and throw `mutationDeferred` there; or move the mutation
  guard to after resolution and gate on `resolved.mutating`. Keep the source-gate
  call (`PendingRunExecutor.swift:113-115`) after the resolved-mutation check.
- **Suggested slice:** `pending-executor: gate mutation on resolved.mutating`

### P1 — `writeTranscript` throw after a completed worker run leaves the item unsettled
- **Invariant:** A worker run that produced an `outcome` must be settled (success
  or failure) so the Pending item does not stick in "running".
- **Evidence:** `runWorkerChat` invokes the worker
  (`PendingRunExecutor.swift:69-74`), then `let transcriptRef = try
  writeTranscript(...)` (`PendingRunExecutor.swift:76`). `writeTranscript` uses
  real `try` for directory creation and file write
  (`PendingRunExecutor.swift:177-178`). If either throws, `settleRun`
  (`PendingRunExecutor.swift:77-83`) is never reached. The worker already ran;
  the outcome is discarded and the item remains "running" until a retry re-runs
  the worker. The teamRun path does not have this hole — `teamTranscriptRef`
  uses `try?` (`PendingRunExecutor.swift:191-192`).
- **Suggested fix:** Settle first, then write the transcript (settle can take a
  nil `transcriptRef`); or mirror `teamTranscriptRef` and use `try?` for the
  write, passing `nil` on failure. Do not let a receipt-write failure un-settle
  completed work.
- **Suggested slice:** `pending-executor: settle before transcript write`

### P1 — No per-id double-dispatch guard in `run(id:)`
- **Invariant:** One Pending id → at most one in-flight execution. The queue
  drainer and a manual retry must not race into two worker invocations.
- **Evidence:** `run(id:options:)` (`PendingRunExecutor.swift:42`) calls
  `service.beginRun` (`PendingRunExecutor.swift:43`) then dispatches work with
  no per-id lock. Two concurrent calls for the same id each `beginRun` a new
  attempt and each invoke the worker (`PendingRunExecutor.swift:69-74`) or the
  coordinator (`PendingRunExecutor.swift:137-146`). The executor is a `struct`
  with no in-flight tracking; nothing here prevents the second dispatch.
- **Suggested fix:** Add a per-id in-flight guard (actor or lock set keyed by
  id) around `run`, or require `beginRun` to reject an already-running item by
  returning a thrown error that the executor propagates. The guard belongs at
  the executor boundary since `PendingService` may be called from multiple
  callers.
- **Suggested slice:** `pending-executor: per-id in-flight guard`

### P1 — `runWorkerChat` does not filter disabled models
- **Invariant:** Disabled workers must not be dispatched (parity with the
  teamRun path, which filters `\.enabled`).
- **Evidence:** `runWorkerChat` resolves `model` from `service.models`
  (`PendingRunExecutor.swift:61-63`) with no `model.enabled` check. The teamRun
  path filters `readyModels = service.models.filter(\.enabled)`
  (`PendingRunExecutor.swift:103`). A disabled model selected as a preferred
  worker id will still be invoked.
- **Suggested fix:** Resolve from `service.models.filter(\.enabled)`, or add
  `guard model.enabled else { throw ... }` after the model lookup.
- **Suggested slice:** `pending-executor: honor enabled in workerChat`

### P2 — `persist` closure swallows `runStore.save` errors
- **Invariant:** A settled team run should be durably persisted; a save failure
  should be observable, not silent.
- **Evidence:** `let persist: @Sendable (TeamRun) -> Void = { try?
  runStore.save(stamped($0), models: readyModels) }`
  (`PendingRunExecutor.swift:136`). A save failure is discarded; the run is then
  settled (`PendingRunExecutor.swift:147-152`) as if persisted. The run record
  can be lost from the store while the Pending item records success.
- **Suggested fix:** Log the save error, or accumulate it into the run's
  `warnings` / a settle-side field. At minimum do not silently drop.
- **Suggested slice:** `pending-executor: surface runStore.save failures`

### P2 — Origin provenance collapsed for iOS / system / preset
- **Invariant:** The settled run's `origin` should reflect where the work was
  requested from.
- **Evidence:** `PendingOriginMapper.runOrigin` maps `.ios`, `.localApi`,
  `.system`, and `.preset` all to `.cli` (`PendingRunExecutor.swift:199-205`).
  `origin` is computed from this mapper (`PendingRunExecutor.swift:122`) and
  passed to the coordinator. An iOS-originated pending run is recorded as CLI.
- **Suggested fix:** Extend `RunOrigin` to carry the iOS/system cases, or retain
  the pending origin on the settled run separately. If the collapse is
  intentional (iOS runs execute on the Mac, so origin is effectively CLI),
  document it on the mapper.
- **Suggested slice:** `pending-executor: preserve ios/system origin`

### P2 — Stale attempt accumulation on crash between `beginRun` and `settle`
- **Invariant:** A crash mid-run must not leave an attempt permanently
  "running" with no reconciliation.
- **Evidence:** `beginRun` (`PendingRunExecutor.swift:43`) creates a new
  attempt; there is no step that expires or reclaims a prior in-flight attempt
  left "running" by a crash. On restart the drainer begins a fresh attempt
  (`PendingRunExecutor.swift:43-45`) while the old one stays running forever,
  so stale attempts accumulate.
- **Suggested fix:** `beginRun` should mark prior running attempts as
  abandoned/failed, or a reconcile pass on drain should close them. Alternatively
  stamp a heartbeat/lease on the attempt and expire it.
- **Suggested slice:** `pending-service: reconcile stale running attempts`

### P2 — `attemptIndex` assumes `beginRun` appends an attempt
- **Invariant:** Indexing into `item.attempts` must not trap.
- **Evidence:** `let attemptIndex = item.attempts.count - 1`
  (`PendingRunExecutor.swift:44`) then `item.attempts[attemptIndex].attemptId`
  (`PendingRunExecutor.swift:45`). If `beginRun` ever returns an item with empty
  `attempts` (e.g. a no-op begin path), `attemptIndex` is -1 and the subscript
  traps. The executor does not precondition `!item.attempts.isEmpty`.
- **Suggested fix:** `guard !item.attempts.isEmpty else { throw
  PendingServiceError.invalidState("beginRun produced no attempt") }` before
  computing `attemptIndex`.
- **Suggested slice:** `pending-executor: guard beginRun attempt`

## False alarms ruled out
- **`stamped` captures `item.threadId`** (`PendingRunExecutor.swift:133`):
  `PendingItem` is a value type; the `@Sendable` closure captures a copy. Safe.
- **`teamTranscriptRef` summary mixes `String` and `String?` in the array
  literal** (`PendingRunExecutor.swift:183-187`): Swift promotes the element
  type to `String?`, so `.compactMap { $0?.trimmingCharacters(...) }` type-checks
  and behaves as intended. Not a bug.
- **`runId` UUID fallback** (`PendingRunExecutor.swift:143`): `item.runId ??
  "run_\(UUID...)"` produces a stable id for the coordinator call. Fine.
- **`writeTranscript` writes an empty file for `.done` with empty output**
  (`PendingRunExecutor.swift:160-161`): `outcome.output == ""` yields `text == ""`
  which passes `guard let text` and writes an empty receipt. Cosmetic, not a
  correctness issue.
- **`stamped` overwrites coordinator-set fields** (`PendingRunExecutor.swift:124-134`):
  `resolved` was computed from `team.lane` / `team.defaultEffort`
  (`PendingRunExecutor.swift:106-108`), so re-stamping lane/effort is idempotent.
  The remaining fields come from `resolved`, which is the intended source of
  truth. Not a bug (modulo the `mutating` field, which is P1 above).
- **`originAgent: nil`** (`PendingRunExecutor.swift:142`): the executor has no
  agent context to pass; nil is the correct value here.

## Greps avoided
Confirmed: no repo exploration performed. All evidence is from the inlined
`PendingRunExecutor.swift` source and the resolved-symbols list. No `grep`,
`glob`, `read`, or `task` calls were issued against the repository. The only
filesystem touch was creating this findings file.