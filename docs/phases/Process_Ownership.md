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

- `alln ps [--all-projects] --json` — the process trees Allnighter owns: id,
  kind (run/relay/pilot/proof), root, identity, lane state, heartbeat/progress
  age. Reconciles read-only (reports what *would* be reaped; kills nothing).
  Defaults to the caller's project scope (Concurrent Invocation Isolation
  F1); `--all-projects` is the explicit machine-wide fleet view.
- `alln kill <id> | --all [--all-projects]` — the big red button: total group
  kill + terminal `endReason: killed`. An exact id may target any project;
  `--all` is scoped to the caller's project root, `--all-projects` makes it
  machine-wide. What makes overnight trust real: see everything, stop
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

## Follow-up slices (approved 2026-07-17, founder: "if nothing blocks, proceed")

- **PO-F1 — watchdog consumes progress, not silence (pilot enabler, FIRST).**
  RunService/relay stall classification must read the turn's
  `lastProgressAt`/heartbeat (S01/S02 primitives) instead of output silence.
  A cold-CLI turn that is identity-alive and progressing (file writes, child
  process activity count as progress; wire the dev-turn runner to record
  progress on stdout bytes AND on child-process spawn/exit) is never
  classified `.stalled`. A turn identity-alive but with no progress for the
  stall budget is stalled honestly. Works test: a scripted dev turn silent on
  stdout for 2× the old threshold but touching progress → never reaped; same
  turn with progress frozen → reaped with `endReason: stalled`.
