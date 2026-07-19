# RLR-S02 Execution Plan — durable FIFO ticket facts · no-spawn-while-blocked · root isolation · terminal ticket withdrawal

Status: **Architect recon + design (RLR-S02). No source changed to produce this.**
Read-only audit of branch `feat/design-chain` (2026-07-19). SSOT:
`docs/archive/phases/Run_Lifecycle_Reliability.md` (FINAL) — laws RLR-L4 (typed
`repoWriteLock` blocker), RLR-L3 atomic rule, Works Test items 3 and 14. Prior:
`docs/archive/phases/rlr/S01_Execution_Plan.md` (landed S01a/b/c —
`53510dc2`/`373baf63`/`704cb315`).

**Headline:** the FIFO + flock + durable-holder + ticket machinery **already
exists and is battle-tested** (`ExecutionLaneRegistry` / `ExecutionLaneFlock` /
`ExecutionLaneTicket`, from the archived Process Ownership + Concurrent
Invocation work). S02 is **not** "build FIFO" — it is **wiring the existing
ticket facts into the run's durable `RunBlocker`** and **closing the
cross-process ticket-withdrawal-on-kill gap**. Foundation is present; the run
lifecycle just isn't reading from it yet.

---

## PART 1 — CURRENT-STATE MAP

### 1.1 The write-lock implementation — FIFO? flock-backed? durable?

**One system, one key.** `RunWriteLock` is a façade (`ExecutionLane.swift:688`)
over `ExecutionLaneRegistry` (actor, `ExecutionLane.swift:97`) +
`ExecutionLaneFlock` (`ExecutionLaneFlock.swift:27`). `RunWriteLock.swift` is an
empty tombstone pointing here (do not reintroduce a second registry).

- **FIFO: YES.** `ExecutionLaneRegistry.waitToAcquire` (`ExecutionLane.swift:215`)
  is a fair queue: in-process `waiters[key]` array + **cross-process** waiter
  files (`ExecutionLaneFlock.registerWaiter`, `:681`) named
  `<nanos>_<uuid>.json` and ranked by filename
  (`waiterPosition`, `:716`; dead-waiter identities filtered out, PO-F9 `#7`). A
  200ms reconcile task (`:256`) re-grants; a timeout task expires
  (`:265`, `endReason: "laneBusy"`); task-cancel expires
  (`onCancel` → `expire(endReason: "cancelled")`, `:288`).
- **flock-backed cross-process: YES.** `ExecutionLaneFlock` holds an OS
  `flock(LOCK_EX|LOCK_NB)` on `Lanes/<key>/lane.lock`
  (`:867-892`), `O_CLOEXEC` so spawned workers don't inherit it (kernel releases
  on holder death). Multi-holder metadata in `Lanes/<key>/holder.json` under a
  brief `meta.lock` (PO-S06). This is **the live cross-process substrate other
  `alln` processes already use** — see Risk #2.
- **Ticket type already exists:** `ExecutionLaneTicket`
  (`ExecutionLaneTicket.swift:9`) = `{ position, holder{identity,kind,id},
  heldSinceSeconds }`. `waitToAcquire` already exposes an
  **`onTicket: (@Sendable (ExecutionLaneTicket) -> Void)?`** callback (`:220`)
  and mints the ticket at enqueue (`busyTicket`, `:653`).

**Verdict: FIFO ✓, durable holder ✓ (on disk), the ticket callback ✓ — all
present.** The gap is that the run's blocker doesn't consume any of it.

### 1.2 Where holder identity lives + whether a holder work-ref is durably attached

- On disk: `holder.json` `HolderMetadata` (`ExecutionLaneFlock.swift:43`) =
  `{ identity(pid/pgid/startTicks/kind), kind, id, acquiredAt, writeScope,
  needsBuildLane }`. `acquiredAt` **is** durable (feeds `heldSinceSeconds` and
  will feed `holderAcquiredAt`). So the holder work-ref **is durably attached —
  but under the WRONG id.**
