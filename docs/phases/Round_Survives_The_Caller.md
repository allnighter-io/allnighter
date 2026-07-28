# Round survives the caller — mini phase doc

Status: **Draft** — grounded in verified code, not yet hardened/scoped for
implementation. Next step: Opus review pass.
Owner: Allnighter product (CLI / Pilot / Relay / `alln run`)
Updated: 2026-07-27

## Founder intent

Raw request, from a pressure-test of `docs/archive/phases/Unattended_Round_Notification.md`'s
own founder feedback: "imagine a thousand agents using alln across hundreds of
repos — what's actually worth improving?" Working hypothesis, confirmed in this
session: **the round surviving its caller is the correct #1**, ranked above
notification, exit codes, or lock preflight, for a specific reason — those are
all about making an *already-correct* system observable or convenient.
Round-survives-caller is about whether the system is correct at all. A
notification about a round that got silently destroyed when its caller died is
not a fix, it's a faster funeral.

**Prior art already proven in this codebase:** `pilot handoff --no-wait`
(PLT-S01–S04, archived `Pilot_Long_Turn_Survival.md`) already solved exactly
this for one verb — forks a detached child, foreground caller returns
immediately, the round survives a killed caller. That fix is not being
re-derived here; it's being **extended to every other dispatch verb that
doesn't have it**, and having its one real gap (no in-flight lock, see below)
closed where the equivalent guard is missing on the relay side.

**Product value:** at one founder's scale, a killed caller costs one lost
round and some confusion. At a thousand agents across hundreds of repos, any
fully-synchronous dispatch verb dies the same way, silently, on essentially
every round that outlives one tool-call timeout — because an agent's natural
way to invoke a CLI command is to run it in the foreground, and no agent
reliably remembers to self-nohup a command the product itself doesn't ask it
to. That's not a rare edge case at scale, it's the default outcome, replicated
identically everywhere the gap exists.

**Trusted workflow slice:** `alln pair relay` / `pair relay-resume` /
`pair relay adopt` / `alln run` each gain the same detached-dispatch survival
`pilot handoff --no-wait` already has, and `RelayCoordinator`'s dispatch path
gets a real in-flight guard instead of an unlocked read-check-write race.

**Non-goals:** not touching `pilot handoff` (already correct). Not
`Unattended_Round_Notification.md`'s URN-S04–S06 (separate packet, lower
priority per this session's reasoning — those are ergonomics on top of a
correct system; this doc is about correctness itself). Not rebuilding
`RelayCoordinator` into an actor wholesale — only closing the specific race
below with the smallest correct mechanism. Not a general audit of every CLI
command — scoped to the dispatch verbs that start a real, possibly-long
round: `pair relay`, `pair relay-resume`, `pair relay adopt`, `alln run`.

## Current state (verified in code this session, file:line)

**Gap 1 — no detached dispatch on relay or `alln run`.** `RelayCLI.runRelay`
(`RelayCLI.swift:15`), `.runResume` (`:66`), `.runAdopt` (`:94`) each `await`
`RelayCoordinator.run`/`.resume`/`.adopt` directly in the caller's process —
no `--no-wait` flag exists in any of their `CommandSpec`s. `RunCLI.run`
(`RunCLI.swift:242`) calls `await service.run(...)` directly, blocking the
caller the same way; the `--stream` branch still `await`s the run before the
process can exit (`RunCLI.swift:59`). `alln run resume <id>` exists but only
reattaches a run already parked on a vendor wait (`RunCLI.swift:414-416`) —
not a general background-then-poll mechanism. `AsyncTeamService` is real but
is wired into `alln serve`'s own reconciler and `alln team start`/`status`
(`AllnighterCLI.swift:1756,1773`) — `RunCLI.swift` never references it; the
interactive `alln run` path is fully synchronous regardless.

**Gap 2 — relay dispatch has no in-flight guard; `alln run` retry-safety is
opt-in only.** `pilot handoff`'s `preflightExternalRound`
(`RelayCoordinator.swift:251-286`) explicitly checks
`if state.status == .running { return .failure(.roundInFlight) }`
(`:257`) before dispatching — a racing second call sees `.running` on disk
and refuses. `RelayCoordinator.run(config:)` (`:194-208`), by contrast, mints
a brand-new `RelayState.id` on every call with **no check for an already-active
relay on the same `projectRoot`/`docPath`** — a retried `pair relay` after an
uncertain prior call just starts a second, independent relay. `.resume`
(`:647-667`) and `.adopt` (`:526-553`) do check `state.isResumable`/status
before flipping to `.running`, but `RelayCoordinator` is a plain `Sendable`
struct (`:15`), not an actor, and `RelayStateStore.save`/`load`
(`RelayStateStore.swift:40,53`) write atomically but provide no
compare-and-swap or lock across the read-check-write window — two concurrent
`relay-resume`/`relay adopt` calls against the same id can both pass the
check and both dispatch a dev turn. `alln run` has real idempotency
(`RunService.run`'s `idempotencyKey` → `claimSyncIdempotency`,
`RunService.swift:427,673,785-787`) — a same-key/same-payload replay returns
the original run, mismatched payload fails `IDEMPOTENCY_CONFLICT`
(`:431-434`) — but it's **opt-in**: no `--idempotency-key` means
`id = runId ?? UUID().uuidString` mints a fresh id every call
(`RunService.swift:743`), so a naive retry with no key is a genuine second
dispatch. `RunWriteLockRegistry`/`ExecutionLaneRegistry`
(`ExecutionLane.swift:765`) only serializes concurrent writers on the same
repo root — it is not an id-based in-flight guard and does not help here.

