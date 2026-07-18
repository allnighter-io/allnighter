# Concurrent Invocation Isolation — two `alln`s must behave like two `claude`s (P0)

Status: **Proposed — P0 architecture, pre-launch.** Hardened via Spec Review (ChatGPT 5.6
Sol lead + 5 lenses, 2026-07-18) — this revision **retracts the original team-start causal
thesis** (see History) and reframes the fix around durable project-root scope and an
executable two-process proof.
Trigger: the founder ran `alln` across three projects in parallel all day (Allnighter,
Ikiro, XTerminal) and it kept breaking — live async runs died `reconciledOrphan`, and a
team reviewed the wrong doc. alln is effectively usable on **one project / one terminal at a
time**. Two `claude`/`codex` invocations in two folders never collide; two `alln` do.

## The bar

> Two `alln` invocations in two different projects must be as isolated as two `claude`
> invocations. One invocation's runs, cleanup, and context must never touch another's —
> **but** resumable async work outlives its launcher, so isolation is scoped to the durable
> **canonical project root**, not to the ephemeral launching process.

## What is already correct (do NOT re-solve, and do NOT regress)

- **Per-process async ownership exists.** An async run is a detached `team __runner`
  process-group leader (`AsyncTeamService.spawnDetachedRunner @ :302`) that writes **its own**
  `OwnerIdentity.current(kind:.detachedRunner)` (pid + startTimeTicks) behind a readiness
  handshake the launcher blocks on (`waitForRunnerReady @ :316`, owner claim `@ :409`).
  Liveness is **not** tied to the build identity — a rebuild does not change a live runner's
  pid/startTicks.
- **Reconcile reaps only a run whose own owner identity is dead**
  (`RunStore.reconcileRunDetailed @ :273` → `isOwnerIdentityDead`). It never clobbers a
  terminal run.
- **`team start` does NOT sweep.** The only caller of `RunStore.reconcileAll @ :291` is the
  **explicit** `alln team reconcile` command (`AsyncTeamService.reconcile(runId:) @ :656`,
  bare-id branch `@ :663`). Starting a team run does not reconcile the machine. Keep this a
  standing **regression invariant** ("start never sweeps"), not a fix.
- **`serve` has no reconcile loop; lane keys are already canonical-root-specific.** Neither is
  the culprit (lane keys collide only in the `nil` / `unknown-root` case — a separate edge).
- **`ExecutionLane` and `RunWriteLock` deliberately share one canonical key system.** Do not
  introduce a second ownership/lane/registry system.

## The actual flaws (verified). Two distinct incidents — do not conflate.

### Incident A — cross-project blast radius from GLOBAL aggregate mutators (verified)

The isolation break is that the **aggregate** operations are machine-wide instead of
project-scoped:

- `ProcessOwnershipSurface.killAll() @ :98` kills **every** owned tree on the box, and
  `list() @ :37` enumerates every tree. `alln kill --all` from one project kills runs in all
  projects; `alln ps` shows the union across projects.
- `alln team reconcile` (no run id) → `reconcileAll() @ :291` sweeps **every** `run_*` under
  the one shared store and reaps any whose owner reads dead — across all projects.

So one project's cleanup command reaches into another project's runs. **Observed 2026-07-18:**
the PM (Claude) `pkill`'d pilot/cursor processes and `kill`'d runs while the founder's
other-project runs were live; because ownership surfaces and kills are machine-wide, those
actions reaped live cross-project work. (The reap itself is *correct* once a runner is dead —
the bug is that an unrelated project could kill/observe it at all.)

### Incident B — wrong-document delivery (REPRODUCED + gated 2026-07-18)

A team run reviewed the wrong doc — a concurrent orchestration's brief reached another run.
**Reproduced at the staged-packet seam:** `team __runner` trusted
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

### Additional verified shared constraints (absent from the original F1–F5)

- **`IdempotencyStore.record()` is an unlocked global RMW** (`IdempotencyStore.swift:33` `load()`
  → mutate → `:39` `save()`, no lock/flock): two concurrent callers lost-update the shared
  idempotency file.
- **A machine-wide capacity governor** caps spend across the box. Making concurrency
  per-project must not silently multiply spend — decide the budget policy explicitly first.

