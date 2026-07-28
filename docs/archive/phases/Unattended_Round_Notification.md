# Unattended round notification — CEO decision brief

Status: **Approved — Ready for Implementation.** URN-S01 → URN-S02 (silent
auto-launch, default-on) → URN-S03, in order. URN-S04–S06 deferred.
Updated: 2026-07-27
Owner: Allnighter product (CLI / Pilot / Relay / `alln serve`) — code SSOT once
approved: `ServeDaemon.swift`, `NotificationCandidateDetection.swift`,
`NotificationEvent.swift`, `PilotCLI.swift`, `RelayCoordinator.swift`,
`ContractRegistry+Milestone1.swift`

Review history: drafted from founder incident report; hardened to
implementation-ready by an Opus pass (corrected CLI grammar and state source,
closed a double-delivery gap, added the full implementation contract);
extended by an outside review (Gemini via `agy`) asked specifically what an
agent driving `alln` purely via CLI would want next — two of its three ideas
were real, verified gaps (URN-S05/S06, both optional/deferred); the third
("run list/attach") was discarded as already shipped (`alln ps` +
`alln run resume`).

---

## The ask (one paragraph)

Three times in one day, an agent started `alln pair pilot` / `alln pair relay`
work from a terminal and nothing told the founder when it landed — not the CLI
(the agent that dispatched it had already moved on or died), not the Mac app (it
was not open), nothing. The founder's bar: **the human should have to do
nothing, and the agent that started the round should not have to build its own
watcher.** Allnighter already knows the moment work lands or needs a PM answer —
it should say so, on its own, without either party polling for it.

**Approved 2026-07-27** — URN-S01 → URN-S02 → URN-S03, S02 auto-launch silent
and default-on (see §Decision).

---

## What went wrong (verified in code, 2026-07-27)

Allnighter already has a real notification pipeline, and it is good machinery.
`NotificationCandidateDetection`
(`Packages/AllnighterCore/Sources/AllnighterCore/NotificationCandidateDetection.swift`)
purely diffs `WorkThread`/`TeamRun` snapshots into `NotificationCandidate`s —
`turnCompleted`, `turnFailed`, `teamRunCompleted`, `vendorParked`/`vendorResumed`,
`threadNeedsAttention`. `NotificationDeliveryFilter` applies policy, mute, quiet
hours and debounce. `MacNotificationDelivery`
(`Apps/AllnighterMac/Sources/MacNotificationDelivery.swift`) posts a real macOS
banner via `UNUserNotificationCenter` with click-to-thread deep linking. This
shipped as NOTIF-S01–S05 (`docs/archive/phases/threads/02_Notifications.md`).

The scope line in that doc is the whole bug: **"Ship Mac local notifications
only in this phase."** The diff only ever runs from `ThreadsViewModel.reload`
(`Apps/AllnighterMac/Sources/ThreadsViewModel.swift`, `processNotificationTransitions`)
— i.e. only while the Mac GUI process is alive and polling. `alln serve`, the
component AGENTS.md already names as the app-closed background scheduler, has
**zero** notification code: `ServeDaemon.swift` contains no `Notification` or
`UserNotifications` reference anywhere.

Meanwhile the state is all there on disk and unread. `RelayThreadProjector`
already projects every relay round onto one `WorkThread` per relay in the shared
file-backed `ThreadStore` — including an open `.running` system-event turn with
`systemEvent: .relayEscalated` and a terminal `.relayStopped` turn. A relay
dispatched purely from a terminal writes complete, correct thread truth that
nothing is watching. This is not a fluke; it is a designed-in gap between "Mac
app open" (notified) and "CLI-only" (silent forever).

A second, smaller bug compounds it. Even when the Mac app **is** running, a
relay round entering `.relayEscalated` (needs a PM answer) or `.relayStopped`
gets no event of its own: `NotificationCandidateDetection.blockingSystemEvent`
and `isOpenBlockingSystem` both list `.relayEscalated, .relayStopped` in their
"return nil / false" cases, and the comment above them claims a per-event push
is "GUI polish deferred to PM_Relay.md R-S08." R-S08 shipped — but it shipped
the Mac GUI escalation *row*, visible only if the thread is already open, not a
push. The comment describes behavior the code does not implement, which is
exactly the "a comment is not a contract" defect class in
`SSOT_Feature_Workflow.md` §Honest Reporting.

