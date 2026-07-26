# Pilot Long-Turn Survival — durable round ≠ disposable waiter

Status: **Draft feature packet — ready to slice.** Field evidence 2026-07-26
(websitemd.studio Pilot round 7: D1 reconcile + `release:ship`). Feedback
folded 2026-07-26 (open questions closed).
Owner: AllnighterCore + CLI (`PilotCLI` / `RelayCoordinator`)
Updated: 2026-07-26
Companions:
- Shipped Pilot substrate: archived `docs/archive/phases/Pilot_Relay.md`
- Pilot DX (watch-as-recovery): archived `docs/archive/phases/Pilot_DX.md` §DX5
- Idle floors / progress attribution: archived
  `docs/archive/phases/Idle_Stall_False_Kill_Hotfix.md`
- Binary identity (argv0): archived `Pilot_DX.md` §DX2 — **detached handoff
  spawn path still bypasses the resolver**
- Poll cadence precedent: `AsyncTeamStatusMapper.waitHintSeconds` /
  `alln team status --wait-for`

## Founder intent

Relay / Pilot rounds that do real deploy, reconcile, or other long ops must
survive host harnesses that reap long-blocking shells. A killed `pilot watch`
must never be read as a failed round. Status against durable relay state is the
truth; waiters are disposable.

## Product value

Agent hosts (Cursor, Claude Code, Codex) routinely stop background commands that
sit silent for a long time. Today that silence is exactly what `pilot watch`
does — poll with no heartbeat until the round settles. The PM session then
assumes the round died. In the field incident the round was still in flight and
had already landed real commits. Re-attaching via `pilot status` recovered the
truth; the product should make that the happy path, not a clever recovery.

The axis generalizes past this bug: **durable state is SSOT; waiters are
disposable.** Any client that blocks on a round (watch, shell, harness job) may
die without changing round truth.

## Trusted workflow slice

```text
pilot handoff --no-wait --json
  → detached child owns the round
       (absolute binary via shared resolver; cwd = projectRoot — two requirements)
  → PM polls: pilot status --json using returned waitHintSeconds
       still running → ownerAlive + lastProgressAt / silenceAge (primary)
                       commitsSinceBaseline labeled supplementary only
       awaitingPM    → read settled report; write next handover
  → optional: pilot watch (SIGTERM exit envelope + heartbeats + default max-wait
       on non-TTY) — never the agent recovery story
```

## Origin (field evidence)

websitemd.studio Pilot round 7 (2026-07-26):

| Observation | Reading |
| --- | --- |
| Background command "Watch round 7" was stopped | Host harness reaped the **waiter**, not the round |
| Round still `.running`; three commits landed mid-flight | Durable `RelayState` + owner pid survived |
| `8916007e` / `84e704a8` / `2342eaa7` | Real deploy/reconcile work progressed under the write lock |
| Detached handoff "worked from repo root" | **Understated.** Root only worked because a prior session left a **gitignored `alln` symlink** in that checkout. The child resolves bare `argv[0]` as `<cwd>/alln`. Without that leftover artifact, detached dispatch fails from **every** directory — including project root. Clean checkouts are broken; one repo masked it. |
| Operator re-attached with `pilot status` / re-watch | Correct recovery — guided by a product-repo memory note, not by alln teaching. Absent that note, re-dispatch under the write lock was the likely (destructive) path. |

Operational notes banked in that repo's deploy quirk catalogue are **Allnighter
bugs**, not product-repo bugs: (1) detached handoff binary resolution is a
**functional bug** (not an ergonomic quirk), (2) long watch reaped by harness →
status, not failure — and watch's death left nothing on stdout to contradict
"round failed."

## Non-goals

- Do not auto-restart watchers as if they owned the round.
- Do not treat harness SIGTERM on `watch` as orphan-reconcile of the relay.
- Do not raise global idle/wall for all chat because deploys are long.
- Do not invent a second "deploy timeout" clock beside idle + wall.
- Do not make the PM session git-watch commits as the turn signal (Allnighter
  already owns turn completion).
- Do not teach `commitsSinceBaseline > 0` as liveness (investigation / no-commit /
  failed-doc rounds read zero while healthy).
- Do not reopen Team Lab or spawn a parallel relay state machine.

## Current state

