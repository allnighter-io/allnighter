# Unattended round notification — CEO decision brief

Status: **Draft — pending founder decision**
Updated: 2026-07-27
Owner: Allnighter product (CLI / Pilot / Relay / `alln serve`) — code SSOT once
approved: `ServeDaemon.swift`, `NotificationCandidateDetection.swift`,
`NotificationEvent.swift`, `PilotCLI.swift`, `RelayCoordinator.swift`

---

## The ask (one paragraph)

Three times in one day, an agent started `alln pilot`/`alln relay` work from a
terminal and nothing told the founder when it landed — not the CLI (the agent
that dispatched it had already moved on or died), not the Mac app (it was not
open), nothing. The founder's bar: **the human should have to do nothing, and
the agent that started the round should not have to build its own watcher.**
Allnighter already knows the moment work lands or needs a PM answer — it should
say so, on its own, without either party polling for it.

**Approve?** Recommend **yes**, scoped to slices URN-S01/S02 below.

---

## What went wrong (plain story, grounded in the actual code)

Allnighter already has a real notification pipeline, and it is good machinery:
`NotificationCandidateDetection` (`Packages/AllnighterCore/Sources/AllnighterCore/NotificationCandidateDetection.swift`)
purely diffs thread/turn/run snapshots into `NotificationCandidate`s —
`turnCompleted`, `turnFailed`, `teamRunCompleted`, `vendorParked`/`vendorResumed`,
`threadNeedsAttention`. `MacNotificationDelivery` (`Apps/AllnighterMac/Sources/MacNotificationDelivery.swift`)
posts a real macOS banner with click-to-thread deep linking. This shipped as
NOTIF-S01–S05 (`docs/archive/phases/threads/02_Notifications.md`) and it works.