---

## Prior art (how mature tools solve this)

The convention across CI and build tooling: **the notifier is a standing
process independent of the caller**, never the caller's own responsibility.
GitHub Actions notifies by webhook/email regardless of whether the machine that
pushed is still online. Xcode posts a system notification when a background
build finishes without asking the build's invoker to poll. `gh run watch` is the
*opt-in* blocking path, deliberately additive to, not a replacement for, the
standing notifier. We adopt that split exactly: `alln serve` is the standing
notifier (URN-S01/S02); a blocking `wait` verb is the optional extra (URN-S04),
never the mechanism.

---

## What we are recommending

1. **URN-S01 — `alln serve` posts OS notifications with the Mac app closed.**
   Reuse the existing portable `NotificationCandidateDetection` pure functions
   inside a new scheduler on `ServeDaemon`, following the pattern of the three
   existing schedulers.
2. **URN-S02 — dispatch guarantees the watcher exists.** Round-dispatching
   `pair` verbs auto-launch a detached `alln serve` if none is alive. Without
   this, S01 only helps founders who remembered to start `serve`.
3. **URN-S03 — real relay escalation/stop events + delete the stale comment.**
4. **URN-S04 (optional, defer first)** — `pair pilot wait` / `pair relay wait`.
5. **URN-S05 (optional, defer first)** — split "needs your answer" from
   "failed" on exit code (outside review, verified real gap).
6. **URN-S06 (optional, defer first)** — `alln lock status --json` +
   `--on-lock=fail` preflight (outside review, verified real gap).

If you only do two, do S01 and S02 — S01 alone is inert without S02. S04-S06
are independent of each other and of S01-S03; none blocks approval of the core
fix.

---

## Why you should care

| If we do nothing | If we ship URN-S01/S02/S03 |
| --- | --- |
| CLI-only relay/pilot work (today's dominant real usage) notifies nobody, ever, unless the Mac app happens to be open | Allnighter pings the human the moment a round lands or needs a PM answer, app open or closed |
| Every agent reinvents a pgrep/poll loop, or nothing; the founder manually re-checks three times a day | Zero caller-side watching, human or agent |
| A code comment claims relay escalation already pushes a notification; it does not | Escalation gets a real, correctly-labelled event |

---

## What we are explicitly not doing

- No new cloud/push service. Local delivery only, same trust boundary as
  NOTIF-S01–S05. No API keys, no accounts, no network egress.
- No iOS push (`docs/phases/ios/03_iOS_Thread_Read_State_And_Push.md` stays
  deferred).
- **No run semantics in `alln serve`.** The new scheduler is strictly
  read-then-shell-out: it reads `ThreadStore`/`RunStore`, and spawns
  `osascript`. It never mutates a run, never dispatches, never touches the write
  lock. This is the AGENTS.md constraint and it is a test assertion (see
  §Inference bans).
- No replacement for `pair pilot status` / `pair pilot watch`; those stay as the
  pull-based path.
- No rebuild of notification detection — `NotificationCandidateDetection` and
  `NotificationDeliveryFilter` are reused unchanged except for the S03 cases.
- No git operations of any kind.

---

## Success looks like

- Quit the Mac app entirely. From a terminal, submit a pilot handoff. Walk away.
  When the round completes or escalates, a macOS banner appears — no human
  polling, no watcher the calling agent had to invent.
- The founder never has to remember to run `alln serve`; dispatch guarantees it.
- A relay round needing a PM answer reads **"PM Relay needs an answer"**, not a
  generic thread-needs-attention line.

---

## Decision

| Option | Meaning |
| --- | --- |
| **Approve** | Build URN-S01 → URN-S02 → URN-S03 in order; URN-S04–S06 stay deferred |
| **Approve with cuts** | Cut URN-S03 (cosmetic sharpening). S01+S02 is the pair that fixes today's failure |
| **Reject** | Leave current behavior; CLI-only relay/pilot work stays silent |

**URN-S02 auto-launch: approved, silent, default-on** (founder ruling
2026-07-27). The user is already asking Allnighter to run a background task —
`alln serve` is that task's own delivery mechanism, not a new one, so it
launches without a prompt. Reasoning: (1) an opt-in daemon reproduces the
original bug — a forgotten manual step fails the exact same way the incident
did, silently; (2) `pair pilot handoff` already forks a detached process
without asking for the round itself, so this is the same trust category, not
a new one; (3) local, no credentials, no data leaving the machine, fully
reversible (`--no-auto-serve` / `ALLN_NO_AUTO_SERVE=1`, or `pkill`) — not a
High-Risk-Stop class action. Nothing else in this packet requires a founder
call.

Founder sign-off: **Approved 2026-07-27** — URN-S01 → URN-S02 (auto-launch,
silent, default-on) → URN-S03. URN-S04–S06 deferred, build after.

---

## Builder slices

### URN-S01 — `alln serve` posts OS notifications for relay/pilot state

**State source (resolved).** `NotificationCandidateDetection.snapshots(from:)`
consumes `[WorkThread]` and `runSnapshots(from:runsById:)` consumes
`[String: TeamRun]`. The source is therefore `ThreadStore.list()` +
`RunStore.list()` — **not** `ProcessOwnershipSurface`, whose `list()` returns
`OwnershipPsJSON` rows (a different shape, built for `alln ps`/`alln kill`).
`RelayThreadProjector` already writes relay rounds into `ThreadStore`, so relay
truth arrives through the same door as every other thread.

- New `NotificationScheduler` in `AllnighterEngine`, added to `ServeDaemon.run`'s
  `TaskGroup` beside `PendingWakeScheduler` / `BoostSeedScheduler` /
  `VendorBackoffReconciler`, gated on `wakeDependencies` exactly as they are.
- Poll interval 10s, injectable sleeper (mirror `PendingWakeSleeper`) so tests
  are deterministic.
- Cold start is quiet: first tick stores the snapshot and passes `before: nil`,
  which `candidates()` already treats as "emit nothing."
- **Policy is read-only from the daemon.** Load `NotificationPolicyStore` each
  tick and call `NotificationDeliveryFilter.shouldDeliver` (which takes policy by
  value). Do **not** call `recordDelivery`, and never write
  `notification_policy.json` from `serve` — the Mac app owns that file and a
  second writer would clobber user settings. Debounce/dedupe bookkeeping lives in
  the daemon's own ledger (`delivered_notifications.json` under
  `AllnighterPaths.coordinator`, next to `coordinator.json`), merged into the
  in-memory policy copy before `shouldDeliver`. Restart therefore does not
  replay.
