# Rate Limit Continuity — parked, not dead: runs survive vendor usage windows

Status: **Complete (archived 2026-07-19).** RLC-S01–S04 delivered on
`feat/design-chain` (`0868a310`, `3dda9e80`, `c712ab8e`, `f89b3601`). Code is
SSOT; this doc is the historical law + proof packet.
Owner: AllnighterCore + AllnighterEngine (`CapacityClassifier`/
`CapacityObservation`, `SourceCapacityLedger`, `SeatReseat`,
`VendorBackoffPolicy`/`VendorBackoffReconciler`, `VendorSubstitutionPolicy`,
`ResidentCoordinator`, `RunBlocker`) + CLI/Mac (park surface).
Updated: 2026-07-19.
Slice status: **RLC-S01–S04 delivered end-to-end.**

Related: `Run_Lifecycle_Reliability.md` (blocker wire, activity truth,
runtimeOwnership) · `parked/Utilization_Admission_Control.md` — RLC is the
**in-flight-run half** of that story: it consumes `CapacityObservation` +
RLR blockers and does **not** revive the admission ledger / Pending drain /
Away Mode (one observation type, two consumers — park now, admission later) ·
`archive/Worker_Session_Continuity.md` (vendor session resume, all five CLIs
proven incl. `codex exec resume`) · SBDS default-model/tier system.

## Founder intent

Every vendor CLI has a usage cap. Hitting it kills work **hard**, and nothing
resumes when the window resets. The founder's real workflow today is an Apple
Watch alarm. Live transcript, 2026-07-19, driving Allnighter's own RLR build:

```text
⏺ Agent "RLR-S03 recon + execution plan" failed: Agent terminated early due to
  an API error: You've hit your session limit · resets 4:20pm (Europe/Madrid)

✻ Baked for 3h 12m 55s

❯ Please continue
```

**3h 12m of dead air**, ended by a human alarm and a typed "Please continue."
The vendor printed the reset time and did nothing with it. Closing that gap —
notice the limit, wait out the stated window, continue — is pure
orchestration. The caps are per-vendor; the work is not, and only a layer
above the vendors can carry it across.

Honest claim (deliberately not absolute — trust is the feature):

> Once accepted, a rate-limited run is never silently lost or mislabeled
> dead. Allnighter records the sourced wait, releases unsafe resources, and
> resumes at the next safe opportunity. When the user's selection policy
> permits, it may continue with a compatible substitute after the prior
> worker is proven quiescent.

## Law: converge, don't invent

Verified in code 2026-07-19 — Allnighter **already has** the Tier 1 parts:

- `CapacityClassifier` → `CapacityObservation` (kinds `accountRateLimit` /
  `providerBusy` / `cooldown` / `authRequired` / …; `observedResetAt`,
  `retryAfterSeconds`, `wakeAfter`, `confidence`; structured + text fixtures)
- `SourceCapacityLedger` (source cooldown projection),
  `PendingCapacityResumeWriter`, `PendingWakePlanner`/`PendingWakeScheduler`
- `SeatReseat` (mid-run hop on capacity walls), `ResidentCoordinator`
- RLR `RunBlocker.resource` wire (`repoWriteLock`/`teamGovernor`/
  `driverCapacity`) with **`vendorBackoff` explicitly deferred post-P0**
