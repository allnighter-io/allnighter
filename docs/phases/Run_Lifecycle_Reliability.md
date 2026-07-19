# Run Lifecycle Reliability — every accepted run stays observable, stoppable, and recoverable

Status: **APPROVED — P0 execution gate. Build RLR-S00–S06 before IR-S02 or
Agent Onboarding V1.** Founder approved 2026-07-19 after the Kimi mutating-run
failure below. Execute one bounded slice at a time; do not mix router/onboarding
work into this phase.
Owner: AllnighterCore + AllnighterEngine + AllnighterCLI (`TeamRun`/`RunStore`,
`RunService`, `ProcessOwnership`, `ExecutionLaneRegistry`, CLI JSON/NDJSON)
Updated: 2026-07-19

Related: `Unified_Run_Model.md` (run/write-policy law) ·
`CLI_Implementation_Contract.md` (wire contract) · archived
`Process_Ownership.md` + `Concurrent_Invocation_Isolation.md` (intended process
and cross-project guarantees) · `Agent_Intent_Router.md` and
`Agent_Onboarding.md` (blocked adoption multipliers).

## Founder intent

An agent launched:

```text
alln run … --worker model_kimi_k3 --lane design --effort high --json
```

for a mutating GUI slice. The run stayed `fanning_out` for 12+ minutes with no
repo edits or usable progress; status disagreed with the journal; `alln kill
--all` did not reap the live Kimi process; a retry competed with the leftover;
and other live work made the actual blocker impossible to identify. The user
abandoned Allnighter and completed the work in-session.

The product claim is not merely “Allnighter can spawn a CLI.” It is:

> Once Allnighter accepts a run, the caller can always identify it, understand
> what it is waiting on, observe sourced activity, stop its whole process tree,
> and retry without competing with leftovers.

Until that claim is proven, routing and onboarding must not send more agents
into the execution path.

## Trusted workflow slice

```text
route a named mutating worker
→ receive one canonical run id
→ observe admission / spawn / real activity
→ poll the same durable truth from another process
→ kill the complete worker tree
→ see the lane released
→ retry once, cleanly
```

This phase owns that slice for foreground `alln run`, async team runs, and
relay/pilot work wherever they share the same run, ownership, lane, or status
substrate.

## Risk and debugger classification

Tier: **T3 Critical** — destructive process control plus repeated persisted-run
truth failures.

Bug fingerprint:

```text
alln run lifecycle + live worker/journal disagreement + RunStore/process-owner/control-plane proof gap
```

- **Truth owner:** `TeamRun`/`RunStore` for durable run truth;
  `ProcessOwnership.OwnerIdentity` for the live process group;
  `ExecutionLaneRegistry`/`ExecutionLaneFlock` for admission; `RunEvent` for
  sourced progress.
- **Lie-prone layers:** `fanning_out`, CLI status projection, `alln ps`,
  `alln kill`, final-only `--json`, and streams that omit real activity.
- **Repeated prior art:** archived Process Ownership intended total group kill,
  visible FIFO tickets, progress truth, and cross-process status. The new
  foreground failure means those laws are not proven across the actual
  `alln run` seam.
- **Missing proof:** a two-process foreground-run harness with a buffered,
  hanging worker and grandchild. Mock-only runner tests are insufficient.
- **Isolation harness:** required by `docs/operations/Debugger.md` before fixes.
  Use a deterministic fake CLI, not a paid/live model.

Before product edits, add this incident to `docs/operations/debugger/DEBUGLOG.md`
with the final RCA and red proof command. Do not claim the precise cause of the
reported `RUN_NOT_FOUND` or cross-project observation until the harness
reproduces it.

## Current state (verified 2026-07-19)

1. `RunService` takes the per-root write lock before minting/persisting the
   foreground run id. Its legacy wait overload passes no ticket callback and may
   wait for 1,800 seconds, so a caller can be blocked without a durable run or
   blocker record.
2. A single-worker execution run uses the aggregate status `fanning_out`, which
   cannot distinguish admission wait, spawn, tool activity, proof, or a wedge.
3. `alln run --stream` emits answer/reasoning deltas, but `RunService` currently
   drops `.toolActivity`, `.rawEvent`, and `.started` at its public projection.
   Process-runner activity used by an idle timer is not the same as durable,
   pollable activity truth.