- **PO-F2 — `waitToAcquire` timeout reliability.** The lane's wait path must
  resume within a bounded skew of its timeout under load (the flaky XCTest
  path from S04 delta #2). Strong-capture the timeout task, test with tight
  bounds, and stamp `laneBusy` deterministically when the wait expires.
  **Landed 2026-07-17:** ContinuousClock timeout + cancel-safe expire hop;
  `lastWaitEndReason` stamps `laneBusy` on timeout; tight-bound contention tests.
- **PO-F3 — blocking wait + stable exit codes.** `alln team status <id>
  --wait-for <state> --timeout <s>` (single process, no poll spin; returns on
  transition or timeout with nextAction + waitHintSeconds). Documented stable
  exit-code table: distinct codes for usage error / lane-busy / run-failed /
  timeout, exported into the contract artifacts, never renumbered.
  **Landed 2026-07-17:** in-process `waitForStatus`; exit codes 0–4 frozen in
  `ExitCode.stableTable` + `exit-codes.json` + drift test; `STATUS_WAIT_TIMEOUT`
  (3), lane-busy class (4).
- **PO-S06 — scoped write lanes.** A dev turn declares `writeScope:
  [path-prefixes]` and whether it needs the build lane. Docs-only turns
  (no build lane) run concurrently with a code turn when scopes are disjoint;
  overlapping scopes queue FIFO with the ticket. **Fail closed:** at turn end
  the harness diffs the turn's commits against the declared scope — out-of-
  scope changes reject the turn's work (typed error, PM decides); no honor
  system. Panels remain no-lane. Works test: docs-only pilot turn and a
  build-lane holder proceed concurrently; a "docs" turn touching `Sources/`
  is rejected.
- **PO-F4 — harness standing invariants (contract-freshness gate).** The
  harness proof phase (PO-S04) runs the dev's *declared* `proofCommands` plus a
  harness-injected list of **standing invariants** the dev cannot omit. First
  standing invariant: **contract freshness** — after building the turn's tree
  on the persistent scratch, the harness runs `<built alln> dev
  export-contracts --check`; drift (a registry change that did not regenerate
  `docs/generated/alln/*`) fails the standing invariant. Motivation: S06
  (`06294899`) changed the contract registry but did not regenerate the
  published artifacts; nothing caught it and the PM had to (`3850a12b`). A
  failed standing invariant is surfaced distinctly in `proofResults` (a
  `standing: true` + `invariant: contractDrift` marker) and marks the turn
  **not clean** — the pilot/relay does not treat the turn as done; the loop
  continues so the next turn regenerates + commits (Allnighter never touches
  git, so no auto-regen/commit — the harness detects, the dev fixes). Keep the
  standing-invariant list minimal and extensible; ship only contract-freshness
  now. Works test: a dev turn that edits the registry without regenerating
  artifacts → standing invariant fails, turn marked not-clean, `proofResults`
  carries the `contractDrift` marker; a clean turn → standing invariant passes
  silently.
- **PO-F5 — run idle-timeout: override flag + progress-truth reset.** From a
  dev's field report: `alln run` with a warm grok worker was killed at 300s
  (`errorKind: timed_out, timeoutKind: idle`) while grok silently *read four
  context files* — legitimate tool-call work that emits no answer tokens. The
  `alln run` warm-streaming idle timer resets only on answer-token deltas, and
  the override (`RunService.workerTimeoutSeconds`) is packet-only with no CLI
  flag. This is PO-F1's disease (output-silence ≠ progress) in the driver/warm
  path instead of the relay watchdog. Two parts: **(1)** add `alln run
  --idle-timeout <seconds>` (plumb to `workerTimeoutSeconds`; register on the
  `run` CommandSpec + regenerate contracts; typed usage error on bad value);
  **(2)** reset the warm-streaming idle timer on *any* activity — tool-call
  events, reasoning/thinking deltas, stderr bytes, child spawn/exit — not just
  answer-token deltas (reuse the F1 progress concept where the streaming path
  allows). Guard: do NOT touch the relay/pilot `ProcessGroupCommandRunner` path
  (already progress-truth from F1); default idle budget unchanged (300s) when
  no flag. Pointers: `RunService.swift:37/406/622/658`, grok manifest
  `invoke.timeoutSeconds:300` in `DefaultConfig.swift`, the `WorkerInvoking`/
  `DefaultWorkerRunner` streaming seam. Works test: idle timer resets on a
  tool-only stream event (only tool events for > budget → NOT timed out);
  still fires on genuine total silence past budget; `--idle-timeout` flows to
  the runner. (First real exercise of the PO-F4 contract-freshness gate, since
  this touches the `run` CommandSpec.)
  **Landed `d4f4242f` — finding corrects part (2):** investigation showed the
  `alln run` idle timer is `ProcessGroupCommandRunner` (`RunService.swift:160`
  default), whose F1 progress-truth **already resets on any raw stdout/stderr
  bytes** — tool-call streaming-JSON, reasoning deltas, stderr all count, before
  parsing (`ProcessGroupCommandRunner` runStreaming `onBytes` →
  `progress.note(phase:"output")`). So part (2) was already satisfied at the
  byte level; the dev's kill was a turn that emitted **zero bytes** for the full
  budget (genuinely silent internal file reads), which no activity-based reset
  can detect — the worker is a black box. Part (1), `--idle-timeout` (raise the
  budget), is therefore the correct and sufficient fix; it shipped with a 9-test
  suite. The `timeoutKind:.idle` label lives in AgentOS
  `DefaultWorkerRunner.swift:272`. PM note: verified independently in both
  directions — first suspected a dodged part (2), traced the runner, found it
  already correct; do not "re-fix" it.
- **PO-F6 — `export-contracts` cwd-robustness (harden the F4 gate's tool).**
  Discovered while dogfooding F5: `alln dev export-contracts [--check]` resolves
  the generated dir from **raw `currentDirectoryPath`** (`runExportContracts` in
  `AllnighterCLI.swift`, `ContractExport.generatedDir = "docs/generated/alln"`),
  producing two real bugs. **(a) `--check` false-positive:** run from any
  subdirectory, each artifact file reads `nil` (not found) and is reported as
  `CONTRACT_DRIFT` — "not found / wrong cwd" is conflated with "content
  drifted." **(b) write-mode litter:** run from a subdirectory, write mode
  `createDirectory(withIntermediateDirectories:)` creates a stray
  `<subdir>/docs/generated/alln/` (confirmed: a gitignored stray copy under
  `Packages/AllnighterCore/docs/` from a prior errant run; removed). This
  threatens PO-F4, whose standing invariant runs `<built alln> dev
  export-contracts --check` — any non-root cwd would cry `contractDrift` on a
  clean turn (F4 passes `repoRoot` to `runProofs` today, so it is correct but
  fragile-by-dependency). Fix: **(1)** resolve the generated dir relative to the
  **repo root** (ascend from cwd to the dir that contains `docs/generated/alln`
  or a `.git`; reuse an existing repo-root finder), not raw cwd; **(2)**
  `--check` must distinguish *artifacts-missing / not-at-repo-root* (a distinct
  typed error + message, exit non-zero) from *content drift* (`CONTRACT_DRIFT`)
  — never label missing files as drift; **(3)** write mode refuses (typed
  error) rather than littering when no repo root is found. Works test: `--check`
  and write both succeed identically from repo root and from a subdirectory
  (same result, no stray dir created); a genuinely-drifted artifact still
  reports `CONTRACT_DRIFT`; a missing generated dir reports the not-found error,
  not drift. (Touches the `dev export-contracts` surface → exercises the F4 gate
  again.)
- **PO-F7 — pilot/relay dev-turn idle-timeout override.** F5 added
  `alln run --idle-timeout` → `RunRequest.workerTimeoutSeconds` → runner idle
  timeout, but the pilot/relay dev turn dispatches through `runService.run`
  (`RelayCoordinator.swift:~1055`) **without** setting `workerTimeoutSeconds`, so
  dev turns are stuck at the manifest default with no operator override. Add
  `--idle-timeout <seconds>` to **both** `alln pair pilot start` and
  `alln pair relay`; thread it into `RelayCoordinator.Config`
  (`devTurnIdleTimeoutSeconds: Int?`); in `dispatchDevTurn` set
  `RunRequest.workerTimeoutSeconds` from it (reuse F5's field + parse helper —
  no second idle system). Register both flags on the CommandSpecs + regenerate
  contracts. Default unchanged when no flag. Motivated hard by the 2026-07-17
  1 MB/s-connection session (a 300s default falsely reaped trickling grok turns;
  the interim default was bumped to 1800s in `DefaultConfig.swift` — F7 is the
  per-run operator control on top of that saner default).
- **PO-F8 — honest turn classification (no "done" on empty work).** Surfaced by
  the same slow-connection session: a dev turn where grok emitted only its
  opening line before the ACP stream died — **zero diff, no commit, no declared
  `proofCommands`** — was classified `endReason: reported` (a clean completion)
  and parked `awaitingPM`. That is a lie: nothing was produced. The harness must
  not treat an *empty* turn as done. Rule: a dev turn that produced **no commit
  (baseline..head unchanged) AND declared no proofCommands AND emitted below a
  minimal substantive-output threshold** is classified `incomplete` (a distinct
  `endReason`, not `reported`/`stalled`) and the pilot/relay does **not** park it
  as a clean turn — the loop continues / surfaces it to the PM. Do not
  auto-retry blindly; surface honestly. (Connection-drop resilience is a
  separate concern — F8 is only about not *lying* that empty work is done.)
  Works test: a turn with unchanged HEAD + no proofCommands + trivial output →
  `endReason: incomplete`, not parked as done; a real turn (commit or declared
  proofs) → unaffected.

- **PO-F9 — ExecutionLaneFlock hardening (Kimi K3 review, all findings verified 2026-07-18).**
  A fresh-model (Kimi K3) adversarial review of `ExecutionLaneFlock.swift` surfaced
  14 issues; the session PM verified **all 14 against the code**. Fix in one slice,
  highest-severity first. Do NOT weaken the cross-process lane guarantees.
  **High:**
  1. `open(path, O_CREAT|O_RDWR, 0o600)` (line ~559) lacks `O_CLOEXEC` — spawned
     worker subprocesses inherit the flock fd, so the kernel keeps the lock until
     every child exits; parent death never releases the lane. Add `O_CLOEXEC`.
  2. `meta.lock` reuses the build-lane refcount table (`tryAcquireFile`), which is
     NOT mutually exclusive between threads of one process (2nd caller just bumps
     refCount and runs) → lost updates to `holder.json`. Give `withMetaLock` a real
     per-lane in-process mutex (recursive/held-set for same-thread re-entry) around
     the whole RMW; keep the flock for cross-process.
  3. `clearHolder` (274-279) deletes the whole `holder.json` (wiping other live
     processes' docs-only holders), takes no meta lock, and has a TOCTOU. Take
     meta lock, re-read, remove only this process's identities, delete only if empty.
  4. `upsertHolder`/`removeHolder` use `try? writeHolders` then report success —
     a failed disk write leaves the holder unregistered while the caller believes
     it is registered (undetected scope overlap). Propagate write failure.
  5. `tryAcquireFile` conflates `open`/`flock` errno (EMFILE, ENOLCK, unsupported
     FS on network-mounted `~/Library`) with contention → permanent false "busy."
     Check errno; only `EWOULDBLOCK` is contention, surface the rest distinctly.
  **Medium:**
  6. Docs-only admission TOCTOU: `conflictingHolders` reads only `holder.json`; a
     foreign build holder between `tryAcquireExclusive` and `upsertHolder` is
     invisible → overlapping docs-only claim wrongly admitted. Conservatively treat
     a foreign-held flock with no visible conflicting holder as a conflict.
  7. Waiter files (`WaiterFile`) carry no owner identity → crash between
     register/unregister leaks a file that inflates every future ticket position.
     Embed `OwnerIdentity`, filter dead waiters (mirror `isHolderEffectivelyLive`).
  8. `ticketIfBusy` mints `unknownTicket` only when `holders.isEmpty`; one live
     docs-only holder makes a foreign-held build flock read as "not busy." Drop the
     `&& holders.isEmpty` for build claims.
  9. `isLocked` probe has side effects (creates dir/lock file; transient
     `isHeldLocally`; can steal the flock for a microsecond from a racing acquirer)
     and returns stale truth. Real acquirers should retry a few times before
     concluding busy.
  **Low:** 10. `removeHolder` matches on `id` alone (add identity check). 11.
  lane-key sanitization collision (`v1:abc` == raw `abc`) — make the fallback
  escape-proof. 12. `writeHolder`/`writeHolders` public with comment-only lock
  contract — make private / route through locked helpers. 13. `waiterPosition`
  missing-file fallback off-by-one vs `wouldBePosition` (return `count+1`). 14.
  table `NSLock` held across `open`/`flock`/mkdir (pre-create dir outside the lock).
  Works test each fix; RelayCoordinatorTests + ExecutionLaneTests stay green;
  add regression tests for O_CLOEXEC (no fd leak into a spawned child) and the
  meta-lock lost-update case. Implementer: Cursor Grok 4.5.

- **PO-F10 — honest worker resolution + fresh-run robustness (founder bug, 2026-07-18).**
  Root cause of an hour of thrash: `alln run --worker model_cursor_grok_45` (and
  the pilot dev-turn) **silently fell back** to a different model
  (`model_chatgpt`, enabled-but-notReady → failure) because
  `model_cursor_grok_45` was `enabled=False` on the bench. The user explicitly
  asked for Cursor Grok and got ChatGPT with no warning; the pilot dev turn just
  died with `devRunId: NONE`. **A silent substitution of an explicitly-named
  worker is a lie** — same class as F8 (turn honesty) and the "never lie about
  state" law. Founder framing: *"if figuring out how to run a pilot/relay can
  fail this easily it is a non-working product; a new run should assume all prior
  runs are dead and nothing stalls it."*
  Fixes:
  1. **Explicit `--worker X` is honored or fails LOUD.** If `X` is not resolvable
     (disabled, notReady, not on bench, unknown id), `alln run`/pilot/relay
     return a typed error naming exactly why and the one-line fix
     (`WORKER_NOT_AVAILABLE`: "model_cursor_grok_45 is disabled — run
     `alln models enable model_cursor_grok_45`" / "is notReady — check
     `alln doctor`"). NEVER substitute a different model behind an explicit
     `--worker`/`--dev-worker`. (Team-resolved default routing may still
     fall back — that path is implicit; the explicit override must not.)
  2. **Pilot/relay dev-turn worker resolution** must surface the same typed
     error before the stall-retry loop — a dev turn that can't resolve its
     worker must escalate with `WORKER_NOT_AVAILABLE`, not 4 silent stalls +
     `devRunId: NONE`.
  3. **Stale-lane GC:** hundreds of dead-pid `holder.json` dirs accumulate under
     `Lanes/` and never get cleaned (functionally harmless — `isHolderEffectivelyLive`
     filters them — but noise, and a symptom). A fresh run / `alln doctor` should
     opportunistically GC lane dirs whose holders are all identity-dead and whose
     flock is unheld. A new run must never be blocked or confused by prior state.
  Works test: `--worker <disabled-model>` → `WORKER_NOT_AVAILABLE` typed error
  (exit non-zero), never a different model; enabling it → the run uses it; a
  pilot with an unresolvable `--dev-worker` escalates with the typed reason, not
  a stall. Implementer: TBD (Cursor Grok / Sonnet).

- **PO-F11 — Sol review hardening (ChatGPT 5.6 Sol adversarial review, verified
  2026-07-18).** An unbiased `alln run --worker model_chatgpt_sol` review of the
  whole pilot/relay/lane/handover subsystem (21 files) surfaced 28 findings;
  five adversarial verifier agents checked each against the real code (and against
  F9/F10). 26/28 point at real code — 1 false positive (`TurnOwnerDirectory.shared`
  is per-process), 1 non-bug stub (`publishMedia` R2 plane unwired). 15 verified
  worth-fixing (SR-1..SR-15), 8 marginal, 3 real-but-not-worth. Highest value:
  SR-3 (kind-chain reentry grants build access without owning the flock — the one
  same-process route to two builders), SR-1/SR-2 (HandoverGate `"without"` cue and
  `rm -rf` first-target-only bypasses), SR-11 (ThreadFlockLock missing `O_CLOEXEC`
  — the O_CLOEXEC class in the one flock file F9 didn't touch), SR-4 (honest errno
  exists at the flock layer post-F9 but isn't wired into the registry). Full
  verified ledger + fix IDs: [Sol_Review_Hardening.md](Sol_Review_Hardening.md).

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
