# Run Lifecycle Reliability — every accepted run stays observable, stoppable, and recoverable

Status: **HARDENED — P0 execution gate. Do not start product patches until
RLR-S00 reproduces the field signatures.** Spec Review (Codex Sol lenses,
2026-07-19 run `2ADCE96A-…`) + live re-hang (Kimi `alln run`, same day) forced
the edits below. Founder intent still stands: build RLR-S00–S06 before IR-S02 or
Agent Onboarding V1. Execute one bounded slice at a time.
Owner: AllnighterCore + AllnighterEngine + AllnighterCLI (`TeamRun`/`RunStore`,
`RunService`, `ProcessOwnership`, `ExecutionLaneRegistry`, CLI JSON/NDJSON)
Updated: 2026-07-19 (spec harden pass)

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

**Reproduced 2026-07-19 (same machine):** `alln run --project . --worker
model_kimi_k3` hung again in `fanning_out` with a live `kimi-code` child,
heartbeat stuck at `phase: accepted` / `sequence: 0`, no `workers/` artifacts,
and `alln kill --all` reporting `killedCount: 0` while the mutating lane holder
still named the dead coordinator pid. Runs: `8AAA520D-…`, `BD26C1D1-…`.

The product claim is not merely “Allnighter can spawn a CLI.” The honest claim:

> Once Allnighter accepts a run, another process can identify it, understand what
> it is waiting on, observe sourced activity, attempt to stop its recorded process
> tree, and either prove settlement or return a typed refusal/partial outcome —
> then retry intentionally without competing with leftovers.

“Always stoppable” is too strong (uninterruptible processes, escaped children,
verification failure). Promise **prove stopped, or name what remains.**

Until that claim is proven, routing and onboarding must not send more agents
into the execution path.

## Trusted workflow slice (P0 gate)

```text
route a named cold mutating worker
→ receive one canonical run id (journal already durable)
→ observe admission / spawn / real activity
→ poll the same durable truth from another process
→ kill the complete recorded ownership tree
→ see the lane released (or typed survivors)
→ intentional linked retry once, cleanly
```

**P0 vertical:** cold, single-worker, foreground mutating `alln run` (fake
CLI / Kimi-like subprocess). Answer teams, warm ACP workers, relay/pilot, and
durable governor/capacity queues extend the same contract afterward — they must
not obscure the first proof. Warm/shared workers are either given explicit
cancel semantics in S04 or **excluded** from the P0 Works Test (S00 spawn-site
matrix decides).

## Spec Review synthesis (2026-07-19)

Sources: Codex Sol First Principles (`model_chatgpt_0.answer.md`) + Cursor Sol
Proof Planner (`model_chatgpt_sol_0.answer.md`) on Spec Review Min run
`2ADCE96A-…` (Lead synthesis never ran — Claude session limit; answers preserved
on disk). Live re-hang above.

| Verdict | Do **not** execute RLR-S00–S06 unchanged. Promise stays; freeze shape changes. |
| --- | --- |
| Contract freeze | S00 freezes **evidence + invariants**, not the draft flat `phase`/`blocker` bag. S01 chooses public lifecycle convergence. |
| Kill | Typed `KillOutcome`; zombies ≠ survivors; never stamp terminal kill on “signal attempted.” |
| Retry | Separate transport replay (same key) from intentional `retryOf` (new key). |
| Capacity | P0 durable blocker = `repoWriteLock` only; governor/capacity stay typed pre-accept refusals unless this phase owns new fairness. |
| RCA | S00 must reproduce exact `RUN_NOT_FOUND` signature classes before status patches. |

## Risk and debugger classification

Tier: **T3 Critical** — destructive process control plus repeated persisted-run
truth failures.

Bug fingerprint:

```text
alln run lifecycle + live worker/journal disagreement + RunStore/process-owner/control-plane proof gap
```

- **Truth owners (joined by one journal snapshot):**
  - `TeamRun`/`RunStore` owns durable lifecycle, phase, blocker reference,
    activity summary, ownership receipts, terminal reason.
  - OS process table (validated against recorded start time) owns liveness.
  - `ExecutionLaneRegistry`/`ExecutionLaneFlock` owns admission holder/ticket.
  - `RunEvent` is a **projection** of journal transitions, not a peer truth.
