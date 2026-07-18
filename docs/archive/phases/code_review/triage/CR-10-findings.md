# CR-10 — Streaming write path coalescing

## Summary
`StreamingPartialBuffer` is a clean, pure-value accumulator with correct
truncation semantics (newest suffix kept, `isTruncated` latched) and a sound
byte-cadence flush signal. The write serializer correctly releases its registry
lock before entering `DispatchQueue.sync`, avoiding a lock-then-queue deadlock.
Two real wins remain. First, `newestSuffix` drops one `Character` at a time and
recomputes `out.utf8.count` (O(n)) on every iteration — once the 64 KB cap is
hit, every `append` pays O(drops × 64 KB), which for a 2 KB ASCII delta is
~128 M byte-counting operations per append on the streaming hot path. Second,
`ThreadStoreWriteSerializer.synchronized` offers no reentrancy guard: a nested
call for the same root deadlocks on `DispatchQueue.sync` with no diagnostic.
Several P2 nits round out the review: a redundant `utf8.count` in the
`newestSuffix` guard, a lane registry that never evicts, symlink-aliased roots
getting separate lanes, no cross-root lock ordering, full-text flush I/O
amplification, and no cancel/reset API on the buffer.

## Findings

### P0 — None
No invariant or security violations found in the inlined sources. Truncation
preserves the newest suffix on a `Character` boundary (`StreamingPartialBuffer.swift:49-56`),
the flush counter tracks incoming delta bytes correctly
(`StreamingPartialBuffer.swift:40-41`), and the serializer releases its
registry lock before entering the queue (`ThreadStoreWriteSerializer.swift:25-26`).

### P1 — `newestSuffix` is O(drops × n) on the streaming hot path
- **Invariant:** the truncation path must be cheap enough to run on every
  `append` once the visible cap is exceeded, because streaming continues past
  64 KB and every subsequent delta triggers re-truncation.
- **Evidence:** `append` calls `Self.newestSuffix(of: text, maxBytes: capBytes)`
  whenever `text.utf8.count > capBytes` (`StreamingPartialBuffer.swift:37-38`).
  Once the cap is first exceeded, `truncated` is latched (`:39`) but the cap
  check fires on every subsequent `append` — the buffer never stops
  re-truncating. Inside `newestSuffix` (`:49-56`), the while loop
  (`:52-54`) drops one `Character` at a time via `out = out.dropFirst()` and
  re-evaluates `out.utf8.count > maxBytes` each iteration. `Substring.utf8.count`
  is O(remaining bytes) — it walks the UTF-8 view to count. The number of
  iterations is approximately `(currentBytes - capBytes) / avgCharBytes`, which
  for a 2 KB ASCII delta is ~2048 iterations, each scanning ~64 KB: ~128 M
  byte-touches per append. For a large delta (e.g. 100 KB), the loop runs
  ~36 K iterations × 64 KB ≈ 2.3 B operations — multiple seconds. This is the
  dominant cost of the streaming write path once the cap is reached.
- **Suggested fix:** compute the byte cut offset directly in one pass. Get the
  total UTF-8 count once (`s.utf8.count`), compute `drop = total - maxBytes`,
  then advance a `String.UTF8View.Index` by `drop` bytes
  (`s.utf8.index(s.utf8.startIndex, offsetBy: drop)`), round outward to the
  next `Character` boundary (`s.index(after: charIndex)` or use
  `s.range(of:offsetBy:)`), and return the suffix `String(s[charBoundary...])`.
  This makes `newestSuffix` O(n) instead of O(drops × n). Alternatively, keep
  a `String.Index` cursor into the retained suffix and advance it by the delta
  size, avoiding a full re-scan on every append.
- **Suggested slice:** "StreamingPartialBuffer: O(n) newestSuffix via byte-offset cut"

### P1 — Re-entrant `DispatchQueue.sync` deadlocks on same root
- **Invariant:** `synchronized` must not deadlock when the body legitimately
  calls back into `synchronized` for the same `rootDirectory` — e.g. a
  `ThreadStore.updateTurn` write that triggers a nested metadata or index
  update on the same store.
- **Evidence:** `Registry.synchronized` looks up the `Lane` for the root
  (`ThreadStoreWriteSerializer.swift:14-24`), then calls
  `lane.queue.sync(execute: body)` (`:26`). `DispatchQueue.sync` is documented
  to deadlock when called from the same queue that is currently executing the
  work item. There is no reentrancy detection (no `dispatch_get_specific` key
  check, no `OS_ALLOCATOR_KEY` on the queue, no recursive lock). If `body`
  calls `ThreadStoreWriteSerializer.synchronized(rootDirectory: ...)` for the
  same root — which the static method at `:32-34` routes back to the same
  `Registry` and thus the same `Lane` — the inner `queue.sync` blocks forever
  waiting for the outer work item to drain, which cannot complete because it
  is waiting on the inner call. The deadlock is silent (no crash, no log) and
  hangs the calling thread.
