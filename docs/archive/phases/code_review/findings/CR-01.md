# CR-01 — RunWriteLock concurrency invariant review

## Summary

`RunWriteLockRegistry` enforces one-writer-per-repo via an actor-isolated `held`
set and a per-key FIFO waiter queue. The handoff core — `release` resumes the head
waiter with `true` (ownership transfer, `held` stays set), `expire` removes a
waiter and resumes `false` — is race-free under actor serialization: no
double-resume, no lost wakeup, no FIFO jump in normal operation. Three real gaps
remain, all P1: (1) `release(key)` carries no ownership token, so a stray or
double `release` by a misbehaving caller can free the lock under the real holder
→ two writers; (2) `key(repoRoot:)` uses `standardizingPath`, which does not
resolve symlinks or normalize case, so two path strings for the same physical
repo can key independently → two writers; (3) a holder that crashes or is
cancelled without calling `release` leaks the key permanently — the per-waiter
timeout only lets *waiters* give up, it never clears `held`.

## Findings

### P0

None. The one-writer invariant holds for all code paths in this file under
correct caller usage (single `release` per `true` acquisition). The identified
gaps require caller misbehavior (P1-1), non-canonical path input (P1-2), or
holder death (P1-3) — none are always-broken.

### P1 — `release` has no ownership guard; stray or double `release` yields two simultaneous writers

- **Invariant:** "At most one mutating run *executing* per canonical repo root at
  a time" (RunWriteLock.swift:3); "Exactly one owner per key at any instant"
  (RunWriteLock.swift:39).
- **Evidence:** `RunWriteLock.swift:104-113` — `release(_ key: String)` mutates
  `held`/`waiters` keyed only by `key`, with no owner token or holder identity
  check. `release` is `public` (RunWriteLock.swift:104). The contract "caller
  MUST call `release(key)` exactly once" (RunWriteLock.swift:64-65) is prose, not
  enforced by the type.
- **Failure path (stray release with queued waiters):** Holder A holds `k`.
  B (buggy/stray) calls `release("k")` → `waiters["k"]` non-empty → head waiter C
  is resumed `true` (RunWriteLock.swift:105-109), `held` stays set. A still
  believes it holds `k`. A and C both believe they own the lock → two writers.
- **Failure path (double release):** A `release`s → head waiter B resumed `true`,
  `held` stays set (RunWriteLock.swift:105-109). A `release`s again → `waiters`
  now empty → `held.remove("k")` (RunWriteLock.swift:111). C now `waitToAcquire`s
  → fast-path `held.insert` succeeds → C holds. B and C are both writers.
- **Suggested fix:** Return an owned `Token` (or `ownerLabel`-keyed receipt) from
  `acquire`/`waitToAcquire`; require it in `release`. `release` is a no-op (or
  assertion failure) if the token does not match the recorded holder. The
  "Resolved symbols" list gives `waitToAcquire(key: String, ownerLabel: String)`,
  which does not match the inlined `waitToAcquire(_ key: String, timeout: Duration)`
  (RunWriteLock.swift:74) — owner-label tracking may have been intended but is
  absent from the source; reconcile.
- **Suggested slice:** `runlock: owner-token release guard`

### P1 — Symlink- and case-unaware normalization can key the same physical repo under two keys, allowing two writers

- **Invariant:** "At most one mutating run *executing* per canonical repo root"
  (RunWriteLock.swift:3); "Canonical key for a repo root" (RunWriteLock.swift:13).
- **Evidence:** `RunWriteLock.swift:22` — `(trimmed as NSString).standardizingPath`.
  `standardizingPath` expands `~` and collapses `..`/`.` but does **not** resolve
  symlinks (requires `URL.resolvingSymlinksInPath()`) and does not normalize case
  (APFS is case-insensitive by default).
- **Failure path (symlink):** One run uses `/Users/mike/Allnighter`, another uses
  a symlink alias `/Code/Allnighter` → same working tree, distinct normalized
  strings, distinct FNV-1a hashes, distinct keys → both `held.insert` succeed →
  two mutating runs execute concurrently.