4. `RunStore` stamps a foreground non-terminal run with the coordinating
   process's `.inProcess` owner. The spawned worker is a process-group leader,
   but its identity is not durably attached to the run for an external kill.
5. `ProcessOwnershipSurface.killRun` can stamp `.cancelled`/`.killed` even when
   `terminateRecordedOwnerIfSafe` returns `false`. A later kill can therefore
   report already-terminal while a child survives.
6. `team status` is intended to read the shared `RunStore`, yet the field run
   returned `RUN_NOT_FOUND` while a journal existed. The exact cause is open;
   emitted-id → status round-trip is the required proof, not a guessed patch.
7. Per-root execution lanes and cross-project scoping are intended to be
   isolated. A floor-wide `ps` view can show unrelated work, but today it does
   not make causality legible: repo write lock, global team governor, driver
   capacity, and vendor-internal waiting must never be presented as one generic
   “lane busy.”

## Binding semantic laws

### RLR-L1 — one canonical run identity

The id emitted by the start/stream surface is the id accepted by status, result,
cancel/kill, history, journal lookup, and GUI/iOS projections. Filesystem folder
names such as `run_<id>` are storage detail and are never presented as a second
id. An emitted id that cannot immediately round-trip is a failed acceptance.

### RLR-L2 — accepted means durably controllable

Mint and persist the run plus its admission state before any potentially long
wait. Do not emit “accepted,” `running`, or `workerStarted` until the facts those
words claim are durable. A caller may lose its terminal; another process must
still recover status and control from the journal.

### RLR-L3 — lifecycle status and phase are different truths

Keep the shared closed run lifecycle (`queued | running | done | failed |
timedOut | cancelled | interrupted`) and add one sourced current phase rather
than minting transport-specific statuses. The minimum phase vocabulary is:

```text
admitting | waitingForWriteLock | waitingForCapacity | spawningWorker |
working | proving | settling
```

`fanning_out` must not remain the visible phase for a one-worker execution run.
Phase transitions are persisted and streamed from the same owner.

### RLR-L4 — every wait names the actual resource

A blocked run records and emits a typed blocker:

```text
resource: repoWriteLock | teamGovernor | driverCapacity | vendor
scopeRoot?
holderId?
holderKind?
ticketPosition?
heldSinceSeconds?
holderDeadlineAt?
```

The per-root write lock must expose the existing FIFO ticket. No fake ETA or
percentage: show position, elapsed hold, and a real configured deadline when
known; otherwise say the completion time is unknown. A run in project A must
never name project B as a repo-write-lock holder.

### RLR-L5 — the complete ownership tree is the kill target

Every spawned worker records `{pid, pgid, startTimeTicks, kind}` in its runtime
worker record at spawn; a detached/foreground coordinator identity remains a
separate owner. The durable run ownership tree is the coordinator plus every
active worker process group (one for execution, potentially many for an answer
team). RLR-S00 audits every current spawn site rather than assuming all children
share the coordinator's pgid. Exact kill, scoped `kill --all`, cancel, idle
timeout, and abnormal settlement all use the one identity-checked group-kill
implementation over that complete set.

Kill is successful only when the recorded group is empty. Do not stamp a new
terminal `killed` state when no signal path was taken or survivors remain;
return a typed nonzero partial/refused result with survivor identities. A
terminal journal with a live recorded worker is an ownership contradiction to
surface and reconcile, not “already terminal.”

### RLR-L6 — liveness, activity, and repo change are not synonyms

- Owner heartbeat proves the coordinating owner is alive.
- `lastActivityAt` advances only on real worker activity: spawn, parsed tool
  event, reasoning/answer bytes, raw stdout/stderr bytes, observed child
  transition, or exit.
- A timer heartbeat event may repeat `lastActivityAt`; it must not advance it or
  fabricate progress.
- Files touched are emitted only when sourced by a driver tool event or a
  deterministic repo observation. Otherwise the field is absent, never guessed.
- Status exposes activity age and `progressStale` without fake percentages.

### RLR-L7 — one clean JSON contract, one live stream contract

- `--json` prints exactly one terminal JSON object and may be silent until
  completion. Never mix progress lines into it.
- `--stream` prints only live NDJSON. Its first event carries the canonical run
  id; it then carries phase/blocker/activity heartbeats and exactly one terminal
  event.