- **Suggested fix:** either (a) replace `DispatchQueue.sync` with an
  `NSRecursiveLock` per `Lane` (reentrant by design, same mutual exclusion),
  or (b) stamp the queue with a `dispatch_queue_specific` key and check
  `dispatch_get_specific` before `sync` — if already on the queue, execute
  `body` directly (reentrant fast path). Option (a) is simpler and removes the
  `@unchecked Sendable` on `Lane` if the lock is stored directly. Document the
  reentrancy contract either way.
- **Suggested slice:** "ThreadStoreWriteSerializer: recursive lock for reentrant writes"

### P2 — Redundant `utf8.count` in `newestSuffix` guard
- **Invariant (clarity):** the byte count already computed by the caller should
  not be recomputed in the callee on the hot path.
- **Evidence:** `append` checks `text.utf8.count > capBytes`
  (`StreamingPartialBuffer.swift:37`) — an O(n) scan — then calls
  `newestSuffix(of: text, maxBytes: capBytes)` (`:38`). `newestSuffix`'s guard
  recomputes `s.utf8.count > maxBytes` (`:50`) on the same string, a second
  O(n) scan of the same 64 KB+ data. Two full byte-counts per truncating
  append.
- **Suggested fix:** drop the guard in `newestSuffix` (the only caller already
  proved the string exceeds the cap), or pass the known count as a parameter
  and skip the re-scan.
- **Suggested slice:** (nit, fold into the P1 `newestSuffix` slice)

### P2 — Lane registry never evicts
- **Invariant (resource):** a long-running app (Allnighter is an overnight
  agent factory) should not accumulate one `DispatchQueue` per unique root
  path for the entire process lifetime.
- **Evidence:** `Registry.synchronized` creates a `Lane` and stores it in
  `lanes[key]` (`ThreadStoreWriteSerializer.swift:21-24`) but no code ever
  removes entries. The dictionary grows monotonically: every distinct
  `rootDirectory.standardizedFileURL.path` (`:15`) adds a permanent `Lane`
  (holding a `DispatchQueue`). For a user who opens many repos over a
  multi-day session, this is a slow leak.
- **Suggested fix:** add an eviction hook called when a `ThreadStore` is
  closed (e.g. `static func releaseLane(rootDirectory:)`), or use
  `NSMapTable`-style weak references. At minimum, document that lanes are
  process-lifetime.
- **Suggested slice:** (nit, optional)

### P2 — Symlink-aliased roots get separate lanes
- **Invariant:** all paths resolving to the same physical directory must share
  one write lane — otherwise two writers through different path spellings bypass
  the mutual exclusion the serializer is meant to provide.
- **Evidence:** the lane key is `rootDirectory.standardizedFileURL.path`
  (`ThreadStoreWriteSerializer.swift:15`). `standardizedFileURL` resolves `.`/
  `..` and trailing slashes but does **not** resolve symlinks. If root A is
  `/Users/x/proj` and root B is a symlink `/Users/x/link-to-proj` pointing at
  the same directory, they get different keys, different `Lane`s, and different
  `DispatchQueue`s — concurrent writes through both paths are not serialized.
- **Suggested fix:** use `rootDirectory.resolvingSymlinksInPath().path` as the
  key (or `standardizedFileURL.resolvingSymlinksInPath()`). Note that
  `resolvingSymlinksInPath` does a filesystem stat, so cache the resolved key
  on the `ThreadStore` rather than resolving on every `synchronized` call.
- **Suggested slice:** (nit, optional)

### P2 — No cross-root lock ordering; nested writes risk AB-BA deadlock
- **Invariant:** if `synchronized` is ever nested across two different roots,
  the acquisition order must be deterministic to prevent classic AB-BA
  deadlock.
- **Evidence:** `synchronized` (`ThreadStoreWriteSerializer.swift:14, 32`)
  acquires one root's queue, then the body may acquire another root's queue.
  If thread A does `synchronized(root1) { synchronized(root2) { ... } }` while
  thread B does `synchronized(root2) { synchronized(root1) { ... } }`, both
  block forever. The serializer enforces no global ordering (e.g. by sorted
  path) and documents no contract against nesting.
- **Suggested fix:** either document "no nested `synchronized` across roots" as
  a hard contract, or if nesting is needed, acquire lanes in sorted-path order
  when multiple roots are needed in one critical section.
- **Suggested slice:** (nit, optional — depends on whether cross-root nesting
  is a real call pattern)

### P2 — Full-text flush is O(n²) I/O amplification
- **Invariant (perf):** the flush cadence (2 KB / 120–250 ms) should not cause
  quadratic total I/O as the stream grows.
- **Evidence:** `visibleText` (`StreamingPartialBuffer.swift:28`) returns the
  full accumulated text (up to 64 KB). The doc comment on `markFlushed`
  (`:45`) says "Call after writing the current `visibleText`," implying each
  flush writes the entire visible text to the store. With `flushByteThreshold
  = 2 * 1024` (`:14`), streaming 1 MB produces ~512 byte-triggered flushes,
  each writing up to 64 KB: ~32 MB of store writes for 1 MB of streamed data.
  The buffer itself is correct — it provides the text — but the contract
  encourages the caller to re-write the full text on every flush rather than
  appending a delta.