- **The core S02 gap:** the mutating run's write-lock wait at
  `RunService.swift:497` calls the **legacy anonymous overload**
  `waitToAcquire(_ key:, timeout:)` (`ExecutionLane.swift:314`), which mints
  `claim.id = "mutatingRun-<UUID>"` — **NOT the canonical `runId`.** Therefore
  `holder.json.id` is a throwaway UUID. A second process reading the holder
  cannot map it back to the holding **run's** canonical id. RLR-L4's "holder
  work ref" (= the holding run's id) is **not** satisfiable today.
- The claim-bearing overload (`:215`) is used only by the **proof lane**
  (`RunService.swift:944-960`, `id: runId, kind: harnessProof`) and by
  relay/pilot — those DO carry a real id. The mutating run is the one that
  doesn't.

### 1.3 How `scopeRoot` is canonicalized today (RLR-L4 symlink/case)

- **Single SSOT, already reused:** `RunWriteLock.normalize`
  (`ExecutionLane.swift:697`) = trim → `NSString.standardizingPath` (resolves
  `.`/`..`/`~`) → strip trailing `/` → `URL.resolvingSymlinksInPath` → strip
  trailing `/`. `ExecutionLane.key` (`:78`) = `"v1:" + fnv1a(normalize(root))`.
- `RunService` already computes `root = RunWriteLock.normalize(request.repoRoot)`
  (`RunService.swift:375`) and writes `blocker.scopeRoot = root`
  (`:482`). **So `scopeRoot` IS the canonical, symlink-resolved root — the same
  SSOT the lane key uses. Do NOT invent a second canonicalizer.**