- **Delivery:** `osascript -e 'display notification "<body>" with title "<title>"'`
  through the injected `WakeDependencies.commandRunner` (`CommandRunner`
  protocol), so a `MockCommandRunner` can assert the exact invocation. Body/title
  come from the existing `NotificationCopy`. `osascript` is used because a bare
  CLI process cannot reliably register with `UNUserNotificationCenter`; there is
  no `osascript` call anywhere in the repo today, so this is a new dependency and
  is named as one. Guard the call site `#if canImport(Darwin)` and no-op with a
  logged line elsewhere (PortabilityHygieneTests).
- **Honest reporting:** every delivery attempt writes one line to the daemon's
  stderr log with candidate id and the `osascript` exit code. A non-zero exit
  (e.g. the user has denied Script Editor notifications) is logged as a failed
  delivery, never swallowed. `serve` does not exit non-zero for it — a failed
  banner must not kill the scheduler.
- **Exactly one owner:** `ThreadsViewModel` skips its own delivery when
  `ServeDaemonProbe().health(...).state == .available`. Without this, an open Mac
  app and a live daemon both fire for the same transition. The daemon wins
  because it is the one that is always there; the cost is the deep link, which is
  a Mac-only affordance and acceptable for v1.
- Tests: one candidate → exactly one `osascript` invocation with the expected
  argv; a restart with the ledger present fires zero; cold start fires zero;
  quiet hours / muted thread / disabled policy fire zero; `ThreadsViewModel`
  suppresses when the probe says `.available`.

### URN-S02 — Dispatch guarantees a live notifier

- New `ServeAutoLaunch.ensureRunning()` in `AllnighterEngine`: if
  `ServeDaemonProbe().health(...).state != .available`, launch a detached
  `alln serve`. Reuse `PilotCLI.detachedHandoffLaunch`'s executable resolution —
  `ProcessOwnership.currentExecutablePath()` first, falling back to
  `InstallCLI.resolvedRunningBinary(argv0:pathEnvironment:)` (the PLT-S01 fix).
  Working directory is irrelevant to `serve`; use the user's home.
