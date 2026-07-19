# RLR-S00 Spawn-Site Matrix — every worker/coordinator OS process spawn

Status: **S00 evidence artifact (hard exit criterion for RLR-S00).** Read-only
audit of the code as of branch `feat/design-chain` (2026-07-19). No source was
modified to produce this.

SSOT: `docs/archive/phases/Run_Lifecycle_Reliability.md` — RLR-L5 requires
`runtimeOwnership = {pid, pgid, startTimeTicks, kind}` recorded **keyed by
worker id**, with the coordinator as a **separate** owner, and a cross-process
kill path that verifies identity-alive before signalling.

Scope: every site in `Packages/AllnighterCore/Sources` (plus the AgentOS
`SubprocessCommandRunner` / warm-serve spawners the engine composes in) that
starts a **worker** or **coordinator** OS process. Auxiliary spawns (git
observation, `@file` resolution, `cp`, PATH probes) are listed at the bottom and
are explicitly out of the RLR ownership contract.

---

## HEADLINE FINDINGS — spawn paths with NO durable ownership identity

These are flagged at the top per the S00 brief. In **none** of them is a
`{pid, pgid, startTimeTicks, kind}` record ever persisted **keyed by the worker
id**. Today only *coordinators* ever get a durable owner file; **no worker in
any path is recorded keyed by worker id.**

1. **Warm ACP / app-server / stream-json workers (grok, cursor, codex, claude)
   — ZERO durable ownership.** All four warm drivers share one spawner,
   `ProcessACPTransport` (`ProcessACPTransport.swift:13`/`:51`). The child pid
   lives only inside the `ProcessACPTransport` instance, held by a `WarmWorker`
   inside the **process-global `WarmWorkerPool.shared`**. Nothing is written to
   disk. Another OS process cannot enumerate, poll, or kill these workers.
   `setpgid` is best-effort (`:56`) and racy (Foundation.Process has no atomic
   SETPGROUP at spawn). This is the exact worker class in the founder repro
   (`kimi` is cold, but the warm dialects have strictly *less* recorded
   identity).

2. **Async team-run worker CLIs via `SubprocessCommandRunner` — ZERO ownership
   recording.** `AsyncTeamService` defaults its worker `commandRunner` to
   AgentOS `SubprocessCommandRunner` (`AsyncTeamService.swift:86`), which spawns
   with `Foundation.Process` + best-effort `setpgid`
   (`SubprocessCommandRunner.swift:349/392/395`) and records **no** identity at
   all. Worse: `setpgid(pid,pid)` moves the worker into **its own** group,
   detaching it from the coordinator's group — so a coordinator group-kill does
   **not** reach the worker. The coordinator's own owner file is durable; the
   worker under it is invisible and orphan-prone.

3. **Cold foreground `alln run` worker via `ProcessGroupCommandRunner` — identity
   is BUILT but not durably persisted on the plain-run path.**
   `ProcessGroupCommandRunner` (RunService's default,
   `RunService.swift:164`) spawns through the good primitive
   (`ProcessOwnership.spawnProcessGroupLeader`, posix_spawn + SETPGROUP) and
   *constructs* a full `OwnerIdentity`, but it only **persists** it when
   `ProcessOwnership.TurnOwnerDirectory.shared` is set, which happens **only in
   the relay/pilot path** (`RelayCoordinator.swift:1143`). For a plain
   `alln run`, the identity stays in-memory inside the streaming task and is
   never written keyed by worker id → not pollable and not killable from another
   process. **This is the precise founder-repro gap** (`kill --all` →
   `killedCount: 0` while a live child remains).

4. **`opencode serve` daemon — pid-only, in-memory.** AgentOS
   `OpenCodeServeCoordinator.defaultLaunchServe`
   (`OpenCodeServeCoordinator.swift:210/223`) spawns a persistent HTTP daemon
   with `Foundation.Process`, recording only `pid` in a `LaunchedServe` value
   (`:231`); teardown is `process.terminate()` / `terminateProcess(pid)`
   (pid-only, no identity verify). Only in play if `opencode` is a configured
   driver.

**Bottom line for S04:** the coordinator side is already durably killable in the
detached-runner path; the **worker side is not recorded keyed by worker id in
any path**, which is the whole of RLR-L5's `runtimeOwnership` requirement.

---

## The one real spawn primitive