- **Suggested fix:** this depends on the `ThreadStore.updateTurn` implementation
  (not inlined). If the store supports append-style writes or a "dirty range,"
  the buffer could expose the delta since last flush. If the store only
  supports full-text replacement, consider raising the flush cadence (e.g. 8 KB
  / 500 ms) once the cap is reached, since the visible text is already
  truncated and the user is seeing a rolling suffix.
- **Suggested slice:** (nit, depends on store contract — not actionable from
  inlined sources alone)

### P2 — No cancel/reset API on the buffer
- **Invariant (lifecycle):** when a run is cancelled, the partial buffer
  should be invalidated so a stale partial is not flushed by the timer after
  cancellation.
- **Evidence:** `StreamingPartialBuffer` has `append` (`:34`), `markFlushed`
  (`:46`), and `visibleText`/`isTruncated` (`:28-29`) but no `cancel()`,
  `reset()`, or `invalidate()`. The wiring layer owns the timer (per the doc
  comment at `:5-6`), so after cancellation the timer may fire one more time,
  read `visibleText`, and write a stale partial to the store. The buffer
  cannot self-invalidate. This is a design choice (the buffer is pure and
  synchronous), but it places the entire cancellation burden on the wiring
  layer with no help from the buffer.
- **Suggested fix:** add a `mutating func invalidate()` that sets a flag the
  caller can check before flushing, or document that the wiring layer must
  cancel the timer before discarding the buffer. Low priority if the wiring
  layer already handles this correctly (not visible from inlined sources).
- **Suggested slice:** (nit, optional)

## False alarms ruled out
- **`unflushedBytes` counts delta bytes after truncation.** `append` adds
  `delta.utf8.count` to `unflushedBytes` (`StreamingPartialBuffer.swift:40`)
  even after truncation (`:37-39`). This is correct: `unflushedBytes` measures
  incoming data rate for flush cadence, not buffer contents. Truncation
  changes what is visible but not how much data has arrived since the last
  flush. Not a finding.
- **`truncated` is never reset.** Once `truncated = true` (`:39`), it stays
  true. Settlement replaces the partial with the complete answer (per the doc
  comment at `:7-8`), which the wiring layer handles by creating a new buffer
  or replacing the text. The latch is correct for the buffer's lifetime. Not
  a finding.
- **`markFlushed` does not clear `text`.** After a flush, the visible partial
  should still show the accumulated text (up to the cap). Clearing `text` would
  lose the visible partial. `markFlushed` only resets `unflushedBytes` (`:46`),
  which is correct. Not a finding.
- **`append` returns `false` for empty delta.** `guard !delta.isEmpty else
  { return false }` (`:34`) skips the flush signal when nothing arrived. The
  timer-based flush (owned by the wiring layer) handles idle flushes. Correct
  by design. Not a finding.
- **Thread safety of `StreamingPartialBuffer`.** It is a `Sendable` struct
  with value-type fields (`String`, `Bool`, `Int`). Mutation is the caller's
  responsibility — the doc comment (`:5`) says "the wiring layer owns the
  wall-clock flush timer." No shared mutable state. Not a finding.
- **NSLock released before `DispatchQueue.sync`.** `lock.unlock()` at
  `ThreadStoreWriteSerializer.swift:25` runs before `lane.queue.sync` at `:26`.
  No lock-then-queue deadlock. Correct. (The *re-entrant* `queue.sync` issue
  is real and filed as P1; the lock ordering is sound.)
- **`@unchecked Sendable` on `Lane` and `Registry`.** `Lane` holds a
  `DispatchQueue` (thread-safe). `Registry` protects `lanes` with `NSLock`
  (`:11, 17-25`). Once a `Lane` is stored (`:22`), it is never removed, so
  no use-after-free. The `@unchecked` annotation is justified. Not a finding.
- **`rethrows` through `queue.sync`.** `DispatchQueue.sync(execute:)` has a
  `rethrows` overload; if `body` throws, the error propagates through
  `Registry.synchronized` (`:14`, `rethrows`) and the static `synchronized`
  (`:32`, `rethrows`). The queue is left in a consistent state (`sync` is
  exception-safe). Correct. Not a finding.
- **`text += delta` is O(n) per append.** Swift `String` uses copy-on-write;
  since `text` is a unique reference (local `var` in the struct), `+=` can
  mutate in place with amortized O(delta) growth. The reallocation cost is
  secondary to the `newestSuffix` cost (P1) and is not separately filed.

## Greps avoided
- Did not read or grep any file outside the two inlined sources
  (`StreamingPartialBuffer.swift`, `ThreadStoreWriteSerializer.swift`).
  `ThreadStore.updateTurn`, the wiring-layer flush timer, and the store's
  write implementation were treated as opaque per the review instructions; the
  full-text-flush I/O finding (P2) is explicitly hedged on that unknown. No
  repo exploration was performed. All line numbers are derived from the inlined
  source and the resolved-symbol anchor (`newestSuffix` at
  `StreamingPartialBuffer.swift:49`).