- **Lie-prone layers:** `fanning_out`, CLI status projection, `alln ps`,
  `alln kill`, final-only `--json`, streams that omit real activity, orphan
  lane holders after coordinator death.
- **Isolation harness:** required by `docs/operations/Debugger.md` before fixes.
  Use a deterministic fake CLI, not a paid/live model.

Before product edits: add an **initial incident packet** to
`docs/operations/debugger/DEBUGLOG.md` (this hang + original field report).
Append **final RCA only after** S00 reproduction. Do not claim the precise
`RUN_NOT_FOUND` cause until the harness reproduces it.

## Current state (verified 2026-07-19)

1. `RunService` can take the per-root write lock before minting/persisting the
   foreground run id. Legacy wait overload may wait ~1,800s with no durable run
   or blocker record.
2. A single-worker execution run uses aggregate status `fanning_out`, which
   cannot distinguish admission, spawn, tool activity, proof, or a wedge. Live
   hang: worker child alive, journal still `fanning_out`, heartbeat never
   advanced past `accepted`.
3. `alln run --stream` drops `.toolActivity`, `.rawEvent`, and `.started` at the
   public projection in places. Idle-timer runner activity ≠ durable pollable
   activity truth.
4. `RunStore` stamps a foreground non-terminal run with the coordinating
   process's `.inProcess` owner. The spawned worker is a process-group leader,
   but its identity is not durably attached for an external kill.
5. `ProcessOwnershipSurface.killRun` can stamp `.cancelled`/`.killed` even when
   `terminateRecordedOwnerIfSafe` returns `false`.
6. `team status` is intended to read the shared `RunStore`, yet the field run
   returned `RUN_NOT_FOUND` while a journal existed. Cause open — see S00 RCA
   classes below.
7. Floor-wide `ps` does not make causality legible: repo write lock, governor,
   driver capacity, and vendor-internal waiting must never collapse to one
   generic “lane busy.”
8. Known race candidate (not proven as the field signature): stream may emit
   `teamRunStarted` before `runStore.save` completes — can cause **transient**
   `RUN_NOT_FOUND`, but does not alone prove “journal existed.”

## Binding semantic laws

### RLR-L1 — one canonical run identity

The id emitted by the start/stream surface is the id accepted by status, result,
cancel/kill, history, journal lookup, and GUI/iOS projections. Filesystem folder
names such as `run_<id>` are storage detail and are never a second id. An
emitted id that cannot immediately round-trip is a failed acceptance.
**Acceptance boundary:** validation failures have no run id; once an id is
emitted, its journal and status projection must already exist.

### RLR-L2 — accepted means durably controllable

Mint and persist the run plus its admission state before any potentially long
wait. Do not emit “accepted,” `running`, or `workerStarted` until the facts those
words claim are durable. A caller may lose its terminal; another process must
still recover status and control from the journal.

### RLR-L3 — lifecycle status and phase are different truths

One **public** closed lifecycle (`queued | running | done | failed | timedOut |
cancelled | interrupted`) plus one sourced current **phase**. Do not mint
transport-specific statuses as peer truth.

Today three vocabularies coexist (internal `RunStatus`, public `TeamRunJSON`,
async `accepted|…|synthesizing|…`). S01 must either:

- **Recommended:** schema-v2 hard converge public surfaces on the closed
  lifecycle (including `--wait-for` values), with explicit legacy mappings; or
- Preserve async compatibility and retract “one shared lifecycle” as a P0 claim.

Minimum phase vocabulary:

```text
admitting | waitingForWriteLock | spawningWorker |
working | proving | settling
```

(`waitingForCapacity` is **not** a P0 durable phase unless capacity becomes an
accepted wait — see L4.)

Validity table (minimum):