- Vendor session continuity proven on all five CLIs (CONT-S1–S5; the "Codex
  session id never captured" note is stale)

RLC is therefore: **promote an observed `CapacityObservation` into a durable
`vendorBackoff` run blocker, reconciled by the resident coordinator, resumed
as the same run.** No second classifier, no second wake planner, no second
hop surface, no `rateLimited(vendor, resumesAt)` type family. S01 must state
which existing Pending-path pieces are promoted into unified-run truth and
which are retired — duplicate capacity truth is the failure mode this law
exists to prevent.

## Lifecycle (the part v1 must get exactly right)

```text
running/working
  → queued/waitingForVendor   (vendorBackoff blocker, quota-scoped)
  → queued/waitingForWriteLock
  → running/working
  → terminal
```

- **One run id, durable sequential `attempts[]`** under the RunRecord:
  attempt number, requested + resolved source/model, start/end, capacity
  observation, vendor session receipt, substitution provenance, terminal
  result. History is appended, never overwritten.
- **Blocked time suspends clocks**: handshake, first-activity, idle, and
  ordinary wall clocks pause while parked; a separate maximum-park policy
  may still apply.
- **Kill/cancel/manual-resume on a parked run are first-class** and
  journal-revision/lease protected so two processes can never resume the
  same run. `alln ps` shows parked truthfully; the watchdog treats
  `waitingForVendor` as quiet-by-design (S03 activity truth), never as
  stalled/orphaned.

## Park rules

- **Release the repo write lock. Never hold it across a capacity wait.** A
  parked mutating run monopolizing the lane for hours would freeze every
  other run in that repo — the feature would feel like a bug. On a settled
  capacity event: close the warm transport, preserve the vendor session
  receipt, release the lock, park outside the lock queue; at wake, transition
  to `waitingForWriteLock` and reacquire normally. The resumed worker is
  instructed to **re-read current repository state** — never depend on the
  repo being unchanged or on frequent commits; continuity must survive
  uncommitted partial work.
- **Close warm workers.** No process is kept alive for hours as a
  checkpoint — that buys little and adds ownership/reboot/idle-TTL/orphan
  complexity. The session id is the checkpoint; the transport is recreated
  at wake.
- **Park only on high confidence.** `accountRateLimit`-class structured
  observations park; low-confidence text cues (`busy`, `unavailable`) stay
  in the existing fail/retry/`SeatReseat` path — never a multi-hour quiet on
  vibes. Classifier order: driver-specific structured events first, text
  fallback only on failed/error channels, **negative fixtures** where
  ordinary model output merely discusses rate limits.
- **Persist a redacted, bounded diagnostic snippet — never raw output**
  (errors can carry prompts, tokens, paths, session material).

## Wake — stateless, from the coordinator tick

No OS timers, no alarm re-arming. The `ResidentCoordinator` periodic tick
inspects journals: any run whose `vendorBackoff` blocker has
`wakeAfter <= now` wakes. This is reboot- and sleep-immune by construction —
overdue parks resume at the next reconciliation. Honest availability
boundary: if the Mac is asleep or the coordinator stopped, resume happens at
next reconciliation; the promise is never "the Mac wakes itself at exactly
4:20."

- `wakeAfter = observedResetAt + anti-drift pad (≥2 min) + jitter (1–5 min)`;
  normalize to a UTC instant immediately at parse (session tz labels drift —
  Vienna→Madrid observed). Date-less times resolve to the next valid future
  occurrence in the stated IANA timezone; DST/clock-jump/malformed/past/
  absurd-future inputs all route to the unknown-reset path — never invent a
  clock, never display a guessed time as vendor truth.
- **Resume-attempt-as-probe**: on wake, send the real resume — a rejection
  re-parks, a success is already working. No separate readiness ping. But no
  "rejections are free" assumption: honor stated reset + `Retry-After`
  always; unknown reset uses bounded exponential backoff with a max cadence,
  a **hard max attempt count, then escalate to human**; single-flight per
  source.
- **Probe hardening**: every resume attempt runs under a strict short
  timeout (~30s) and is tracked via `runtimeOwnership` so the reaper can
  kill a hung probe. The resident engine resumes the run **directly** —
  never by spawning a child `alln run` that could mint a second run.
- **Source-scoped cooldown, not run-scoped.** Ten runs on one capped source
  must not produce ten wake attempts. One cooldown fact per quota scope
  (driver-provided where known: source/account/profile/model-family) lives
  in `SourceCapacityLedger`; the **oldest parked run is the nominated
  readiness attempt** — still limited updates the shared cooldown and the
  rest stay parked; success releases the others gradually through normal
  admission. Cooldown truth is retained **through the observed reset**
  (weekly/monthly caps outlive any 12-hour lookback).

## Resume

Recreate the transport and resume the vendor session (proven on all five
CLIs — see `archive/Worker_Session_Continuity.md`). If the vendor rejects
the stored session (expired during a long park), fall back cleanly to a
fresh session with a **bounded handoff**: original goal, prior-attempt
summary, transcript reference, and the instruction to inspect current repo
state. Then work; on another sourced limit, re-park (append a new attempt).

## Substitution — authorized by provenance, never inferred

"Chat hops, Execute waits" was wrong: default chat is mutating-allowed and
safety must never be inferred from prompt prose. Substitution follows **how
the worker was selected**:

| Selection origin | Automatic substitution |
| --- | --- |
| Auto/default selection | Same-tier compatible substitute when the existing Auto toggle is on |
| Team preset with declared fallbacks | Follow the declared chain |
| Explicitly named worker | Never silently hop — park and offer "Use another model" |
| Substitutions off / unresolved | Wait for the same source |

- A tier is a quality shelf, not a full equivalence map: candidates are
  additionally filtered on tool/image/context/permission/write/model-family/
  driver capability requirements.
- Mutating work: the original worker must be **proven quiescent** (RLR-S04
  ownership/settlement semantics) before another source starts; one source
  executes at a time; keep a visited-source set and a bounded hop count —
  never bounce between cooling vendors.
- All of it flows through the existing SBDS resolver + `SeatReseat` — no
  third substitution surface.
- Product default: same-vendor continuation **always on**; cross-vendor
  follows the table above.

## Scope — v1 is single-worker accepted runs only

Answer teams already have one-shot reseating: a limited answer seat
fail-softs (board proceeds with remaining answers, absence explicit to the
plan writer) or reseats immediately — **never park a parallel round**.
Parked-seat / partial-board settlement semantics are a later slice.

Moved out of RLC:

- **Tier 3 self-metering + cost advisor** — conflicts with the product law
  "Observed usage only. No estimates." Parked as a separate idea on its own
  law-compliant (retrospective, observed-facts) footing; nothing in RLC
  productizes burn advice. Limit events are logged durably anyway (they are
  the blocker facts).
- **Qwen** — not supported (founder 2026-07-19: its subscription doesn't
  include their best frontier models; trivial to add later if that changes).
- **Detached `alln` binary-path bug** (dispatch spawns `<project>/alln`
  cwd-relative; killed detached rounds in the field) — real, prerequisite,
  but belongs to dispatch/runtime reliability, not RLC. Fix there: resolve
  `argv[0]` via `realpath` at runtime and record the absolute path at
  `alln bootstrap`; referenced here only because resume dispatch depends on
  it.
- Vendor-motive speculation and "they can't stop us" language — the bright
  lines below are **enforced product policy**, not a legal argument.

Bright lines (never weakened): honor stated reset/`Retry-After`; never probe
faster than the floor; jittered wakes; hard attempt caps; no multi-account,
no client spoofing, no hammering.

## Product surface (RLC-S03)

The notification loop **completes the founder story** — it is not polish:

- Run row: **"Waiting for Claude — resumes around 4:20"** with `Resume now`
  / `Use another model` / `Cancel`.
- One park notification ("Claude paused until ~4:20. No action needed."),
  one recovery notification ("Claude resumed at 4:22."), completion as
  normal.
- **Morning receipt** — the growth artifact: "Allnighter covered 3h 12m of
  vendor waiting and completed the run without intervention." Optional local
  weekly summary (runs resumed, waits covered, interventions avoided) —
  observed facts only, no estimates, nothing leaves the machine.
- Activation demo: the fake-CLI two-minute-limit fixture run during
  onboarding — a visibly pausing-and-resuming run sells the wedge better
  than settings copy.

## Slices

| Slice | Deliverable |
| --- | --- |
| RLC-S01 | **Delivered — contract convergence**: `vendorBackoff` case on `RunBlocker.resource` + quota-scope fields; `attempts[]` on the RunRecord; lifecycle transitions frozen; `CapacityObservation` promoted as the only capacity truth (name what retires from the Pending path); redacted-snippet rule; classifier fixtures incl. negatives |
| RLC-S02 | **Durable same-source continuation**: settle capacity event → close transport, release write lock, persist `wakeAfter`, coordinator-tick reconcile, reacquire lock, vendor-session resume (fresh-session fallback w/ bounded handoff), re-park on repeat; probe timeout + runtimeOwnership; source-scoped single-flight cooldown |
| RLC-S03 | **Product surface**: park/resume statuses + actions, two notifications, morning receipt, onboarding fixture demo |
| RLC-S04 | **Delivered — authorized substitution**: provenance table, capability filter, quiescence proof, visited-set + hop bound, one run id + sequential attempts |

## Works test / proof matrix

Core shape: fake CLI emits a limit with a stated reset 2 minutes out → run
parks with truthful blocker, survives a watchdog pass and `alln ps` from
another process, write lock is released and taken by an intervening run,
wakes at reset, reacquires, resumes the vendor session, settles. Plus:

- Known reset · `Retry-After` · unknown reset · malformed reset ·
  false-positive text (model *discussing* rate limits) → no park.
- Redaction: no secrets/prompt content in persisted diagnostics.
- Repeated limit responses → bounded attempts, no retry loop, escalation.
- Coordinator crash before wake / during wake claim / after spawn; two
  coordinators attempting one wake (lease holds).
- Mac sleep + clock jump → overdue reconciliation resumes correctly.
- Cancel and manual substitution while parked.
- Original worker not quiescent → substitution refused.
- Auto substitution allowed; explicitly-named-worker substitution refused;
  incompatible and already-visited substitutes rejected.
- Weekly/monthly cooldown surviving beyond any short lookback.
- N runs on one capped source → exactly one readiness attempt.

## Appendix (nonbinding, observational): vendor window landscape

Observed 2026-07-19; drifts — informs the short-vs-long-reset policy split,
binds nothing:

| Vendor | Window shape |
| --- | --- |
| Claude | 5h rolling window + weekly cap |
| Kimi | 5h window |
| Codex | weekly only (recently dropped its 5h window) |
| Grok | weekly |
| Cursor | monthly (plan-based) |

Short resets (hours) → park + wake is the whole answer. Long resets
(days) → parking is not a completion strategy; the substitution table or a
loud human decision applies. Resume strategy always keys off the observed
`wakeAfter` distance, never a hardcoded window shape.