`ProcessOwnership.spawnProcessGroupLeader(...)` — `ProcessOwnership.swift:717`
(actual `posix_spawn` at `:834`). `posix_spawn` + `POSIX_SPAWN_SETPGROUP` so the
child is its own process-group leader (`pgid == pid`) atomically at creation. It
returns `SpawnedProcessGroup { pid, identity: OwnerIdentity, stdio FDs }` where
`identity = {pid, pgid == pid, startTimeTicks, kind}`
(`OwnerIdentity.forSpawnedLeader`, `:849`). It **does not** write any durable
owner file itself; the only durable write it triggers is the *turn-owner* file,
and **only** when `kind == .devTurn` and `TurnOwnerDirectory.shared` is set
(`recordSpawnedTurnOwner`, `:166` / `:852` / `:858`).

Every good spawn in-repo funnels through this. The two spawners that do **not**
are AgentOS `SubprocessCommandRunner` and `ProcessACPTransport`, both of which
use `Foundation.Process` and best-effort `setpgid` (no SETPGROUP, no identity).

---

## Matrix

| # | Site (file:line) | Driver / dialect | Cold/Warm | Identity recorded | Where / when persisted | Cross-process kill path | Gap vs RLR-L5 `runtimeOwnership` |
|---|---|---|---|---|---|---|---|
| A | `ProcessOwnership.swift:717` (`posix_spawn` `:834`) | primitive (all cold PG spawns) | n/a | Builds `{pid, pgid==pid, startTimeTicks, kind}` | In-memory return only; turn-owner file iff `kind==.devTurn` **and** `TurnOwnerDirectory` set (`:166/852/858`) | Via `terminateOwnerIdentityIfSafe` **iff** the identity was persisted somewhere a killer can read | Primitive is fine; it never persists keyed by worker id — callers must |
| A1 | `ProcessOwnership.spawnDetachedRunner:673` → used at `AsyncTeamService.swift:336` | detached `alln team __runner` (**coordinator**) | cold | `{pid,pgid,startTimeTicks,kind=.detachedRunner}` | Launcher discards returned pid (`_ =`); the **runner process itself** writes `owner.json` on claim (`AsyncTeamService.swift:604`, kind `.detachedRunner`); F2 stage-lease covers the gap | `ProcessOwnershipSurface.kill`/reconcile read `owner.json` → `terminateOwnerIdentityIfSafe` (group-kills recorded pgid, identity-verified) | Coordinator IS durably killable. **But** its worker children (site C) are in their own groups → NOT reaped by this group kill |
| B | `ProcessGroupCommandRunner.swift:64` (run) & `:173` (runStreaming) | **cold worker CLI** for `RunService` (kimi, agy, and any non-warm driver); default spawnKind `.devTurn` | cold | Full `OwnerIdentity` built via primitive; held in `spawned.identity` | **In-memory only** for plain `alln run`. Durable turn-owner file **only** when relay/pilot set `TurnOwnerDirectory` (`RelayCoordinator.swift:1143`) | In-process only (cancel/timeout/buffer-cap call `terminateOwnerIdentityIfSafe(identity)` on the live task). No cross-process reach on the plain path | **Worker identity never persisted keyed by worker id** on the P0 foreground path → the founder-repro hole |
| C | `SubprocessCommandRunner.swift:349/392` (`setpgid` `:395`) | **worker CLI** for `AsyncTeamService` (default, `:86`) + `WorkerInvokerFactory` fallback default (`:56`) | cold | **None** | Nothing persisted; pid only in the in-process `Process`; `setpgid(pid,pid)` gives worker its own group | In-process `killGroup(process)` on timeout/cancel only. No identity, no durable record, **detached from coordinator group** | **Total gap** — no pid/pgid/startTime/kind anywhere; orphan on coordinator kill |
| D | `ProcessACPTransport.swift:13` (Process()) / `:51` (run()); constructed at `RunService.swift:607` | **warm** grok (ACP stdio), cursor (ACP `acp`), codex (app-server), claude (stream-json) — all four via `ACPTransportProfile.makeDriver` (`:56`) | **warm** | **None** (pid read back into local var at `:55`, used only for local `setpgid`) | Nothing on disk; pid lives inside the `ProcessACPTransport` instance held by `WarmWorker` in `WarmWorkerPool.shared` | `terminate()` (`:85`) group-kills its own pid **from the same process only**. No cross-process reach whatsoever | **Total gap** — zero durable identity; unkillable and un-pollable from another OS process |
| E | `OpenCodeServeCoordinator.swift:210/223` (AgentOS) | `opencode` warm-serve HTTP daemon (**coordinator-like**), routed by `OpenCodeRoutingWorkerRunner` | warm (persistent daemon) | pid only (`LaunchedServe.pid:231`) | In-memory value; no disk record | `process.terminate()` / `terminateProcess(pid)` pid-only, in-process; no identity verify | No pgid/startTime/kind; pid-reuse-unsafe; not keyed by worker id |
| F | Delegated: `RunProofRunner.swift:20`, `ProjectVerificationService.swift:53`, `WorkerImageInvoker.swift:102`, `DesignImageRunner.swift:78`, `ModelHealthChecker.swift:53/93` | proof commands / image-gen / health probes | cold | Inherits injected `CommandRunner` | Inherits — whatever runner is passed | Inherits | Not own spawn paths. `RelayCoordinator` injects `ProcessGroupCommandRunner(spawnKind:.harnessProof)` (`:172`); `RunService` passes its own runner (`:807`). Doctor probes intend `.doctorProbe`. Ownership only as good as the injected runner (usually site B or C properties) |
| G1 | `PanelCLI.swift:702` | re-exec `alln panel round` (Spec Review **coordinator**) | cold detached | raw pid only | `PanelStateStore` owner pid (for orphan reconcile) | Pid-based reconcile in `panel status/watch`; no identity-verified group kill | Raw pid, not `{pgid,startTimeTicks}`; **outside the P0 cold-single-worker vertical** |
| G2 | `PilotCLI.swift:344` | re-exec `alln pair pilot handoff` (pilot **coordinator**) | cold detached | raw pid (`:377`) | `RelayStateStore` owner pid | Pid-based orphan reconcile in `pilot status/watch` | Raw pid only; **outside the P0 vertical** |

