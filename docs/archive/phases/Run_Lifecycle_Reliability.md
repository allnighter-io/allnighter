# Run Lifecycle Reliability — every accepted run stays observable, stoppable, and recoverable

Status: **Complete (archived 2026-07-19).** RLR-S00–S06 delivered on
`feat/design-chain` (through `e75b7c96`). Code is SSOT; this doc is the
historical law + proof packet. Works Test matrix GREEN (item 7 waived).
Unblocks IR-S02 + Agent Onboarding V1 (Onboarding still waits on IR-S02).
Owner: AllnighterCore + AllnighterEngine + AllnighterCLI (`TeamRun`/`RunStore`,
`RunService`, `ProcessOwnership`, `ExecutionLaneRegistry`, CLI JSON/NDJSON)
Updated: 2026-07-19 (archived).
Slice status: **RLR-S00–S06 delivered end-to-end.** Plans + matrix:
`docs/archive/phases/rlr/`.

Related: `Unified_Run_Model.md` · `CLI_Implementation_Contract.md` · archived
`Process_Ownership.md` + `Concurrent_Invocation_Isolation.md` ·
`Agent_Intent_Router.md` · `Agent_Onboarding.md`.

Provenance: Codex Sol Spec Review Min lenses (`2ADCE96A-…`) · live Kimi
`alln run` re-hang (`8AAA520D-…`, `BD26C1D1-…`) · Kimi K3 direct review
(2026-07-19, GO-WITH-EDITS — applied below).

**S00 evidence delivered 2026-07-19** (Claude-internal orchestration; commits
`c9e8ec1b`, `1c14b823`, `55bbeb73`): incident packet
`docs/debuglog/RLR_incident_packet.md` · spawn-site matrix
`docs/archive/phases/rlr/Spawn_Site_Matrix.md` · fake CLI +
`RunLifecycleTwoProcess` tests reproducing the terminal-lie and
single-worker `fanning_out` signatures. Evidence correction: the two cited
incident runs are **4 seconds apart on 2026-07-19** — one continuous session
(occurrence + immediate reproduction), no earlier journal exists on disk.
Root causes located: unstamped-gate kill lie (`ProcessOwnershipSurface`),
worker identity built but never persisted on plain cold runs, warm drivers
recorded nowhere (S00 matrix verdict: exclude all four warm drivers from the
P0 Works Test).

**S01 DELIVERED 2026-07-19** (commits `53510dc2` S01a, `373baf63` S01b,
`704cb315` S01c; plan `docs/archive/phases/rlr/S01_Execution_Plan.md`): lifecycle +
phase converged (`RunLifecycle`/`RunPhase`, `AsyncTeamLiveStatus` retired,
one-worker `fanning_out` dead — RLR_RED signature (a) GREEN); acceptance
boundary durable-before-waits with hard-gated acceptance save
(`RUN_JOURNAL_UNAVAILABLE`), save-before-emit, support-dir on errors,
idempotency key+hash at acceptance; `JOURNAL_CORRUPT` guard, clock-default
constants, wire freeze + catalog/docs regen. Signature (b) terminal-lie
stayed red for S04 (flipped green in S04b). Spawn-policy debt folded into S04a.

**S02 DELIVERED 2026-07-19** (commits `7ff18d7b` S02a, `84b42268` S02b,
`9655b6a1` S02c; plan `docs/archive/phases/rlr/S02_Execution_Plan.md`): blocked
runs carry durable FIFO ticket facts naming the true holder by canonical
runId (live position re-fire included), `blocker{}` on the wire,
no-spawn-while-blocked proven; root isolation proven (case collapse
verified at the normalize layer — no second normalizer; frozen key
untouched); terminal revision clears blocker + withdraws the FIFO waiter
atomically incl. second-process kill (self-abandon poll + pre-spawn
terminal guard; late-grant race pinned). Works Test items 3 + 14 GREEN
cross-process.