| Lifecycle | Allowed phases |
| --- | --- |
| `queued` | `admitting`, `waitingForWriteLock`, `spawningWorker` |
| `running` | `working`, `proving`, `settling` |
| terminal | no active phase (omit `phase`, or retain only `settling` during settle — S01 picks one rule) |

Atomic rule: changing phase clears/replaces `blocker` in the **same** journal
revision. `startedAt` is when a worker OS identity is durably recorded — not
when spawn is merely attempted. `fanning_out` must not remain the visible phase
for a one-worker execution run.

### RLR-L4 — every wait names the actual resource

Blockers are a **discriminated union**, not a flat bag of optional fields:

| Resource | P0 policy | Required facts |
| --- | --- | --- |
| `repoWriteLock` | Durable accepted FIFO wait | `scopeRoot`, holder work ref, FIFO position, `holderAcquiredAt`, optional deadline |
| `teamGovernor` | Typed **pre-accept refusal** (fail-fast today) | configured limit + observed occupancy; no fake holder |
| `driverCapacity` | Typed **pre-accept refusal** / cooling | driver/`sourceId`; position only if a real gate owns one |
| `vendorBackoff` | Only when vendor emits a sourced wait | driver id + sourced reason/reset; never infer from silence |

Persist stable timestamps (`blockedAt`, `holderAcquiredAt`). Derive
`heldSinceSeconds` at **read/projection** time — do not treat a ticking duration
as journal truth. Map internal holder kinds (`mutatingRun`, `relayDevTurn`, …)
to the public `holderKind` enum in S01. A run in project A must never name
project B as a repo-write-lock holder.

### RLR-L5 — the complete ownership tree is the kill target

Every spawned worker records `{pid, pgid, startTimeTicks, kind}` in a
**runtimeOwnership** section (keyed by worker id) — not overloaded onto catalog
`Worker` rows. Coordinator identity remains a separate owner. S00 audits every
spawn site (cold `ProcessGroupCommandRunner`, warm ACP/`Foundation.Process`,
etc.) with ownership type, exclusivity, recording point, cancel mechanism, and
proof.

Kill uses one identity-checked group-kill over the complete recorded set.

**KillOutcome** (required):

```text
stopped | partial | refused | verificationUnavailable
```

- Terminal success (`status: cancelled`, `endReason: killed`) requires no
  **execution-capable** survivors.
- Zombie-only residuals may be terminal with a cleanup warning (cannot mutate
  the repo; must not hold the lane hostage forever).
- `partial` / `refused` / unverifiable must **not** stamp terminal killed.
- Report signal attempts + errno, surviving identity-checked members, and
  zombie-only residuals separately.
- Kill order: snapshot identities → terminate worker groups → terminate
  coordinator if safe → verify → release admission.
- Retain ownership receipts after terminal settlement long enough to detect
  contradictions (today terminal saves delete owner markers too eagerly).

### RLR-L6 — liveness, activity, and repo change are not synonyms

- Owner heartbeat proves the coordinating owner is alive.
- `lastActivityAt` advances only on real worker activity: **post-spawn** tool
  events, reasoning/answer bytes, bounded raw stdout/stderr **metadata**
  (timestamp, byte count, worker id — not raw secret-bearing content), observed
  child transition, or exit.
- Spawn itself advances ownership/`startedAt`, **not** `lastActivityAt` (see L8).
- Timer heartbeats may repeat `lastActivityAt`; they must not advance it.
- Files touched only from driver tool events or deterministic repo observation.
- Status exposes activity age and `progressStale` without fake percentages.

### RLR-L7 — one clean JSON contract, one live stream contract

- `--json` prints exactly one terminal JSON object (silent until completion).
- `--stream` prints only live NDJSON: first event = canonical run id; then
  phase/blocker/activity; exactly one terminal event.
- Router/onboarding recipes use `--stream` or async start/status/result — not
  final-only JSON as a monitor.

No parallel run schema. Grammar consolidation is a later hard cutover. Surfaces
project the same `TeamRunJSON` / `TeamStatusResponse` / `RunEvent` / error
catalog once S01 converges lifecycle enums.

### RLR-L8 — stale is not permission to kill