- **Failure path (case / `/var`):** `/Users/Mike/Repo` vs `/Users/mike/Repo` are
  the same directory on case-insensitive APFS but normalize differently → two
  keys. Likewise `/var/...` vs `/private/var/...` (the macOS canonical form)
  diverge because `/var` is a symlink to `/private/var`.
- **Suggested fix:** After `standardizingPath`, resolve symlinks
  (`URL(fileURLWithPath: std).resolvingSymlinksInPath().path`) before hashing.
  Case normalization is filesystem-dependent; a lowercase fallback is the common
  conservative choice. Cache by raw input if the key path is hot.
- **Suggested slice:** `runlock: symlink-resolving canonical key`

### P1 — Holder crash/cancellation leaks the key permanently; the timeout only vents waiters, not the holder

- **Invariant:** "the timeout is the safety valve so a wedged holder ... can't
  hang every later run forever" (RunWriteLock.swift:68-69).
- **Evidence:** `RunWriteLock.swift:104-113` — `release` is the only path that
  clears `held` (RunWriteLock.swift:111) or hands off (RunWriteLock.swift:109).
  There is no holder-side lease, no watchdog hook, and no recovery path that
  clears `held` without an explicit `release` call.
- **Failure path (crash):** Holder's task dies (`fatalError`, force-quit, or a
  forgotten `release` in an error path). The key stays in `held` for the life of
  the process. Every subsequent `waitToAcquire` on that key waits the full
  `timeout` and returns `false` — runs are refused, not hung, but the repo is
  effectively dead until process restart. The docstring's claim that the timeout
  prevents a wedged holder from hanging later runs is technically true (they
  return `false`) but misleading: the lock is never recovered.
- **Failure path (ownership transfer to a cancelled waiter):** Waiter W is
  queued. W's task is cancelled → `onCancel` spawns `Task { expire(key, W.id) }`
  (RunWriteLock.swift:89). Before that `expire` runs on the actor, the holder
  calls `release` → W is the head → `release` removes W and resumes it `true`
  (RunWriteLock.swift:105-109). The `expire` Task then runs but W is gone from
  `waiters` → no-op (RunWriteLock.swift:98 guard). W's `waitToAcquire` returns
  `true` (ownership transferred) but W's task is cancelled — if the caller does
  not call `release` before bailing on cancellation, the key leaks. The
  `onCancel` defense is defeated by this scheduling race.
- **Suggested fix:** (a) Pair `waitToAcquire` with a holder-side watchdog `Task`
  that auto-`release`s after a lease duration; or (b) have the caller pass a
  `Task` handle whose cancellation triggers `release`; or (c) at minimum,
  document that holder death requires process restart, and have `waitToAcquire`
  check `Task.isCancelled` immediately after a `true` return and re-`release`.
- **Suggested slice:** `runlock: holder-side lease / auto-release on death`

### P2 — `expire` still runs after `timeoutTask.cancel()` (minor wasted actor hop)

- **Invariant:** (efficiency, not correctness)
- **Evidence:** `RunWriteLock.swift:91` — `timeoutTask.cancel()` is called after
  the continuation resumes. The timeout Task (RunWriteLock.swift:79-82) uses
  `try? await Task.sleep(...)`; on cancel, `try?` swallows the
  `CancellationError` and execution continues to `await self?.expire(...)`
  (RunWriteLock.swift:81). `expire` finds no waiter (already removed by
  `release` or by the timeout itself) and returns, but the actor hop still
  happens.
- **Suggested fix:** Use `try await Task.sleep(...)` (no `?`) and let
  cancellation propagate, or guard with `if Task.isCancelled { return }` before
  the `expire` call.
- **Suggested slice:** (nit)

### P2 — `nextWaiterId` wraps with `&+=`; after 2^64 waiters, IDs can collide

- **Invariant:** "Resumed exactly once" (RunWriteLock.swift:71-73).
- **Evidence:** `RunWriteLock.swift:77` — `nextWaiterId &+= 1`. Wrapping add at
  2^64 could reuse an ID still present in a queue, causing `expire`
  (RunWriteLock.swift:98) to match the wrong `Waiter`.