| Piece | Where | State |
| --- | --- | --- |
| Durable relay / pilot state | `RelayState` / `RelayStateStore` | Built — SSOT across waiter death |
| Blocking + `--no-wait` handoff | `PilotCLI` | Built |
| Detached handoff spawn | `PilotCLI.dispatchHandoffInBackground` | **Functional bug** — raw `CommandLine.arguments[0]` → `<cwd>/alln`; no projectRoot cwd |
| `pilot status` recovery ladder | `PilotStatusJSON` + `InFlightRecovery` | Built (DX5) — already answers in-flight vs orphan; thin mid-round progress; **no `waitHintSeconds`** |
| Orphan reconcile (dead **owner**) | `RelayCoordinator.reconcileOrphan` | Built — settles `.running` + dead owner → `.stopped` + `orphanReconciledReason`; must not fire for dead **watchers** |
| `pilot watch` | `PilotCLI.runWatch` | Built — silent 1s poll; no heartbeat; no `--max-wait`; **no SIGTERM exit envelope** |
| Idle / wall floors | driver `invoke.timeoutSeconds` 1800; wall 3600 | Shipped IDLE-HF; ops turns may still need overrides |
| Progress attribution (pgid) | `ProcessGroupCommandRunner` / IDLE-HF-S02 | Shipped — do not add deploy-script heartbeats until field proves worker false-kill |
| Teaching: watch = recovery | help / bootstrap / DX5 `nextAction` | **Wrong for agent hosts** — status must lead; teaching is harm-reduction, not polish |

## Truth owner

- Round liveness / outcome: `RelayState` (+ in-flight run under `RunStore`)
- Waiter / watch process: **never** truth — disposable client
- Handoff **owner** process: round identity while `.running` — **not** a waiter;
  dead owner triggers orphan reconcile (defined verdict below)
- Binary path for detached spawn: shared argv0/PATH resolver (same as DX2 /
  `InstallCLI` / bootstrap), not raw `argv[0]`
- Child working directory for the round: relay `projectRoot` (independent of
  binary resolution)

## Lie-prone layers

1. Host harness exit on `pilot watch` → **agent narrative** "round failed"
   (not a code path — the insight most packets miss)
2. Silent watch → harness "hung command" reaper (and empty stdout on death)
3. Detached child `executableURL = argv[0]` when invoked as bare `alln` —
   masked by leftover gitignored symlinks in dirty checkouts
4. Teaching that still names `watch` before `status` for agent hosts
5. Surfacing commit count co-equal with progress → agents latch onto the easy
   wrong heuristic

## New / changed semantic rules

1. **Durable state is SSOT.** A killed watcher never implies a dead or failed
   round. Always `pilot status --json` before retry / escalate / "failed."
2. **Agent happy path is `--no-wait` + status poll.** Blocking `watch` remains
   for interactive TTYs; agents must not depend on it surviving.
3. **Watch death must self-document.** On SIGTERM/SIGINT, `pilot watch` prints
   one status envelope (`stillRunning: true` when owner alive, `reattach` /
   `nextActions` → `pilot status`) then exits 0 (or a dedicated non-failure
   code — never the same exit as round failure). Cheaper than heartbeats; fixes
   lie-prone layer 1 at the moment of death.
4. **Watchers that stay emit progress and bound their wait.** Heartbeats while
   `.running`; `--max-wait` defaults on non-TTY (agent proxy) with
   `maxWaitApplied: true` in the envelope; interactive TTY stays unbounded unless
   explicit. Bounded exit is clean reattach, not a crash.
5. **Detached handoff resolves an absolute binary** via the shared resolver.
   Independent of cwd. No symlink / "run from root" workaround.
6. **Detached handoff sets child cwd = `projectRoot`.** Independent of binary
   resolution — required for the round's git / tool operations.
7. **Status poll cadence is product-owned.** `pilot status --json` returns
   `waitHintSeconds` (reuse the team-status field name). Flat **45s** while
   `.running` until a real round-class signal exists — do not leave cadence to
   agent judgment.
8. **Progress truth while running:** `ownerAlive` + `lastProgressAt` /
   `silenceAgeSeconds` are primary. `commitsSinceBaseline` (if present) is
   **supplementary evidence**, contract-labeled as such — never co-equal, never
   taught as liveness.