Four bounded clocks: runner-ready handshake, **time to first post-spawn
activity**, rolling activity-idle timeout, total wall timeout. Existing
`--idle-timeout` owns the rolling budget over the L6 activity set.

An unrelated new run never auto-kills an identity-alive stale run. Explicit
kill/cancel or visible wait under policy. A timeout belonging to the run may
kill its own group.

### RLR-L9 — transport replay ≠ intentional retry

Two distinct mechanics:

1. **Transport replay** — same idempotency key + same canonical payload returns /
   reattaches to the **original** run for the retention window. Never starts a
   second worker because stdout was lost. Same-key after a killed terminal must
   not unexpectedly re-execute.
2. **Intentional retry** — new key + `retryOf:<old-run-id>` (`RunLink.retryOf`),
   only after the old ownership tree is verified safe (or typed survivors are
   accepted by the operator).

Generalize the existing atomic `IdempotencyStore` (do not invent a second store).
Foreground canonical payload includes: normalized root, message/context,
resolved team/worker, effort, attachment digests, thread, timeouts, proof
command, commit/no-commit, contract version.

`--json` replay waits for the original terminal result (or a separately named
start envelope). `--stream` replay attaches to / replays the durable event
sequence, or returns an acknowledgement directing the caller to status — never
a second silent worker.

## CLI-first contract

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

