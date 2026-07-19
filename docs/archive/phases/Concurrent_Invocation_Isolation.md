# Concurrent Invocation Isolation — two `alln`s must behave like two `claude`s (P0)

Status: **SHIPPED 2026-07-19 — archived.** F1–F5b + two-process isolation gate
landed (including atomic same-key idempotency claim/replay). Hardened via Spec
Review (ChatGPT 5.6 Sol lead + 5 lenses, 2026-07-18) and re-audited by direct
Codex Sol review (2026-07-19, run `C5192F32`). Code is SSOT; mutation receipts
remain deferred observability, not a phase blocker.
Trigger: the founder ran `alln` across three projects in parallel all day
(Allnighter, Ikiro, XTerminal) and it kept breaking — live async runs died
`reconciledOrphan`, and a team reviewed the wrong doc. Two `claude`/`codex`
invocations in two folders never collide; two `alln` did — until F1–F5 + the
two-process gate. Remaining launch risk is same-key idempotency single-flight.

## The bar

> Two `alln` invocations in two different projects must be as isolated as two
> `claude` invocations. One invocation's runs, cleanup, and context must never
> touch another's — **but** resumable async work outlives its launcher, so
> isolation is scoped to the durable **canonical project root**, not to the
> ephemeral launching process.

## What is already correct (do NOT re-solve, and do NOT regress)

- **Per-process async ownership exists.** An async run is a detached
  `team __runner` process-group leader (`AsyncTeamService.spawnDetachedRunner`)
  that writes **its own** `OwnerIdentity.current(kind:.detachedRunner)` (pid +
  startTimeTicks) behind a readiness handshake the launcher blocks on. Liveness
  is **not** tied to the build identity — a rebuild does not change a live
  runner's pid/startTicks.
- **Reconcile reaps only reclaimable runs** via the lease-aware
  `ProcessOwnership.isReclaimable` decision (`staged lease → owned identity →
  terminal`). It never clobbers a terminal run. Do not regress to
  "missing ⇒ dead" prose.
- **`team start` does NOT sweep.** The only caller of `RunStore.reconcileAll` is
  the **explicit** `alln team reconcile` command. Starting a team run does not
  reconcile the machine. Keep this a standing **regression invariant** ("start
  never sweeps"), not a fix.
- **`serve` has no reconcile loop; lane keys are already canonical-root-specific.**
  Neither is the culprit (lane keys collide only in the `nil` / `unknown-root`
  case — a separate edge).
- **`ExecutionLane` and `RunWriteLock` deliberately share one canonical key
  system.** Do not introduce a second ownership/lane/registry system.
- **F1 / F3 project scoping landed.** `ps`, `kill --all`, and bare
  `team reconcile` default to the caller's canonical root; `--all-projects` is
  the explicit fleet opt-in. Unresolvable roots fail closed
  (`ProcessOwnershipSurface`, `RunStore.reconcileAll(scopeRoot:)`, CLI).
- **F2 stage-lease liveness landed** (`ProcessOwnership.livenessVerdict` /
  `isReclaimable`, `ProcessOwnershipStageLeaseTests`).
- **F4 context-provenance gate landed.** Detached packets carry
  `RunContextProvenance`; the runner refuses mismatches with
  `CONTEXT_PROVENANCE_MISMATCH` (`AsyncTeamService`).
- **F5 `IdempotencyStore.record()` RMW lock landed.** Per-file `flock` + atomic
  save (`IdempotencyStore.swift`); proved for concurrent distinct keys
  (`AsyncTeamLifecycleTests`).
- **Two-process isolation gate committed** (`a61ad9ef`):
  `ConcurrentInvocationTwoProcessTests.testTwoRealProcessesMutationAndContextIsolation`.

## The actual flaws (verified). Two distinct incidents — do not conflate.

### Incident A — cross-project blast radius from GLOBAL aggregate mutators (historical — fixed)

**Was:** aggregate operations were machine-wide instead of project-scoped:

- `ProcessOwnershipSurface.killAll()` killed every owned tree; `list()`
  enumerated every tree. `alln kill --all` from one project killed runs in all
  projects; `alln ps` showed the union across projects.
- Bare `alln team reconcile` → `reconcileAll()` swept every `run_*` under the
  shared store across all projects.

**Observed 2026-07-18:** the PM (Claude) `pkill`'d pilot/cursor processes and
`kill`'d runs while the founder's other-project runs were live; because
ownership surfaces and kills were machine-wide, those actions reaped live
cross-project work.

**Fixed by F1 + F3.** Scoped defaults + fail-closed unresolved roots. Do not
re-open as present-tense.

### Incident B — wrong-document delivery (REPRODUCED + gated 2026-07-18)

A team run reviewed the wrong doc — a concurrent orchestration's brief reached
another run. **Reproduced at the staged-packet seam:** `team __runner` trusted
`runner_request.json` blindly — it re-assembled the prompt from the DELIVERED
packet, never comparing it to the run's own minted journal, so a packet staged
into the wrong run dir executed verbatim under that run's id (RED proof:
`RunContextProvenanceTests.testWrongDocumentDelivery_crossDeliveredPacketIsRejected`).
Whether the production incident crossed at exactly this seam is not established
(no ambient-state read was found in the context paths — relay prompts assemble
from per-relay state; thread context appends per explicit thread id), so the
fix is a hard gate at the one seam where context crosses a process boundary:
every staged packet carries immutable `RunContextProvenance` (resolved
**absolute root + content hash + thread/run id**); the runner refuses
(`CONTEXT_PROVENANCE_MISMATCH`) any packet that is not its run's own request —
run-id match, hash recompute, then a cross-check against the minted journal.
In-process runs never stage a packet (no process boundary) and are out of gate
scope.