- Long-running router/onboarding recipes use `--stream` or the existing async
  start/status/result path. They do not teach final-only JSON as a monitoring
  transport.

RLR hardens the current CLI grammar; it does **not** rename
`team status/result/cancel` or create a parallel run schema. Grammar consolidation can be a later
hard cutover. All current commands continue to project the same `TeamRunJSON`,
`TeamStatusResponse`, `RunEvent`, error catalog, and exit-code table.

### RLR-L8 — stale is not permission to kill

Use four bounded clocks where supported: runner-ready handshake, time to first
real activity, rolling activity-idle timeout, and total wall timeout. The
existing `--idle-timeout` owns the rolling activity budget and resets on the
RLR-L6 activity set.

An unrelated new run never auto-kills an identity-alive stale run. It surfaces
the blocker and requires explicit kill/cancel authority, or waits visibly under
the configured policy. A timeout belonging to the run may kill its own group.

### RLR-L9 — retry reuses intent before it duplicates work

Add idempotency to the foreground run path using the same canonical-payload
discipline as async team start. A retry with the same key and payload returns the
existing run id and current status; a changed payload returns the existing typed
conflict. A retry never starts a second worker merely because the first caller
lost stdout.

## CLI-first contract

This phase hardens existing commands:

```text
alln run "<message>" --project <id|path> ... [--idempotency-key <key>] --json
alln run "<message>" --project <id|path> ... [--idempotency-key <key>] --stream
alln team status <run-id> --json [--wait-for <state> --timeout <seconds>]
alln team result <run-id> --json
alln team cancel <run-id> --json
alln ps [--all-projects] --json
alln kill <run-id> --json
alln kill --all [--all-projects] --json
```

Additive shared fields, finalized in RLR-S01 before implementation spreads:

```jsonc
{
  "runId": "canonical-id",
  "status": "queued|running|done|failed|timedOut|cancelled|interrupted",
  "phase": "waitingForWriteLock|spawningWorker|working|…",
  "blocker": {
    "resource": "repoWriteLock",
    "scopeRoot": "/absolute/canonical/root",
    "holderId": "…",
    "holderKind": "run|relay|pilot|proof",
    "ticketPosition": 1,
    "heldSinceSeconds": 42,
    "holderDeadlineAt": null
  },
  "lastActivityAt": "…",
  "lastActivityKind": "tool|stdout|stderr|child|spawn|exit",
  "progressStale": false
}
```

`blocker` is absent when unblocked. Optional facts remain absent rather than
`unknown` strings. New errors must be stable catalog entries with existing exit
classes; regenerate `docs/generated/alln/*` from the registry.

## Inference bans

| Junction | Owner | Forbidden inference | Negative proof |
| --- | --- | --- | --- |
| Journal → status | `RunStore` | Directory exists, therefore status may invent/recover a different id | Emitted id round-trips exactly; malformed/other id fails |
| Owner → kill | recorded worker identity | Run is terminal, therefore no process survives | Terminal+journal/live-group contradiction is surfaced |
| Heartbeat → progress | `RunEvent` activity owner | Timer fired, therefore worker advanced | Heartbeats leave `lastActivityAt` unchanged |
| `ps` row → blocker | lane/governor/driver owner | Visible concurrent work caused this wait | Blocker names only the causal resource/holder |
| Repo diff → worker activity | `GitObserver` baseline | Any concurrent repo change belongs to this worker | Deterministic isolated harness attributes only owned work |
| Retry → new spawn | idempotency store | Lost stdout means prior work is dead | Same-key two-process retry yields one worker/run id |

## Slices (execute strictly in order)

