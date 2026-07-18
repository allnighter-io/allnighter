# CR-12 — RunService write-lock acquire/release path (lines 226-292)

## Summary

Read-only advisory review of the write-lock path in `RunService.swift:226-292`,
covering defer release ordering, the bounded wait vs worker timeout, mutating
classification, lock duration, and root normalization race. The top-of-function
`defer { events?.finish() }` and the LIFO defer model are sound. No P0 invariant
violation is provable from the inlined range. Three P1 issues stand out: (1) two
independent fields gate "mutating" behavior (`preset.mutating` vs
`preset.writePolicy == .mutating`), so a divergence lets a mutating run execute
without the write lock; (2) `observeRootState` runs ~45 lines before the lock
acquire, a TOCTOU window; (3) the safety-valve "outlives the worker timeout"
invariant is asserted only in a comment and cannot be verified from the inlined
source. Plus two P2 nits.

## Findings

### P0 — None provable from inlined source

No invariant/security violation is provable from lines 226-292 alone. The
closest candidate — write-lock bypass via `preset.mutating` /
`preset.writePolicy` divergence — is ranked P1 below because divergence is not
provable without the `TeamPreset` definition (not inlined).

### P1 — Dual source of truth for "mutating" can bypass the write lock

- **Invariant:** One writer per repo root (comment, `RunService.swift:289`).
  A run that prepends a mutating starter prompt must hold the write lock.
- **Evidence:** The starter-prompt path gates on `preset.mutating`
  (`RunService.swift:277`), while the lock decision gates on
  `preset.writePolicy == .mutating` (`RunService.swift:287`). These are two
  distinct fields. If a `TeamPreset` is constructed with `mutating == true` but
  `writePolicy != .mutating` (or vice versa), the run prepends a mutating
  starter prompt and executes **without** acquiring the write lock — a silent
  violation of the one-writer invariant. Conversely `writePolicy == .mutating`
  with `mutating == false` takes the lock but skips the starter prompt the team
  expects.
- **Suggested fix:** Collapse to one source of truth. Either derive
  `takesWriteLock` from `preset.mutating` (the same field the starter path
  uses), or add a `TeamPreset` init invariant asserting
  `mutating == (writePolicy == .mutating)`. The init assertion is the lower-
  risk fix because it catches divergence at construction rather than at run
  time.
- **Suggested slice:** "Unify TeamPreset mutating flag and writePolicy"

### P1 — `observeRootState` check is not atomic with lock acquire (TOCTOU)

- **Invariant:** Root availability should still hold when the write lock is
  taken, not just when the run is queued.
- **Evidence:** `guard RootNormalization.observeRootState(key: root) == .available`
  runs at `RunService.swift:241-243`. Between that check and the lock acquire
  (`RunService.swift:285-288`, with the actual acquire below line 292) the
  function executes preset resolution (`:245-256`), auto-substitution including
  `loadDefaultSettings()` and `sourceReadyModelIds()` (`:263-274`), and prompt
  construction (`:276-279`). That is ~45 lines of work — including two
  synchronous settings/model reads — during which the root can become
  unavailable (directory removed, disk unmounted, another coordinator claims
  it). The run then proceeds to acquire the lock on a stale availability read.
- **Suggested fix:** Re-check `observeRootState` immediately before
  `RunWriteLock.acquire` (inside the `if takesWriteLock` block), or fold the
  availability check into the lock-acquire critical section so the check and
  the acquire are atomic with respect to each other.
- **Suggested slice:** "Move root-availability check into lock-acquire critical section"

### P1 — Safety-valve timeout invariant is comment-only, unverifiable

- **Invariant (stated in comment):** The bounded wait timeout must outlive the
  worker's own timeout/watchdog, so a wedged holder is reclaimed by its worker
  timeout before the safety valve refuses.