**S03 DELIVERED 2026-07-19** (commits `45e2674c` S03a, `defe7354` S03b,
`a3ff27d4` S03c; plan `docs/archive/phases/rlr/S03_Execution_Plan.md`): durable
`lastActivityAt`/`lastActivityKind` on the journal from L6 events only
(spawn provably never advances; ≤1 coalesced write/s); the L6-banned
per-tick heartbeat floor timer DELETED (the incident's frozen-heartbeat
lie), heartbeat.json demoted to never-read debug artifact, all readers
re-sourced; `progressStale`/heartbeat age are read-time derivations;
`--stream` rides the durable per-Mac seq (restart/reattach continuity
proven), exactly-one-terminal per attachment, replay attach marked +
gap-detectable, `--json` final-only pinned; dropped activity events now
flow as bounded `workerActivity`/`stageActivity` metadata (never payload
text). Works Test 4 shape GREEN.

**S04 DELIVERED 2026-07-19** (commits `3087179e` S04a, `701dc6f6` S04b,
`bf4e8cdf` S04c; plan `docs/archive/phases/rlr/S04_Execution_Plan.md`): worker
`runtimeOwnership` keyed by worker id; async setpgid detachment dead;
spawn signal dispositions reset (inherited SIG_IGN for SIGTERM fixed);
one identity-checked `KillSettlement` (terminal only on verified stop);
`status`/`ps` surface `killOutcome` + read-time
`contradiction: terminalWithLiveOwnership`; ownership receipts retained
after terminal; warm kill returns `verificationUnavailable` (never a
`killed` lie). Terminal-lie signature GREEN.

**S05 DELIVERED 2026-07-19** (plan `docs/archive/phases/rlr/S05_Execution_Plan.md`):
four clocks (`--handshake-timeout` / `--first-activity-timeout` /
`--idle-timeout` / `--wall-timeout`) with budgets on the journal;
`RunClockEnforcer` stamps `timedOut` + `killOutcome` even on partial
(operator-vs-clock asymmetry); idempotency replay /
`IDEMPOTENCY_CONFLICT` / `IDEMPOTENCY_EXPIRED` (24h retention);
`--retry-of` + `--accept-survivors`.

**S06 DELIVERED 2026-07-19** (matrix `docs/archive/phases/rlr/S06_Works_Test_Matrix.md`):
full Works Test 1–15 mapped (14 GREEN, item 7 waived); two-process suite
ungated; `JOURNAL_CORRUPT` + orphan-scan + idle→lane-release + wait-for
lifecycle-only + governor no-id proofs; bounded ownership-receipt reaper;
IR-S02 / Onboarding V1 unblocked in docs. Phase **Complete** — ready to
archive.

## Founder intent

An agent launched:

```text
alln run … --worker model_kimi_k3 --lane design --effort high --json
```

sat in `fanning_out` for 12+ minutes with no usable progress; status disagreed
with the journal; `alln kill --all` did not reap the live worker; a retry
competed with leftovers. The user abandoned Allnighter.

**Reproduced 2026-07-19:** same hang pattern — live `kimi-code` child, heartbeat
stuck at `accepted`/`sequence: 0`, no `workers/` artifacts, `kill --all` →
`killedCount: 0` while the lane holder still named the dead coordinator pid.

Honest claim:

> Once Allnighter accepts a run, another process can identify it, understand what
> it is waiting on, observe sourced activity, attempt to stop its recorded process
> tree, and either prove settlement or return a typed refusal/partial outcome —
> then retry intentionally without competing with leftovers.

Promise **prove stopped, or name what remains** — not “always stoppable.”

Until proven, routing and onboarding must not send more agents into this path.

## Trusted workflow slice (P0 gate)

```text
route a named cold mutating worker
→ receive one canonical run id (journal already durable)
→ observe admission / spawn / real activity
→ poll the same durable truth from another process
→ kill/cancel the recorded ownership tree
→ see the lane released (or typed survivors)
→ intentional linked retry once (--retry-of), cleanly
```

**P0 vertical:** cold, single-worker, foreground mutating `alln run` with a
deterministic fake CLI. Warm/ACP workers: S00 spawn-site matrix either gives
them cancel semantics in S04 or **excludes** them from the P0 Works Test.
Answer teams, relay/pilot, durable capacity queues come after the vertical
proof.

