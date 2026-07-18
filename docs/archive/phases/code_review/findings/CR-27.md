# CR-27 — Review ThreadStore write serialization

## Summary
`ThreadStoreWriteSerializer` provides a per-root `DispatchQueue.sync` lane keyed
by `rootDirectory.standardizedFileURL.path`, with same-root reentrancy trapping
via `preconditionFailure` (throwing in DEBUG via `synchronizedForTesting`). The
core locking mechanics are sound: the per-`Lane` `DispatchSpecificKey` correctly
distinguishes same-root reentry (trapped) from cross-root nesting (allowed,
deadlock-free), and `Registry.lanes` is properly lock-guarded. Four real
concerns remain. (1) Symlinked / differently-spelled roots bypass the write lock
entirely because `standardizedFileURL` does not resolve symlinks. (2) The lane
registry never evicts, leaking `Lane` + `DispatchQueue` objects across long-lived
processes with many transient roots. (3) Reentrant `synchronized` still kills
the app in production via `preconditionFailure` — the deadlock was traded for a
crash, not a recovery path. (4) Read paths (`get`, `list`, `threadDirectory`)
bypass the serializer, which is only safe if `persistContent` writes atomically —
unverifiable from the inlined source.

## Findings

### P0 — None
No invariant/security violation definitively established from the inlined
sources. The closest candidate (symlink roots defeating the per-root write lock,
below) is ranked P1 because it requires a non-canonical path-spelling input to
trigger; it would escalate to P0 if app code ever constructs
`ThreadStore(rootDirectory:)` from non-canonicalized user input.

### P1 — Symlinked / non-canonical roots bypass the write lock
- **Invariant:** Per-root write lock must hold for "the same canonical
  `rootDirectory`" (doc comment, `ThreadStoreWriteSerializer.swift:3-4`) and the
  project law "one worker (mutating) under the per-root write lock" (AGENTS.md).
- **Evidence:** `ThreadStoreWriteSerializer.swift:49` —
  `let key = rootDirectory.standardizedFileURL.path`. `standardizedFileURL`
  resolves `.`/`..`/trailing slashes but **does not** resolve symlinks
  (`URL.resolvingSymlinksInPath()` is the only URL API that does). Two
  `ThreadStore` values pointing at the same physical directory via different
  spellings (e.g. `/tmp` vs `/private/tmp` on macOS, a symlinked repo path,
  iCloud Drive aliases) hash to distinct keys, miss `lanes[key]` at
  `ThreadStoreWriteSerializer.swift:52`, and create a second `Lane` with its own
  `DispatchQueue` at `ThreadStoreWriteSerializer.swift:55-56`. The two stores
  then `queue.sync` on independent queues and can write the same
  `thread_<id>/thread.json` concurrently — torn writes / lost updates.
- **Suggested fix:** Canonicalize the key with
  `rootDirectory.resolvingSymlinksInPath().standardizedFileURL.path` (one `stat`
  per call; cache per input URL if hot). Better: canonicalize in
  `ThreadStore.init` so the invariant holds regardless of caller, and re-verify
  all `ThreadStore(rootDirectory:)` call sites pass already-canonical paths.
- **Suggested slice:** PWT-SXX — canonicalize ThreadStore root keys

### P1 — Lane registry never evicts
- **Invariant:** Long-lived processes must not accumulate unbounded per-root
  lock state.
- **Evidence:** `ThreadStoreWriteSerializer.swift:46` declares
  `private var lanes: [String: Lane] = [:]`; `lane(for:)` at
  `ThreadStoreWriteSerializer.swift:48-58` only inserts (`lanes[key] = created`
  at line 56) and never removes. `Lane` holds a `DispatchQueue` with an attached
  `DispatchSpecificKey` — small but nonzero, and never reclaimed.
