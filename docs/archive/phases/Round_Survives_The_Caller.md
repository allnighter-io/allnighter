# Round survives the caller — mini phase doc

Status: **Complete — archived 2026-07-28.** S01–S05 shipped, then RSC-HF redesign
closed the mid-flight audit (ack-after-accept, collapsed hidden verbs, safe run
ids). See sibling archive `Round_Survives_The_Caller_Hot_Fixes.md`.
Owner: Allnighter product (CLI / Relay / `alln run`)
Updated: 2026-07-28

Review history: drafted from a pressure-test of the founder feedback behind
`docs/archive/phases/Unattended_Round_Notification.md`; hardened by an Opus pass
that re-read every cited file. That pass **corrected three claims** the draft got
wrong and **found one live P0** (see §Corrections).

## Founder intent

**Raw request:** "imagine a thousand agents using alln across hundreds of repos —
what's actually worth improving?" Answer, confirmed with the founder: **the round
surviving its caller is #1**, above notification, exit-code split, or lock
preflight — those make an *already-correct* system observable; this one is about
whether the system is correct at all. A notification about a round that was
silently destroyed when its caller died is not a fix, it's a faster funeral.

**Product value:** at one founder's scale a killed caller costs one lost round. At
a thousand agents across hundreds of repos, every fully-synchronous dispatch verb
dies the same way, silently, on essentially every round outliving one tool-call
timeout — an agent's natural way to invoke a CLI is foreground, and none of them
reliably self-`nohup` a command the product never asked them to.

**Prior art.** Mature tooling never asks the caller to survive: `docker run -d`,
`systemd-run`, and `gh run` own the detach themselves. `terraform` guards
concurrent mutation with a **state lock file**, not in-process synchronization,
precisely because the racing parties are separate processes. Stripe's
`Idempotency-Key` is **caller-supplied and opt-in, never derived** — a
server-derived key would silently collapse two intentional identical charges. We
already have the local version of all three (`pilot handoff --no-wait`,
`ThreadFlockLock`, `--idempotency-key`); this packet spreads them, deriving nothing.

**Trusted workflow slice:** `alln pair relay` / `pair relay-resume` /
`pair relay adopt` / `alln run` each gain the detached-dispatch survival
`pilot handoff --no-wait` already has, and relay dispatch gets a real cross-process
in-flight guard instead of an unlocked read-check-write window.

**Non-goals.** Not touching `pilot handoff` (already correct). Not rebuilding
`RelayCoordinator` as an actor (§Decision 1 explains why that would be the *wrong*
fix, not merely a bigger one). Not notification: a detached `alln run` will land
silently, exactly as a detached `pilot handoff` did before URN-S02, and wiring
`ServeAutoLaunch.ensureRunning` into `alln run` is a one-line follow-up that
belongs to a fresh notification scoping — naming it here so it is a known residual,
not an oversight. Not URN-S04–S06. Not a general CLI audit.

## Current state (re-verified against HEAD, 2026-07-27)

**Gap 1 — no detached dispatch on relay or `alln run`.** `RelayCLI.runRelay`
(`RelayCLI.swift:15`), `.runResume` (`:70`), `.runAdopt` (`:102`) each `await`
`RelayCoordinator.run`/`.resume`/`.adopt` in the caller's process (`:39`, `:87`,
`:129`). Their `CommandSpec`s (`ContractRegistry+Milestone1.swift:466-512`) carry
no `--no-wait` or equivalent. `RunCLI.run` (`RunCLI.swift:92`) blocks on
`await service.run(...)` (`:242`); the `--stream` branch (`:204-236`) also awaits
the full run (`:213`) before the process can exit. `AsyncTeamService` is wired only
into `alln serve` and `alln team start`/`status` (`AllnighterCLI.swift:1756,1773`);
`RunCLI.swift` never references it, so the interactive path is synchronous
regardless of flags.