| Slice | Deliverable |
| --- | --- |
| **RLR-S00 — RED harness + contract freeze** | Add the Debugger packet/DEBUGLOG entry and a deterministic fake CLI that can buffer stdout, emit tool activity, spawn a grandchild, hang, and ignore graceful termination. Add red two-process tests for id round-trip, visible blocker, total kill, and clean retry. Freeze `phase`/`blocker`/activity event shapes against the registry before product edits. |
| **RLR-S01 — identity + status truth** | Mint/persist foreground runs before long waits; make the emitted id pollable from a second CLI process; persist the shared lifecycle phase; remove one-worker visible `fanning_out`; make journal/status/result use the same canonical id and atomic truth. |
| **RLR-S02 — visible admission** | Route `RunService` through the claim-bearing FIFO API with ticket callback; persist/stream typed blockers for repo lock, governor, and driver capacity; prove no worker spawns while blocked and different canonical roots do not share a repo lock. Promote `Unified_Run_Model.md`'s approved forward collision policy from blocked/current-gap prose to shipped truth. |
| **RLR-S03 — live activity stream** | Project `.started`, sanitized `.toolActivity`, raw stdout/stderr activity, child transitions, and sourced repo observations into durable activity truth + NDJSON; emit bounded heartbeats that repeat rather than fabricate `lastActivityAt`; keep `--json` final-only. |
| **RLR-S04 — total kill and contradiction recovery** | Attach every active worker identity/pgid to its run worker record while retaining the coordinator owner; exact/scoped kill, cancel, watchdog, and settlement reap and verify the complete ownership tree; refuse/partial-fail without terminal stamping when no safe signal occurred or survivors remain; detect terminal+journal/live-worker contradictions. |
| **RLR-S05 — watchdog + idempotent retry** | Implement handshake/first-activity/rolling-idle/wall clocks over the shared activity set; add foreground `--idempotency-key`; same-key retries return the active run/status and never duplicate the worker. No new-run auto-kill of an unrelated live owner. |
| **RLR-S06 — full trust gate + dependent-doc handoff** | Run the two-process matrix, contract drift check, Core wall, and morning-zero-orphans assertion. Only after green: unblock IR-S02 and Agent Onboarding V1; update their recipes to the exact shipped lifecycle fields/commands. |

## Works Test

Using a built `alln` and the fake Kimi-like CLI:

1. Start a named mutating run with `--stream`; capture its first event's run id.
2. From a second `alln` process, poll that exact id while the worker is live;
   journal and status agree on lifecycle + phase.
3. Hold the same root with run A. Start run B: it persists
   `waitingForWriteLock`, names A, exposes FIFO position/held time, and spawns no
   worker. Start run C on another root: it is not blocked by A's repo lock.
4. Let A buffer answer output while emitting tool/raw activity. NDJSON heartbeat
   remains live, `lastActivityAt` advances only on sourced events, and status
   exposes the same facts.
5. Freeze all activity past the configured idle budget. The harness kills A's
   worker and grandchild, verifies the pgid is empty, stamps one truthful
   terminal reason, and releases B.
6. Separately invoke `alln kill <id>` while the fake worker/grandchild are live;
   prove both die. Force a terminal-journal/live-child fixture and prove it is
   surfaced/reaped rather than skipped as already terminal.
7. Retry the same payload/key from two processes; exactly one run id and one
   worker exist. A changed payload returns the idempotency conflict.
8. `alln ps --all-projects --json` at close shows zero identity-alive orphan
   trees from the harness.

Proof commands when the slices exist:

```bash
swift test --package-path Packages/AllnighterCore --filter RunLifecycleReliability
swift test --package-path Packages/AllnighterCore --filter RunLifecycleTwoProcess
bash scripts/check.sh
```

Missing proof today: the named harness/tests do not exist; that is RLR-S00, not
a waiver.

## Non-goals

- No intent matching, named-worker semantics, recipe installer, or onboarding UI.
- No new scheduler, daemon, per-project registry, or second ownership/lane system.
- No fake progress percentages, runtime forecasts, cost forecasts, or queue ETA.
- No automatic killing of unrelated identity-alive work on fresh-run startup.
- No vendor CLI redesign; adapters expose only activity the vendor actually emits.
- No GUI polish. Mac/iOS later render the same CLI/Core contract.
- No broad CLI noun/verb cutover in the reliability phase.

## Done when

- Every accepted foreground or async run id round-trips from another process.
- Every wait has a causal typed blocker or is not presented as blocked.
- Every live worker has a durable killable group identity and its run exposes
  the complete coordinator + worker ownership tree.
- Kill/cancel/timeout leave every recorded group empty before terminal success.
- `--stream` stays live through sourced tool/silence periods; `--json` stays one
  clean final object.
- Same-key retry produces one run and one worker.
- Same-root serialization and different-root isolation pass in real subprocess
  tests.
- Generated contracts are fresh; focused tests + `scripts/check.sh` are green.
- IR-S02 and Agent Onboarding V1 are unblocked only by this green Works Test.