### Remaining shared-state gap (post F1–F5)

- **`IdempotencyStore.record()` RMW is locked (shipped).** Distinct-key concurrent
  writers no longer lost-update the shared file.
- **Same-key claim is NOT yet atomic across processes (remaining P0).**
  `AsyncTeamService.start` does `lookup` first, then later mints/persists and
  calls `record`. Two simultaneous same-key starts can both see no entry and
  launch different runs. Existing tests prove sequential replay and distinct-key
  RMW safety, **not** simultaneous same-key single-flight.
- **Capacity governor policy is settled:** `TeamGovernor` remains one
  machine-wide slot directory with global `maxConcurrentTeamRuns`. Per-project
  scoping did **not** multiply spend. Do not invent per-project governors in
  this phase.

## The fix epic

**Scope model (foundational):** `Scope = canonical project root`
(`TeamRun.repoRoot` / `RelayState.projectRoot`). Aggregate commands default to
the caller's project scope; exact run-id operations remain explicit targets and
may cross projects when named. Unresolved / legacy / `unknown-root` scope must
**never** join an implicit aggregate mutation (fail closed). Enforce via
existing root metadata — **no physical registry partitioning or migration in
P0** (that would break the daemon's fleet/iOS inventory).

- **F1 — Scope the aggregate mutators to the project root.** ✅ Landed.
  `kill --all` and bare `alln team reconcile` operate on the caller's
  canonical-root scope; `alln ps` defaults to project-filtered
  (`--all-projects` opt-in). **Regression invariant:** `team start` never calls
  `reconcileAll`.
- **F2 — Real liveness lease contract.** ✅ Landed.
  `staged lease → owned identity → terminal` via `ProcessOwnership.isReclaimable`.
- **F3 — Enforce scope from root metadata, fail closed.** ✅ Landed.
- **F4 — Wrong-document investigation gate.** ✅ Landed.
  Immutable context provenance on every staged packet; mismatch →
  `CONTEXT_PROVENANCE_MISMATCH`.
- **F5a — Lock `IdempotencyStore.record()` RMW.** ✅ Landed
  (per-file flock / atomic save).
- **F5b — Atomic same-key idempotency claim/replay.** ✅ Landed 2026-07-19.
  Exactly one caller may mint/spawn for a given key+payload; concurrent
  identical callers must resolve to the same run; same-key/different-payload
  remains the existing typed conflict.
- **Forensics (deferred observability).** Persist a bounded **mutation receipt**
  for scoped `kill --all` / bare `team reconcile` (initiating scope, requested
  scope, target run ids, owner verdict, decision). Improves post-incident
  diagnosis; **does not enforce isolation** and is **not** required to close
  this phase.

## Acceptance proof — the isolation gate

Two layers (do not conflate):

1. **In-process:** `ConcurrentInvocationIsolationTests` /
   `testTwoProjectInvocationsAreMutationAndContextIsolated` — two services, one
   shared store.
2. **Real subprocess gate (committed):**
   `ConcurrentInvocationTwoProcessTests.testTwoRealProcessesMutationAndContextIsolation`
   — two real `alln` CLI subprocesses, two distinct repos, one shared support
   root, deterministic blocking fake workers (no real models). Asserts:

   - A `kill --all` / `team reconcile` in project A does **not** reap or alter
     project B's live run (mutation isolation).
   - A team run in project A receives **only** its own context (path + content
     hash match), never project B's brief (context isolation).

This invariant — not logs, dry-run mode, or blast-radius metrics — is what
proved F1–F4 + scoped ownership. **Phase closeout additionally requires the
F5b same-key single-flight Works Test below.**

**Landed 2026-07-18.** The subprocess gate asserts both isolations at three
layers: the durable journal, the staged packet's F4 provenance (absolute root +
content hash), and the spawned worker process's own argv/cwd.

