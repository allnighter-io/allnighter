# Process Ownership — every process has an owner, a group, and a heartbeat

Status: **Approved for implementation** (founder, 2026-07-17). Reliability slice.
Trigger: two production failures on 2026-07-16 — async `alln team start` runs die
at `fanning_out` (no durable owner; reconcile reaps them), and relay/pilot dev
turns stall repeatedly because killed turns orphan `swift-test` processes that
wedge build locks (4 corpses in one round; both relay attempts escalated).
At thousands-of-agents scale these are not edge cases; they are the steady state.

## The law (binds all current and future spawn sites)

Every process Allnighter creates MUST have, at creation time:

1. **A durable owner** — a live process whose pid is the owner-of-record and
   which outlives the work, OR self-ownership (the work IS the owner process).
2. **Process-group ownership** — spawned via `setsid` (its own pgid) so that
   terminating it terminates its *entire tree* with one `kill(-pgid)`. No
   turn/run may ever end (done, stalled, killed, crashed PM, escalated) while
   any process it spawned survives.
3. **A heartbeat** — a liveness file the owner touches on a fixed cadence.
   Reconcile marks work dead ONLY on (stale heartbeat AND dead owner). Owner
   exit alone is never death for self-owned work; a fresh heartbeat is never
   overridden by a pid check.
4. **Surfaced contention** — a process that would block on a lane/lock either
   acquires it, or fails fast with a typed error naming the holder (pid, since
   when). Silent queueing (0% CPU waits) is forbidden.

Non-goals (rejected for complexity — do NOT build):
- A resident daemon as owner of async runs (`alln serve` stays skeleton/v2;
  the 2026-07-16 stale-serve incident is the evidence: version skew + single
  point of failure). Self-owning runners have blast radius = 1 run and can
  never be version-skewed from their spawner.
- Build-cache orchestration / warm build farms. Serialization via the existing
  lane is enough.
- Any change to the sync paths that already work.

## PO-S01 — self-owning async runs

`alln team start` currently spawns work that dies with (or is reaped after)
the exiting CLI process. Repro: run `team start`, poll from another process →
journal freezes at `fanning_out`, workers stay `queued`, status flips to
`interrupted` on/after the first external status read.

Contract:
- `team start` forks a **runner** process (double-fork/`setsid`, stdio
  redirected to files under the run directory, working dir = project root).
  The parent prints the accepted envelope (unchanged shape) and exits.
- The runner's pid is the owner-of-record in the run record; the runner
  touches `heartbeat` (mtime) at least every 10s for the life of the run.
- Reconcile (any `alln` invocation that inspects runs): mark `interrupted`
  ONLY if heartbeat older than 60s AND owner pid dead. Then PG-kill the
  runner's group (in case of a wedged-but-dead-owner tree) and stamp
  `endReason: reconciledOrphan`.
- Run record gains `endReason` (`completed | failed | cancelled |
  reconciledOrphan | killed`) — never empty for a terminal run.

Works test (cross-process, the one that would have caught this):
process A runs `team start`; process B polls `team status` every 2s from a
separate invocation until ≥1 worker reaches `running` and then `done`,
asserting status never becomes `interrupted` while heartbeat is fresh.
Use a mock/fast team so it runs in CI.

## PO-S02 — harness-owned proof + total turn kill

Relay/pilot dev turns run proof (`swift build/test`) as ad-hoc shell commands
inside the agent's own session; nobody owns those processes. When the
stalled-work watchdog ends a turn it kills the agent, not the tree → orphaned
`swift-test` wedges the SwiftPM lock → every retry queues behind the corpse.

Contract:
- Dev-turn worker CLIs are spawned `setsid` into their own process group.
  Ending a turn for ANY reason = `kill(-pgid)` + short grace + `SIGKILL`,
  then assert the group is empty (works test below).
- Proof moves from agent-shell to harness: a dev turn's deliverable declares
  `proofCommands: [string]` (same shape as `ProjectVerificationService`
  proofs). The relay/pilot runner executes them itself via the existing
  bounded-subprocess verification primitive (REUSE `ProjectVerificationService`
  / extract its runner if needed — do not write a second subprocess runner):
  `setsid` group, hard timeout, captured output, per-attempt scratch dir
  (`--scratch-path` injected for swift, `mktemp -d`, deleted on turn end).
  The agent never runs the proof of record; agent-run builds may still happen
  inside its turn but die with the turn's group.
- `roundLog` gains per-dev-turn `endReason`
  (`reported | stalled | killed | proofTimeout | laneBusy`) and
  `proofResults[]` (command, exit, durationMs, truncated tail). A PM must
  never again be unable to distinguish "chose to stop" from "died".

Works test: start a dev turn whose proof is `sleep 300`; watchdog-kill the
turn; assert (a) no process from the turn's group survives (`pgrep -g` empty),
(b) `endReason` recorded, (c) an immediate next turn on the same root starts
clean with a fresh scratch dir.

## PO-S03 — one lane, surfaced

The per-root execution lane (one Running mutating worker per root,
INVIOLABLE) already exists in `ExecutionLaneRegistry` but relay/pilot dev
turns and proof runs do not all pass through it, and contention today is a
silent SwiftPM lock queue.

Contract:
- Relay/pilot dev turns AND harness proof runs acquire the per-root execution
  lane for their duration. Same key, same registry — no second lane system.
- If the lane is held: fail fast with the existing typed code
  (`EXECUTION_LANE_BUSY`) extended with holder pid, holder kind
  (run/relay/pilot id), and heldSinceSeconds. Relay/pilot surface it in
  `status` as a first-class field (`laneBlocked: {holder, sinceSeconds}`) and
  the round waits/retries on a visible cadence instead of spawning anyway.
- Stale lane holders are reconciled by the same heartbeat rule as PO-S01
  (stale + dead → release lane, log `reconciledOrphan`).

Works test: two relays on one root; second's dev turn reports `laneBlocked`
with the first's id (no swift process from the second exists while blocked);
first finishes → second proceeds; kill first mid-turn → lane reconciles and
second proceeds without human help.

## Slice order

PO-S01, PO-S02, PO-S03 — strictly in order, one commit per slice, each green
(build + its works test + existing suites) before the next. No slice may land
disabled or flag-gated; zero users → no compatibility shims.

## Done when

A machine can run overnight with dozens of concurrent async runs and
relay/pilot rounds and the morning state contains: zero orphaned swift/worker
processes, zero runs `interrupted` with fresh heartbeats, zero silent 0%-CPU
waits (every blocked turn names its blocker), and every terminal run/turn has
an `endReason`.