- **Evidence:** `RunService.swift:291-292` — "The bounded timeout is the
  safety valve: if a wedged holder outlives even its own worker
  timeout/watchdog, we stop queueing forever and refuse." The actual wait
  timeout value and the worker timeout value are both below line 292 (not
  inlined). If the wait timeout is <= the worker timeout, the safety valve
  fires while a legitimate long run still holds the lock — a queued peer is
  refused even though the holder is not actually wedged. The invariant is
  load-bearing for liveness but exists only as prose.
- **Suggested fix:** Add a startup/test-time assertion that
  `lockWaitTimeout > workerTimeout` (plus margin), and surface both values in
  the same place so the relationship is machine-checked, not comment-checked.
- **Suggested slice:** "Add lockWaitTimeout > workerTimeout invariant test"

### P2 — `TeamCatalog.defaultRunTeam()` called twice

- **Invariant:** The default-team identity is stable within one run.
- **Evidence:** `RunService.swift:252` resolves the default team in the preset
  `else` branch; `RunService.swift:264` calls `TeamCatalog.defaultRunTeam()`
  again to test `preset.id == TeamCatalog.defaultRunTeam()?.id`. If
  `defaultRunTeam()` is non-deterministic (config reload between calls, race
  with a settings write), the auto-substitution guard can misfire — either
  skipping auto resolution for the actual default team or applying it to a
  non-default team.
- **Suggested fix:** Capture `TeamCatalog.defaultRunTeam()` once into a local
  before the preset resolution block and reuse it at `:264`.

### P2 — Timing stamps recorded before the availability guard

- **Invariant:** Timing reports should reflect runs that actually proceed past
  validation, or be explicitly documented as best-effort.
- **Evidence:** `timing.stamp(RunTimingKey.runRequested, ...)` and
  `timing.set(RunTimingKey.contextBytes, ...)` run at `RunService.swift:238-239`,
  before the `observeRootState` guard at `:241-243`. On a
  `.repoRootUnavailable` early return the stamps are either lost (if
  `RunTimingReport` is a value type) or leaked to the caller's shared report
  (if a reference type) — either way the failure path has an inconsistent
  timing footprint relative to the other early returns at `:248` and `:253`,
  which stamp nothing.
- **Suggested fix:** Move the two timing calls to after the availability guard,
  or document that pre-guard timing is best-effort and applies to all early
  returns uniformly.

## False alarms ruled out

- **`defer { events?.finish() }` release ordering (`:232`):** The events
  finish is registered as the first defer, so by Swift LIFO semantics it runs
  *last* — after any lock-release defer registered later (below line 292). That
  is the correct order: release the write lock before finishing the event
  stream. On early-return failure paths (`:242`, `:248`, `:253`, `:269`) the
  defer correctly finishes the stream so the caller's continuation is not left
  dangling. No double-finish risk is introduced by this defer alone.
- **Auto-substitution reads settings outside the lock (`:265-267`):**
  `loadDefaultSettings()` and `sourceReadyModelIds()` run before lock acquire
  by design — resolving the worker identity before acquiring the lock
  *minimizes* lock hold time. A settings/model-readiness change between this
  read and worker spawn is a substitution-freshness concern, not a write-lock
  invariant concern, and is out of scope for this review.
- **`request.advisoryReview` overriding `writePolicy == .mutating` (`:287`):**
  This is intentional — an advisory review of a mutating team should not take
  the write lock. The flag is a caller contract; the code correctly respects
  it. (A debug log when the override fires would help observability but is not
  a correctness issue.)
- **`lockKey` computed from normalized root (`:285`):** `lockKey` is derived
  from the same `root` used for `observeRootState`, so the lock and the
  availability check agree on identity. The residual risk is in
  `RunWriteLock.normalize` determinism (symlink resolution), noted under the
  P1 TOCTOU finding, not a separate defect.

## Greps avoided

Confirmed: no repo exploration performed. This review is based solely on the
inlined source `RunService.swift:226-292` provided in the review request. No
grep, glob, or file reads outside the inlined range were used. Findings that
depend on definitions below line 292 or on `TeamPreset` / `RunWriteLock` /
`RootNormalization` internals are explicitly marked as not verifiable from the
inlined source.