9. **Deploy-class budgets reuse one idle + one wall.** Existing
   `--idle-timeout` / wall overrides on `pilot start`. No parallel clock. No
   remembered per-project ops posture in this packet (flag teaching is enough).
10. **Dead owner ≠ dead waiter (recovery ladder).** See §Dead-owner verdict.

## Dead-owner verdict (closed)

"Waiters are disposable" does **not** answer: owner process gone, round never
reached `awaitingPM`. The handoff owner is the round's process identity while
`.running`, not a waiter.

| State | Product verdict | Agent must |
| --- | --- | --- |
| Watcher dead, owner alive, `.running` | Round alive | `pilot status`; continue poll — never re-dispatch |
| Owner dead, `.running` | **Must not remain `.running`** — `reconcileOrphan` settles to `.stopped` + `orphanReconciledReason` (already built) | Treat as **unsettled failure of ownership**, not as success and not as "safe to blindly retry" |
| After orphan reconcile | Durable `status: stopped`, recovery `orphanReconciled` | Inspect round log + repo delta + in-flight run journal; decide continue (new handoff) vs done vs escalate — **never** invent immediate re-dispatch |

`nextActions` after orphan reconcile must name **inspect**, not **retry**. Partial
work under the write lock is the hazard; silence here is how agents duplicate
turns.