- **Suggested fix:** None practical — accepted. A `UUID` per waiter would remove
  the collision at negligible cost.
- **Suggested slice:** (nit)

### P2 — `[weak self]` on `timeoutTask` vs strong `self` in `onCancel`; inconsistent retain, benign for the singleton

- **Invariant:** (consistency, not correctness for `shared`)
- **Evidence:** `RunWriteLock.swift:79` (`[weak self]`) vs
  `RunWriteLock.swift:89` (`Task { await self.expire(...) }`, strong). If a
  non-`shared` registry were deallocated while a waiter is queued, the
  `timeoutTask`'s `self?` would be nil and `expire` would never run; the waiter
  would hang. `onCancel` retains `self`, so cancellation still works, but a
  non-cancelled, non-timed-out waiter on a deallocated non-singleton would leak.
- **Suggested fix:** Make both paths consistent (both strong, or both weak +
  document). For `static let shared` (RunWriteLock.swift:41), this is benign.
- **Suggested slice:** (nit)

## False alarms ruled out

- **TOCTOU gap between `held.insert` (line 75) and waiter append (line 85):**
  ruled out. The two `await` expressions on lines 83-84 do not suspend before
  the append. `withTaskCancellationHandler` starts its operation synchronously,
  and `withCheckedContinuation` runs its closure body (the `append`) synchronously
  before suspending — the closure is documented to run synchronously. The first
  real actor suspension is inside `withCheckedContinuation`, *after* the waiter
  is registered. Therefore `release`/`expire` cannot observe a
  "checked-but-unregistered" waiter, there is no lost-wakeup window, and FIFO is
  not broken by a registration gap. The timeout Task and the `onCancel`-spawned
  `expire` Task also cannot run before the append: both require the actor, which
  is busy until the suspension inside `withCheckedContinuation` — i.e., after
  the append. (An earlier review claimed this gap; it does not hold under Swift's
  continuation semantics.)
- **Double-resume of a waiter by `release` + `expire`:** ruled out. Both run
  under actor isolation, so they are serialized. Whichever runs first removes the
  waiter from `waiters` (`release` at RunWriteLock.swift:105-107, `expire` at
  RunWriteLock.swift:99-100); the second finds no matching waiter and is a no-op
  (RunWriteLock.swift:98 guard). No double-resume.
- **`acquire` (non-blocking) jumping the FIFO queue:** ruled out. `acquire` does
  `held.insert(key).inserted` (RunWriteLock.swift:60-61), which can only succeed
  when `held` does not contain `key`. The invariant "waiters exist ⟹ `held` is
  set" is maintained by `release` (transfers ownership, keeps `held` set —
  RunWriteLock.swift:109) and `expire` (removes a waiter, does not touch `held` —
  RunWriteLock.swift:99-100). So `held` being free implies no waiters, and
  `acquire` cannot cut a queued `waitToAcquire`.
- **Read/answer runs blocked by the lock:** ruled out by design. There is no
  read-lock API; read runs simply never call `acquire`/`waitToAcquire`/`release`,
  so they stay fully parallel as the header docstring (RunWriteLock.swift:4-5)
  promises.
- **`release` on a never-acquired key corrupts state:** ruled out. `waiters[key]`
  is nil and `held.remove(key)` is a no-op on a `Set` (RunWriteLock.swift:111).
  Harmless.
- **FNV-1a hash collision producing key aliasing:** ruled out as a practical
  concern. 64-bit FNV-1a on short path strings has negligible collision
  probability for any realistic repo count; the `v1:` prefix
  (RunWriteLock.swift:15) leaves room to re-key if needed.

## Greps avoided

No repo exploration performed. Review is based solely on the inlined
`RunWriteLock.swift` source and the resolved-symbols list provided in the task.
The discrepancy between the inlined
`waitToAcquire(_ key: String, timeout: Duration) async -> Bool`
(RunWriteLock.swift:74) and the resolved-symbols
`waitToAcquire(key: String, ownerLabel: String) async` is noted in P1-1; not
resolved by grepping, per instructions.