## Applied review outcomes

| Law | Locked decision |
| --- | --- |
| Freeze timing | S00 freezes evidence + L1–L9 invariants; S01 freezes wire shape |
| Kill | Typed `KillOutcome`; identity-alive excludes zombies; foreground-kill settlement protocol (below) |
| Retry | Transport replay (same key) ≠ intentional `--retry-of` (new key) |
| Capacity | P0 durable wait = `repoWriteLock` only; governor/capacity = typed pre-accept refusals |
| RCA | S00 must reproduce `RUN_NOT_FOUND` signature classes before status patches |

## Risk and debugger classification

Tier: **T3 Critical**.

Fingerprint:

```text
alln run lifecycle + live worker/journal disagreement + RunStore/process-owner/control-plane proof gap
```

**Truth owners (one journal snapshot joins them):**

- `RunStore`/`TeamRun` — lifecycle, phase, blocker, activity summary, ownership
  receipts, terminal reason, idempotency key + payload hash (from acceptance).
- OS process table (pid + `startTimeTicks` + non-zombie) — liveness.
- `ExecutionLaneRegistry`/`ExecutionLaneFlock` — admission holder/ticket.
- `RunEvent` — projection of journal transitions, not peer truth.

**Lie-prone layers:** `fanning_out`, status projection, `ps`, `kill`, silent
`--json`, streams without activity, orphan lane holders after coordinator death.

Before product edits: initial DEBUGLOG incident packet (original + re-hang).
Final RCA only after S00 reproduction. Harness = fake CLI, not paid models.

## Current state (verified 2026-07-19)

1. Write lock can be taken before mint/persist; long waits may leave no durable
   run or blocker.
2. One-worker runs show `fanning_out`; re-hang left a live child with frozen
   heartbeat and no worker artifacts.
3. Stream drops tool/raw/started events in places; idle-timer activity ≠ durable
   pollable activity.
4. Coordinator `.inProcess` owner is recorded; worker pgid is not durably
   attached for external kill.
5. Kill can stamp terminal cancelled/killed when terminate returned false.
6. Field `RUN_NOT_FOUND` with journal present — cause open (S00 RCA classes).
7. Floor-wide `ps` collapses unrelated contention into illegible “busy.”
8. Candidate race: stream emit before `runStore.save` (transient only — not
   sufficient for “journal existed”).

**Legacy journals** on disk from pre-v2 shapes: S01 states a map / quarantine /
typed-error policy (do not invent silently).

## Binding semantic laws

### RLR-L1 — one canonical run identity

The emitted start/stream id is the only id for status, result, cancel, kill,
history, journal, GUI/iOS. Folder names `run_<id>` are storage detail.

**Acceptance boundary:** validation/governor/capacity refusals have **no** run
id and **no** journal. Once an id is emitted, journal + status already exist.

**Mid-run `--json` discovery:** `--json` stays silent until the terminal object.
Discover the id mid-run only via `alln ps` (every live row includes `runId`,
`status`, `phase`). No unnamed “start envelope.”

An emitted id that cannot round-trip is a failed acceptance. Status/kill errors
print the effective `ALLNIGHTER_SUPPORT_DIR` (RCA class 5 diagnosis).

### RLR-L2 — accepted means durably controllable

Mint and persist the run (including `idempotencyKey` + canonical payload hash
when a key is supplied) plus admission state before any long wait. Do not emit
accepted/running/workerStarted until those facts are durable.

### RLR-L3 — lifecycle, phase, and transitions

**Public lifecycle (P0):** `queued | running | done | failed | timedOut |
cancelled`. (`interrupted` cut from P0 — no producer.)

S01 converges public surfaces (including `--wait-for`, which accepts **lifecycle
states only**) onto this enum with explicit legacy mappings, or retracts “one
shared lifecycle.”

**Phases (P0):** `waitingForWriteLock | spawningWorker | working | proving |
settling`. (`admitting` cut — nothing observable between accept and
lock/spawn.)