- **Suggested fix:** Bounded in production by the number of repos the user runs
  against (small), so this is primarily a test-suite / process-lifetime leak
  when per-test temp directories are used. Either (a) document the no-evict
  contract and bound it explicitly, or (b) expose a `Registry.resetForTesting()`
  and/or canonicalize roots (see above) so test temp dirs collapse to fewer
  lanes. A weak-value map will not help here — `Lane` has no external strong
  refs, so weak values would dealloc immediately.
- **Suggested slice:** PWT-SXX — evict or reset ThreadStore write lanes

### P1 — Reentrant `synchronized` crashes the app in production
- **Invariant:** Same-root nested `synchronized` must not take the process down
  silently; the doc comment (`ThreadStoreWriteSerializer.swift:6-10`) promises
  "reentrant entry is detected."
- **Evidence:** `ThreadStoreWriteSerializer.swift:25-32` — `synchronized` calls
  `preconditionFailure` (line 27) when `DispatchQueue.getSpecific(key:
  onQueueKey) != nil`. The throwing variant `synchronizedThrowingOnReentrancy`
  at `ThreadStoreWriteSerializer.swift:35-40` is `#if DEBUG` only and reachable
  solely via `synchronizedForTesting`
  (`ThreadStoreWriteSerializer.swift:65-67`, `78-80`) — not via the production
  `synchronized` path. So in Release builds, any accidental same-root nesting
  (e.g. a caller wrapping `create` / `appendTurn` / `saveForImport`
  [ThreadStore.swift:80, 113, 106] in their own `synchronized` block on the same
  root) traps the whole process.
- **Suggested fix:** The deadlock→crash trade is defensible (better than a hang),
  but (a) make the prod `synchronized` throw `WriteSerializerError.reentrantSynchronized`
  and have `ThreadStore` surface it as a typed `ThreadStoreError` case so callers
  can recover / report, or (b) make reentrancy impossible by construction: audit
  all public `ThreadStore` mutators so none call another mutator under the same
  lock. Do **not** switch to `NSRecursiveLock` — reentrant mutation breaks the
  serialization invariant the caller asked for.
- **Suggested slice:** PWT-SXX — typed reentrancy failure for ThreadStore

### P1 — Read paths bypass the write lock (atomicity assumption unverifiable)
- **Invariant:** Readers must never observe a half-written `thread.json`.
- **Evidence:** `ThreadStore.get` at `ThreadStore.swift:52-57` reads
  `Data(contentsOf: url)` with no `synchronized`; `list` at
  `ThreadStore.swift:62-77` scans the directory and decodes each `thread.json`
  with no `synchronized`; `threadDirectory(forThreadId:)` at
  `ThreadStore.swift:45-50` calls `createDirectory` outside the lock. Meanwhile
  writers (`create` line 80, `saveForImport` line 106, `appendTurn` line 113)
  hold the lock. `get` swallows decode failure via `try?`
  (ThreadStore.swift:57) and `list` via `compactMap` (ThreadStore.swift:71), so a
  torn read silently drops a thread from the result.
- **Suggested fix:** Confirm `persistContent` writes atomically
  (`Data.WritingOptions.atomic` or write-temp-then-rename). If atomic, the
  no-lock-on-read design is sound — document the contract on
  `ThreadStoreWriteSerializer` ("mutation lane; reads rely on atomic writes"). If
  non-atomic, either write atomically or take a read lock. Cannot fully close
  without `persistContent` source (not inlined).
- **Suggested slice:** PWT-SXX — prove/fix ThreadStore write atomicity

### P2 — `threadDirectory(forThreadId:)` is public and mutates FS state outside the lock
- **Invariant:** Public API should not pre-commit filesystem state that `create`'s
  existence check then observes.
- **Evidence:** `ThreadStore.swift:45-50` — `threadDirectory(forThreadId:)` is
  `public` and calls `createDirectory(...withIntermediateDirectories: true)`
  with no `synchronized`. `create` at `ThreadStore.swift:90-93` checks
  `FileManager.default.fileExists(atPath: threadDirectory.path)` inside the lock;
  a prior `threadDirectory(forThreadId:)` call would make that check true,
  causing `create` to throw `threadAlreadyExists` for a thread that was never
  actually created — a footgun for callers that touch the directory helper first.