The scope line in that doc is the whole bug: **"Ship Mac local notifications
only in this phase."** The candidate-detection diff only ever runs inside
`ThreadsViewModel` (`Apps/AllnighterMac/Sources/ThreadsViewModel.swift:1536,1557`)
— i.e. only while the Mac GUI process is alive and polling. `alln serve`, the
component AGENTS.md and `CLI_Product_Spine.md` already name as the
**app-closed** background owner ("Resident mode... `alln serve` is required
before public Pending can promise app-closed execution"), has **zero**
notification code (`ServeDaemon.swift` — no reference to `Notification` or
`UserNotifications` anywhere in the scheduler). A relay/pilot round dispatched
purely from a terminal, with the Mac app never opened, writes real state to
disk (`RelayState`, thread/turn projections via `RelayThreadProjector`) that
nothing is watching. This is exactly the founder's three failures today — not
a fluke, a designed-in gap between "Mac app open" (notified) and "CLI-only"
(silent forever).

A second, smaller bug compounds it. Even when the Mac app **is** running, a
relay round entering `.relayEscalated` (needs a PM answer) or `.relayStopped`
does not get its own notification event — `NotificationCandidateDetection.swift:293,305`
explicitly excludes both from `isOpenBlockingSystem`/`blockingSystemEvent`, and
a code comment (lines 289-292) claims a "per-event specific push... is GUI
polish deferred to PM_Relay.md R-S08." R-S08 shipped — but it shipped the Mac
GUI escalation *row* (`RelayEscalationRow`, visible only if the thread is
already open), not a push notification. The comment overclaims; it describes
behavior the code does not implement. Today a relay escalation only surfaces
via the generic `threadNeedsAttention` transition, which is one more layer
riding on the same Mac-app-must-be-running assumption above.

---

## Prior art (how mature tools solve this)

The common pattern across CI/build tooling: **the notifier is a standing
process independent of the caller**, never the caller's own responsibility.
GitHub Actions notifies via webhook/email regardless of whether the machine
that pushed the commit is still online. Xcode posts a system notification when
a background build finishes even if Xcode is not frontmost — but Xcode's own
process is still alive; it never asks the build's *invoker* to poll. iTerm2's
"alert on next mark" watches a shell command from the terminal app itself, not
from the command. The same shape applies here: `alln serve` is Allnighter's
already-declared standing, app-closed process — this is squarely its job, not
a new architectural concept, and not something `pilot`/`relay`'s calling agent
should ever reinvent as a pgrep loop.

---

## What we are recommending

1. **`alln serve` delivers OS notifications for relay/pilot rounds, with the
   Mac app fully closed.** Reuse the existing, portable
   `NotificationCandidateDetection` pure functions (already living in
   `AllnighterCore`, no `UserNotifications` import, so no portability-hygiene
   violation) inside a new scheduler loop on `ServeDaemon`, following the exact
   pattern already used by `PendingWakeScheduler`/`BoostSeedScheduler`/
   `VendorBackoffReconciler` (`ServeDaemon.swift:126-162`). Deliver via
   `osascript -e 'display notification ...'` through the existing
   `CommandRunner` dependency already injected into `ServeDaemon.WakeDependencies`
   — no new framework, no app-bundle registration problem (bare CLI processes
   cannot reliably register with `UNUserNotificationCenter`; `osascript` has no
   such requirement).

2. **Dispatch guarantees the watcher exists — the human does nothing, the
   calling agent builds nothing.** `PilotCLI.dispatchHandoffInBackground` and
   `alln relay` start should check whether a serve daemon is already alive
   (`ServeDaemonStore`/`ServeDaemonProbe` already expose this) and auto-launch
   a detached `alln serve` if not, using the same detached-`Process()` pattern
   `PilotCLI` already uses for the round itself. This is what actually closes
   the founder's ask — without it, slice 1 only helps founders who remembered
   to leave `alln serve` running.

3. **Give relay escalation/stop their own notification event** instead of
   riding the generic `threadNeedsAttention` fallback, and delete the stale
   comment. Copy the comment's own suggested language: "PM Relay needs an
   answer." Cheap, and it sharpens slice 1's dedupe key.

4. **(Optional, lower priority) `pilot wait` / `alln relay wait` blocking
   primitive**, parity with `team status --wait-for <state> --timeout`
   (`ContractRegistry+Milestone1.swift:344`), which pilot/relay currently lack.
   This helps an agent that *chooses* to block in-process; it does not replace
   slices 1-2, since the founder's ask is specifically that nobody — human or
   agent — should have to watch at all.

If you only do two, do #1 and #2 — #1 alone is inert without #2 guaranteeing
the daemon is actually running.

---

## Why you should care

| If we do nothing | If we ship URN-S01/S02 |
| --- | --- |
| CLI-only relay/pilot work (today's dominant real usage) notifies nobody, ever, unless the Mac app happens to be open | Allnighter pings the human the moment a round lands or needs a PM answer, app open or closed |
| Every agent independently reinvents a pgrep/poll loop, or nothing, and founders manually re-check three times a day | Zero caller-side watching, human or agent |
| A code comment claims relay escalation already pushes a notification; it does not | Escalation gets a real, correctly-labeled event |

---

## What we are explicitly not doing

- Not building a new cloud/push service — this is local `osascript`/`UserNotifications` delivery only, same trust boundary as NOTIF-S01–S05.
- Not touching iOS push (that is `docs/phases/ios/03_iOS_Thread_Read_State_And_Push.md`, already deferred and out of scope here).
- Not giving `alln serve` any run semantics — it only *reads* existing `RelayState`/thread state and shells out to notify; it owns no run.
- Not replacing `pilot status`/`pilot watch`; those stay as the pull-based path for a caller that wants to poll in-process.
- Not rebuilding notification detection — `NotificationCandidateDetection` is reused as-is.

---

## Scope and cost (feel)

Small, bounded CLI/engine work: one new scheduler loop on `ServeDaemon`
(same shape as three existing ones), one auto-launch check at two dispatch
sites, one new `NotificationEventKind` pair + copy. No Mac redesign required
for slices 1-2 (the Mac app's own NOTIF-S01–S05 pipeline is untouched and still
works when it happens to be open). No new billing, no new permission class
beyond the macOS notification permission already requested by NOTIF-S01.

---

## Success looks like

- Quit the Mac app entirely. From a terminal, dispatch a pilot round or start a
  relay. Walk away. When the round completes or escalates, a macOS notification
  banner appears — with no human polling and no watcher process the calling
  agent had to invent.
- The founder never has to remember to run `alln serve` first; dispatching a
  round guarantees a notifier is alive.
- A relay round that needs a PM answer reads "PM Relay needs an answer," not a
  generic thread-needs-attention line.

---

## Decision

| Option | Meaning |
| --- | --- |
| **Approve** | Build URN-S01 → URN-S02 → URN-S03 in order; URN-S04 optional/deferred |
| **Approve with cuts** | Say which slices to drop (URN-S04 is the one to cut first; URN-S01/S02 are the pair that actually fixes today's failure) |
| **Reject** | Leave current behavior; CLI-only relay/pilot work stays silent until the founder happens to check |

Founder sign-off: _pending_

---

## Builder slices (proposed)

### URN-S01 — `alln serve` posts OS notifications for relay/pilot state

- New scheduler (e.g. `RelayNotificationScheduler`) added to `ServeDaemon.run`'s
  `TaskGroup` alongside `PendingWakeScheduler`/`BoostSeedScheduler`/
  `VendorBackoffReconciler` (`ServeDaemon.swift:126-162`), gated on an optional
  dependency bundle the same way `remoteDependencies` is.
- Polls relay/pilot state the same way `alln ps`'s process-ownership
  enumeration already does machine-wide (`ProcessOwnershipSurface.swift`) —
  reuse that enumeration rather than inventing a parallel relay registry.
- Feeds snapshots through the existing `NotificationCandidateDetection.candidates`/
  `runCandidates` (unchanged; already portable, already tested).
- Delivery: shell `osascript -e 'display notification "<body>" with title
  "Allnighter"'` via the existing `CommandRunner` protocol (already injected as
  `WakeDependencies.commandRunner`) — keeps delivery unit-testable with a mock
  runner; the real macOS banner itself needs one manual on-host confirmation
  per SSOT_Feature_Workflow's host-boundary rule (a mock cannot close that
  claim).
- Dedupe: persist delivered `NotificationCandidate.id`s in `ServeDaemonStore`
  so a daemon restart does not replay old notifications (mirrors the
  `before`-must-be-non-nil cold-start-quiet rule already in
  `NotificationCandidateDetection.candidates`).
- Tests: scheduler fires exactly once per real transition; restart does not
  re-fire; mock `CommandRunner` receives the expected `osascript` invocation.

### URN-S02 — Dispatch guarantees a live notifier

- `PilotCLI.dispatchHandoffInBackground` and `alln relay` start: before/while
  forking the round's detached child, check `ServeDaemonProbe`/`ServeDaemonStore`
  for a live daemon; if none, auto-launch a detached `alln serve` using the
  same executable-resolution fix PLT-S01 already built
  (`InstallCLI.resolvedRunningBinary`).
- Idempotent: never double-launch if a daemon is already alive (reuse the
  existing probe, do not invent a second liveness check).
- Tests: dispatch with no daemon running launches exactly one; dispatch with a
  daemon already running launches zero.

### URN-S03 — Real relay escalation/stop notification event + comment fix

- Add `.relayEscalated`/`.relayStopped` (or equivalent) to
  `NotificationEventKind`; wire `blockingSystemEvent`/`isOpenBlockingSystem`
  (`NotificationCandidateDetection.swift:283-308`) to emit them instead of
  falling through to the generic `threadNeedsAttention` path.
- Delete the stale "deferred to PM_Relay.md R-S08" comment; R-S08 shipped the
  GUI row, not this push.
- Copy: "PM Relay needs an answer" per the existing comment's own suggestion.
- Regen contracts/fixtures if `NotificationEventKind` cases are contract-visible.

### URN-S04 (optional, defer-first) — `pilot wait` / `alln relay wait`

- Blocking flag parity with `team status --wait-for <state> --timeout`
  (`ContractRegistry+Milestone1.swift:344`). Lower priority: solves the same
  problem for an agent that chooses to poll in-process, not the founder's
  actual ask (nobody should have to watch).

---

## Open questions

- Does `alln serve` already have a clean, scoped way to enumerate active
  relay/pilot state across projects on one machine, or does URN-S01 need to
  add one? (Lean on `ProcessOwnershipSurface`/`alln ps` first — do not build a
  second machine-wide registry; `Concurrent_Invocation_Isolation.md` already
  established the scoped-enumeration pattern.)
- Should `osascript` delivery in URN-S01 also carry a click-to-thread deep
  link, or is a plain banner (open Allnighter manually) good enough for v1?
  Recommend plain banner for v1 — richer click-through only works when the Mac
  app is the one delivering (NOTIF-S03, already shipped for that case).