| Lifecycle | Allowed phases |
| --- | --- |
| `queued` | `waitingForWriteLock`, `spawningWorker` |
| `running` | `working`, `proving`, `settling` |
| terminal | omit `phase` |

**Transition producers (minimum):**

| Event | Lifecycle | `endReason` (when terminal) |
| --- | --- | --- |
| Accept (journal durable) | `queued` | — |
| Worker OS identity recorded | `running` | — |
| Proof/settlement success | `done` | `completed` |
| Handshake / first-post-spawn / idle / wall clock | `timedOut` | `timedOut` (+ typed `KillOutcome`) |
| Operator `cancel` (grace then escalate) | `cancelled` | `cancelled` |
| Operator `kill` (immediate) after verified stop | `cancelled` | `killed` |
| Unrecoverable worker/coordinator failure | `failed` | `failed` |
| Governor/capacity refusal | *no run* | — |

Atomic rule: phase change and blocker clear/replace happen in the **same**
journal revision. Terminal transitions clear `blocker` and withdraw any FIFO
ticket in that revision. `startedAt` = worker OS identity durably recorded.
`fanning_out` must not be the visible phase for one-worker execution.

### RLR-L4 — typed blockers

Discriminated union:

| Resource | P0 policy | Facts |
| --- | --- | --- |
| `repoWriteLock` | Durable FIFO wait | Canonical `scopeRoot` (symlink + case normalized), holder work ref, waiter `ticketPosition`, `holderAcquiredAt`; `holderDeadlineAt` null in P0 |
| `teamGovernor` | Pre-accept refusal | Limit + occupancy; no fake holder; error `GOVERNOR_REFUSED` |
| `driverCapacity` | Pre-accept refusal / cooling | `sourceId`; error `CAPACITY_REFUSED` |

`vendorBackoff` deferred post-P0 (inference ban remains: never invent from
silence). P0 public `holderKind` = `run` (relay/pilot/proof later).

Persist timestamps; derive `heldSinceSeconds` at projection. Project A never
names project B as lock holder. Different path spellings of one root share one
lock; true different roots do not.

### RLR-L5 — ownership tree, identity-alive, kill/cancel

Record `{pid, pgid, startTimeTicks, kind}` in **runtimeOwnership** (keyed by
worker id). Coordinator is a separate owner. S00 spawn-site matrix is a **hard
exit criterion** (cold vs warm; recording point; cancel path).

**Identity-alive** (single definition for kill verify, `ps`, S06 orphans):

```text
pid exists ∧ startTimeTicks match ∧ process state ≠ zombie
```

Verify **per recorded member** before any group signal (pgid-reuse guard).

**Cancel vs kill:**

- `alln team cancel` — graceful stop, bounded TERM grace, then escalate; verify;
  return `KillOutcome`.
- `alln kill` — immediate identity-checked group terminate; verify; return
  `KillOutcome`.

**KillOutcome:** `stopped | partial | refused | verificationUnavailable`.

**Foreground-kill settlement protocol:**

1. Killer snapshots recorded identities.
2. Killer terminates **worker** groups (not a responsive foreground coordinator
   first).
3. Killer stamps the terminal journal revision + `KillOutcome` itself.
4. A **responsive** coordinator observes settlement, emits the single terminal
   NDJSON event (if `--stream`), then exits — it is **not** force-killed.
5. Force-kill the coordinator only if orphaned or past TERM grace (stream
   truncation then accepted; journal already terminal).
6. Concurrent killers are idempotent: second kill sees terminal + verifies
   survivors; does not invent a second terminal stamp.
7. Verify identity-alive members; release admission / withdraw FIFO ticket in
   the terminal revision.
8. Retain ownership receipts after terminal long enough to detect
   `status.contradiction: terminalWithLiveOwnership`.

Zombie-only residuals may be terminal with cleanup warning. `partial` /
`refused` / `verificationUnavailable` must **not** stamp `endReason: killed` —
an **operator** kill/cancel that does not reach verified stop leaves the
lifecycle **non-terminal** (run stays `running`/`queued`, `killOutcome`
recorded, survivors visible in `ps`); the operator retries, escalates, or the
clocks fire.