**Gap 2 — relay dispatch has no cross-process in-flight guard.** `pilot handoff`'s
`preflightExternalRound` (`RelayCoordinator.swift:251-286`) refuses on
`state.status == .running` (`:257`). `RelayCoordinator.run(config:)` (`:194-208`)
by contrast mints a brand-new id every call with **no check for an already-active
relay on the same `projectRoot`/`docPath`** — a retried `pair relay` after an
uncertain prior call starts a second, independent relay against the same repo.
`.resume` (`:647-667`) and `.adopt` (`:526-553`) do check status before flipping to
`.running` (`:650`, `:531`), but `RelayCoordinator` is a plain `Sendable` struct
(`:15`) and `RelayStateStore.save`/`load` (`RelayStateStore.swift:40,53`) write
atomically with **no compare-and-swap and no lock across the read-check-write
window** — two concurrent `relay-resume`/`relay adopt` calls on one id can both
pass the check and both dispatch a dev turn.

**Gap 3 (found this pass) — the teaching surface already promises a flag that does
not exist.** `AgentBootstrap.startTeamRun` / `.retryLater`
(`AgentBootstrap.swift:36,44`) hand agents the paste-ready command
`alln run "<message>" --team <id> --detach --json`. There is no `--detach` flag in
any `CommandSpec`, and unknown flags fail closed (`AllnighterCLI.swift:31` →
`CLIUsage.validateFlagConstraints`, `CLIUsage.swift:135`), so that next-action
exits 2 with "unknown flag --detach". `.retryLater` reaches users for real —
`AllnighterCLI.swift:1034` attaches it to `alln run --dry-run` output whenever the
team governor is busy; `.startTeamRun` currently has no live call site, which makes
it a loaded gun rather than a firing one. The same phantom grammar is in
`CommandProjection.swift:93`, `CommandDescription.swift:64`, and `run`'s own
`trigger` string (`ContractRegistry+Milestone1.swift:406`, "detach when stepping
away") — while `HelpTopicRegistry.swift:124-125` states the opposite ("Runs are
foreground only; there is no detached mode"). This is a live P0 under the Teaching
Surface Rule and a direct self-contradiction in the help corpus.

**Truth owner:** unchanged — durable state on disk (`RelayStateStore`, `RunStore`).
The defect is that the *dispatch decision* is taken without consulting that truth
under a lock. **Lie-prone layers:** the teaching surface (Gap 3, already lying
today) and the detached-child boundary (a `dispatched` ack must never precede an
unvalidated round). **Duplicate truth to delete:** the phantom `--detach` grammar
in four places.

### Corrections to the draft (do not propagate the old text)

1. `alln run resume <id>` is **not** vendor-park-only. `RunCLI.swift:401-441`
   prints a terminal run, waits for an in-flight one, and only then takes the
   vendor-wake path — it is already the general attach-by-id primitive. The only
   thing missing for a detached run is *learning the id at dispatch time*.
2. `RelayCLI` line numbers moved (URN-S02 inserted the auto-serve calls); the
   figures above are the current ones.
3. The claim that the write lock "does not help here" stands, but the
   `ExecutionLane.swift:765` citation was wrong and is dropped: per-root write
   locking serializes mutating writers, it is not an id-based in-flight guard.

## Decisions (the draft's open questions, resolved)

**1. Actor isolation vs. file lock → file lock. Actor isolation would not fix the
bug.** The racing parties are separate OS processes: two `alln` invocations, or a
CLI invocation and the Mac app (`RelayGUIRuntime.makeCoordinator` builds a
coordinator field-for-field identical to the CLI's, `RelayGUIRuntime.swift:36-53`).
Actor isolation serializes within one process only, so it would leave the real race
untouched while forcing a signature churn everywhere. The correct mechanism already
exists and is already used for exactly this shape of RMW window:
`ThreadFlockLock.tryAcquire(lockURL:)` (`ThreadFlockLock.swift:28`) — a
non-blocking, `O_CLOEXEC`, advisory `flock(2)` released on handle deinit. This is
an engineering call with a demonstrable right answer, not a founder call.

**2. `alln run` idempotency → keep the key opt-in; do not derive one.** A derived
key (hash of prompt+team+root+time-bucket) would silently collapse two
*intentional* identical runs into one — a silent drop of requested work, which
the Honest Reporting Rule bans outright — and would make behavior depend on an
invisible clock boundary, so the same command is reproducible or not depending on
the second it was typed. Stripe made the same call for the same reason. The real
retry-safety primitive for a dying caller is **knowing the run id at dispatch
time**, which RSC-S04 delivers; `alln run resume <id>` then attaches to it
(correction 1). RSC-S05 makes `--idempotency-key` discoverable so the opt-in is
not a secret.

**3. One packet or two → one packet, guard slices first.** They are separable, but
detach *amplifies* the race (a caller that gets an ack but cannot confirm the child
survived is precisely the caller that retries), so shipping detach first would
multiply concurrent dispatches against an unguarded coordinator. One packet, five
slices, guard before detach. A second doc would also violate the founder's explicit
"keep it light" instruction for this packet.

**4. Flag name → `--no-wait` everywhere; `--detach` gets swept and deny-listed.**
`--no-wait` is the name that actually ships today (`pilot handoff`), is named in its
`ErrorSpec` and help prose, and shipping a second name for one concept is exactly
the drift the Retirement Rule exists to stop. `--detach` is not retired code — it is
grammar that never existed — so it goes on the deny-list as a phantom.

## Implementation contract

**CLI surface.**

| Command | Change | Exit codes |
| --- | --- | --- |
| `pair relay` | `FlagSpec("no-wait", …)`. New refusal `RELAY_ALREADY_ACTIVE` when a live-owner `.running` relay exists on the same normalized `projectRoot` + `docPath`. | unchanged (`RELAY_ALREADY_ACTIVE` has no `exitClass` ⇒ operational ⇒ 1, `ExitCode.swift:64`) |
| `pair relay-resume`, `pair relay adopt` | `FlagSpec("no-wait", …)`. Lost dispatch-lock or `.running` on disk ⇒ existing `RELAY_ROUND_IN_FLIGHT`. | unchanged (1) |
| `alln run` | `FlagSpec("no-wait", …)` + `FlagSpec("run-id", takesValue: true, valueType: "id", …)`. New refusal `RUN_ID_IN_USE`. Mutually exclusive: `["no-wait","stream"]`, `["no-wait","dry-run"]`, `["no-wait","try-fix"]`. | unchanged (1 / 2) |

No new exit codes. `ExitCode.stableTable` (`ExitCode.swift:30-36`) is untouched —
this packet deliberately does not reopen URN-S05.

**Dispatch ack JSON.** One new CLI-local `Encodable`, mirroring
`PilotHandoffDispatchJSON` (`PilotCLI.swift:1165-1173`) which is likewise not an
`OutputSchema` case, so **no `OutputSchema` enum change is needed**:

```swift
struct DetachedDispatchJSON: Encodable {
    let kind: String     // "relay" | "run"
    let id: String       // relayId or runId
    let status: String   // "dispatched"
    let pid: Int32
}
```

`PilotHandoffDispatchJSON` is left exactly as-is — renaming a shipped envelope
would cost a retirement sweep for no user-visible gain.

**Contract / version.** `ContractRegistry.contractVersion` **4.1.0 → 4.2.0**
(`ContractRegistry+Milestone1.swift:11`; additive flags + error specs, no removals
or renumbering). `AllnighterVersionIdentity.binaryVersion` **0.10.1 → 0.10.2**
(`VersionJSON.swift:15`; one shipped batch), with `VersionIdentityTests` as the
drift gate. Then `alln dev export-contracts` and commit the regenerated artifacts —
never hand-edit them.

**New error specs** (`ContractRegistry+Milestone1.swift`, beside
`RELAY_ROUND_IN_FLIGHT` at `:1077`):

- `RELAY_ALREADY_ACTIVE` — "a relay is already running for this project + doc";
  `agentAction`: read it with `alln pair relay-status --relay <id> --json`, resume
  or adopt it, or wait — do not start a second relay on the same doc.
- `RUN_ID_IN_USE` — "a run already exists with this id"; `agentAction`: attach with
  `alln run resume <id> --json`, or omit `--run-id`.
- `RELAY_ROUND_IN_FLIGHT`'s `explain` currently says "A **pilot** relay round is
  already dispatching" — broaden to cover spawned relays now that resume/adopt can
  emit it. Text-only; the code and exit class are unchanged.

**Mac app impact (real, not none).** The Mac GUI calls the same coordinator
entry points: `RelayLaunchViewModel.start` → `coordinator.run` (`:134`), and
`RelayResumeController.resume` → `coordinator.resume` (`:92`). So:

- The new guard is enforced in `RelayCoordinator`, not in `RelayCLI` — a
  CLI-only guard would leave the GUI racing the CLI.
- `RelayLaunchViewModel.start` pre-seeds the relay's thread *before* dispatching
  (`:124-129`). It must preflight **before** seeding, or a refused start leaves an
  orphan thread; the refusal surfaces through its existing `validationIssues`.
- `RelayResumeController` already renders a `nil` return as "This relay is no
  longer resumable." (`:100`). That string must become cause-specific — asserting
  "not resumable" when the observed fact is "another process holds the dispatch
  lock" names an unobserved cause.
- iOS impact: none. WebSocket/protocol: none. Agent drivers: none.
  Auth/privacy/permissions: none — no new file class beyond lock files under
  `AllnighterPaths.relays/.locks/`.

**Teaching surface.**

- `pm_relay` (`HelpTopicRegistry.swift:205`): new section
  `("survive", "The round outlives your session", …)` — `--no-wait` on `pair relay`
  / `relay-resume` / `relay adopt`, then poll `pair relay-status --relay <id>
  --json`; a killed caller is not a killed relay; a second dispatch on a live relay
  is refused, not raced. Aliases to add: `"no-wait"`, `"background"`,
  `"detached"`, `"my session died"`, `"survive"`. Add `RELAY_ALREADY_ACTIVE` to
  `errorRefs`.
- `team_run_loop` (`:153`): new section `("no-wait", "Detached runs", …)` naming
  `alln run --no-wait` → printed run id → `alln run resume <id> --json`, and
  `--idempotency-key` as the explicit retry-safety contract (Decision 2). Aliases:
  `"no-wait"`, `"background run"`, `"detach"`, `"idempotency"`, `"retry safely"`.
- **Phantom-grammar sweep (Gap 3):** replace `--detach` with `--no-wait` in
  `AgentBootstrap.swift:36,44`, `CommandProjection.swift:93`,
  `CommandDescription.swift:64`, and `run`'s `trigger`
  (`ContractRegistry+Milestone1.swift:406`); delete the now-false "there is no
  detached mode" sentence at `HelpTopicRegistry.swift:124-125`. Add `"--detach"` to
  `RetiredVocabulary.denyTerms` so it can never be re-taught.
- Gate: `alln dev export-contracts --check` + the help-corpus test must be green.

## Builder slices

Ship order **RSC-S01 → S02 → S03 → S04 → S05**. Commit each slice.

### RSC-S01 — Cross-process dispatch lock on resume / adopt

- New `RelayDispatchLock` in `AllnighterEngine`: `tryAcquire(relayId:)` wrapping
  `ThreadFlockLock.tryAcquire` over
  `AllnighterPaths.relays/.locks/<relayId>.dispatch.lock`.
- `RelayCoordinator.resume` and `.adopt`: take the lock, then load → check status →
  flip `.running` → `persist`, then **release before the round loop**. The lock
  covers the RMW window only; a crashed holder must never wedge the relay — liveness
  after the flip is already owned by `owner.pid` + `reconcileOrphan`
  (`RelayCoordinator.swift:710`).
- Failure channel: `resume` returns `Result<RelayState, RelayCoordinator.DispatchRefusal>`
  (`.relayNotFound`, `.notResumable(status:)`, `.roundInFlight`) instead of
  `RelayState?`; `AdoptError` gains `.roundInFlight`. Update `RelayCLI.runResume`
  (`:87`), `RelayCLI.runAdopt` (`:129`), `RelayResumeController.resume` (`:92`).
- Tests: two concurrent `resume` calls on one id ⇒ exactly one dispatch, the other
  `RELAY_ROUND_IN_FLIGHT`; same for `adopt`; lock released after the flip (a later
  legitimate resume of the settled relay succeeds); a stale lock file left by a dead
  process does not block (flock is released by the OS on process death).

### RSC-S02 — `pair relay` start refuses a duplicate live relay

- `RelayCoordinator.run` becomes `Result<RelayState, DispatchRefusal>` with new case
  `.alreadyActive(relayId:)`, plus a static
  `preflightStart(projectRoot:docPath:stateStore:)` mirroring
  `preflightExternalRound`'s shape so a foreground caller can check before acking.
- Under a start lock keyed on `sha256(RootNormalization.normalize(root).key + "|" +
  docPath)`, scan `RelayStateStore.list()` for a relay with matching normalized root
  + docPath, `status == .running`, and `!stateStore.isOwnerDead(id:)`. Match ⇒
  `.alreadyActive`. **Parked relays (`awaitingPM`/`escalated`) do not block a
  start** — they need resume/adopt, and refusing them would break Pilot.
- Update `RelayCLI.runRelay` (`:39`) and `RelayLaunchViewModel.start` (preflight
  before the thread pre-seed at `:124-129`).
- Tests: second start on same root+doc while the first is live ⇒
  `RELAY_ALREADY_ACTIVE` naming the existing relay id; dead-owner `.running` relay
  does **not** block (it is an orphan, reconcilable); different doc, same root ⇒
  allowed; `awaitingPM` relay ⇒ allowed.

### RSC-S03 — `--no-wait` on the three relay verbs

- Extract `PilotCLI.detachedHandoffLaunch` (`PilotCLI.swift:365-390`) into a shared
  `DetachedDispatch.launch(cwd:)` helper in `AllnighterCLI` — same resolution order
  (`ProcessOwnership.resolveRunningExecutablePath`, `:378`), same
  `AllnighterSpawnEnvironmentPolicy.processEnvironment()`, same null stdio.
  `PilotCLI` switches to it; **do not write a second implementation.**
- Child argv = the parent's argv with `--no-wait` removed (the child runs the
  normal blocking path). cwd = the relay's `projectRoot`.
- **All non-mutating validation runs in the foreground before the ack** — flag
  parse, project/worker resolution, state eligibility, and the S01/S02 guard — so a
  `dispatched` ack can never hide a refusal the child would dump to `/dev/null`.
  This is the same rule `dispatchHandoffInBackground` follows (`:406-414`).
- SR-12 staging (`PilotCLI.swift:445-452`) is **deliberately not copied**: it exists
  because a handover *file* could be mutated between ack and child open. Relay's
  `--doc` is re-read fresh every round by design, and every other relay value is an
  argv string (already an immutable copy). State this in the slice so a later reader
  does not "fix" it.
- Emit `DetachedDispatchJSON(kind: "relay", id: relayId, …)` under `--json`, else a
  one-line human ack naming `alln pair relay-status --relay <id> --json`.
- Tests: `--no-wait` spawns exactly one child with the parent's argv minus
  `--no-wait` and cwd = projectRoot; a guard refusal exits non-zero and spawns
  nothing; ack JSON shape.

### RSC-S04 — `--no-wait` + `--run-id` on `alln run`

- `--run-id <id>`: passed to `RunService.run(runId:)`, a public seam already used by
  `FollowUpCoordinator.swift:27` and `ThreadsViewModel.swift:811` — this exposes it,
  it does not invent it. Guard: `RunStore.loadRaw(runId:)` non-nil ⇒ `RUN_ID_IN_USE`.
- `--no-wait`: parent resolves project/worker (existing code path, `RunCLI.swift:92-148`),
  mints `runId` unless `--run-id` was given, spawns the detached child with the
  parent's argv minus `--no-wait` plus `--run-id <id>`, cwd = `project.normalizedRootPath`,
  and prints `DetachedDispatchJSON(kind: "run", id: runId, …)` (or a human line naming
  `alln run resume <id> --json`).
- Residual, stated not hidden: if the child dies before persisting a `RunRecord`,
  `alln run resume <id>` returns `RUN_NOT_FOUND` — a distinguishable, honest outcome,
  not a silent success. Pre-persisting a draft record is out of scope.
- Tests: `--no-wait` prints a run id and returns before the run settles; the printed
  id is the one the child persists; `--run-id` collision ⇒ `RUN_ID_IN_USE` with no
  spawn; each mutual exclusion is rejected at parse time (exit 2).

### RSC-S05 — Teaching surface + phantom `--detach` sweep

Everything under §Teaching surface, in one slice with the code that makes it true.
The `AgentBootstrap` next-actions are the priority: they are the single most likely
place a cold agent copies a broken command from.

- Tests: `RetiredVocabularyTests` fails on `--detach` anywhere in the live corpus;
  every command string in `AgentBootstrap` resolves against `ContractRegistry`
  (assert this generally, not just for these two rows — a phantom flag in a
  next-action must be impossible, not merely fixed once).

## Inference bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| CLI/GUI → relay dispatch | `RelayStateStore` on disk | "In-process checks are enough" | The guard lives in `RelayCoordinator` under a file lock; no caller-side-only check | Two processes racing `resume` on one id ⇒ exactly one dev turn |
| dispatch lock → round | `owner.pid` + `reconcileOrphan` | "Hold the lock for the whole round" | The lock covers the read-check-write window only and is released before the loop | A relay whose dispatcher was `kill -9`'d is still resumable afterwards |
| `--no-wait` ack → round validity | foreground preflight | "Ack means only that a process started" | Every non-mutating refusal is evaluated before the ack; a refusal spawns nothing | Guard refusal ⇒ non-zero exit and zero child processes |
| teaching surface → CLI | `ContractRegistry` | "Prose may name a flag the registry will add later" | Every command string in `AgentBootstrap`/help resolves against `ContractRegistry` | A next-action naming an unregistered flag fails the corpus test |

## Proof

**Works Test (owner-visible).**

```bash
# 1. Detached relay survives a killed caller.
alln pair relay --doc docs/phases/Round_Survives_The_Caller.md --project "$PWD" \
  --pm-worker <pm-id> --dev-worker <dev-id> --no-wait --json   # -> {"kind":"relay","id":"relay_…","status":"dispatched","pid":N}
kill -9 $$                                                      # from a throwaway subshell
alln pair relay-status --relay <relayId> --json                 # rounds keep advancing

# 2. Duplicate start is refused, not silently duplicated.
alln pair relay --doc docs/phases/Round_Survives_The_Caller.md --project "$PWD" \
  --pm-worker <pm-id> --dev-worker <dev-id> --json              # -> RELAY_ALREADY_ACTIVE, exit 1, names the live relay id

# 3. Concurrent resume dispatches exactly one dev turn.
alln pair relay-resume --relay <escalatedId> --answer "go" --json &
alln pair relay-resume --relay <escalatedId> --answer "go" --json      # -> RELAY_ROUND_IN_FLIGHT, exit 1
alln pair relay-status --relay <escalatedId> --json                    # exactly one new round

# 4. Detached run is addressable.
alln run "summarize AGENTS.md" --project . --no-wait --json     # -> {"kind":"run","id":"…","status":"dispatched","pid":N}
alln run resume <runId> --json                                  # attaches and prints the settled run

# 5. The phantom flag is gone from every live surface.
grep -rn -- '--detach' Packages/AllnighterCore/Sources | wc -l  # -> 0
```

**Supporting checks.**

```bash
swift test --package-path Packages/AllnighterCore \
  --filter 'Relay|Run|Pilot|ContractRegistry|FixtureRoundTrip|VersionIdentity|RetiredVocabulary|HelpTopic'
alln dev export-contracts --check
scripts/check_architecture_policy.sh
xcodebuild test -scheme AllnighterMac   # RelayLaunchViewModel / RelayResumeController refusal paths
```

**Missing proof / waiver:** none requested. Works Test steps 1 and 3 are the
host-boundary claims (a real killed process, two real concurrent processes) — a
mock cannot close either, so both must run as written.

## Done when

- **User-visible claim:** "Starting work with Allnighter does not depend on the
  session that started it staying alive — and asking twice never runs it twice."
- `pair relay` / `relay-resume` / `relay adopt` / `alln run` each survive a killed
  caller, proven the same way `pilot handoff --no-wait` already is.
- Relay dispatch has a cross-process in-flight guard; a duplicate `pair relay` start
  on the same project + doc is refused with `RELAY_ALREADY_ACTIVE`.
- `alln run --no-wait` prints a run id at dispatch; `alln run resume <id>` attaches.
- No live teaching surface names `--detach`; it is on the deny-list.
- Contract 4.2.0 + binary 0.10.2 regenerated and committed; Works Test green;
  full green wall.
- Closeout: promote nothing (behavior is code-owned), then archive to
  `docs/archive/phases/` naming `RelayCoordinator.swift`, `RelayCLI.swift`,
  `RunCLI.swift`, and the shared `DetachedDispatch` helper as successors.