Works Test must prove reconcile with a **dead waiter** leaves the round
untouched (Non-goal #2), and dead **owner** settles exactly once to the orphan
path above.

## Duplicate truth to delete

- Help / bootstrap lines that imply "if watch dies, the round died"
- Any recovery copy that lists `watch` before `status` for agent hosts
- Any teaching that equates commit count with liveness

## Implementation impact

| Slice | Deliverable | Proof |
| --- | --- | --- |
| **PLT-S01** | Detached handoff: (a) absolute binary via shared resolver, (b) `currentDirectoryURL = projectRoot` — two assertions, two tests | Bare/relative/absolute argv0; child cwd; **clean checkout without `<cwd>/alln` symlink** still dispatches |
| **PLT-S03** | Teaching only: bootstrap / help / `nextAction` / recovery nextActions — agent path = `--no-wait` + status + `waitHintSeconds` once present; watch demoted. **No dependency on S02 fields** — today's in-flight status is enough | Help/contract regen; bootstrap snippet; cold-agent recipe prefers status |
| **PLT-S04** | `pilot watch`: **(1) SIGTERM/SIGINT exit envelope first**, (2) heartbeats, (3) `--max-wait` default on non-TTY + `maxWaitApplied`, explicit override always wins | SIGTERM mid-flight → stdout envelope `stillRunning` + reattach; no orphan; max-wait default + flag; heartbeat lines |
| **PLT-S02** | Enrich `PilotStatusJSON` while `.running`: `elapsedSeconds`, `ownerAlive`, `lastProgressAt` / `silenceAgeSeconds` (**primary**), `commitsSinceBaseline` (**supplementary**, contract description says so), `waitHintSeconds: 45`, `watcherDisposable: true`; nextActions = status poll with hint | Contract + PilotCLI tests; assert commit field is not required for "alive" |
| **PLT-S05** | Deferred — only if field still **worker**-false-kills (not waiters). Flag teaching for idle/wall; no ops-posture store | Field waiver or doctor silence evidence |

Recommended ship order: **S01 → S03 → S04 → S02**. S05 only on worker
false-kill evidence.

Rationale: S01 is a clean-checkout functional break. S03 cuts silent
re-dispatch harm immediately with zero new instrumentation. S04's SIGTERM
envelope fixes the actual field event (reaped watch → empty "killed") cheaper
than heartbeats. S02 then deepens the status-poll path agents were taught to
use.

## Mac app impact

None required. Inbox / thread already observe durable relay state. Do not add a
GUI-only long-wait surface.

## iOS app impact

None.

## Driver / protocol impact

No new driver. Reuse `RunRequest.workerTimeoutSeconds` / wall overrides already
wired through `RelayCoordinator.Config.devTurnIdleTimeoutSeconds` (PO-F7).
Reuse `waitHintSeconds` field name from team status; pilot chooses its own
constant (45s running) until round-class signals exist.

## Auth / privacy / permissions impact

None. No new Keychain, network, or TCC surface.

## Works Test

1. **S01 — clean checkout:** bare `alln` on PATH, cwd ≠ project root, **no**
   `<cwd>/alln` symlink → `handoff --no-wait` child still starts; child cwd is
   `projectRoot`. Repeat from project root without a local `alln` file/symlink.
2. **S04 — watcher SIGTERM ≠ orphan:** long fixture `.running`; SIGTERM the
   watch process → stdout contains status envelope with `stillRunning: true` (or
   equivalent) + reattach to `pilot status`; relay remains `.running` /
   `handoffAlive`. Then run reconcile / status-with-reconcile → round **untouched**
   (Non-goal #2).
3. **S04 — dead owner ≠ dead waiter:** kill the **handoff owner** mid-round →
   status/reconcile settles to orphan path once; `nextActions` name inspect, not
   blind retry.
4. **S03 — teaching:** cold bootstrap recipe uses `--no-wait` + status, not
   infinite watch as recovery.
5. **S04 — max-wait:** non-TTY `pilot watch` applies default max-wait,
   `maxWaitApplied: true`, exits with `stillRunning` envelope; `--max-wait 5`
   honored; TTY without flag stays unbounded (or documented interactive default).
6. **S02 — progress primary:** fixture round with zero commits since baseline
   but fresh progress heartbeat → status still reports alive; contract /
   help text marks commit count supplementary.

## Proof command

```text
swift test --package-path Packages/AllnighterCore --filter 'Pilot|Relay'
alln pair pilot status --relay <id> --json   # mid-flight field check
```

## Missing proof / waiver

Live multi-minute Cloudflare deploy under Cursor harness is a field Works Test,
not a unit gate. Close S01–S04 on package tests + one recorded Pilot status
capture from a real long round (or explicit waiver naming harness reaping as
out-of-process).

## Done when

- Detached handoff works on a clean checkout with bare `alln` on PATH from any
  cwd (binary resolution) and always uses `projectRoot` as child cwd.
- Agent teaching and `nextActions` lead with status polls + `waitHintSeconds`;
  watch is optional.
- Reaped watch prints a reattach envelope; reconcile does not orphan the round.
- Dead owner has a single defined orphan verdict; agents are told to inspect.
- Status mid-flight answers alive/progress without requiring commits.
- Silent infinite watch is gone on agent (non-TTY) hosts.
- No second timeout system for deploy; no ops-posture store in this packet.

## Closed questions (was Open questions)

| # | Question | Decision | Why |
| --- | --- | --- | --- |
| 1 | Default `--max-wait` on agent hosts? | **Yes — default on non-TTY**, always report `maxWaitApplied: true`; explicit flag wins; interactive TTY stays unbounded unless flagged | All three named hosts reap long silent shells — that's the norm. Explicit-only preserves the footgun. Non-TTY is the durable agent proxy (no Cursor/Claude/Codex fingerprinting). Visibility answers "mysterious host-dependent behavior." |
| 2 | Per-project ops idle/wall posture? | **No slice in this packet** — flag teaching only | One idle + one wall already exist. A posture store is a second clock dressed as convenience; revisit only if founders repeatedly burn turns forgetting flags. |
| 3 | Deploy-script heartbeats vs IDLE-HF pgid? | **Do nothing speculative** — trust IDLE-HF until a **worker** (not waiter) false-kill is evidenced | This packet's field bug was waiter reap, not idle kill. Adding script heartbeats before proof invents work and couples product repos to alln's watchdog. |
| 4 | Dead owner, unsettled round? | **Orphan reconcile → stopped + inspect nextAction** (see §Dead-owner verdict) | Owner ≠ waiter. Leaving `.running` with a dead owner is a lie; blind retry duplicates under the write lock. Inspect is the only honest next step. |

## Practical shape (operators, until shipped)

```text
alln pair pilot handoff --relay <id> --no-wait --json
# loop until awaitingPM / terminal — sleep ~45s between polls:
alln pair pilot status --relay <id> --json
# do not treat a killed watch as round failure
# do not re-dispatch while status is running or before inspecting an orphan stop
```

For ship/reconcile turns today: raise budgets at start, e.g.
`pilot start … --idle-timeout 3600` (and wall override on the underlying run
when needed).