**Operator vs clock terminality (deliberate asymmetry):** an operator
kill/cancel stamps terminal only on verified stop, because its claim *is* the
stop. A clock firing (L8) stamps `timedOut` terminal **regardless** of reap
outcome, because the deadline itself is the terminal truth — any survivors are
recorded via `killOutcome` and surface as
`contradiction: terminalWithLiveOwnership` until reaped.

### RLR-L6 — activity vs heartbeat

- `lastActivityAt` advances only on **post-spawn** activity: tool events,
  structured **message** (reasoning/answer), bounded stdout/stderr metadata
  (timestamp, byte count, worker id — never raw secrets), child transition,
  exit.
- Spawn advances `startedAt` / ownership, **not** `lastActivityAt`.
- Heartbeats are **read-time derivations** (like `heldSinceSeconds`) — never
  per-tick journal writes. Status may expose derived `ownerAlive` /
  `ownerHeartbeatAge`.
- `lastActivityKind`: `tool | message | stdout | stderr | child | exit`.
- `progressStale`: true when `now - lastActivityAt` exceeds the configured
  rolling idle budget (same source as `--idle-timeout`); absent before first
  post-spawn activity.
- Files touched only from tool events or deterministic repo observation.

### RLR-L7 — JSON and stream contracts

- `--json`: exactly one terminal object; silent until then; mid-run id via `ps`.
- `--stream`: NDJSON only; every event has monotonic durable `seq`; first event
  carries `runId`; exactly one terminal event per attachment.
- Stream **replay attach**: replay history with events marked replayed; exactly
  one terminal per attachment (an ack-and-close attachment's ack **is** its
  terminal event). Gap detection via `seq`.
- No parallel run schema.

### RLR-L8 — clocks and stale policy

| Clock | Flag (S05) | Default (S01 may tune) | On fire |
| --- | --- | --- | --- |
| Runner-ready handshake | `--handshake-timeout` | TBD in S01; must be finite | `timedOut` + kill tree |
| First post-spawn activity | `--first-activity-timeout` | TBD; finite | `timedOut` + kill tree |
| Rolling activity idle | `--idle-timeout` (exists) | keep current product default | `timedOut` + kill tree |
| Total wall | `--wall-timeout` | TBD; finite | `timedOut` + kill tree |

Unrelated new runs never auto-kill identity-alive work. Explicit cancel/kill or
visible wait.

### RLR-L9 — replay vs intentional retry

1. **Transport replay** — same `--idempotency-key` + same canonical payload
   within the retention window → original run. Never second worker. After
   retention expiry → `IDEMPOTENCY_EXPIRED`; **never** silently re-execute a
   mutating run.
2. **Intentional retry** —

```text
alln run … --retry-of <old-run-id> --idempotency-key <new-key> [--accept-survivors]
```

   Requires old tree verified stopped, or `--accept-survivors` after typed
   partial. Re-presents the original message against **current** repo state; no
   automatic rollback of partial mutations. Links via `RunLink.retryOf`.

Retention window: configured value (S01 names default + config path). S01
persists key + payload hash at acceptance so S05 does not reshape acceptance.

Canonical payload: normalized root, message/context, resolved team/worker,
effort, attachment digests, thread, timeouts, proof command, commit/no-commit,
contract version. Generalize existing `IdempotencyStore` — no second store.

## CLI-first contract

```text
alln run "<message>" --project <id|path> ... [--idempotency-key <key>] [--retry-of <id>] [--accept-survivors] --json
alln run "<message>" --project <id|path> ... [--idempotency-key <key>] [--retry-of <id>] [--accept-survivors] --stream
alln team status <run-id> --json [--wait-for <lifecycle> --timeout <seconds>]
alln team result <run-id> --json
alln team cancel <run-id> --json
alln ps [--all-projects] --json
alln kill <run-id> --json
alln kill --all [--all-projects] --json
```