- **Suggested fix:** Either make `threadDirectory(forThreadId:)` internal, or
  make it not create the directory (return the URL without `createDirectory`),
  reserving directory creation for `persistContent` inside the lock.
- **Suggested slice:** (nit, fold into the atomicity slice above)

### P2 — Reentrancy guard is documentation-only
- **Invariant:** Compile-time > runtime > doc-time guarantees.
- **Evidence:** The only protection against same-root nested `synchronized` is
  the doc comment at `ThreadStoreWriteSerializer.swift:6-10` plus the runtime
  trap. Nothing prevents a future caller from wrapping `appendTurn` in
  `ThreadStore.synchronized { ... }` on the same root.
- **Suggested fix:** No code change required; pair with the P1 reentrancy fix
  above so the runtime failure is typed, not a crash.

## False alarms ruled out
- **`@unchecked Sendable` on `Lane`/`Registry` is warranted.** `Lane`'s only
  stored properties are `let` (`onQueueKey`, `queue`) — effectively immutable
  post-init, so unchecked Sendable is fine (could even be implicit `Sendable`).
  `Registry.lanes` is mutable but every access goes through `lock.lock()` /
  `defer lock.unlock()` in `lane(for:)` (`ThreadStoreWriteSerializer.swift:50-51`,
  `60-62`), so no data race. No finding.
- **Per-`Lane` `DispatchSpecificKey` is correct, not a bug.** A fresh key per
  `Lane` means `DispatchQueue.getSpecific(key: laneA.onQueueKey)` returns non-nil
  only when running on Lane A's queue. Cross-root nesting
  (`synchronized(rootB)` from inside `synchronized(rootA)`) correctly returns nil
  for Lane B's key and proceeds to a different queue — no deadlock, no false
  trap. Same-root reentry is the only trapped case, as intended.
- **`rethrows` propagation is correct.** `queue.sync(execute:)` has a `rethrows`
  overload matching the `() throws -> T` body; throwing bodies propagate through
  both `synchronized` and `synchronizedForTesting` without being swallowed.
- **`!= nil` vs `== 1` for the queue-specific value** is equivalent given the
  value is the non-nil `UInt8` `1` set at `ThreadStoreWriteSerializer.swift:22`;
  no off-by-one.
- **No deadlock in the production path.** The original CR-10 deadlock concern is
  gone — `preconditionFailure` fires before `queue.sync` would block. The
  remaining issue is that the trap is a hard crash, captured as P1 above.
- **Registry lock is not held during `queue.sync`.** `Registry.synchronized`
  (`ThreadStoreWriteSerializer.swift:60-62`) calls `lane(for:)` (which locks only
  for the lookup) and then calls `lane.synchronized(body)` after unlock — so the
  registry lock does not serialize unrelated roots. Correct.
- **No use-after-free on the returned `Lane`.** `lane(for:)` returns a strong
  reference; `Registry.lanes` never removes entries, so the `Lane` is retained
  for the duration of `queue.sync`. (If eviction is added per the P1 above, this
  reasoning must be re-checked.)

## Greps avoided
- Did not grep or read any file outside the two inlined sources. Specifically,
  did **not** read `persistContent`, `validateContextPacket`,
  `ensureLegacyReadBaseline`, `CoreJSON`, `AllnighterPaths`, the declaration of
  `ThreadStore.synchronized` (the private wrapper invoked by `create` /
  `appendTurn` / `saveForImport` — its visibility is inferred from call sites,
  not confirmed), or any caller of `ThreadStore(rootDirectory:)`. The read-path
  P1 finding explicitly flags `persistContent`'s atomicity as unverifiable from
  inlined sources rather than assuming it. No repo exploration performed.