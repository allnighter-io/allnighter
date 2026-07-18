# CR-29 — RemoteSnapshotPublisher consistency

## Summary
`RemoteSnapshotPublisher` is a thin `Sendable` struct that snapshots local run
state via `RemoteSnapshotService.snapshot(since:)` and forwards it to
`RemoteMacRelay.publishSnapshot`. The code is small and readable, and its
`Sendable`/all-`let` shape is correct. The consistency risks live in the seams
the file does not own: there is no guard against concurrent or out-of-order
`publish` calls, the synchronous `snapshot` step runs on the cooperative thread
pool, a failed `relay.publishSnapshot` leaves the caller unable to tell whether
the relay applied part of the snapshot, and the publisher trusts
`snapshot.lastSeq` without validating monotonicity against `since`. None of
these are proven invariants broken in this file alone — all depend on the
relay/service contracts that are out of scope here — but each is a real hazard
for the iOS mirror's staleness and ordering guarantees.

## Findings

### P1 — Concurrent / out-of-order `publish` is not guarded
- **Invariant:** A mirror's published cursor must advance monotonically; a stale
  snapshot must never overwrite a fresher one on the relay.
- **Evidence:** `RemoteSnapshotPublisher.swift:31` — `publish(since:)` is a plain
  `async` method on a `Sendable` struct with no actor, lock, or sequence guard.
  Because the struct is `Sendable` and all properties are `let`, the same
  publisher can be shared across tasks and called concurrently. Two calls can
  interleave: e.g. `publish(since: nil)` (full snapshot, `lastSeq = N`) and
  `publish(since: N)` (incremental, `lastSeq = N+15`) can both be in flight; if
  the full-snapshot publish completes after the incremental one, the relay
  receives an older view second. Safety here depends entirely on the relay
  rejecting/regating by `lastSeq`, which this file neither enforces nor asserts.
- **Suggested fix:** Serialize publishes through an `actor` wrapper or a single
  in-flight `Task` owned by the caller, and require the relay to reject snapshots
  whose `lastSeq` is older than the last applied. At minimum, document the
  single-writer assumption on `publish`.
- **Suggested slice:** `remote-snapshot-publish-serialization`

### P1 — Synchronous `service.snapshot` runs on the cooperative thread pool
- **Invariant:** `async` functions must not block the cooperative thread pool on
  long I/O.
- **Evidence:** `RemoteSnapshotPublisher.swift:32` —
  `let snapshot = try service.snapshot(since: since)` is synchronous (no `await`).
  `RemoteSnapshotService.snapshot` is not shown, but snapshotting run state
  plausibly reads disk/DB. Called from an `async` context, it executes on the
  cooperative pool and can stall unrelated tasks. The `try` propagates throws
  correctly, but the blocking concern is unaddressed.
- **Suggested fix:** Make `RemoteSnapshotService.snapshot(since:)` `async`
  (preferred), or offload the sync call with `await Task.detached { … }.value`
  if the service cannot be made async.
- **Suggested slice:** `remote-snapshot-service-async-snapshot`

### P1 — Partial-publish opacity on relay failure
- **Invariant:** A failed publish must not leave the mirror in a partially-applied
  state that the caller cannot distinguish from "nothing applied."
- **Evidence:** `RemoteSnapshotPublisher.swift:33-37` —
  `try await relay.publishSnapshot(...)` is all-or-nothing from this function's
  view: on throw, no `RemoteSnapshotPublishResult` is returned, so the caller
  knows it failed but not *how far*. If the relay applies part of the snapshot
  before failing (network mid-stream, partial write), the caller will retry with
  the same `since`. Retry safety is therefore entirely a property of the relay's
  idempotency, which is not visible or asserted here.
- **Suggested fix:** Define and document the relay's apply atomicity
  (replace-whole vs. merge). If replace-whole, a retry is safe and this is fine.
  If merge/append, the publisher needs a relay-level dedup key (e.g.,
  `macAgentId` + `lastSeq`) so a retry cannot double-apply.
- **Suggested slice:** `remote-relay-publish-atomicity-contract`

### P1 — `lastSeq` trusted without monotonicity check against `since`
- **Invariant:** The cursor returned to the caller must not regress below the
  `since` they passed in.
