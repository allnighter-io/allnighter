# Process Ownership — every process has an owner, a group, and a heartbeat

Status: **Approved for implementation — v2** (founder, 2026-07-17; v2 same day
after two mentor reviews of v1 + the in-flight diffs. Ledger at bottom).
Reliability slice.
Trigger: two production failures on 2026-07-16 — async `alln team start` runs die
at `fanning_out` (no durable owner; reconcile reaps them), and relay/pilot dev
turns stall repeatedly because killed turns orphan `swift-test` processes that
wedge build locks (4 corpses in one round; both relay attempts escalated).
At thousands-of-agents scale these are not edge cases; they are the steady state.

## The law (binds all current and future spawn sites)

Every process Allnighter creates MUST have, at creation time:

1. **A durable owner with an identity** — the owner-of-record is
   `{pid, pgid?, startTimeTicks, kind}` (start time via `kinfo_proc`/sysctl).
   "Alive" means pid alive AND start time matches. A raw pid is never an
   identity (macOS recycles pids; a recycled pid must read as dead, and must
   never be signalled). Work is either owned by a live process that outlives
   it, or self-owned (the work IS the owner process).
2. **Process-group ownership** — detached work is spawned as its own
   process-group leader (`posix_spawn` + `POSIX_SPAWN_SETPGROUP` or `setsid`;
   the requirement is the semantics, not a ritual). Ending a turn/run for ANY
   reason = `kill(-pgid)` + grace + `SIGKILL` of the **recorded** pgid, only
   when the identity matches. Never `kill(-pid)` assuming pgid == pid; owners
   recorded without a pgid (in-process saves, the Mac app, sync paths) are
   never PG-killed by reconcile. Group kill is best-effort by OS design
   (re-exec/XPC escapees exist): after a kill, surviving strays are *surfaced*
   (`doctor`, PO-S05 `ps`), not silently ignored — and no cgroup machinery in
   this phase.
3. **Death is identity-truth; heartbeat is progress-truth.** Reconcile
   declares work dead when its owner is identity-verified dead — immediately,
   no staleness timer. The heartbeat answers a different question: *is it
   moving?* The owner touches it on real progress events (worker state
   transitions, output bytes) with a monotonic sequence + phase, plus a timer
   floor. Status surfaces `lastProgressAt`; "alive but nothing moved for N
   minutes" is flagged, never auto-reaped. (v1's `stale ∧ dead` conjunction
   is retired: it could only delay a correct reap, and a timer-touched
   heartbeat cannot detect the wedged-alive failure that actually happened.)
4. **Surfaced contention** — a process that would block on the lane either
   acquires it or receives a **FIFO ticket** naming position, holder
   (identity, kind, id), heldSinceSeconds. The harness owns the wait loop and
   shows it in status; agents are told (docs + error text) never to busy-loop.
   Silent queueing (0%-CPU waits) is forbidden.
5. **Terminal truth** — every terminal run/turn carries `endReason`
   (`completed | failed | cancelled | reconciledOrphan | killed | unknown`).
   `endReason` is stamped by the actor that knows, **never inferred after the
   fact** — an inferred cause is fabricated evidence. `unknown` is honest and
   is itself a bug report.

Reconcile discipline (applies wherever the law is enforced):
- **Reads never kill.** `team list`/`load` project state read-only. Kill +
  terminal writes happen only in explicit paths (`team status <id>`,
  `team cancel`, `alln team reconcile`, `doctor`) under a per-run flock.
- Reconcile is a pure decision + **one atomic terminal write**; it never
  clobbers an existing terminal status and never flips state on torn reads.

Non-goals (rejected for complexity — do NOT build):
- A resident daemon as owner of async runs (`alln serve` stays skeleton/v2;
  the 2026-07-16 stale-serve incident is the evidence: version skew + single
  point of failure). Self-owning runners have blast radius = 1 run.
- Build-cache orchestration / warm build farms. Serialization via the lane +
  one persistent scratch per root is enough.
- A cleanup timer daemon as the primary design — opportunistic reconcile on
  explicit inspect + `doctor` sweep is the mechanism.
- Per-attempt scratch dirs (v1 mistake): total turn kill removes the corpses,
  the lane removes the contention; per-attempt scratch only removes the build
  cache. One scratch per root, owned by the harness, protected by the lane.

## PO-S01 — self-owning async runs, truthful accept

Repro of the death: `team start`, poll from another process → journal freezes
at `fanning_out`, workers stay `queued`, status flips to `interrupted` on the
first external read.