- Called from the `pair` verbs that actually start a dev turn:
  `pair pilot handoff`, `pair relay`, `pair relay-resume`, `pair relay adopt`.
  **Not** `pair pilot start` (it only parks `awaitingPM`; nothing runs).
- Idempotent: the probe is the single liveness check. Never invent a second one.
- **Never fails the round.** A launch failure prints one stderr line and
  continues; the exit code of the dispatch is unchanged.
- Tests: no daemon → exactly one launch; live daemon → zero launches;
  `--no-auto-serve` / `ALLN_NO_AUTO_SERVE=1` → zero launches; a throwing
  launcher leaves the dispatch's exit code untouched.

### URN-S03 — Real relay escalation/stop event + comment fix

- Add `relayNeedsAnswer = "relay.needs_answer"` and
  `relayStopped = "relay.stopped"` to `NotificationEventKind`.
- `blockingSystemEvent` returns `.relayNeedsAnswer` for `.relayEscalated` and
  `.relayStopped` for `.relayStopped`; `isOpenBlockingSystem` returns `true` for
  `.relayEscalated` (it is an open `.running` system turn) and `false` for
  `.relayStopped` (terminal — it lands through the terminal-turn path).
- `NotificationDeliveryFilter.eventEnabled` gains both under
  `policy.notifyFailuresAndBlocked` (the switch is exhaustive; the compiler
  enforces this).
- `NotificationCopy` title: **"PM Relay needs an answer"** / **"PM Relay
  stopped"**.
- Delete the "deferred to PM_Relay.md R-S08" comment and both "deliberately
  excluded" comments. Replace with a one-line statement of what the code now
  does.
- Tests: an `.relayEscalated` transition yields exactly one
  `.relayNeedsAnswer` candidate and no `.threadNeedsAttention` duplicate for the
  same turn.

### URN-S04 (optional, deferred) — `pair pilot wait` / `pair relay wait`

- Blocking flag parity with `team status --wait-for <state> --timeout`
  (`ContractRegistry+Milestone1.swift`, `team status` CommandSpec; exit 3 =
  `timeout` per `ExitCode.stableTable`). Solves the problem only for an agent
  that chooses to poll in-process — not the founder's ask. Do not build it
  before S01–S03 land.

### URN-S05 (optional, deferred) — separate "needs your answer" from "failed" on exit code

Outside review (Gemini via `agy`, 2026-07-27) flagged that a caller reading
only `$?` — a very common shell pattern, and the one thing a dying/amnesiac
agent can check without JSON parsing — cannot tell "the round is fine and
waiting on you" from "the round broke." Verified in code: `PilotCLI.swift:480,968`
call `exit(1)` for both an escalated/stopped round and a genuine failure —
same bucket as `ExitCode.runFailed`. The JSON envelope already carries the
real distinction (`RelayJSON.status`, `PilotHandoffDispatchJSON.status` /
`roundInFlight`), so this is a narrow exit-code addendum, not new plumbing —
`ExitCode.stableTable` (`ExitCode.swift:11-36`) is contract-frozen "never
renumber," so add one new additive code (e.g. `needsAttention = 5`) rather
than repurpose an existing one, and update `ExitCodeContractTests` +
`ContractRegistry.contractVersion` deliberately. Do not build before S01–S03;
`--no-auto-serve` callers are unaffected either way since this only changes
which of two already-correct-in-JSON states the process exit code reports.
(Gemini's companion "no-op vs. did-work" ask is already covered —
`PilotHandoffDispatchJSON.roundInFlight`/`rounds` already say this in JSON —
so no exit-code change is proposed for that half.)

### URN-S06 (optional, deferred) — `alln lock status --json` + `--on-lock=fail`

