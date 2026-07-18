# Concurrent Invocation Isolation — two `alln`s must behave like two `claude`s (P0)

Status: **Proposed — P0 architecture, pre-launch.** (2026-07-18)
Trigger: the founder ran `alln` across three projects in parallel all day (Allnighter,
Ikiro, XTerminal) and it kept breaking — live async runs died `reconciledOrphan`, and a
team run reviewed the wrong doc. alln is effectively usable on **one project / one
terminal at a time**. Two `claude` or `codex` invocations in two folders never collide;
two `alln` invocations do. This doc is the fix epic.

## The bar

> Two `alln` invocations in two different projects must be as isolated as two `claude`
> invocations. One invocation's runs, cleanup, and context must never touch another's.

Claude Code / Codex are share-nothing per-process: own memory, own child processes, no
daemon, no global registry, no global identity. Nothing to collide over. `alln` funnels
work through **global shared state**, so concurrent orchestrations reap and hijack each
other. The number of CLIs is not the problem — the shared globals are.

## What is already correct (do NOT re-solve this)

The Process Ownership epic (`Process_Ownership.md`, PO-S01–S05) already gave async runs
**per-process** ownership — a common misdiagnosis is that liveness is tied to the build
identity; it is not:

- An async run is a **detached `team __runner`** process-group leader
  (`AsyncTeamService.swift:302` `spawnDetachedRunner … ["team","__runner","--run-id",id]`).
- The runner writes **its own** `OwnerIdentity.current(kind: .detachedRunner)`
  (pid + startTimeTicks) into the run dir (`AsyncTeamService.swift:409`), behind a
  readiness handshake the launcher blocks on (`waitForRunnerReady`, `AsyncTeamService.swift:316`).
- Reconcile reaps a run **only if its own recorded owner identity is dead**
  (`RunStore.reconcileRunDetailed` → `ProcessOwnership.isOwnerIdentityDead(in: directory)`,
  `RunStore.swift:273`). A rebuild does not change a live runner's pid/startTicks.

So the fix is **not** "add per-launcher ownership" (largely present). The fix is to stop
one invocation's **global sweeps and kills** from touching another's runs, and to close
the liveness edge cases that let a logically-live run read owner-dead.

## The actual flaws (verified, file:line)

1. **Global reconcile sweep.** `RunStore.reconcileAll()` (`RunStore.swift:291`) walks
   **every** `run_*` dir under the one shared store and reaps any whose owner reads dead —
   and it is fired from `AsyncTeamService` (`AsyncTeamService.swift:663`). So when caller B
   starts a team run, its reconcile pass sweeps caller A's runs machine-wide. Any run of A
   that momentarily reads owner-dead (see #4) is stamped `interrupted / reconciledOrphan`
   by B's unrelated team-start.
2. **Global kill.** `ProcessOwnershipSurface.killAll()` (`ProcessOwnershipSurface.swift:98`)
   and `list()` (`:37`) operate on **every owned tree on the machine**. `alln kill --all`
   from one project kills runs in all projects; `alln ps` shows the union (this is also why
   the count reads ~2000 — see [Process-tree accumulation]). A cleanup in one terminal is a
   machine-wide event.
3. **One shared registry + one daemon.** Every run, relay, project, and lane lives under a
   single `~/Library/Application Support/Allnighter/` tree, and a single resident
   `alln serve` coordinator manages async work machine-wide. All callers read/write the same
   tables; there is no per-invocation or per-project namespace on the run/relay stores.
4. **Liveness edge cases amplified globally.** A run can read owner-dead while logically
   alive — handshake/timeout races, a runner killed out from under its run (e.g. a manual
   `pkill`, a `serve` restart, or a `kill --all` from another project), pid reuse windows.
   Because reconcile is global (#1), any such blip is turned into a durable `reconciledOrphan`
   by the next team-start anywhere on the box. **Observed 2026-07-18:** the PM (Claude)
   `pkill`'d pilot/cursor processes, restarted `serve`, and rebuilt repeatedly while the
   founder's other-project runs were live; on a share-nothing tool those actions are inert,
   here they reaped live cross-project work.
5. **Per-project mutable state / context bleed (confirm exact path).** The founder saw a
   team run review the wrong doc — a concurrent orchestration's active brief injected into
   another run. The relay/pilot keeps per-project active state, and context assembly
   (`ThreadContextBuilder`/`ThreadContextPacket`) plus per-project relay docs are candidates.
   **Action:** trace whether any project-global mutable "active doc / work order" can be read
   by a team run instead of that run's own prompt/args/cwd, and make context strictly
   per-invocation. (Mechanism not yet pinned to a line — verify during implementation.)

## The fix epic (by impact)

- **F1 — Scope reconcile to the invocation, never a machine sweep on team-start.** A team
  start must not `reconcileAll()` the whole box. Options: reconcile only the runs *this*
  invocation owns/launched; or gate the global sweep behind an explicit `alln team reconcile`
  / doctor, never a side effect of starting unrelated work. Kills the cross-invocation reap.
- **F2 — Harden run liveness so a live run never reads dead.** Never reap a run within a
  grace of its readiness handshake; treat "identity present + process alive" as the only
  live signal; require a positive dead-proof (identity written AND its process gone), not
  "missing ⇒ dead," inside any cross-invocation-reachable path. Fold in "never react to the
  binary being rebuilt" (already true, keep it true).
- **F3 — Scope kill/reap.** `kill --all` means "this invocation's trees." Cross-invocation
  or machine-wide kill must be explicit and opt-in (e.g. `alln kill --all --machine`), never
  the default and never a sweep side effect.
- **F4 — Per-invocation context, no shared active-work-order bleed.** A team/relay run's
  context is its prompt/args/cwd + its own thread — never a project-global mutable brief set
  by another orchestration. (Resolve #5 first.)
- **F5 — Namespace the registry per project/launcher.** Partition run/relay tables so a sweep
  or listing in one project cannot enumerate or mutate another's. The daemon and remote/iOS
  floor-manager (the legitimate reasons a shared coordinator exists) query across namespaces
  explicitly, but per-invocation operations stay scoped.

**Do F1 + F4 and the founder's exact pain disappears** — PM-relay and a Growth Panel could
run side by side in two projects like two Claudes. F2/F3/F5 harden the rest.

## Why the daemon is not the sin

The shared coordinator is not gratuitous: `claude` doesn't need one because it doesn't
promise resumable async runs (close the lid, run continues), an iOS remote floor-manager
(phone querying/controlling Mac runs needs a resident daemon + a queryable registry), or
fleet `ps`/`kill`/reap of genuinely-crashed runs. Those features require *some* shared
state. The sin is that ownership/cleanup is **coarse and global**: the janitor that should
reap only crashed runs sweeps the whole machine, and per-invocation context is a mutable
singleton. Keep the daemon; scope the ownership.

## Priority

**P0, pre-launch.** At launch, users WILL run `alln` in multiple projects and dogfood it on
itself; today that corrupts their runs. This is the difference between "a real coding CLI"
and "usable in one window." Sequence after the current doctor/GC hardening lands.

Related: [Process_Ownership.md](Process_Ownership.md) (the per-process ownership this builds
on), [Sol_Review_Hardening.md](Sol_Review_Hardening.md).