Wire shape **finalized in S01 after S00 evidence**:

```jsonc
{
  "runId": "canonical-id",
  "status": "queued|running|done|failed|timedOut|cancelled",
  "phase": "waitingForWriteLock|spawningWorker|working|proving|settling",
  "blocker": {
    "resource": "repoWriteLock",
    "scopeRoot": "/absolute/canonical/root",
    "holderId": "…",
    "holderKind": "run",
    "ticketPosition": 1,
    "holderAcquiredAt": "…",
    "holderDeadlineAt": null
  },
  "lastActivityAt": "…",
  "lastActivityKind": "tool|message|stdout|stderr|child|exit",
  "progressStale": false,
  "killOutcome": "stopped|partial|refused|verificationUnavailable",
  "contradiction": null
}
```

`ps` rows include at least `runId`, `status`, `phase`, identity-alive summary.

**Error catalog (stable codes; regenerate `docs/generated/alln/*`):**
`RUN_NOT_FOUND` (malformed / never-emitted / wrong support root only — not
“journal corrupt”), `JOURNAL_CORRUPT`, `IDEMPOTENCY_CONFLICT`,
`IDEMPOTENCY_EXPIRED`, `GOVERNOR_REFUSED`, `CAPACITY_REFUSED`, `KILL_REFUSED`,
`KILL_PARTIAL`.

`KILL_REFUSED`/`KILL_PARTIAL` are the error-envelope projections of
`KillOutcome.refused`/`.partial` (non-zero exit for scripted callers) — same
fact from the same journal revision, never a second truth.

## Inference bans

| Junction | Forbidden inference | Negative proof |
| --- | --- | --- |
| Journal → status | Dir exists ⇒ invent another id | Emitted id round-trips |
| Owner → kill | Terminal ⇒ nothing survives | Contradiction surface |
| Heartbeat → progress | Timer ⇒ activity advanced | Heartbeats don't write `lastActivityAt` |
| `ps` → blocker | Visible work caused this wait | Blocker names causal resource only |
| Repo diff → activity | Any change is this worker | Isolated harness |
| Retry → spawn | Lost stdout ⇒ dead | Same-key → one worker |
| Silence → vendor wait | No output ⇒ capacity | Sourced signals only |

## Slices (strict order)

Full Works Test runs only as the **S06** gate (never red-fail mid-phase slices
on the whole matrix). S01 may ship `running`/`working` before S03 activity
truth — say so; keep behind harness flag.

| Slice | Deliverable |
| --- | --- |
| **RLR-S00** | DEBUGLOG packet. Fake CLI. **Spawn-site matrix (hard exit).** Red two-process tests. RCA classes for `RUN_NOT_FOUND`. Freeze L1–L9 invariants. |
| **RLR-S01** | Mint/persist before waits; pollable id; lifecycle convergence; drop one-worker `fanning_out`; transition table; persist idempotency key+hash; legacy-journal policy; clock flag defaults. |
| **RLR-S02** | FIFO claim + ticket callback; `repoWriteLock` blockers; no spawn while blocked; root isolation; **terminal revision withdraws FIFO ticket**. |
| **RLR-S03** | Activity projection + `seq` NDJSON; derived heartbeats; `--json` final-only. |
| **RLR-S04** | runtimeOwnership; foreground-kill protocol; cancel vs kill; contradiction surface; warm policy from S00 matrix. |
| **RLR-S05** | Four clocks; idempotency replay; `--retry-of` / `--accept-survivors`. |
| **RLR-S06** | Full Works Test matrix; contract drift; Core+CLI wall; morning zero identity-alive orphans; unblock IR-S02 / Onboarding. |

## Works Test

Fake CLI + built `alln` (tests locate binary via env/`swift build` path —
document in S00). Full matrix = S06 only.

1. `--stream` start; capture first-event `runId`.
2. A second process polls that id while the worker is live; journal ≡ status.
3. Run A holds root; run B gets durable `waitingForWriteLock` naming A + FIFO
   facts, no spawn. Run C on a true different root is not blocked. Same root
   via two path spellings shares one lock.