Contract:
- `team start` spawns a detached **runner** (own process group, stdio to
  files under the run directory, working dir = project root, executable
  resolved via `_NSGetExecutablePath` — never argv[0]; `posix_spawn` does no
  PATH search and cwd changes make relative argv[0] resolve wrongly or
  dangerously).
- **The accept is truthful (no TOCTOU):** the runner acquires the
  governor/lane slot and writes a `runner_ready` handshake (accepted or
  typed-refused); the parent waits briefly on the handshake and prints either
  the accepted envelope or the synchronous typed error (`TEAM_GOVERNOR_BUSY` /
  lane ticket). A caller must never hold an accepted run id that dies at
  start for a reason knowable at accept time.
- **Idempotent start:** double-submit (agent retry) returns the same run id
  and never spawns a second runner (wire the existing `IdempotencyStore`).
  Two runners fighting one root is ownership's failure mode under retry.
- Owner-of-record = the runner's identity record; heartbeat per law §3.
- Reconcile per law: identity-dead owner → PG-kill recorded pgid, stamp
  `endReason: reconciledOrphan`, one atomic write — from explicit paths only.

Works test (cross-process, the one that would have caught this): process A
runs `team start`; process B polls `team status` every 2s via separate
invocations until ≥1 worker reaches `running` then `done`, asserting status
never becomes `interrupted` while the owner is identity-alive. Mock/fast team
for CI. Plus seam tests: identity-alive → never reaped regardless of
heartbeat age; identity-dead → reaped immediately with `reconciledOrphan`;
recycled-pid simulation (same pid, different start time) → treated as dead,
**no signal sent**.

## PO-S02 — total turn kill

The corpse fix, shipped alone and first (it is pure ownership; it needs no
schema changes): with group kill, everything an agent spawned dies with the
turn no matter who invoked it.

Contract:
- Relay/pilot dev-turn worker CLIs are spawned as their own process-group
  leaders, identity recorded.
- Ending a turn for ANY reason (reported, stalled, watchdog-killed, PM
  escalation, crash of the PM CLI) = grace-then-SIGKILL of the recorded
  group; then assert the group is empty.
- `roundLog` gains per-dev-turn `endReason`
  (`reported | stalled | killed | proofTimeout | laneBusy | unknown`) —
  stamped by the killer/reporter, never inferred.

Works test: dev turn spawns `sleep 300` in its shell; watchdog-kill the turn;
assert (a) no process from the recorded group survives, (b) `endReason:
killed` recorded, (c) an immediate next turn on the same root starts clean.

**Implementation note (2026-07-17, S02 landed):** the relay stall watchdog
classifies turns by *output silence*, which reaps long-silent cold-CLI turns
(three pilot escalations while building this very spec). Once dev turns carry
the S01/S02 progress heartbeat, the stall classifier must consume
`lastProgressAt` instead of output silence — wire this when S03/S04 touch the
turn loop. Also: mock runners in unit tests spawn no processes (owner nil,
kill no-op, endReason still stamped); the live spawn path is covered by the
SETPGROUP works test. ACP warm transports use post-spawn `setpgid` (group
terminate) rather than SETPGROUP-at-spawn — same semantics, recorded here.

## PO-S03 — one lane, FIFO ticket

Contract:
- Relay/pilot dev turns AND harness proof runs acquire the existing per-root
  execution lane (`ExecutionLaneRegistry`, same key — no second lane system)
  for their duration.
- Lane busy → **FIFO ticket**, not caller retry-cadence: typed
  `EXECUTION_LANE_BUSY` carrying `{position, holder: {identity, kind, id},
  heldSinceSeconds}`; relay/pilot status surfaces `laneBlocked` with the
  ticket; the harness owns the wait. (v1 said both "fail fast" and "retry on
  a cadence" — that was a queue in the caller with no fairness. The lane is
  FIFO; say so and hand out tickets.)
- Lane holders are reconciled by identity: holder identity-dead → release
  immediately (no staleness timer), log `reconciledOrphan`.
- **Build-lane scope:** anything that runs SwiftPM against a root (relay/
  pilot proofs, panel verification, GUI works-test, ad-hoc agent builds
  inside turns) is classified build → takes the lane, or is explicitly
  classified non-build in the registry. No second silent queue.

Works test: two relays on one root; second's dev turn surfaces `laneBlocked`
with the first's id and a position (and spawns nothing while blocked); first
finishes → second proceeds; kill first mid-turn → lane releases on identity
reconcile and second proceeds without human help.

## PO-S04 — harness-owned proof of record

A different law than ownership (proof integrity: the agent cannot lie about
green), deliberately after S02/S03 — the corpse fix must not wait on a
schema debate.