## Why the daemon is not the sin

The shared coordinator is not gratuitous: `claude` needs none because it doesn't
promise resumable async runs, an iOS remote floor-manager (phone
querying/controlling Mac runs needs a resident daemon + queryable registry), or
fleet `ps`/`kill`/reap. Those need *some* shared state. `serve` itself has no
reconcile loop. The historical sin was that **aggregate ownership operations
were machine-global instead of project-scoped**. Keep the daemon; keep scoped
mutations; do not replace with per-project registries.

## Priority

**P0 closeout, pre-launch.** Cross-project mutation/context isolation is gated
and passing. Remaining launch fix: **atomic same-key idempotency claim/replay**.
Done = F5b Works Test green **and** the existing two-process isolation gate
still passes. Then archive this phase; move mutation receipts to a separate
deferred observability packet if still wanted.

**Cut from this phase:** per-project registries, per-project governors, daemon
replacement, SQLite migration, or any second ownership-key system.

## Closeout (F5b landed 2026-07-19)

`IdempotencyStore.claim` / `forceClaim` + `AsyncTeamService` claim-before-mint.
Works Test green:
`ConcurrentInvocationTwoProcessTests.testTwoRealProcessesSameKeyIdempotencySingleFlight`
(+ in-process `IdempotencyTests`). Mutation receipts stay deferred.

## History (why this was rewritten)

The original commit (`db8a47f8`) claimed `reconcileAll` fired from
`AsyncTeamService` **on team start**, and that "F1 + F4 removes the pain." Spec
Review (Sol lead + 5 lenses) verified that path is the **explicit**
`alln team reconcile` command, not startup — so the original F1 fixed a
non-existent call path. The 2026-07-18 revision retracted that thesis, split the
two incidents, reframed isolation around durable project-root scope, and made
the two-process test the gate.

**2026-07-19 Codex Sol audit** (`model_chatgpt` / `gpt-5.6-sol`, run
`C5192F32`): verified F1–F5a + the two-process gate as landed; reframed remaining
work as F5b atomic same-key claim; deferred mutation receipts; corrected board
lies that still said "F5 + commit the two-process gate remain."

Related: archived Process Ownership (per-process ownership this builds on).