- **Evidence:** `RemoteSnapshotPublisher.swift:39-42` — the result is built
  directly from `snapshot.lastSeq` with no check that
  `snapshot.lastSeq >= (since ?? 0)`. If `RemoteSnapshotService` returns an empty
  incremental snapshot with a sentinel `lastSeq` (e.g., `0` or `-1`) when there
  are no new runs, the caller storing `result.lastSeq` as the next cursor would
  re-publish from the beginning on the next call — a silent full re-publish and a
  staleness regression. The publisher is the natural place to assert this because
  it is the only layer that sees both `since` and the returned `lastSeq`.
- **Suggested fix:** Assert/`precondition` that `snapshot.lastSeq >= (since ?? 0)`
  before returning, or clamp the returned `lastSeq` to `max(snapshot.lastSeq,
  since ?? 0)`. Better: fix the service contract so an empty incremental snapshot
  returns `lastSeq == since`.
- **Suggested slice:** `remote-snapshot-lastseq-monotonicity`

### P2 — Empty snapshot still triggers a relay round-trip
- **Invariant:** (efficiency) Don't do network work when there is nothing to say.
- **Evidence:** `RemoteSnapshotPublisher.swift:32-37` — when
  `snapshot.runs.isEmpty`, the code still calls `relay.publishSnapshot`. If the
  relay treats an empty snapshot as a no-op this is wasted bandwidth; if it treats
  it as a heartbeat, this is intentional. The intent is not visible here.
- **Suggested fix:** If empty snapshots are not heartbeats, short-circuit:
  `if snapshot.runs.isEmpty { return .init(runCount: 0, lastSeq: snapshot.lastSeq) }`
  before the relay call. If they *are* heartbeats, add a comment saying so.

### P2 — `since` defaults to `nil` (full snapshot) — easy footgun
- **Invariant:** (usability) The common case should be the cheap case.
- **Evidence:** `RemoteSnapshotPublisher.swift:31` —
  `publish(since: Int64? = nil)`. A caller who forgets the cursor gets a full
  snapshot every cycle, which is the most expensive path and the most likely to
  overwrite the mirror with a stale full view if ordering is loose (see P1
  above). Defaulting to "full" rewards forgetfulness with the worst case.
- **Suggested fix:** Either remove the default (force callers to choose
  explicitly) or default to an incremental cursor sourced from the last
  successful publish.

### P2 — `runCount` semantics differ for full vs. incremental snapshots
- **Invariant:** (clarity) A result field's meaning should not depend on the
  request mode.
- **Evidence:** `RemoteSnapshotPublishResult.swift:3-4` and
  `RemoteSnapshotPublisher.swift:40` — `runCount = snapshot.runs.count`. For an
  incremental snapshot this is "runs published this round"; for a full snapshot
  (`since == nil`) it is "total runs in the mirror." Same field, two meanings.
  Callers comparing across modes will misread it.
- **Suggested fix:** Rename to `runsPublished` and document that for full
  snapshots it equals the total, or split into `runsPublished` / `totalRuns`.

## False alarms ruled out
- **`Sendable` conformance is not a finding.** `RemoteSnapshotPublisher` is a
  `struct` with all-`let` stored properties; declaring `Sendable` is correct and
  the compiler will enforce that `RemoteSnapshotService` and `RemoteMacRelay` are
  also `Sendable`. No issue.
- **`Equatable` on `RemoteSnapshotPublishResult`** is fine and useful for tests;
  not a finding.
- **`accountId` / `macAgentId` as `String`** — a stronger ID type would be nicer
  but is a design nit, not a consistency bug. Not ranked.
- **No retry inside `publish`** — retry policy belongs to the caller (backoff,
  jitter, partial-publish handling), not this thin struct. Not a finding.
- **Staleness window between snapshot and publish completion** — by the time
  `relay.publishSnapshot` returns, local state may have advanced past
  `snapshot.lastSeq`. This is inherent to snapshot publishing; the next
  `publish(since: result.lastSeq)` picks up the delta, so there is no data loss,
  only a bounded staleness equal to the round-trip time. Not a finding.

## Greps avoided
Confirmed: no repo exploration performed. Analysis used only the inlined
`RemoteSnapshotPublisher.swift` source and the resolved `publish` symbol at
RemoteSnapshotPublisher.swift:31. No `grep`, `glob`, or file reads outside the
inlined source were used to produce these findings.