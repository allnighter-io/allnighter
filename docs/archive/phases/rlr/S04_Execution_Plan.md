# RLR-S04 Execution Plan — runtimeOwnership · foreground-kill settlement · cancel vs kill · KillOutcome · contradiction surface

Status: **S04a–S04c DELIVERED 2026-07-19.** Terminal-lie GREEN; contradiction
surface + receipts retention + warm honesty landed. Next: S05.
Read-only audit of branch `feat/design-chain` (HEAD `7ff14bba`, 2026-07-19).
SSOT: `docs/archive/phases/Run_Lifecycle_Reliability.md` (FINAL) — law **RLR-L5** IN
FULL (runtimeOwnership, identity-alive, cancel/kill, `KillOutcome`, the 8-step
foreground-kill settlement protocol, operator-vs-clock terminality asymmetry),
the contradiction surface (`terminalWithLiveOwnership`), the
`KILL_REFUSED`/`KILL_PARTIAL` envelope projections, Works Test items **5–8** +
**11 (kill leg)**. Executes on the S00 spawn-site matrix
(`rlr/Spawn_Site_Matrix.md`). Prior landed: S01/S02/S03 plans.

**This is the slice the phase exists for.** It turns
`RunLifecycleTwoProcessTests.testKillStampsTerminalKilledWhileLiveWorkerSurvives`
(signature (b), the "terminal lie") green.

**Headline:** the kill machinery already exists and is *almost* honest — the ONE
identity-checked group-kill (`terminateOwnerIdentityIfSafe`), per-group member
enumeration (`processGroupMemberPids` / `isProcessGroupEmpty`), and the run flock
are all live. The lie is that `ProcessOwnershipSurface.killRun` computes
`signalled` and then **ignores it**, stamping `endReason: killed`
unconditionally — over a worker that was **never recorded** and therefore never
signalled. S04 is: (1) **record worker OS identity keyed by worker id** at spawn
on the two cold paths (the whole of RLR-L5's `runtimeOwnership`, unmet for every
worker today), coordinator as a separate owner; (2) replace both stampers
(`ProcessOwnershipSurface.killRun` and `AsyncTeamService.cancel`) with **one
settlement routine** that verifies per recorded member, returns a typed
`KillOutcome`, and stamps `killed` **only on verified stop**; (3) derive
`contradiction: terminalWithLiveOwnership` at read time from retained receipts.

---

## PART 1 — CURRENT-STATE MAP

### 1.1 Where worker `OwnerIdentity` is BUILT and LOST — the cold foreground `alln run` path (site B)

`alln run` → `RunCLI.run` → **`RunService`** (foreground, in-process).

- `RunService` default worker runner is `ProcessGroupCommandRunner`
  (`RunService.swift:184`), composed via `WorkerInvokerFactory.makeWorkerInvoker`
  (`RunService.swift:593`) and driven by `CatalogRunCoordinator`
  (`RunService.swift:1126`).
- `ProcessGroupCommandRunner` spawns through the **good primitive**
  `ProcessOwnership.spawnProcessGroupLeader` (`ProcessGroupCommandRunner.swift:64`
  non-stream / `:173` stream) → `posix_spawn` + `POSIX_SPAWN_SETPGROUP`
  (`ProcessOwnership.swift:717`/`:834`), building a full `OwnerIdentity`
  (`pgid == pid`, `startTimeTicks`, `kind`) at `ProcessOwnership.swift:849`.
- **The identity is held only in `spawned.identity`** (`ProcessGroupCommandRunner.swift:93`/`:204`),
  consumed by in-process cancel/timeout/buffer-cap handlers
  (`terminateOwnerIdentityIfSafe(identity)` at `:102/109/144/150/213/236/296/311`).
- **It is NEVER written to disk keyed by worker id.** The only durable write the
  primitive triggers is `recordSpawnedTurnOwner` (`ProcessOwnership.swift:166`),
  which **no-ops** unless `kind == .devTurn` **and**
  `TurnOwnerDirectory.shared` is set (`:168`) — set **only** by
  `RelayCoordinator.swift:1143`. For a plain `alln run` the turn dir is unset →
  no worker owner file. **A second process running `alln kill <runId>` has no
  worker record to read.** (S00 matrix headline 3.)

### 1.2 The path that DOES persist a durable owner — and what it persists

The **coordinator**, not the worker, is the only thing durably recorded, and
only on the detached-runner path:

- **Relay/pilot dev turn:** `RelayCoordinator` sets `TurnOwnerDirectory.shared`
  (`RelayCoordinator.swift:1143`); the `.devTurn` worker spawn then writes
  `dev_turn_owner.json` via `recordSpawnedTurnOwner`
  (`ProcessOwnership.swift:166`/`:852`/`:858`). This is the *only* worker-side
  durable identity in the tree today — and it is keyed by **directory**, one file,
  not by worker id (fine for one turn; not RLR-L5's per-worker map).
- **Async detached runner (coordinator):** the runner process writes its own
  `owner.json` (`kind == .detachedRunner`) on claim
  (`AsyncTeamService.swift:610-611`, `ProcessOwnership.writeOwnerIdentity:260`),
  guarded by the F2 stage-lease. `ProcessOwnershipSurface` / reconcile read this
  file and route kills through `terminateOwnerIdentityIfSafe`. **The coordinator
  is genuinely cross-process killable; its worker children are invisible.**

### 1.3 The async worker spawn (site C) — SubprocessCommandRunner + setpgid detachment

`alln team start` → `runTeamStart` → **`AsyncTeamService`** → `spawnDetachedRunner`
(`AsyncTeamService.swift:335`) → the runner re-execs and runs `launchInProcess`
(`:686`), building a `CatalogRunCoordinator` whose worker runner is
`WorkerInvokerFactory.makeWorkerInvoker(commandRunner: <injected>)`
(`:737-738`). The injected `commandRunner` defaults to AgentOS
**`SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy())`**
(`AsyncTeamService.swift:85`).

`SubprocessCommandRunner` (AgentOS,
`Sources/AgentOSCLI/SubprocessCommandRunner.swift`):
- spawns via `Foundation.Process.run()` then **`setpgid(pid, pid)`**
  (`:395`) — best-effort, non-atomic, and it moves the worker into its **own**
  group, **detaching it from the coordinator's group**. A coordinator group-kill
  cannot reach it.
- records **no identity** anywhere; the pid lives only inside the in-process
  `Process`. Kill is in-process `killGroup(process)` (`:425`) on timeout/cancel.

⇒ **This is the site the red kill test exercises.** The test uses `alln team
start` (async), so its worker is a site-C child: its own group leader, pgid never
recorded, unreachable by the coordinator-only `alln kill`. (S00 matrix finding 2.)

**The spawn-policy gate's exact complaint.** `scripts/check_spawn_policy.sh`
greps `Sources/` for a bare `SubprocessCommandRunner()` (the constructor that
defaults to `IdentitySpawnEnvironmentPolicy` — dropping the team-recursion depth
guard + `ALLNIGHTER_TOOL_TOKEN` scrub). The single failing hit is
**`SpawnResolvingCommandRunner.swift:21`**:
`inner: any StreamingCommandRunner = SubprocessCommandRunner()` — a bare default
parameter. It is never reached at runtime (`WorkerInvokerFactory` always passes
`inner: base`, `:57-58`), but the grep flags the textual construction, and
`bash scripts/check.sh` fails on it. (§2.1 folds the fix in.)

### 1.4 `ProcessOwnershipSurface.killRun` — the terminal lie (the exact bug)

`ProcessOwnershipSurface.killRun` (`ProcessOwnershipSurface.swift:183-224`), under
the run flock (`ProcessOwnership.withRunLock:190`):

```
let signalled = ProcessOwnership.terminateRecordedOwnerIfSafe(in: directory)  // :202
current.status = .cancelled                                                    // :203
current.endReason = .killed                                                    // :204
… workerAnswers → .cancelled … blocker cleared … FIFO withdrawn …
_ = try? runStore.save(current, models: [])                                    // :221
return .success(OwnershipKillRowJSON(id:…, signalled: signalled))
```

**`signalled` is captured and returned but never gates the stamp.**
`terminateRecordedOwnerIfSafe` (`ProcessOwnership.swift:613`) reads **`owner.json`
only** — i.e. the *coordinator*. On the async path that signals the detached
runner's group; the worker (site C, own group) survives; the journal is stamped
terminal `killed` anyway. **No verification, no worker record, no `KillOutcome`.**
This is signature (b).

`killAll` (`:110-136`) filters by `identityAlive` / mismatch on the **coordinator**
row then calls `kill(id:)` per row — same lie inherited, plus it never enumerates
workers.

### 1.5 `AsyncTeamService.cancel` — the same lie on the cancel verb

`AsyncTeamService.cancel` (`:895-923`):
- reconciles, then either `active.task.cancel()` (in-process; only when the CLI is
  the *same* process as the runner — never true for a detached run) **or**
  `terminateRecordedOwnerIfSafe(in: directory)` (`:906`) — **coordinator only**.
- then **unconditionally** `run.status = .cancelled; run.endReason = .cancelled`
  (`:914-915`) regardless of whether anything stopped. Same non-verified terminal
  stamp; no grace-then-escalate, no per-member verify, no typed outcome.

`cancelAll` (`:925`) loops `cancel`.

### 1.6 The verification primitives that ALREADY exist (S04 composes, does not build)

- **The one identity-checked group kill:** `terminateOwnerIdentityIfSafe`
  (`ProcessOwnership.swift:595`) — refuses non-PG-killable kinds, refuses when
  `pgid` absent, refuses a live-but-mismatched pid (recycled), else
  `terminateProcessGroup(pgid)` = `SIGTERM` → 200 ms grace → `SIGKILL`
  (`:579-588`). A `terminateSignalHook` (`:572`) lets tests observe without
  signalling.
- **Per-member enumeration:** `processGroupMemberPids(pgid)` (`:635`) via sysctl
  `KERN_PROC_ALL` filtering `e_pgid`; `isProcessGroupEmpty(pgid)` (`:629`).
  Already used in `ProcessOwnershipSurfaceTests.swift:390/469`. **This is the
  post-signal verify surface S04b needs** — nothing new required to *enumerate*.
- **Run flock:** `withRunLock(in:)` (`:657`) serializes terminal writes;
  concurrent killers can be made idempotent on top of it.

### 1.7 Identity-alive today vs the RLR-L5 definition (the two gaps)

`isIdentityAlive` (`ProcessOwnership.swift:279-283`) = `processAlive(pid)` ∧
`processStartTimeTicks(pid) == recorded`. RLR-L5 requires **`pid exists ∧
startTimeTicks match ∧ process state ≠ zombie`**, verified **per recorded member
before any group signal**.

- **Gap A — zombie exclusion is MISSING.** A reaped-but-not-waited child is a
  `<defunct>` zombie: `kill(pid,0)` succeeds and start-time matches, so
  `isIdentityAlive` reports **alive**. RLR-L5 (and the "zombie-only residuals may
  be terminal with cleanup warning" rule) needs `p_stat == SZOMB` excluded.
  `kinfo_proc.kp_proc.p_stat` is already available (same sysctl as
  `processStartTimeTicks`, `:530-539`).
- **Gap B — no per-member pre-signal verify.** Callers verify the *owner* pid, not
  each recorded group member, and only *after* signalling. RLR-L5 wants a
  per-member identity-alive gate **before** any group signal (pgid-reuse guard).

### 1.8 Where ownership receipts live + retention (contradiction surface input)

- Coordinator `owner.json` (`writeOwnerIdentity:260`) is **not cleared on terminal**
  — it lingers in the run dir (only `clearStageLease` runs at terminal). `alln ps`
  already re-reads it (`ProcessOwnershipSurface.swift:153`) and reports
  `identityAlive`. **Receipts already survive terminal for the coordinator** —
  S04 must add the same retention for the new per-worker receipts and derive the
  contradiction from them.
- `OwnershipProcessJSON` (`OwnershipJSON.swift:31`) **explicitly reserves
  `killOutcome` / `contradiction` as owed by S04** (doc-comment `:24-30`);
  `OwnershipKillRowJSON.endReason` defaults to `"killed"` (`:149`).
- `TeamRun` (`TeamRun.swift`) has **no** `killOutcome` / `contradiction` field yet
  (grep clean); it has `endReason` (`:133`), `status` (`:66`), `blocker` (`:137`),
  `lastActivityAt/Kind` (`:144/146`), `workers` (`:78`), `repoRoot` (`:108`). Run
  dir already has a **`workers/` subtree** (`RunStore.swift:167`,
  `workers/<id>.answer.md` / `.metadata.json`) — the natural home for
  `workers/<id>.owner.json`.

### 1.9 Warm pool — the exclusion seam (do NOT design warm ownership)

Warm drivers (grok/cursor/codex/claude) spawn via `ProcessACPTransport`
(`ProcessACPTransport.swift:13/51`), pid held only inside
`WarmWorkerPool.shared` in the app/CLI process — **zero durable identity, no
cross-process reach** (S00 matrix finding 1, verdict: **exclude all four from the
P0 Works Test**). The P0 fake CLI is not warm-capable
(`WarmWorkerCapability.supportsACPStdio == false`), so warm is **naturally out**
of the P0 harness. The only seam S04 needs: **a run with no recorded worker
`runtimeOwnership` yields `KillOutcome.verificationUnavailable`** (never a
`killed` stamp). Because warm workers record nothing, the generic
"no recorded worker identity ⇒ `verificationUnavailable`" rule in §2.2 covers
them for free — **no warm-specific code**. Follow-up warm-ownership slice
(posix_spawn + keyed record at ACP init) stays out of S04.

### 1.10 The red test's runtime reality (and a harness gotcha found during recon)

`testKillStampsTerminalKilledWhileLiveWorkerSurvives` (`:103-165`):
`alln team start` (async, site C) → worker child (`sleep 4933`), fake worker
`trap '' TERM` + a **`setsid`** grandchild (`sleep 4934`). Kill via a **third**
process `alln kill <runId>`. Asserts: survivors non-empty (precondition), then
`endReason != .killed` and `!status.isTerminal`.

**Gotcha (verified this recon):** `setsid` is **absent on macOS** (not in the
fixture PATH `<fakebin>:/usr/bin:/bin:/usr/sbin:/sbin`, not shipped by macOS).
On the dev/CI Mac the grandchild spawn **silently fails** — so the *only*
surviving process today is the worker itself, and it survives **because the
current coordinator-only kill never reaches its group.** This has a direct design
consequence (§2.4): once S04 records + reaps the worker group, a
correctly-reaped worker would leave **no survivor on macOS**, tripping the test's
own `XCTAssertFalse(survivors.isEmpty)` precondition. The green path therefore
depends on the survivor being **detectable-but-unreaped inside the kill's bounded
window**, and the S04b harness step must make that deterministic (portable
escapee and/or a worker that stays identity-alive through the grace) — see §2.4.

---

## PART 2 — EXECUTION PLAN (S04a → S04b → S04c, strict order)

Design spine: **compose the existing primitives, don't build a second ownership
system.** `runtimeOwnership` is a per-worker owner file written through the same
`spawnProcessGroupLeader` the relay path already uses; the kill/cancel verbs
become **one settlement routine** over `terminateOwnerIdentityIfSafe` +
`processGroupMemberPids`; the contradiction is a **read-time derivation** over
retained receipts (the `heldSinceSeconds` / S03 `progressStale` pattern). Each
sub-slice is independently committable + testable. Wire law: `OwnershipProcessJSON`
field **names** are frozen — `killOutcome` / `contradiction` were **pre-reserved**
(`OwnershipJSON.swift:29-30`), additive only.

---

### S04a — `runtimeOwnership`: record worker OS identity keyed by worker id (foundation)

**Goal:** every cold worker gets a durable `{pid, pgid, startTimeTicks, kind}`
record **keyed by worker id** at spawn, coordinator recorded as a **separate**
owner; the async worker spawn stops detaching from a killable tree; identity-alive
becomes zombie-aware. **No kill behaviour changes yet — the red test stays red.**

**Files + types:**

1. **New Core record shape (reuse `ProcessOwnerRecord`, add worker key).** A tiny
   `RuntimeOwnership` value in Core: `{ workerId: String, record: ProcessOwnerRecord }`
   (`ProcessOwnerRecord` already exists, `Enums.swift:110`). Persisted at
   **`workers/<safeStem(workerId)>.owner.json`** in the run dir (mirrors the
   existing `workers/<id>.metadata.json` convention, `RunStore.swift:167`).
   Coordinator stays at the run-dir-root `owner.json` (unchanged) — that IS the
   "coordinator is a separate owner" requirement.

2. **The worker-owner recording seam** (`ProcessOwnership.swift`, new statics
   next to `recordSpawnedTurnOwner`):
   ```swift
   /// Process-global context: the run dir + current worker id a PG spawn should
   /// record its runtimeOwnership under. Mirrors TurnOwnerDirectory, but keyed.
   public final class RuntimeOwnershipContext: @unchecked Sendable {
       public static let shared = RuntimeOwnershipContext()
       public func runDirectory() -> URL?          // set by RunService / async runner
       public func set(runDirectory: URL?)
   }
   @TaskLocal public static var currentWorkerId: String?   // set by the coordinator per invoke
   public static func recordSpawnedWorkerOwner(_ identity: OwnerIdentity)  // writes workers/<id>.owner.json
   public static func readWorkerOwners(inRunDirectory: URL) -> [(workerId: String, identity: OwnerIdentity)]
   public static func clearWorkerOwner(workerId: String, inRunDirectory: URL)  // NOT called on terminal (retain)
   ```
   Split of responsibility (both known-facts already live at their layers):
   - **run dir** is known by `RunService` / the async runner → set on
     `RuntimeOwnershipContext.shared` before the coordinator runs.
   - **worker id** is known by `CatalogRunCoordinator` → set as the
     `currentWorkerId` **task-local** around each `runner.collect(WorkerInvocation)`
     (`CatalogRunCoordinator.swift:227` / `:312`). Task-locals are captured
     synchronously into the spawn, so **parallel fan-out workers each carry their
     own id** — no process-global race (P0 is single-worker; this is fan-out-safe
     for free).
   - `spawnProcessGroupLeader` (`:849-858`) additionally calls
     `recordSpawnedWorkerOwner(identity)` when both context + task-local are set
     (alongside the existing `recordSpawnedTurnOwner`).

3. **Swap the async worker base runner** (`AsyncTeamService.swift:85`):
   `SubprocessCommandRunner(…)` → **`ProcessGroupCommandRunner(environmentPolicy:
   AllnighterSpawnEnvironmentPolicy(), spawnKind: .devTurn)`**. This is the
   **decision on the setpgid-detachment question (RLR-L5): record the worker's OWN
   group.** Justification: `spawnProcessGroupLeader` makes `pgid == pid` **atomically
   at creation** (no racy post-hoc `setpgid`), and we **record that pgid** keyed by
   worker id — so the recorded tree is exactly what a killer signals. We do **not**
   try to keep the worker inside the coordinator's group: the settlement protocol
   (step 2) terminates **worker** groups first and leaves a responsive coordinator
   alive to emit its terminal, so worker and coordinator must be **separately
   addressable** groups. Recording the worker's own group is precisely L5.

4. **Record the coordinator as a separate owner on the cold foreground path.**
   `RunService` is itself the (in-process) coordinator; write its
   `OwnerIdentity.current(kind: .inProcess)` to the run-dir `owner.json` at mint
   (it is never PG-killed — `inProcess.isProcessGroupKillable == false`,
   `:62-67` — but it is a receipt the contradiction surface reads). The async
   coordinator already writes `owner.json` (`:610`) — unchanged.

5. **Zombie-aware identity-alive (Gap A, §1.7).** Add
   `ProcessOwnership.processIsZombie(_ pid) -> Bool` (reads `kp_proc.p_stat ==
   SZOMB` via the existing sysctl) and fold it into `isIdentityAlive`
   (`:279-283`): `… ∧ !processIsZombie(pid)`. This is shared by kill-verify,
   `ps`, and S06 orphan scan (single definition, RLR-L5). Audit callers of
   `isIdentityAlive` for the semantic tightening (a zombie now reads dead — the
   correct answer; reconcile/GC already want zombies reaped).

6. **Fold in the spawn-policy debt (§1.3).** `SpawnResolvingCommandRunner.swift:21`:
   drop the bare default → `inner: any StreamingCommandRunner =
   SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy())`
   (or make `inner` non-defaulted — `WorkerInvokerFactory` always passes it).
   **Verdict: YES, fold here** — it is the same worker-spawn composition S04a is
   rewiring, and every RLR sub-slice's acceptance runs `bash scripts/check.sh`,
   which is red until this is fixed. Trivial + on the critical path. (This is env-
   policy hygiene, not the killable-identity fix — noted so it isn't conflated.)

**`ps` gains the worker rows.** `ProcessOwnershipSurface.listRuns`
(`:140-181`) additionally emits one `OwnershipProcessJSON` per
`workers/<id>.owner.json` (kind `"worker"`, `identityAlive` zombie-aware), so
`alln ps` shows the recorded worker tree (Works Test 12 substrate). Frozen names,
additive rows.

**Tests (S04a):**
- `RuntimeOwnershipRecordingTests` (Engine): drive a fake-CLI cold `alln run` and
  a fake-CLI `alln team start`; assert `workers/<id>.owner.json` exists with
  `pgid == pid`, matching `startTimeTicks`, `kind`, and that `readWorkerOwners`
  round-trips; assert the coordinator `owner.json` is a **separate** file.
- `testAsyncWorkerIsProcessGroupLeaderNotDetached`: the recorded worker `pgid ==
  its pid` and its `sleep` child shares that pgid (i.e. group-reachable), proving
  the site-C detachment is gone.
- `ZombieIdentityTests` (pure/seam): a `<defunct>` pid reads `isIdentityAlive ==
  false`; a live matching pid reads true; recycled pid false.
- `ps` fixture: shows worker rows with correct `identityAlive`.
- `bash scripts/check.sh` (green — spawn-policy fold).

**Acceptance proof:**
```bash
swift test --package-path Packages/AllnighterCore --filter RuntimeOwnership
swift test --package-path Packages/AllnighterCore --filter ProcessOwnershipSurface
bash scripts/check_spawn_policy.sh
```
Red test unchanged (still red): `RLR_RED=1 … --filter RunLifecycleTwoProcess`
(signature (b) red — `killRun` not yet touched).

---

### S04b — `KillOutcome` + one settlement routine (cancel vs kill) — **FLIPS THE RED TEST**

**Goal:** `alln kill` (immediate) and `alln team cancel` (grace-then-escalate)
become one identity-checked, per-member-verified settlement that returns a typed
`KillOutcome` and stamps `endReason: killed` / `cancelled` **only on verified
stop**. `partial` / `refused` / `verificationUnavailable` leave the lifecycle
**non-terminal**. This turns
`testKillStampsTerminalKilledWhileLiveWorkerSurvives` green.

**Files + types:**

1. **`KillOutcome` (Core, `OwnershipJSON.swift` or a new `KillOutcome.swift`):**
   ```swift
   public enum KillOutcome: String, Codable, Sendable, CaseIterable {
       case stopped, partial, refused, verificationUnavailable
   }
   ```
   `TeamRun` gains `public var killOutcome: KillOutcome? = nil` (additive, legacy
   decodes nil, frozen names untouched).

2. **The settlement routine** — one engine function both verbs call
   (`ProcessOwnership` + a small `RunKillSettlement` helper), implementing the
   RLR-L5 8-step protocol:
   ```swift
   struct KillSettlement {
       enum Mode { case kill /* immediate */, case cancel /* grace-then-escalate */ }
       static func settle(runDirectory: URL, mode: Mode, now: …) -> KillOutcome
   }
   ```
   Steps mapped to the primitives (§1.6):
   1. **Snapshot** recorded identities: coordinator `owner.json` +
      `readWorkerOwners(inRunDirectory:)`.
   2. **Terminate worker groups first** (not a responsive foreground coordinator):
      `terminateOwnerIdentityIfSafe` per worker owner. `mode == .cancel` uses a
      longer TERM grace before escalation; `mode == .kill` is the current
      `terminateProcessGroup` (TERM → 200 ms → KILL).
   3. **The killer stamps** the terminal revision + `killOutcome` **itself**, under
      `withRunLock`, **only when the verify below is `.stopped`** (operator-vs-clock
      asymmetry — an operator kill's claim *is* the stop).
   4. A **responsive** coordinator (identity-alive, `kind == .detachedRunner`) is
      **not force-killed** — it observes worker exit, emits its single terminal
      NDJSON event (S03b one-terminal guard), and exits. The killer detects "coord
      responsive" via `isIdentityAlive(coordinator)` and leaves it.
   5. Force-kill the coordinator only if **orphaned** (identity-dead) or past a
      bounded grace.
   6. **Idempotent concurrent killers:** under `withRunLock`, if the run is already
      terminal, re-verify survivors and return the *observed* `KillOutcome`
      **without** a second terminal stamp (do not clobber; do not double-signal a
      recycled pgid — the `terminateOwnerIdentityIfSafe` mismatch guard already
      refuses).
   7. **Verify identity-alive per recorded member** (zombie-aware, S04a) **and**
      `isProcessGroupEmpty(recordedPgid)` per worker. Release admission / withdraw
      any FIFO ticket in the terminal revision (the S02c logic at
      `ProcessOwnershipSurface.swift:215-220` already does the FIFO withdraw — keep
      it, now gated on a `.stopped` terminal).
   8. **Retain** worker + coordinator owner receipts after terminal (do **not**
      `clearWorkerOwner` on terminal) so §2.3 can derive the contradiction.

   **`KillOutcome` decision (the verified-stop rule):**
   - `verificationUnavailable`: **no** recorded worker `runtimeOwnership` for the
     run (warm workers / unrecorded legacy). Never stamps terminal `killed`.
     *(This is the warm exclusion seam, §1.9 — no warm-specific code.)*
   - `refused`: recorded members exist but **none** could be signalled (all
     identity-mismatch / non-PG-killable) — nothing was stopped. Non-terminal.
   - `partial`: signalled, but ≥1 recorded member is **still identity-alive** OR a
     recorded worker group is **non-empty** after the grace. Non-terminal; survivors
     named; `killOutcome` recorded.
   - `stopped`: **every** recorded member identity-dead **and** every recorded
     worker group empty. Stamp terminal (`endReason: killed` for `kill`,
     `cancelled` for `cancel`). Zombie-only residual → `.stopped` **with a cleanup
     warning** (RLR-L5).

3. **Rewrite the two stampers to call `settle`:**
   - `ProcessOwnershipSurface.killRun` (`:183-224`): replace the unconditional
     `.cancelled`/`.killed` stamp with `let outcome = KillSettlement.settle(…,
     mode: .kill)`; stamp terminal **only** on `.stopped`; otherwise persist
     `current.killOutcome = outcome` and **leave status/endReason unchanged**
     (non-terminal). `OwnershipKillRowJSON` gains `killOutcome` (additive) and its
     `endReason` becomes optional/absent when not `.stopped`.
   - `AsyncTeamService.cancel` (`:895-923`): same, `mode: .cancel`. Keep the
     in-process `active.task.cancel()` fast path (same-process runs) but route its
     terminal decision through the same verify.
   - `killAll` (`:110-136`): unchanged control flow; inherits honest `killRun`.

4. **CLI + error envelopes** (`AllnighterCLI.runOwnershipKill:1403`,
   `runTeamCancel:1307`): surface `killOutcome`. Map `KillOutcome.refused` →
   **`KILL_REFUSED`** and `.partial` → **`KILL_PARTIAL`** (non-zero exit for
   scripted callers, the error-envelope projection per RLR-L5 / spec error
   catalog) — same fact from the same journal revision, not a second truth.
   `.verificationUnavailable` surfaces as a distinct honest code (e.g.
   `KILL_VERIFICATION_UNAVAILABLE`) or rides `KILL_REFUSED` with a reason — **pick
   one and regenerate the catalog** (`docs/generated/alln/*`).

**What flips green + ungates.** `killRun` no longer stamps `killed` over an
unverified/live tree ⇒ signature (b) green. Ungate in S04b:
- **Works Test 6** (`alln kill <id>` → verified stop or typed survivors) — kill
  leg + the `contradiction` leg deferred to S04c.
- **Works Test 5** (idle-budget kill → typed `KillOutcome`, lane releases) — the
  clock isn't wired until S05, but the *kill-tree + KillOutcome + lane-release*
  mechanics land here; gate the clock-fire itself to S05.
- **Works Test 8** (`kill --all` same-root scope, other root protected) — the
  scope filter already exists (`killAll(scopeRoot:)`); assert honest outcomes.
- **Works Test 11 (kill leg)** — exactly-one terminal NDJSON on kill: only on a
  `.stopped` outcome does the responsive coordinator emit the single terminal
  (S03b's guard); on `partial`, no terminal event, run stays live. Add the kill
  case to `testExactlyOneTerminalPerAttachment`.
- **Works Test 7** (orphaned-coordinator recover + kill worker from a second
  process, responsive coordinator not force-killed) — settlement steps 4-5.

**Tests (S04b):**
- **`RunLifecycleTwoProcessTests.testKillStampsTerminalKilledWhileLiveWorkerSurvives`
  → GREEN** (remove/relax the `RLR_RED` skip for signature (b), or keep gated and
  add a green assertion twin — decide with PM; the spec wants it in the default
  suite eventually via S06).
- `KillSettlementTests` (Engine, `terminateSignalHook`-driven, no real signals):
  drive each outcome — all-dead → `.stopped` + terminal; one live recorded worker
  → `.partial` + non-terminal + `killOutcome` persisted; identity-mismatch owner →
  `.refused`; no worker owners → `.verificationUnavailable`; zombie-only → `.stopped`
  + cleanup warning.
- `testCancelGraceThenEscalate` vs `testKillImmediate` (distinct grace windows).
- `testConcurrentKillersIdempotent`: two `alln kill` on one run → one terminal
  stamp, both return the same observed outcome, no double terminal.
- `testPartialLeavesLifecycleNonTerminal`: after `partial`, `status` is still
  `running`/`queued`, survivors visible in `ps`.

**Acceptance proof:**
```bash
RLR_RED=1 swift test --package-path Packages/AllnighterCore --filter RunLifecycleTwoProcess   # (a)+(b) green
swift test --package-path Packages/AllnighterCore --filter KillSettlement
swift test --package-path Packages/AllnighterCore --filter ProcessOwnershipSurface
bash scripts/check.sh
```

---

### S04c — contradiction surface + receipts retention + warm honesty assertion + contract regen

**Goal:** `status.contradiction: terminalWithLiveOwnership` is **derived at read
time** from retained receipts + zombie-aware identity-alive; warm kill honesty is
asserted; wire/contract/docs regen.

**Files + edits:**

1. **`contradiction` derivation** (`AllnighterCore`, a pure helper `RunContradiction`
   alongside `RunActivity`):
   ```swift
   enum RunContradiction: String, Codable, Sendable { case terminalWithLiveOwnership }
   static func contradiction(run: TeamRun, workerOwners: […], coordinator: …, now:) -> RunContradiction?
   ```
   Returns `terminalWithLiveOwnership` when `run.status.isTerminal` **and** any
   retained recorded member is still identity-alive (zombie-aware). Derived — no
   stored boolean. This is the negative proof for the "Owner → kill: terminal ⇒
   nothing survives" inference ban.

2. **Surface it** additively (frozen names, pre-reserved):
   - `OwnershipProcessJSON.contradiction: String?` +
     `killOutcome: String?` (`OwnershipJSON.swift`, the S04-owed additions) —
     populated in `listRuns` (`:140`) from retained receipts.
   - `TeamStatusResponse` gains `contradiction: String?` + `killOutcome: String?`
     (`AsyncTeamContracts.swift:127`), set in `AsyncTeamStatusMapper`.
   - Same two on the `alln run --json` / `team status` wire per the spec's wire
     block.

3. **Receipts retention policy.** Keep `workers/<id>.owner.json` + coordinator
   `owner.json` after terminal; a bounded reaper (S06 GC territory) may clear them
   once identity-dead **and** past a retention window (long enough to observe the
   contradiction — reuse the `stageLeaseSeconds`-style constant). S04c only needs
   **retain**; document the window, defer the reaper to S06.

4. **Warm honesty assertion (the exclusion seam made explicit).** A test proving a
   run with **no** recorded worker `runtimeOwnership` (simulated warm) → `alln
   kill` returns `verificationUnavailable`, never stamps `killed`, and the P0
   Works Test does not cover warm. No warm code — just the assertion + a doc note
   in the matrix that S04 formalized the exclusion.

5. **Contract + docs regen.** Add `killOutcome` / `contradiction` /
   `KILL_REFUSED` / `KILL_PARTIAL` to `ContractSchema.swift` /
   `HelpTopicRegistry` as needed; regenerate `docs/generated/alln/*`; extend the
   contract-drift/parity test. Additive-only (all-optional keys).

**Tests (S04c):**
- `RunContradictionTests` (pure): terminal + live retained owner →
  `terminalWithLiveOwnership`; terminal + all-dead → nil; non-terminal → nil;
  zombie owner → nil (zombie reads dead).
- `testContradictionSurfacesAfterClockKilledWithSurvivor` (shape now; the clock
  itself is S05): a terminal `timedOut` run with a live recorded worker reports
  the contradiction (Works Test 6 contradiction leg).
- `testWarmKillReturnsVerificationUnavailable`.
- `Contract` drift green after regen.

**Acceptance proof:**
```bash
swift test --package-path Packages/AllnighterCore --filter RunContradiction
swift test --package-path Packages/AllnighterCore --filter Contract
bash scripts/check.sh
```

---

## §2.4 — The red-test green path: an explicit, honest walk-through (READ THIS)

The test is subtle and macOS-specific (§1.10). The chain that makes it **green**:

- **S04a** records the worker owner → the killer now *knows a worker tree exists*.
- **S04b** replaces the unconditional `killed` stamp with the verify: it stamps
  `killed` **only** when every recorded member is verified dead **and** its group
  empty; otherwise `partial`, non-terminal.

**The determinism hazard.** Today the survivor exists because the coordinator-only
kill never reaches the worker. Once S04 records + reaps the worker group, a
cleanly-reaped worker leaves **no survivor on macOS** (the fixture's `setsid`
grandchild does not spawn there), which would trip the test's own
`XCTAssertFalse(survivors.isEmpty)` precondition. So the S04b **harness step must
make the survivor deterministic and detectable-but-unreaped within the kill's
bounded grace**, and the KillOutcome decision must read it **before** any reaping
`SIGKILL`. Two concrete, spec-true options (pick in implementation, confirm
against the live test):

- **(preferred) Worker stays identity-alive through the grace.** Have the fake
  worker `trap '' TERM` **and** re-loop its sleep (no signalable child that lets
  `wait` return and the shell exit), so during `alln kill`'s TERM→grace window the
  **recorded worker is still identity-alive** → the settlement verify observes a
  live recorded member → `.partial` → non-terminal. Deterministic on macOS, no
  `setsid`. The survivor is a **recorded** member — honestly named in `ps`.
- **(belt-and-suspenders) Portable escapee.** Replace `setsid /bin/sh -c …` with a
  portable session detach (`perl -MPOSIX -e 'POSIX::setsid(); exec "sleep","4934"'`)
  so the grandchild genuinely escapes where `perl` exists. Note: a **fully-escaped**
  setsid orphan (reparented to init, own session) is undetectable by *any* process
  and is **beyond P0's process-group ownership model** — it must not be the thing
  the assertion depends on. Keep it as extra realism, not the load-bearing survivor.

**UNDETERMINED — implementer must confirm against the live test:** the exact
process mechanics of the fake worker under a real group `SIGTERM`/`SIGKILL` on the
target OS (I verified `setsid` is absent on this macOS and reasoned through the
`sleep & wait` + `trap` behaviour, but did not run the built `alln` + real
settlement). The safe design (preferred option above) makes the survivor a
recorded, identity-alive member so `.partial` is provable without relying on an
undetectable escapee. Adjust `scripts/rlr_fake_worker.sh` accordingly in S04b (a
script, not `Sources/Tests` — in-scope for the implementation slice).

---

## RISKS

**Existing kill-caller expectations (blast radius of the honest stamp):**
- **GUI kill buttons / relay watchdog / reconcile / GC** all funnel through
  `ProcessOwnershipSurface.kill` / `AsyncTeamService.cancel` /
  `terminateRecordedOwnerIfSafe` / `reconcileRun`. After S04b a kill that used to
  *always* stamp terminal may now leave the run **non-terminal** (`partial`). Any
  caller that assumed "kill ⇒ terminal" (e.g. a GUI that greys out a row on kill,
  or `reconcile` that expects the run gone) must handle `partial`/`refused`.
  `reconcile`'s `reconciledOrphan` path (identity-dead owner) is **unaffected** —
  it already gates on identity-dead; only the operator verbs change.
- **`alln kill --all` scope:** `killAll(scopeRoot:)` (`:110`) already scopes by
  project root (Concurrent Invocation Isolation F1); the honest per-row outcome
  must not regress the scope filter or the machine-wide `--all-projects` path.
- **`OwnershipKillRowJSON.endReason` default `"killed"`** (`OwnershipJSON.swift:149`)
  is now a lie for non-`.stopped` rows — make it reflect the actual outcome
  (absent/`null` unless `.stopped`). Additive `killOutcome` field; frozen names
  untouched (`killOutcome`/`contradiction` pre-reserved).

**The KillOutcome wire addition vs frozen names:** additive-only on
`OwnershipProcessJSON` (pre-reserved), `TeamStatusResponse`, `TeamRun`,
`OwnershipKillRowJSON`; regen the catalog. A strict scripted caller that rejects
unknown keys could break — mitigate with the additive contract + drift test
(same discipline as S03c).

**Top 3 risks:**
1. **Race between the killer's settlement stamp and the coordinator's own terminal
   write.** On the async path the coordinator (detached runner) is a *separate live
   process* that, on seeing its worker exit, will try to stamp its own terminal —
   which can (a) clobber the killer's `partial` non-terminal decision, or (b) hide
   a recorded survivor. Mitigation: **the run flock is the single serialization
   point** — both the killer and the coordinator's `persistDuringRun`/settlement
   take `withRunLock`, and the terminal write is guarded "never clobber an existing
   terminal" (already present, `AsyncTeamService.swift:913`) **plus** a new "the
   coordinator must not stamp terminal while a recorded worker is identity-alive or
   a `killOutcome: partial` marker exists." This is the crux invariant of S04b —
   test it explicitly (`testConcurrentKillersIdempotent` +
   `testCoordinatorDoesNotClobberOperatorPartial`).
2. **Semantic tightening of `isIdentityAlive` (zombie-aware) ripples to `ps`,
   reconcile, GC, S06 orphans.** A zombie now reads **dead** everywhere. This is
   correct (a defunct child is not doing work), but reconcile/GC will now reap
   zombie-owner runs they previously left alone. Mitigation: audit every
   `isIdentityAlive` caller in S04a; the "zombie-only residual → terminal with
   cleanup warning" rule (RLR-L5) is the intended behaviour; cover with
   `ZombieIdentityTests` + a reconcile regression.
3. **Recording the worker makes the kill actually lethal — which can erase the
   red test's survivor on macOS (§2.4).** If S04b reaps the worker cleanly and the
   fixture has no portable escapee, the test's own precondition trips. Mitigation:
   the S04b harness step makes the survivor a **recorded, identity-alive** member
   through the grace window (preferred option §2.4), so `.partial` is deterministic
   and honestly named — not dependent on an undetectable setsid orphan.

---

## Verdicts (for PM)

- **Cold-path ownership fix (3 sentences):** Today every worker's `OwnerIdentity`
  is either built-then-thrown-away in memory (cold `alln run` via
  `ProcessGroupCommandRunner`, persisted only when a relay turn-dir happens to be
  set) or never built at all (async `alln team start` via AgentOS
  `SubprocessCommandRunner`, which `setpgid`-detaches the worker into its own
  unrecorded group). S04a persists `{pid, pgid, startTimeTicks, kind}` **keyed by
  worker id** at `workers/<id>.owner.json` via the same `spawnProcessGroupLeader`
  primitive (context-dir set by the run layer + `currentWorkerId` task-local set by
  the coordinator), with the coordinator recorded as a separate root `owner.json`.
  We record the worker's **own** process group (`pgid == pid`, atomic at spawn) —
  the settlement kills workers separately from a responsive coordinator, so the two
  must be independently addressable.
- **Cancel-vs-kill design (3 sentences):** Both verbs collapse into one
  identity-checked settlement routine that snapshots recorded members, signals
  worker groups first (`cancel` = long TERM grace then escalate; `kill` = immediate
  TERM→grace→KILL), then verifies **per recorded member** (zombie-aware) that every
  group is empty. It returns a typed `KillOutcome`
  (`stopped|partial|refused|verificationUnavailable`) and stamps terminal
  (`killed`/`cancelled`) **only** on `stopped` (or zombie-only residual, with a
  cleanup warning); `partial`/`refused`/`verificationUnavailable` record the
  outcome and **leave the lifecycle non-terminal** so the operator retries or the
  clocks fire — the deliberate operator-vs-clock asymmetry. Concurrent killers are
  idempotent under the run flock (no second terminal stamp), and a responsive
  coordinator is left to emit its single terminal event, not force-killed.
- **Sub-slices:**
  - **S04a** — record worker `runtimeOwnership` keyed by worker id + coordinator
    separate; swap async worker base runner to `ProcessGroupCommandRunner`
    (kills the setpgid detachment); zombie-aware identity-alive; **fold the
    spawn-policy debt**. Red test stays red.
  - **S04b** — `KillOutcome` type + one settlement routine for `kill`/`cancel`
    (per-member verify, verified-stop-only terminal, non-terminal on
    partial/refused/verificationUnavailable, idempotent concurrent killers, warm
    exclusion for free). **Flips `testKillStampsTerminalKilledWhileLiveWorkerSurvives`
    green.**
  - **S04c** — `contradiction: terminalWithLiveOwnership` derived at read time from
    retained receipts; receipts retention; warm honesty assertion; wire/contract/
    docs regen.
- **Which sub-slice flips the red test:** **S04b.** (S04a is the foundation the
  honest verify reads; S04c is read-side derivation + wire.)
- **Spawn-policy fold-in verdict:** **YES — fold into S04a.** The bare
  `SubprocessCommandRunner()` at `SpawnResolvingCommandRunner.swift:21` sits in the
  exact worker-spawn composition S04a rewires, and it fails `bash scripts/check.sh`
  — the acceptance gate every RLR sub-slice runs. It is a one-line env-policy
  hygiene fix (not the killable-identity fix; noted so the two aren't conflated),
  on the critical path, so it lands with S04a rather than tracked separately.
- **Warm exclusion seam:** warm workers record **no** `runtimeOwnership`, so the
  generic "no recorded worker identity ⇒ `KillOutcome.verificationUnavailable`,
  never `killed`" rule (S04b) covers all four warm drivers with **no warm-specific
  code**; the P0 fake CLI is not warm-capable, so the Works Test never enters the
  warm path. Real warm ownership (posix_spawn + keyed record at ACP init) stays a
  post-S04 follow-up.
- **Top 3 risks:** (1) killer-stamp vs coordinator-terminal-write race — the run
  flock + "coordinator must not clobber an operator `partial` / stamp over a live
  recorded worker" is the crux invariant; (2) zombie-aware `isIdentityAlive`
  tightens semantics across `ps`/reconcile/GC/S06 — audit all callers; (3)
  recording the worker makes the kill lethal, which can erase the red test's
  macOS survivor — the harness must present a recorded, identity-alive survivor
  through the grace (not an undetectable `setsid` orphan; `setsid` is absent on
  macOS — verified this recon).
- **UNDETERMINED (what I checked):** the exact fake-worker process behaviour under
  a real built-`alln` settlement on the target OS — I verified `setsid` is absent
  on this macOS and reasoned through `trap ''/sleep & wait`, but did not run the
  real kill; the preferred §2.4 fixture design removes the dependency on that
  runtime by making the survivor a recorded, provably-alive member. Whether any
  out-of-tree GUI/relay tooling assumes "kill ⇒ terminal" — I audited `Packages/`
  callers (`ProcessOwnershipSurface`, `AsyncTeamService`, CLI); an app-side kill
  button that greys rows on kill should be re-checked in the GUI slice.
```