Same outside-review pass flagged repo-lock preflight as missing. Verified:
there is no standalone lock-status verb and no `--on-lock`/`--wait-for-lock`
flag anywhere in `AllnighterCLI.swift` or `ContractRegistry+Milestone1.swift`
today. The underlying data already exists and is already exposed, just not as
a targeted preflight — `alln ps --json` returns `OwnershipJSON` rows with
`holderId`/`holderKind`/`heldSinceSeconds`
(`Sources/AllnighterCore/OwnershipJSON.swift:133-135`, populated from
`ExecutionLaneFlock` holder metadata in
`Sources/AllnighterEngine/ProcessOwnershipSurface.swift:539-556`, including
queue position via `wouldBePosition`). Today a second mutating dispatch always
queues FIFO against the held lock and only exits `4`
(`RUN_WRITE_LOCK_BUSY`/`laneBusy`) if the wait bound is exceeded — there is no
way to ask for immediate-fail-on-contention instead of joining the queue. A
real, narrow gem: (a) `alln lock status --repo . --json`, a thin projection of
data `ps` already computes, scoped to the current repo root, no run id
required; (b) an `--on-lock=fail|wait` flag on the mutating dispatch verbs,
default `wait` (unchanged behavior) so this is additive, never a default
change. Do not build before S01–S03.

**Discarded as noise (already shipped, verified 2026-07-27):** the same
review proposed `alln run list` / `alln run attach <run_id>` for a
turn-dying caller to rediscover in-flight work without duplicating it. This
already exists: `alln ps [--all-projects] --json` is repo-scoped by default
(`AllnighterCLI.swift:1252-1264`) and `alln run resume <runId> --json`
(`RunCLI.swift:401-416`) is the attach-by-id primitive, backed by the same
`RunStore`. Not re-proposing under a new name.

---

## Implementation contract

**CLI surface.**

| Command | Change |
| --- | --- |
| `serve` | `CommandSpec` summary gains: "…and posts local notifications when a run, team run, or PM Relay round lands or needs an answer." No new flags. Exit codes unchanged. |
| `pair pilot handoff` | New `FlagSpec("no-auto-serve", summary: "Do not auto-start the background notifier for this dispatch.")`. `PilotHandoffDispatchJSON` gains `serveAutoLaunch: String` — `"alreadyRunning" \| "launched" \| "skipped" \| "failed"`. Exit codes unchanged. |
| `pair relay`, `pair relay-resume`, `pair relay adopt` | Same `--no-auto-serve` flag. Their envelope is the shared `RelayJSON`; do **not** add a field there — report auto-launch on stderr only. |

Environment opt-out: `ALLN_NO_AUTO_SERVE=1` suppresses auto-launch everywhere.

**Model / package / contract impact.**

- `ContractRegistry.contractVersion` **4.0.9 → 4.1.0** (minor: flag + field
  additions, no removals or renames — the registry's own
  `agentAction` for contract drift states this rule). Then
  `alln dev export-contracts` and commit the regenerated artifacts; never
  hand-edit them.
- `VersionJSON.binaryVersion` **0.10.0 → 0.10.1** (one shipped batch), with
  `VersionIdentityTests` as the drift gate.
- `NotificationEventKind` is *not* referenced by `ContractRegistry` and has no
  `outputSchema`, so the two new cases are not a wire-contract change on their
  own. They are persisted indirectly inside `NotificationPolicy`'s
  `deliveredLifecycleEventIds` strings, which are additive and forward-safe.
- New durable file: `delivered_notifications.json` under
  `AllnighterPaths.coordinator`. Deleting it costs at most one duplicate banner.
- Mac app impact: one suppression check in `ThreadsViewModel` (see URN-S01).
- iOS impact: none. WebSocket/protocol impact: none. Agent driver impact: none.
- Auth/privacy/permissions: no new permission class. The macOS notification
  permission requested by NOTIF-S01 covers the Mac app path; the `osascript`
  path is attributed to Script Editor and is subject to *that* app's
  notification permission — the one real host-boundary risk, which is why the
  Works Test below requires an on-host confirmation and why S01 logs delivery
  failures instead of assuming success.

**Teaching surface.**

- `HelpTopicRegistry` topic `pm_relay`: add a `sections` entry
  `("notify", "You do not have to watch", …)` describing that a dispatched round
  notifies on completion/escalation with the app closed, and that the notifier
  auto-starts. Aliases to add: `"notify me"`, `"notification"`,
  `"tell me when it's done"`, `"background notifier"`.
- `HelpTopicRegistry` topic `pending` / `quickstart`: wherever `alln serve` is
  described as "optional background scheduler", extend to name notifications so
  the two descriptions cannot drift.