4. Activity advances `lastActivityAt` only on L6 events; NDJSON stays live with
   monotonic `seq`.
5. Idle budget → kill worker+grandchild; typed `KillOutcome`; lane releases; B
   proceeds.
6. `alln kill <id>` while fake worker/grandchild live; verified stop or typed
   survivors. Terminal+live-child → `contradiction` surface.
7. Kill orphaned coordinator after first event; recover + kill worker from a
   second process (responsive coordinator not force-killed mid-stream).
8. `kill --all` same-root scope; other-root protected.
9. Same-key two-process replay → one run/worker. Changed payload →
   `IDEMPOTENCY_CONFLICT`. `--retry-of` with new key after verified stop.
10. Corrupt journal → `JOURNAL_CORRUPT` (not invent).
11. Exactly one terminal NDJSON event on success, cancel, timeout, kill
    (settlement protocol).
12. Close: `ps --all-projects` → zero identity-alive harness orphans.
13. Governor/capacity over-limit → typed refusal, **no** run id, **no** journal.
14. Cancel/kill of a **blocked** run withdraws FIFO ticket in the terminal
    revision.
15. `--wait-for` accepts lifecycle states only.

```bash
swift test --package-path Packages/AllnighterCore --filter RunLifecycleReliability
swift test --package-path Packages/AllnighterCore --filter RunLifecycleTwoProcess
# CLI/Engine invocation path documented in S00 (or explicit “none — Core only”)
bash scripts/check.sh
```

Prefer extending `ConcurrentInvocationTwoProcessTests` fixtures.

## Non-goals

- Intent matching, onboarding UI, named-worker semantics, recipe installer.
- New scheduler/daemon/second ownership system; durable capacity **queues**.
- Fake progress/ETA; auto-kill of unrelated identity-alive work.
- Vendor CLI redesign; GUI polish; broad CLI noun cutover.
- Unbounded raw stdout/stderr in the journal.
- P0 `vendorBackoff` durable waits; P0 `interrupted` status; P0 `admitting`
  phase.

## Done when

- [x] Accepted ids round-trip; mid-run `--json` runs discoverable via `ps`.
- [x] Every wait is a typed blocker or not presented as blocked.
- [x] Cold workers have durable killable identity; kill/cancel return typed
      outcomes without terminal lies; contradictions are named.
- [x] Stream stays live with `seq`; `--json` is one final object; kill settlement
      preserves the single terminal event when the coordinator is responsive.
- [x] Same-key replay is one worker; `--retry-of` is linked and safe.
- [x] Same-root serialization + different-root isolation proven.
- [x] Contracts regenerated; S06 Works Test + `scripts/check.sh` green (or
      remaining failures named with quarantine — see S06 closeout).
- [x] IR-S02 / Onboarding V1 unblocked only then.

## Pre-implementation checklist

Verified complete 2026-07-19 (PM finalization pass) — spec is closed;
implementation may start at RLR-S00.

- [x] Every lifecycle status, phase, and `endReason` has a named producer; no
      orphan enums.
- [x] Foreground-kill settlement written (terminal stamper, coordinator grace,
      stream-terminal guarantee).
- [x] `--json` mid-run id path stated (`ps`); no unnamed start envelope.
- [x] Identity-alive algorithm defined and shared by kill/`ps`/S06.
- [x] `--retry-of` + `--accept-survivors` + retention window specified.
- [x] Four clocks have flags, a default policy (S01 names finite values), and
      `timedOut` mapping.
- [x] Error catalog enumerated; `RUN_NOT_FOUND` restricted; kill codes mapped
      to `KillOutcome`; docs regen noted.
- [x] `lastActivityKind` covers messages; `progressStale` defined.
- [x] S01 persists idempotency key + hash; legacy-journal policy stated.
- [x] Works Test covers refusal, blocked-run ticket withdrawal, contradiction
      surface, and `--wait-for`.
- [x] Operator-vs-clock terminality asymmetry stated; partial/refused kill
      leaves lifecycle non-terminal.