**Truth owner:** durable relay/run state on disk (`RelayStateStore`,
`RunStore`) is already the correct truth owner — this doc does not propose a
new one. The gap is that the *dispatch decision* (fork vs. block; proceed vs.
refuse a concurrent call) is made without reliably consulting that truth
under a lock, for relay specifically, and is entirely absent for `alln run`.

**Lie-prone layer:** none newly introduced. The risk is a silent one — a
caller inferring "my dispatch didn't work" from a dead process and retrying
into a race, or inferring "it worked" from a returned pid when the round it
started may already be a duplicate.

**Duplicate truth to delete:** none. This closes a gap, it doesn't consolidate
existing parallel truth.

## Implementation impact (draft — Opus to firm up)

- **CLI surface:** `--no-wait` (or the same flag name) on `pair relay`,
  `pair relay-resume`, `pair relay adopt`, and `alln run`, reusing exactly the
  detached-process pattern `PilotCLI.detachedHandoffLaunch`/
  `dispatchHandoffInBackground` already proved (`PilotCLI.swift:356-465`) —
  same executable-resolution order, same staged-file-not-live-path lesson
  (SR-12/Sol F19, `PilotCLI.swift:432-446`), do not re-derive it a third time.
- **In-flight guard:** give `RelayCoordinator`'s dispatch entry points the
  same `.running`-check `preflightExternalRound` already has, and close the
  read-check-write race under a real lock (actor isolation, or a file lock on
  the relay's state file — Opus's call which is the smaller correct fix vs.
  the more disruptive one; do not silently pick the actor rewrite if the file
  lock is sufficient and smaller).
- **`pair relay` (start) specifically** should refuse or clearly warn when an
  active relay already exists for the same `projectRoot`/`docPath`, not just
  guard resume/adopt — a retried `relay` start today has no signal at all
  that it might be creating a duplicate.
- **`alln run` idempotency:** decide whether `--idempotency-key` should
  default to something derived (e.g. hash of prompt+team+root+time-bucket) so
  a naive retry is safe without the caller having to know the flag exists, or
  whether the CLI surface / help / teaching layer should just make the flag
  impossible to miss instead. Name this as an open question if it's a real
  product-posture call, not an engineering one — do not silently pick one.
- Contract-visible (new flags, possibly new JSON fields for
  dispatch-in-background acknowledgment on the three relay verbs, mirroring
  `PilotHandoffDispatchJSON`) — will need a contract version bump, same
  discipline as `Unattended_Round_Notification.md`'s URN-S02.
- Mac/iOS impact: none expected — this is a CLI dispatch-layer fix; if any
  Mac GUI code path also calls `RelayCoordinator.run`/`.resume`/`.adopt`
  directly (check `RelayGUIRuntime.swift`, named in
  `docs/archive/phases/Pilot_Long_Turn_Survival.md`'s R-S08), confirm the new
  guard doesn't regress a legitimate GUI-initiated dispatch.

## Works Test (draft)

1. Start `pair relay --doc ... --project ... --pm-worker ... --dev-worker ...`
   with `--no-wait` (once built) from a terminal; kill the terminal/process
   immediately after dispatch acknowledges. Confirm via `pair relay-status`
   that the relay keeps advancing rounds after the caller is dead — same
   proof shape as Pilot's existing survival test.
2. Fire two `pair relay-resume` calls against the same escalated relay id
   back-to-back (simulating an uncertain caller retrying). Confirm exactly
   one dev turn dispatches, not two, and the second call gets a clear
   "already resumed"/in-flight refusal, not a silent race.
3. Start `pair relay` twice against the same `--project`/`--doc` without an
   explicit distinguishing flag. Confirm the CLI surfaces the existing active
   relay instead of silently minting a duplicate.

## Proof command (once built)

```bash
swift test --package-path Packages/AllnighterCore --filter 'Relay|Run|ContractRegistry'
scripts/check_architecture_policy.sh
```

## Done when

- `pair relay` / `pair relay-resume` / `pair relay adopt` / `alln run` each
  survive a killed caller, proven the same way Pilot's `--no-wait` already is.
- Relay dispatch has a real in-flight guard (no unlocked read-check-write
  race); `pair relay` start refuses/warns on an existing active relay for the
  same project+doc.
- `alln run`'s retry-safety story is a deliberate decision (default key vs.
  unmissable flag), not an accident of nobody having asked yet.
- Proof: Works Test above green; full green wall; contract regenerated if the
  CLI surface changed.

## Open questions (for Opus / founder)

- Smallest correct fix for the relay race: actor isolation on
  `RelayCoordinator`, or a narrower file lock on the relay's state file
  during the check-then-mutate window? Recommend the narrower fix unless it
  demonstrably can't close the race.
- Should `alln run` default to a derived idempotency key, or is an explicit
  opt-in flag (made impossible to miss via teaching surface) the more honest
  contract? This is closer to a product-posture call than an engineering one.
- Does this warrant one packet or two (detach-survival vs. in-flight-guard
  are related but separable slices) — Opus's call on the cleanest split.