## The fix epic (rewritten)

**Scope model (foundational):** define `Scope = canonical project root`
(`TeamRun.repoRoot` / `RelayState.projectRoot`). Aggregate commands default to the caller's
project scope; exact run-id operations remain explicit targets and may cross projects when
named. Unresolved / legacy / `unknown-root` scope must **never** join an implicit aggregate
mutation (fail closed). Enforce via existing root metadata — **no physical registry
partitioning or migration in P0** (that would break the daemon's fleet/iOS inventory).

- **F1 — Scope the aggregate mutators to the project root.** `kill --all` and bare
  `alln team reconcile` operate on the caller's canonical-root scope; `alln ps` defaults to
  project-filtered (a `--all-projects` opt-in for the fleet view). Machine-wide is explicit,
  never a default. **Regression invariant:** `team start` never calls `reconcileAll`.
- **F2 — A real liveness lease contract, replacing "missing ⇒ dead" prose.** Model liveness as
  `staged lease → owned identity → terminal`. A run within its staging lease (spawned,
  identity not yet written) is **not** reclaimable; a run with a live owner is alive; only a
  written-then-dead owner, or an expired stage lease with no owner, is reclaimable. Specify
  precisely when missing/unreadable identity is reclaimable. Update the Process Ownership
  dependency accordingly.
- **F3 — Enforce scope from root metadata, fail closed.** Filter every aggregate op by
  canonical root before it touches anything; a record whose scope can't be resolved is skipped,
  never swept.
- **F4 — Wrong-document investigation gate.** Before any fix: reproduce, then require immutable
  context provenance on every run — resolved **absolute path + content hash + thread/run id** —
  and reject a run whose delivered context doesn't match its own request.
- **F5 — Fix the verified shared-state defects.** Lock the `IdempotencyStore` RMW
  (per-file lock / atomic compare-write). Decide the capacity-governor budget policy before
  per-project concurrency.
- **Forensics (new).** Persist a bounded **mutation receipt** for every aggregate op:
  initiating scope, requested scope, target run ids, owner verdict, decision. So a
  cross-project reap is explainable after the fact, not a mystery.

## Acceptance proof — the P0 gate

`testTwoProjectInvocationsAreMutationAndContextIsolated`: **two real `alln` CLI subprocesses**,
**two distinct repos**, **one shared support root**, deterministic **blocking fake workers**
(no real models — they burn quota and add nondeterminism). Assert:

1. A `kill --all` / `team reconcile` in project A does **not** reap or alter project B's live
   run (mutation isolation).
2. A team run in project A receives **only** its own context (path + content hash match),
   never project B's brief (context isolation).

This invariant — not logs, dry-run mode, or blast-radius metrics (useful rollout aids, but
theater without the test) — is what proves the epic is done.

## Why the daemon is not the sin

The shared coordinator is not gratuitous: `claude` needs none because it doesn't promise
resumable async runs, an iOS remote floor-manager (phone querying/controlling Mac runs needs a
resident daemon + queryable registry), or fleet `ps`/`kill`/reap. Those need *some* shared
state. `serve` itself has no reconcile loop. The sin is that **aggregate ownership operations
are machine-global instead of project-scoped**. Keep the daemon; scope the mutations.

## Priority

**P0, pre-launch.** At launch users WILL run `alln` in multiple projects and dogfood it on
itself; today an aggregate command in one corrupts another's runs. Sequence after the current
doctor/GC hardening lands. Done = the two-process acceptance test passes.

## History (why this was rewritten)

The original commit (`db8a47f8`) claimed `reconcileAll` fired from `AsyncTeamService:663` **on
team start**, and that "F1 + F4 removes the pain." Spec Review (Sol lead + 5 lenses) verified
`:663` is the **explicit** `alln team reconcile` path, not startup — so the original F1 fixed a
non-existent call path. This revision retracts that thesis, splits the two incidents, reframes
isolation around durable project-root scope, adds the verified `IdempotencyStore`/governor
constraints, and makes the two-process test the gate. Line numbers cited are at `db8a47f8`.

Related: [Process_Ownership.md](Process_Ownership.md) (the per-process ownership this builds
on), [Sol_Review_Hardening.md](Sol_Review_Hardening.md).