Additive shared fields — **shape finalized in RLR-S01 after S00 evidence**, not
frozen blindly in S00:

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
    "holderAcquiredAt": "…",
    "holderDeadlineAt": null
  },
  "lastActivityAt": "…",
  "lastActivityKind": "tool|stdout|stderr|child|exit",
  "progressStale": false,
  "killOutcome": "stopped|partial|refused|verificationUnavailable"
}
```

`blocker` absent when unblocked. `heldSinceSeconds` is derived at projection.
New errors are stable catalog entries; regenerate `docs/generated/alln/*`.

## Inference bans

| Junction | Owner | Forbidden inference | Negative proof |
| --- | --- | --- | --- |
| Journal → status | `RunStore` | Directory exists ⇒ invent/recover a different id | Emitted id round-trips; malformed/other id fails |
| Owner → kill | recorded worker identity | Terminal ⇒ no process survives | Terminal+live-group contradiction surfaced |
| Heartbeat → progress | activity owner | Timer fired ⇒ worker advanced | Heartbeats leave `lastActivityAt` unchanged |
| `ps` row → blocker | lane/governor/driver | Visible concurrent work caused this wait | Blocker names only the causal resource/holder |
| Repo diff → activity | `GitObserver` | Any concurrent change belongs to this worker | Isolated harness attributes only owned work |
| Retry → new spawn | idempotency store | Lost stdout ⇒ prior work is dead | Same-key two-process retry yields one worker/run id |
| Silence → vendor wait | vendor adapter | No output ⇒ capacity blocker | Vendor wait only from sourced signals |

## Slices (execute strictly in order)

| Slice | Deliverable |
| --- | --- |
| **RLR-S00 — RED harness + evidence/invariant freeze** | DEBUGLOG initial packet. Deterministic fake CLI (buffer, tool activity, grandchild, hang, ignore graceful kill). Spawn-site matrix (cold/warm). Red two-process tests. **RCA gate** for `RUN_NOT_FOUND` classes: (1) run dir absent (2) dir without `run.json` (3) unreadable/undecodable (4) decoded id differs (5) different support-root namespaces — assert exact emitted id bytes, expected journal present under same `ALLNIGHTER_SUPPORT_DIR`, second-process status still fails. Freeze **invariants** (L1–L9), not an unproven flat contract shape. |
| **RLR-S01 — identity + status truth** | Mint/persist before long waits; pollable id from second process; choose public lifecycle convergence; remove one-worker visible `fanning_out`; journal/status/result same id; phase/blocker validity + atomic revision rule. |
| **RLR-S02 — visible admission** | Claim-bearing FIFO + ticket callback; persist/stream **`repoWriteLock`** blockers; prove no spawn while blocked; different roots do not share a lock. Governor/capacity remain typed refusals unless explicitly promoted. |
| **RLR-S03 — live activity stream** | Project `.started`, sanitized tool activity, bounded stdout/stderr metadata, child transitions, sourced repo observations; heartbeats repeat rather than fabricate `lastActivityAt`; `--json` final-only. |
| **RLR-S04 — total kill + contradiction recovery** | Attach runtimeOwnership; typed `KillOutcome`; exact/scoped kill/cancel/watchdog verify the tree; refuse terminal lies; warm-worker policy from S00 matrix. |
| **RLR-S05 — watchdog + replay/retry** | Handshake / first-post-spawn / rolling-idle / wall clocks; foreground `--idempotency-key`; transport replay vs `retryOf` intentional retry. |
| **RLR-S06 — full trust gate** | Two-process matrix, contract drift, Core wall, morning-zero-orphans. Only then unblock IR-S02 / Onboarding V1 with shipped fields/commands. |

## Works Test

Using a built `alln` and the fake Kimi-like CLI:

1. Start a named mutating run with `--stream`; capture first event's run id.
2. Second process polls that exact id while the worker is live; journal and
   status agree on lifecycle + phase.
3. Hold root with run A; start B → durable `waitingForWriteLock` naming A + FIFO
   facts, no spawn. Run C on another root is not blocked by A's repo lock.
4. Buffer answer output while emitting tool/raw activity; NDJSON stays live;
   `lastActivityAt` advances only on L6 events.
5. Idle budget expires → harness kills worker + grandchild; pgid empty or typed
   `KillOutcome`; lane releases; B proceeds.
6. `alln kill <id>` while fake worker/grandchild live; both die or typed
   survivors. Terminal-journal/live-child fixture is surfaced, not skipped.
7. Kill coordinator after first event; recover + kill worker from process B.
8. `kill --all` same-root scope; other-root work protected.
9. Same-key two-process replay → one run/worker. Changed payload → conflict.
   Intentional new-key `retryOf` after verified stop.
10. Corrupt/unreadable journal → typed error (not silent invent).
11. Exactly one terminal NDJSON event on success, cancel, timeout, kill.
12. Close: `alln ps --all-projects --json` shows zero identity-alive harness
    orphans.

Proof commands when the slices exist:

```bash
swift test --package-path Packages/AllnighterCore --filter RunLifecycleReliability
swift test --package-path Packages/AllnighterCore --filter RunLifecycleTwoProcess
bash scripts/check.sh
```

Missing proof today: the named harness/tests do not exist; that is RLR-S00, not
a waiver. Prefer extending `ConcurrentInvocationTwoProcessTests` fixtures over
parallel plumbing.

## Non-goals

- No intent matching, named-worker semantics, recipe installer, or onboarding UI.
- No new scheduler, daemon, per-project registry, or second ownership/lane system.
- No durable governor/capacity **queue** in this phase (refusals only unless
  explicitly re-scoped).
- No fake progress percentages, runtime forecasts, cost forecasts, or queue ETA.
- No automatic killing of unrelated identity-alive work on fresh-run startup.
- No vendor CLI redesign; adapters expose only activity the vendor actually emits.
- No GUI polish. Mac/iOS later render the same CLI/Core contract.
- No broad CLI noun/verb cutover in the reliability phase.
- No unbounded raw stdout/stderr retention in the journal (bounded metadata only).

## Done when

- Every accepted foreground or async run id round-trips from another process.
- Every wait has a causal typed blocker or is not presented as blocked.
- Every live cold worker has durable killable group identity; run exposes the
  complete coordinator + worker ownership tree.
- Kill/cancel/timeout either leave recorded groups empty or return typed
  `KillOutcome` without terminal lies.
- `--stream` stays live through sourced tool/silence periods; `--json` stays one
  clean final object.
- Same-key replay produces one run and one worker; intentional retry is linked.
- Same-root serialization and different-root isolation pass in real subprocess
  tests.
- Generated contracts are fresh; focused tests + `scripts/check.sh` are green.
- IR-S02 and Agent Onboarding V1 are unblocked only by this green Works Test.