- `relatedCommandNames` on `pm_relay` already lists the four dispatch verbs; the
  new `--no-auto-serve` flag is discoverable through their `CommandSpec`s.
- Nothing is retired, so there is no deny-list sweep.
- Gate: `alln dev export-contracts --check` plus the existing help-corpus test
  must be green — prose naming a flag `ContractRegistry` cannot resolve is a P0.

**Deletion targets (duplicate truth).**

- The three stale comments in `NotificationCandidateDetection.swift` (S03).
- The Mac app's unconditional delivery path becomes conditional (S01) — there
  must never be two live notifiers for one transition.

---

## Inference bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| `serve` scheduler → runs | `RunService` | "The notifier may nudge/resume a stuck run" | The notification scheduler may only read stores and spawn `osascript`; no `RunService`, no `AsyncTeamService`, no `RunWriteLockRegistry` reference | Architecture-policy check: the new scheduler file imports/uses no run-mutating symbol |
| `serve` ↔ Mac app | one live notifier | "Both can deliver; dedupe will sort it out" | Mac app suppresses when `ServeDaemonProbe` reports `.available` | Probe `.available` → `ThreadsViewModel` delivers zero |
| `serve` → `notification_policy.json` | Mac app / user settings | "The daemon can record its deliveries in the shared policy file" | Daemon reads the policy, never writes it | Daemon tick leaves the policy file's mtime and bytes unchanged |
| dispatch → round outcome | the round | "A failed notifier launch means the round failed" | Auto-launch failure never changes the dispatch exit code | Throwing launcher → dispatch exit code identical to baseline |

---

## Proof

**Works Test (owner-visible, on-host — a mock cannot close this).**

Setup, with the Mac app **quit**:

```bash
osascript -e 'tell application "Allnighter" to quit' 2>/dev/null || true
pkill -f 'alln serve' || true
alln serve --health --json          # expect "state":"foregroundOnly"
```

Gesture (from the repo root, with an existing pilot relay id):

```bash
alln pair pilot start --doc docs/phases/Unattended_Round_Notification.md \
  --project "$PWD" --dev-worker <dev-id> --json      # -> relayId
printf 'Add one line to README.md, then stop.\n' > /tmp/order.md
alln pair pilot handoff --relay <relayId> --verdict continue \
  --handover-file /tmp/order.md --no-wait --json
```

Assertions:

1. The dispatch JSON contains `"serveAutoLaunch":"launched"`.
2. `alln serve --health --json` now reports `"state":"available"`.
3. **A macOS banner appears when the dev turn settles, with the Mac app closed.**
   This is the claim; it is the step no mock can prove.
4. `alln pair pilot status --relay <relayId> --json` reports `awaitingPM`.
5. Escalation copy: submit `--verdict escalate --note "which file?"` and confirm
   the banner reads **"PM Relay needs an answer."**
6. Idempotence: a second `handoff` reports `"serveAutoLaunch":"alreadyRunning"`
   and `pgrep -f 'alln serve' | wc -l` stays at 1.

**Supporting checks.**

```bash
swift test --package-path Packages/AllnighterCore \
  --filter 'Notification|ServeDaemon|Pilot|ContractRegistry|FixtureRoundTrip|VersionIdentity|PortabilityHygiene'
alln dev export-contracts --check
scripts/check_architecture_policy.sh
```

**Missing proof / waiver:** none requested. Step 3 is the host-boundary claim
and must be run on the founder's Mac before this packet is called shipped.

---

## Done when

- **User-visible claim:** "Allnighter tells you when a round lands or needs your
  answer, even with the app closed — and you never have to start the notifier."
- CLI contract shipped and tested: `--no-auto-serve` on four verbs,
  `serveAutoLaunch` on `PilotHandoffDispatchJSON`, contract 4.1.0 regenerated.
- Teaching surface updated: `pm_relay` notify section + aliases; `serve`
  description no longer says the scheduler is notification-free; help corpus
  green.
- Proof: the six Works Test assertions above, including the on-host banner.
- Closeout: promote nothing to a standing doc (behavior is code-owned), then
  archive this packet to `docs/archive/phases/` naming `ServeDaemon.swift` /
  `NotificationCandidateDetection.swift` / `PilotCLI.swift` as successors.