Contract:
- A dev turn's deliverable declares `proofCommands: [string]`
  (`ProjectVerificationService` shape). The relay/pilot runner executes them
  itself via the existing bounded-subprocess verification primitive (REUSE /
  extract `ProjectVerificationService`'s runner — do not write a second one):
  own process group, hard timeout, captured output, under the root's lane,
  using the root's persistent scratch dir.
- The agent never runs the proof of record; agent-run builds inside its turn
  are permitted and die with the turn's group (S02).
- `roundLog` += `proofResults[]` (command, exit, durationMs, truncated tail).
  A PM must never again be unable to distinguish "chose to stop" from "died".

Works test: dev turn declares a proof of `sleep 300`; harness times it out;
assert group empty, `endReason: proofTimeout`, `proofResults[]` captured, and
the next turn's proof starts clean on the same scratch (warm cache intact).

**Implementation note (2026-07-17, S04 landed):**
- **Declare:** `proofCommands` from turn state (`RelayRound.proofCommands`) or
  the dev report tail via `HarnessProofCommandsParser` — fenced
  ` ```proofCommands ` (JSON array or one command per line) or a JSON object
  `{"proofCommands":[…]}` (last match wins). Turn state wins when non-empty.
- **Run:** after the agent group is killed, the harness releases the dev-turn
  lane hold and re-acquires as `harnessProof`, then runs
  `ProjectVerificationService` with `ProcessGroupCommandRunner(spawnKind:
  .harnessProof)` — no second spawn path. `endReason` becomes `proofTimeout`
  if any proof is killed on timeout, or `laneBusy` if the proof phase cannot
  acquire the lane.
- **Scratch (one per root, not per-attempt):**
  `~/Library/Application Support/Allnighter/Lanes/<lane-key>/scratch/`
  (`ExecutionLaneFlock.ensuredScratchPath`). SwiftPM commands get
  `--scratch-path` injected when missing.

## PO-S05 — observable ownership: `alln ps` / `alln kill`

The law creates a registry as a side effect (every run/turn dir holds an
identity, a pgid, a heartbeat). Expose it, or agents reimplement `ps` and
invent competing cleanup:

- `alln ps --json` — every process tree Allnighter owns: id, kind
  (run/relay/pilot/proof), root, identity, lane state, heartbeat/progress
  age. Reconciles read-only (reports what *would* be reaped; kills nothing).
- `alln kill <id> | --all` — the big red button: total group kill + terminal
  `endReason: killed`. What makes overnight trust real: see everything, stop
  everything, one command.
- `alln ps --json` is the **oracle for the works tests above** ("group
  empty", "zero orphans in the morning") — machine-checkable, not
  aspirational.

## Slice order

PO-S01 → S02 → S03 → S04 → S05, strictly in order, one commit per slice, each
green (build + its works test + existing suites) before the next. No slice
lands disabled or flag-gated; zero users → no compatibility shims.

One audit (not a slice): verify sync worker-driver paths already create
killable groups and `cancel` kills the tree; if one path lies, it becomes a
follow-on slice — otherwise write the proof note and stop.

## Done when

A machine runs overnight with dozens of concurrent async runs and relay/pilot
rounds, and `alln ps --json` in the morning shows: zero orphaned processes,
zero runs reaped while identity-alive, zero silent waits (every blocked turn
holds a ticket naming its holder), every terminal run/turn a stamped
`endReason`, and a warm scratch per root (no cold-build tax paid for
isolation).

## v2 review ledger (2026-07-17)

Accepted from mentors: owner identity record incl. start time (pid reuse =
safety bug: recycled pid must never be signalled); pgid recorded ≠ pid, never
PG-kill unrecorded/in-process owners; truthful accept via runner handshake
(TOCTOU); `_NSGetExecutablePath`; heartbeat reframed liveness→progress
(surface, never auto-reap); reads-never-kill + atomic terminal writes;
`endReason: unknown`, never inferred; split total-kill from proof-of-record;
FIFO lane ticket (harness owns the wait); drop per-attempt scratch (cache-
hostile; lane + total kill already provide the isolation); idempotent start;
`alln ps`/`kill`; build-lane scope classification; mechanism-neutral spawn
wording; sync-path audit.

Rejected: two-tier staleness SLA (dissolves — death is identity-truth,
immediate; no timers to tune); cleanup timer daemon as primary (a second
owner in disguise); cgroup-style containment (out of phase).

Deferred, recorded: `team status --wait-for <state>` blocking wait; stable
exit-code table (align with the error catalog as its own doc pass);
`alln status --root` aggregate (subsumed by `alln ps`).