---

## Per-site notes

**A / A1 — the primitive and the detached coordinator.** This is the one place
the codebase gets it right: SETPGROUP at creation, a full identity, and (for the
detached runner) a durable `owner.json` written by the runner process on claim,
guarded by an F2 stage-lease so the launcher's death mid-handshake doesn't cause
a false reap. `ProcessOwnershipSurface.kill` (`:92`) and reconcile read that
file and route every kill through `terminateOwnerIdentityIfSafe` — the single
identity-checked group-kill. The coordinator is genuinely cross-process
killable. The unsolved half is that the *workers this coordinator spawns* (site
C) are never recorded, and `setpgid` puts them in their own groups, so the
coordinator group-kill cannot reap them.

**B — cold foreground `alln run` (the P0 vertical's own path).**
`ProcessGroupCommandRunner` is a faithful drop-in that uses the good primitive
and holds a correct `OwnerIdentity`, but on the plain-run path that identity is
consumed only by in-process cancel/timeout/buffer-cap handlers
(`terminateOwnerIdentityIfSafe(identity)` at `:102/109/144/150/213/236/296/311`).
It is **never written to `owner.json` keyed by the worker id**, because
`recordSpawnedTurnOwner` no-ops unless `TurnOwnerDirectory.shared` is set, and
that is set only by `RelayCoordinator`. So a second process running `alln kill`
has no worker record to read — exactly the reproduced
`killedCount: 0`/live-child signature. **This is the site RLR-S04 must fix
first**: persist `runtimeOwnership` keyed by worker id at spawn on this path.

**C — async team worker CLIs.** Strictly worse than B: no identity is even
constructed. Any run dispatched through `AsyncTeamService` (the detached runner
coordinator) spawns its worker via `SubprocessCommandRunner`, which records
nothing and detaches the worker into its own group. This is the layer that
produces "live worker, dead coordinator pid still named as lane holder"
orphans.

**D — the four warm drivers.** `grok`, `cursor`, `codex`, `claude` are all warm
and all spawn through the single `ProcessACPTransport`. Because the pid is held
only inside a process-global in-memory pool, there is no durable
`runtimeOwnership` and no external kill path at all. Foundation.Process cannot
SETPGROUP atomically; the `setpgid(pid,pid)` at `:56` races the child's own
`exec` and any grandchildren it spawns before the call lands. Giving these
drivers RLR-L5 cancel semantics requires two real changes: (1) route the warm
spawn through `spawnProcessGroupLeader` (or an equivalent posix_spawn path) so
`pgid == pid` is atomic, and (2) persist `{pid,pgid,startTimeTicks,kind}` keyed
by the warm worker's session key at init. Neither exists today.

**E — opencode serve.** A persistent daemon, closer to a coordinator than a
per-turn worker; pid-only, in-memory, AgentOS-owned. Relevant only if `opencode`
is enabled as a driver. Same durable-identity gap as D.

**F — delegated runners.** These never own a spawn; they take an injected
`CommandRunner`. Their ownership properties are whatever the injector supplies —
so proof runs under `RelayCoordinator` get `.harnessProof` group-killable
identity via `ProcessGroupCommandRunner`, while proof/health runs that receive a
`SubprocessCommandRunner` inherit site C's total gap. No new record type is
introduced here; note them only so S04 doesn't double-count them as independent
spawn sites.

**G1 / G2 — panel/pilot background coordinators.** Detached self-re-execs
(`alln panel round`, `alln pair pilot handoff`) that track a **raw pid** in
their state stores for orphan reconcile. They are coordinators, not the P0
single-worker path, and their identity is a raw pid (no `pgid`/`startTimeTicks`),
so they are outside RLR-L5's `{pid,pgid,startTimeTicks,kind}` contract. Flagged
for completeness; not part of the P0 Works Test.

---

## Auxiliary (non-worker / non-coordinator) spawns — out of the RLR contract

Listed so the audit is exhaustive; none start a worker or coordinator and none
need `runtimeOwnership`:

- `GitObserver.swift:141/164` — `git` observation (head, dirty files, delta).
- `ProjectFileReferenceResolver.swift:455/483` — `git` / `rg` for `@file`
  resolution.
- `PanelSeatIsolation.swift:234` — `/bin/cp` worktree seat clone.
- `AllnighterCLI.swift:1809` — `sh -lc 'printf %s "$PATH"'` PATH probe.

(`AllnighterCLI.swift:1118` is a comment about `_NSGetExecutablePath`, not a
spawn.)

---

## CONCLUSIONS

### Per-warm-driver S04 recommendation

All four warm drivers share site D (`ProcessACPTransport`), which records no
durable ownership and holds the pid only inside `WarmWorkerPool.shared` in the
app/CLI process. None is reachable by a second OS process today.

| Driver | Dialect | S04 recommendation | Justification |
|---|---|---|---|
| grok | ACP stdio | **EXCLUDE from P0 Works Test** | Warm spawn via Foundation.Process with no SETPGROUP and no durable identity; cross-process cancel is not achievable in S04 without first rebuilding the warm spawn on posix_spawn + a keyed `runtimeOwnership` write. |
| cursor | ACP `acp` | **EXCLUDE from P0 Works Test** | Same `ProcessACPTransport` path; identical gap. Cursor Sol is also never auto-routed, so excluding it from the P0 kill matrix costs no coverage of a default flow. |
| codex | app-server | **EXCLUDE from P0 Works Test** | Same transport; the app-server child (and any tool subprocesses it forks) is unrecorded and un-group-killable cross-process. |
| claude | stream-json | **EXCLUDE from P0 Works Test** | Same transport; no durable identity. |

Concrete stance: the P0 vertical is already defined as **cold, single-worker,
foreground mutating `alln run` with a deterministic fake CLI** (spec §Trusted
workflow slice), and the fake CLI is not warm-capable
(`WarmWorkerCapability.supportsACPStdio` is false for it), so the warm path is
**naturally out** of the P0 harness. Formalize that: **exclude all four warm
drivers from the S06 Works Test**, and until a dedicated warm-ownership slice
lands, have warm cancel/kill return `KillOutcome.verificationUnavailable`
(never a terminal `killed` lie), so the honest-refusal contract still holds for
warm workers. **S04c formalized this exclusion** with
`testWarmKillReturnsVerificationUnavailable` (simulated warm = executing run
with no recorded worker `runtimeOwnership` → `verificationUnavailable`, never
`killed`). The follow-up warm slice must (1) move the warm spawn onto
`spawnProcessGroupLeader` for atomic `pgid == pid`, and (2) persist
`{pid,pgid,startTimeTicks,kind}` keyed by the warm session key at
`ProcessACPTransport` init.

### Cold-path recommendation (the P0 vertical itself)

**INCLUDE and fix.** Site B (`ProcessGroupCommandRunner` under `RunService`) is
the P0 path and already builds a correct `OwnerIdentity` — S04's job is to
**persist it keyed by worker id at spawn** (not only when a relay turn-dir
happens to be set), and to record the coordinator as a separate owner. Site C
(`SubprocessCommandRunner` under `AsyncTeamService`) should be migrated onto the
same recorded-ownership discipline, or the async path stays orphan-prone; if
async team runs are out of the P0 single-worker vertical, state that explicitly
and keep site C behind the same `verificationUnavailable` honesty until it is
converted.

### One-line gap summary against RLR-L5

Coordinators can be durably recorded and killed today (detached-runner
`owner.json` + `ProcessOwnershipSurface`). **No worker in any path is recorded
keyed by worker id** — the entire `runtimeOwnership` requirement is unmet for
workers, most acutely on the warm path (no identity at all) and on the plain
cold `alln run` path (identity built, never persisted). That is the S04 build.