- **GAP — case normalization:** `normalize` does symlink + `.`/`..` + trailing
  slash, but **no case-folding.** On the default case-insensitive-but-preserving
  macOS FS, `/Users/mike/Repo` and `/Users/mike/repo` resolve to the same inode
  yet `resolvingSymlinksInPath` does **not** guarantee they collapse to one
  string → different `fnv1a` → **two lane keys for one root.** RLR-L4 explicitly
  says "symlink **+ case** normalized" and Works Test 3 requires "two path
  spellings share one lock." **Whether `resolvingSymlinksInPath` already
  case-canonicalizes an existing path on this FS is UNDETERMINED — I read the
  normalize source but did not execute a case-difference probe (no build/run per
  constraints).** S02b must test it and, if it fails, close it *without* changing
  the frozen key formula for existing spellings (Risk #2).

### 1.4 What happens to a waiting run's journal today (S01b stub vs RLR-L4)

- S01b landed: `RunBlocker` (`TeamRun.swift:25`) = **`{ resource, scopeRoot }`
  only.** Written at `RunService.swift:482` before the wait; cleared to `nil` on
  grant (`:512`) and on timeout terminal (`:503`), each in the same `save`
  revision (atomic rule already honored for these two fields).
- **Missing vs RLR-L4:** `holderId`, `holderKind`, `ticketPosition`,
  `holderAcquiredAt`. None are written because the mutating wait uses the
  **no-`onTicket`** overload (`:497`) — the ticket facts are computed by the
  registry but never handed to the run. The blocker names the *resource and
  root* but not *who holds it* or *where in line we are*.
- **Blocker is also not projected onto the status wire yet.** Grep of
  `TeamRunJSON.swift` / `TeamRunJSONMapper.swift` for `blocker` is **clean** —
  the CLI-first `blocker{}` object in the spec's JSONC block has **no mapper**.
  So even the two S01b fields are invisible to `alln team status --json`. S02
  must add the projection.

### 1.5 Where cancel/kill of a BLOCKED run flows + any ticket withdrawal

- **Kill:** `ProcessOwnershipSurface.killRun` (`:177`) under `withRunLock`: reads
  run.json, refuses if terminal, stamps `status=.cancelled, endReason=.killed`,
  signals the recorded owner, saves. **It does NOT clear `blocker`, does NOT
  withdraw any FIFO waiter file, and does NOT release/deregister the lane.**
- **The cross-process withdrawal gap (Works Test 14):** a blocked mutating run is
  parked inside `await writeLock.waitToAcquire` in **its own** CLI process
  (`RunService.swift:497`); its waiter lives in **that process's**
  `ExecutionLaneRegistry` actor + an on-disk waiter file. A `kill` issued from a
  **second** process stamps run.json terminal but **cannot** reach process 1's
  in-memory continuation. Process 1 stays parked until either (a) timeout, or (b)
  it is *granted the lock for an already-terminal run* — then its `defer`
  releases immediately, but it may have briefly held/spawned. **No self-abandon
  path exists.** The only existing withdrawals are **same-process**: task-cancel
  (`onCancel` → `expire`, `:288`) and timeout (`:272`). Both `unregisterWaiter`
  the file.
- Same-process `alln team cancel` on a blocked run: whether the CLI cancels the
  `RunService.run` Task (triggering `onCancel`) is **the graceful path that
  works today**; the second-process kill is the hole.

### 1.6 Async path (`AsyncTeamService`) equivalents

- `AsyncTeamService` **does not take the write lock itself** (grep for
  `waitToAcquire`/`writeLock` in it is clean). The detached runner
  (`team __runner`, `AsyncTeamService.swift:532`) calls into `RunService.run`,
  which is the **same** `RunService.swift:497` mutating wait. So the async path
  inherits S02's fix for free once `RunService` is wired — **no separate lock
  path to change.** The async path's own waits are governor/handshake
  (`waitForRunnerReady`), which are S04/L8, not L4.
- Kill of an async run flows through the same `ProcessOwnershipSurface.killRun`.

---

## PART 2 — EXECUTION PLAN (S02a → S02b → S02c, strict order)

Design spine: **consume the existing ticket, don't rebuild it.** Every sub-slice
is independently committable + testable. Wire-freeze law: `RunBlocker`
field names `resource`/`scopeRoot` are frozen — **additions only, no renames.**

### S02a — durable FIFO ticket facts in the blocker, written atomically

**Goal:** the mutating run claims the lane **by its own `runId`**; while blocked,
its `RunBlocker` carries `holderId / holderKind / ticketPosition /
holderAcquiredAt`, written into the **same** journal revision as the phase; on
grant the blocker clears + phase → `spawningWorker` atomically (RLR-L3); spawn
provably cannot happen while blocked.

**Files + edits:**

1. **`TeamRun.swift:25` — extend `RunBlocker` (additive):**
   ```swift
   public var resource: Resource
   public var scopeRoot: String
   public var holderId: String?          // holding run's canonical id
   public var holderKind: String?        // public "run" in P0 (RLR-L4)
   public var ticketPosition: Int?       // 1 = head of queue
   public var holderAcquiredAt: Date?    // persist; heldSinceSeconds derived at projection
   ```
   New optional fields → legacy `run.json` decodes them `nil`. Init gains
   optional params defaulting `nil`. **Frozen names untouched.** Note:
   `holderDeadlineAt` stays out of the struct in P0 (spec: null) — surface it as
   a literal `null` in the JSON projection only.
2. **`RunService.swift:497` — switch to the claim-bearing wait with `runId` +
   `onTicket`:**
   ```swift
   let claim = ExecutionLane.Claim.current(
       id: id, kind: ExecutionLaneSite.mutatingRun.rawValue) ?? <explicit-identity fallback>
   guard let token = await writeLock.waitToAcquire(
       lockKey, claim: claim, timeout: Self.writeLockWaitTimeout,
       onTicket: { [weak self] ticket in
           // Atomic: re-load pending, stamp the 4 ticket facts into blocker, save.
           self?.recordBlockerTicket(runId: id, ticket: ticket)
       }
   ) else { … terminal … }
   ```
   - `recordBlockerTicket` (new private helper) loads the run, sets
     `blocker.holderId = ticket.holder.id`, `holderKind = "run"` (**mapped** from
     the internal `ExecutionLaneSite` — see Risk #1/#3), `ticketPosition =
     ticket.position`, `holderAcquiredAt = now - ticket.heldSinceSeconds` (or
     carry `acquiredAt` — see note), and `runStore.save`s in one revision.
   - **`claim.id = id` (the runId)** makes `holder.json.id` the holding run's
     canonical id, so a *second* run's ticket names *this* run correctly.
   - Grant path (`:509-513`) already clears blocker + sets `spawningWorker`
     atomically — keep. Timeout path (`:501-505`) already clears blocker — keep.
3. **`onTicket` firing:** `waitToAcquire` fires `onTicket` **once at enqueue**
   (`ExecutionLane.swift:254`). For a **live-updating** `ticketPosition` as the
   queue drains, add an **optional re-notify** hook: extend the registry's
   `grantCompatibleWaiters`/reconcile loop to call a stored per-waiter
   `onTicket` again with the new position when the head changes. **Scope
   decision:** P0 Works Test 3 only requires B to show *a* durable FIFO ticket
   naming A (position 1 for a single waiter) — a **single enqueue-time write is
   sufficient for S02a**; live position re-write is a **bounded S02a stretch**
   only if the reconcile loop already has the waiter's closure (it does, in
   `Waiter`). Recommend: store `onTicket` on `Waiter`, re-fire on position
   change — cheap and closes the "stale ticketPosition" inference.

4. **Projection (make the blocker visible on the wire) —
   `TeamRunJSONMapper` / `TeamRunJSON`:** add a `BlockerJSON` sub-object
   (`resource, scopeRoot, holderId, holderKind, ticketPosition, holderAcquiredAt,
   holderDeadlineAt: null`) and map `run.blocker` into it (only for non-terminal
   runs). This is the CLI-first `blocker{}` object; it was never wired (Part
   1.4). Also thread it into `alln ps` rows if not already (surface reuses
   `OwnershipLaneJSON`, which already has holderId/holderKind/ticketPosition —
   keep both consistent).

**No-spawn-while-blocked proof (structural, already true — assert it):** the
worker spawn (`RunService.swift:519` `WorkerInvokerFactory…` and downstream) is
strictly **after** `await writeLock.waitToAcquire` returns a **non-nil token**.
While blocked, control never reaches spawn. S02a adds a test that asserts the
ordering explicitly (no worker log line, no owner identity file, while
`status=queued, phase=waitingForWriteLock`).

**Tests (extend `RunAcceptanceBoundaryTests` — already has the pre-hold
fixture):**
- `testBlockedRunCarriesFifoTicketFactsNamingHolderRun`: pre-hold the lane with
  a claim whose `id = holderRunId`; start run B; assert
  `B.blocker.holderId == holderRunId`, `holderKind == "run"`, `ticketPosition ==
  1`, `holderAcquiredAt != nil`; assert **no** worker spawned (no owner file /
  no fake-worker log) while blocked.
- `testGrantClearsBlockerAndAdvancesPhaseInOneRevision`: release the holder →
  B's next durable revision has `blocker == nil` **and** `phase ==
  .spawningWorker` (no interleaved revision with one set and not the other).

**Acceptance proof:**
```bash
swift test --package-path Packages/AllnighterCore --filter RunAcceptanceBoundary
swift test --package-path Packages/AllnighterCore --filter ExecutionLane
```

---

### S02b — root isolation: one root = one lock, true different roots don't serialize, project A never names project B

**Goal:** prove and tighten the isolation invariants of RLR-L4 / Works Test 3.

**Files + edits:**

1. **Case normalization (the one real correctness gap, Part 1.3):** add a
   case-canonicalization step to `RunWriteLock.normalize` **that only affects
   existing on-disk paths and never changes the key for a path spelling already
   in flight.** Safe approach: resolve the *actual on-disk casing* via
   `FileManager` canonical path (or `realpath(3)`) **when the path exists**, and
   fall back to the current `resolvingSymlinksInPath` string when it does not
   (non-existent roots keep today's behavior → byte-identical key, preserving
   cross-process compat, Risk #2). **First write the failing test; only change
   `normalize` if the test proves two case-spellings currently produce two
   keys.** If `resolvingSymlinksInPath` already collapses case on this FS, this
   step is a no-op + a regression test.
2. **Holder projection is already root-scoped — assert it never crosses
   projects:** `laneState(forRoot:)` (`ProcessOwnershipSurface.swift:405`) and
   the blocker's `holderId` (S02a) are derived per-root from
   `ExecutionLane.key(root)`. Different roots → different keys → different
   `holder.json` → a run on root B can never read root A's holder. Add a test
   asserting `A.blocker` and `B.blocker` never name each other's holder id.
3. **Public `holderKind` mapping:** confirm the S02a projection maps the internal
   `mutatingRun`/`harnessProof`/`relayDevTurn` kinds to the **public `"run"`**
   (RLR-L4: "P0 public holderKind = run"). Single mapping point in the
   `BlockerJSON` mapper.

**Tests (extend `ConcurrentInvocationTwoProcessTests` — the real cross-process,
two-repo, fake-worker fixture):**
- `testSameRootTwoSpellingsShareOneLock`: hold with `/repo`, start a mutating run
  with `/repo/` (and a case variant) → the second run **blocks** with a ticket
  naming the first (one lock).
- `testTrueDifferentRootsDoNotSerialize`: hold root A; a mutating run on root B
  acquires **immediately** (`blocker == nil`, worker spawns) — no serialization.
- `testBlockerHolderKindIsPublicRun`: blocked run's `blocker.holderKind ==
  "run"`, never `"mutatingRun"`.

**Acceptance proof:**
```bash
swift test --package-path Packages/AllnighterCore --filter ConcurrentInvocationTwoProcess
swift test --package-path Packages/AllnighterCore --filter RunWriteLock
```

---

### S02c — terminal transition withdraws the FIFO ticket (Works Test 14), incl. the second-process kill

**Goal:** cancel/kill of a **blocked** run withdraws its FIFO ticket **in the
terminal revision**, from *either* process, and never leaves it parked or lets it
acquire-then-hold as a corpse.

**Files + edits:**

1. **`ProcessOwnershipSurface.killRun` (`:177`) — clear blocker + withdraw the
   waiter file in the terminal save (same revision):**
   - After stamping `status=.cancelled, endReason=.killed`, set
     `current.blocker = nil`.
   - Compute `laneKey = ExecutionLane.key(repoRoot: current.repoRoot)` and call a
     **new** `ExecutionLaneFlock.withdrawWaiter(laneKey:, claimId: current.id)`
     that scans `waiters/`, decodes `WaiterFile.id == runId`, and removes the
     file. This collapses *other* waiters' positions immediately even when the
     killer is a different process.
2. **Self-abandon the parked wait (the cross-process hole) —
   `ExecutionLaneRegistry.waitToAcquire`:** add an optional
   `shouldAbandon: (@Sendable (ExecutionLane.Claim) -> Bool)?` param, checked in
   the existing 200ms reconcile loop (`ExecutionLane.swift:256`). When it returns
   true, `expire(key:, id:, endReason: "withdrawn")` the waiter (which
   `unregisterWaiter`s and resumes the continuation with `nil`). `RunService`
   passes a closure that loads `run.json` for `claim.id` and returns
   `status.isTerminal`. This keeps `ExecutionLane` free of any `RunStore`
   dependency (predicate injection).
   - **Grant-of-a-corpse guard:** even without the poll, if `waitToAcquire`
     returns a token, `RunService` must re-check the run isn't already terminal
     before spawning; if terminal, `release` immediately and return (the `defer`
     at `RunService.swift:515` already releases — add the terminal re-check
     before spawn). Belt-and-suspenders with the self-abandon poll.
3. **Same-process cancel already works** (task-cancel → `onCancel` → `expire` →
   `unregisterWaiter`) — add a regression test so it stays wired when `RunService`
   switches overloads in S02a.

**Tests:**
- Extend `RunLifecycleTwoProcessTests` (the gated two-process fixture, currently
  the S00 red harness): `testKillOfBlockedRunWithdrawsFifoTicketFromSecondProcess`
  — process 1 starts run B blocked behind a held lane; process 2 `alln kill B`;
  assert (a) `B.status` terminal with `blocker == nil`, (b) B's waiter file gone,
  (c) a third waiter C's `ticketPosition` decremented, (d) process 1's
  `RunService.run` returns (not parked to timeout). This is the **Works Test 14
  acceptance shape**.
- `testCancelOfBlockedRunWithdrawsTicketSameProcess` (in-process, fast).

**Acceptance proof:**
```bash
RLR_RED=1 swift test --package-path Packages/AllnighterCore --filter RunLifecycleTwoProcess
swift test --package-path Packages/AllnighterCore --filter ExecutionLane
bash scripts/check.sh
```

---

## RISKS

**Consumers of the current write-lock API (must keep working):**
- `RunService.swift:497` (mutating wait — the one we rewire) and `:956` (proof
  lane, already claim-bearing — unchanged).
- `RelayCoordinator.swift`, `ThreadSendCoordinator.swift`, `TeamService.swift`
  all take the lane via `ExecutionLaneRegistry` — the S02a change is **additive**
  (new `shouldAbandon` param defaulted `nil`, new `onTicket` usage). Existing
  callers unaffected. Verify the legacy anonymous `waitToAcquire(_:timeout:)`
  overload (`:314`) stays for any caller that still uses it, or migrate them
  deliberately.
- `ProcessOwnershipSurface.laneState` / `killRun` — the projection + kill sites.

**flock-file cross-process compatibility (per-root law IS cross-process):**
`holder.json` / `waiters/*.json` / `lane.lock` are the **live substrate other
`alln` processes are using right now.** S02 is compatible **as long as it does
NOT change the key formula or the on-disk schema.** The two touch points:
(1) the mutating claim's `id` changes from `mutatingRun-<UUID>` → `runId` — this
changes the **value** of `holder.json.id`, not its shape; an older concurrent
process reading it just sees a different id string (harmless — it never
interprets the id semantically for exclusion, only for display/reentry-by-equal-
id). (2) `withdrawWaiter` reads/removes the same `WaiterFile` format (additive).
**The one thing that WOULD break cross-process compat is changing
`RunWriteLock.normalize`/`key` for path spellings already in flight** (S02b case
fix) — that reshuffles every live lane key and could orphan an in-flight
foreign holder. Mitigation: S02b changes casing **only for paths that exist on
disk** and keeps the non-existent-path fallback byte-identical, and lands behind
a test that proves the gap is real first.

**Where the S01b stub's shape must change (wire freeze constraint):**
`RunBlocker` gains 4 optional fields — **additions are allowed; the frozen names
`resource`/`scopeRoot` are untouched** → legal under the S01 wire freeze. No
renames. The new `BlockerJSON` projection is net-new (blocker was never
projected), so no existing wire field changes.

### Top 3 risks

1. **Re-keying the mutating claim from anon-UUID → `runId` touches reentry and
   holder semantics shared with relay/pilot/proof.** `canReenter`
   (`ExecutionLane.swift:623`) treats **equal claim ids** as same-turn reentry
   (depth bump, returns existing token). runIds are unique UUIDs so cross-run
   collision is impossible, but the nested **proof** lane already claims with
   `id = runId, kind = harnessProof` (`RunService.swift:945`) — with S02a the
   *outer* mutating hold now also has `id = runId` (different kind). Verify the
   kind-chain rule (`mutatingRun` admits `harnessProof`, `:638`) still grants
   reentry given **equal ids** now short-circuit to `true` at `:627` (it will —
   equal id is a strict superset of the kind-chain grant, so the nested proof
   still reenters). Must add a reentry regression test.

2. **Case-normalization vs the frozen, cross-process key formula.** "Two
   spellings share one lock" (Works Test 3) needs case-folding, but the key
   formula is documented byte-frozen and is **live in other processes.** Changing
   it globally would orphan in-flight foreign holders. The scoped fix
   (case-canonicalize only existing paths, unchanged fallback otherwise) is
   correct but subtle; if `resolvingSymlinksInPath` turns out to already collapse
   case on the target FS, no change is needed — **UNDETERMINED until S02b runs a
   probe test** (could not execute here; build/run is PM-owned).

3. **Cross-process ticket withdrawal requires the blocked run's OWN process to
   abandon its parked continuation — the killer can't reach it.** The killer
   (process 2) can only stamp the journal + remove the on-disk waiter file; the
   in-memory continuation lives in process 1. The `shouldAbandon` poll in the
   200ms reconcile loop is the mechanism, but there is a race window (up to
   ~200ms + grant timing) where process 1 could be **granted the lock for an
   already-terminal run**. The pre-spawn terminal re-check (S02c edit 2) closes
   the "corpse holds the lane / spawns a worker" outcome; without it, Works Test
   14's "lane releases, B proceeds" could momentarily regress. Both the poll and
   the pre-spawn guard are required — neither alone is sufficient.

---

## Verdicts (for PM)

- **Write-lock current-state (3 sentences):** The lane is **FIFO and
  flock-backed and durable** — `ExecutionLaneRegistry.waitToAcquire` runs a fair
  in-process + cross-process-waiter-file queue over an OS `flock`, with a durable
  `holder.json` and a ready-made `ExecutionLaneTicket` (position/holder/
  heldSince) plus an `onTicket` callback. The **holder work-ref is durable but
  under the wrong id** — the mutating wait uses the anonymous overload
  (`RunService.swift:497`) so `holder.json.id` is a throwaway
  `mutatingRun-<UUID>`, not the holding run's canonical `runId`, and the run's
  `RunBlocker` never consumes the ticket (only `resource`+`scopeRoot` written,
  no projection to the status wire). **`scopeRoot` canonicalization is already
  reused** (`RunWriteLock.normalize`, symlink+`.`/`..`+trailing-slash), with
  **case-folding the one missing piece** of RLR-L4 (undetermined whether the FS
  already collapses it — needs an S02b probe).
- **Sub-slices:**
  - **S02a** — claim the lane by `runId`; write `holderId/holderKind/
    ticketPosition/holderAcquiredAt` into `RunBlocker` via `onTicket` in the same
    revision as phase; project `blocker{}` onto the status wire; prove
    no-spawn-while-blocked.
  - **S02b** — root isolation: case-normalize existing spellings without breaking
    the frozen cross-process key; prove different roots don't serialize and A
    never names B; map `holderKind` → public `"run"`.
  - **S02c** — cancel/kill of a blocked run clears blocker + withdraws the FIFO
    waiter file in the terminal revision, with a `shouldAbandon` self-poll +
    pre-spawn terminal guard for the second-process kill (Works Test 14).
- **flock cross-process compatibility:** **Compatible.** `holder.json` /
  `waiters/` / `lane.lock` schema and the key formula are unchanged; the only
  disk-value change is the claim `id` string (shape-identical, non-semantic for
  exclusion) and an additive `withdrawWaiter`. The **sole** compat hazard is the
  S02b case fix if it re-keys in-flight paths — scoped to existing-path casing
  with a byte-identical fallback to avoid orphaning live foreign holders.
- **Top 3 risks:** (1) re-keying the mutating claim to `runId` intersects
  relay/pilot/proof reentry semantics (equal-id short-circuit — needs a reentry
  regression); (2) case-normalization vs the frozen cross-process key formula
  (undetermined if already collapsed — probe first, scope the fix); (3)
  cross-process withdrawal needs the blocked run's own process to self-abandon
  (poll + pre-spawn terminal guard, both required, ~200ms race window).
