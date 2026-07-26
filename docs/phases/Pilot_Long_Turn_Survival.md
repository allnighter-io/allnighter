# Pilot Long-Turn Survival — durable round ≠ disposable waiter

Status: **Draft feature packet — ready to slice.** Field evidence 2026-07-26
(websitemd.studio Pilot round 7: D1 reconcile + `release:ship`).
Owner: AllnighterCore + CLI (`PilotCLI` / `RelayCoordinator`)
Updated: 2026-07-26
Companions:
- Shipped Pilot substrate: archived `docs/archive/phases/Pilot_Relay.md`
- Pilot DX (watch-as-recovery): archived `docs/archive/phases/Pilot_DX.md` §DX5
- Idle floors / progress attribution: archived
  `docs/archive/phases/Idle_Stall_False_Kill_Hotfix.md`
- Binary identity (argv0): archived `Pilot_DX.md` §DX2 — **detached handoff
  spawn path still bypasses the resolver**

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

## Trusted workflow slice

```text
pilot handoff --no-wait --json
  → detached child owns the round (absolute binary + projectRoot cwd)
  → PM polls: pilot status --json (short, frequent)
       still running → elapsed / ownerAlive / commitsSinceBaseline / lastProgress
       awaitingPM    → read settled report; write next handover
  → optional interactive: pilot watch (heartbeats + --max-wait) on a human tty
```

## Origin (field evidence)

websitemd.studio Pilot round 7 (2026-07-26):

| Observation | Reading |
| --- | --- |
| Background command "Watch round 7" was stopped | Host harness reaped the **waiter**, not the round |
| Round still `.running`; three commits landed mid-flight | Durable `RelayState` + owner pid survived |
| `8916007e` / `84e704a8` / `2342eaa7` | Real deploy/reconcile work progressed under the write lock |
| Detached handoff needed cwd = repo root | Child resolved binary via cwd-relative `argv[0]` |
| Operator re-attached with `pilot status` / re-watch | Correct recovery; not taught as primary agent path |

Operational notes banked in that repo's deploy quirk catalogue are **Allnighter
bugs**, not product-repo bugs: (1) detached handoff binary path, (2) long watch
reaped by harness → status, not failure.

## Non-goals

- Do not auto-restart watchers as if they owned the round.
- Do not treat harness SIGTERM on `watch` as orphan-reconcile of the relay.
- Do not raise global idle/wall for all chat because deploys are long.
- Do not invent a second "deploy timeout" clock beside idle + wall.
- Do not make the PM session git-watch commits as the turn signal (Allnighter
  already owns turn completion).
- Do not reopen Team Lab or spawn a parallel relay state machine.

## Current state

| Piece | Where | State |
| --- | --- | --- |
| Durable relay / pilot state | `RelayState` / `RelayStateStore` | Built — SSOT across waiter death |
| Blocking + `--no-wait` handoff | `PilotCLI` | Built |
| Detached handoff spawn | `PilotCLI.dispatchHandoffInBackground` | **Bug** — `CommandLine.arguments[0]` raw; no projectRoot cwd |
| `pilot status` recovery ladder | `PilotStatusJSON` + `InFlightRecovery` | Built (DX5) — thin mid-round progress |
| `pilot watch` | `PilotCLI.runWatch` | Built — silent 1s poll; no heartbeat; no `--max-wait` |
| Idle / wall floors | driver `invoke.timeoutSeconds` 1800; wall 3600 | Shipped IDLE-HF; ops turns may still need overrides |
| Progress attribution (pgid) | `ProcessGroupCommandRunner` / IDLE-HF-S02 | Shipped — verify wrangler children count |
| Teaching: watch = recovery | help / bootstrap / DX5 | **Wrong for agent hosts** — status must lead |

## Truth owner

- Round liveness / outcome: `RelayState` (+ in-flight run under `RunStore`)
- Waiter / watch process: **never** truth — disposable client
- Binary path for detached spawn: shared argv0/PATH resolver (same as DX2 /
  `InstallCLI` / bootstrap), not raw `argv[0]`

## Lie-prone layers

1. Host harness exit on `pilot watch` → agent narrative "round failed"
2. Silent watch → harness "hung command" reaper
3. Detached child `executableURL = argv[0]` when invoked as bare `alln`
4. Teaching that still names `watch` as the primary recovery for agents

## New / changed semantic rules

1. **Durable state is SSOT.** A killed watcher never implies a dead or failed
   round. Always `pilot status --json` before retry / escalate / "failed."
2. **Agent happy path is `--no-wait` + status poll.** Blocking `watch` remains
   for interactive TTYs and hosts that do not reap long shells.
3. **Watchers that stay must emit progress.** Heartbeat lines (human or NDJSON)
   while `.running`; optional `--max-wait` exits 0 with `stillRunning: true` and
   the same status envelope (clean reattach, not a crash).
4. **Detached handoff resolves an absolute binary and runs with cwd =
   `projectRoot`.** No "dispatch from repo root" workaround.
5. **Deploy-class budgets reuse one idle + one wall.** Set via existing
   `--idle-timeout` / wall overrides on `pilot start` (re-read from durable
   state). No parallel clock. Optional later: remembered per-project ops
   posture — only if founders keep forgetting flags.

## Duplicate truth to delete

- Help / bootstrap lines that imply "if watch dies, the round died"
- Any recovery copy that lists `watch` before `status` for agent hosts

## Implementation impact

| Slice | Deliverable | Proof |
| --- | --- | --- |
| **PLT-S01** | Detached handoff: absolute binary resolver + `currentDirectoryURL = projectRoot` | Unit: bare/relative/absolute argv0 shapes; child cwd asserted |
| **PLT-S02** | Enrich `PilotStatusJSON` while `.running`: `elapsedSeconds`, `ownerAlive`, baseline→HEAD commit count, `lastProgressAt` / silence age, `watcherDisposable: true`; nextActions prefer short status polls | Contract + PilotCLI tests; cold-agent status read mid-fixture round |
| **PLT-S03** | Teaching: bootstrap / help / `nextAction` — agent path = `--no-wait` + status; watch demoted | Help/contract regen; bootstrap snippet ≤ budget |
| **PLT-S04** | `pilot watch` heartbeats + `--max-wait <sec>` → exit 0 + `stillRunning` envelope | CLI tests with injected clock/sleep |
| **PLT-S05** (optional) | Ops-turn budget teaching: document idle/wall for ship/reconcile; verify pgid progress covers wrangler | Doctor silence / one live ship waiver if needed |

Recommended ship order: **S01 → S02 → S03 → S04**; S05 only if field still
false-kills workers (not waiters).

## Mac app impact

None required. Inbox / thread already observe durable relay state. Do not add a
GUI-only long-wait surface.

## iOS app impact

None.

## Driver / protocol impact

No new driver. Reuse `RunRequest.workerTimeoutSeconds` / wall overrides already
wired through `RelayCoordinator.Config.devTurnIdleTimeoutSeconds` (PO-F7).

## Auth / privacy / permissions impact

None. No new Keychain, network, or TCC surface.

## Works Test

1. Start a pilot relay; `handoff --no-wait` from a directory that is **not** the
   project root while invoking bare `alln` on PATH → child still starts (S01).
2. While a long fixture round is `.running`, kill the watch process (SIGTERM) →
   `pilot status --json` still reports `handoffAlive` / progress fields; round
   not reconciled as orphan (S02).
3. Cold agent recipe from bootstrap uses `--no-wait` + status, not infinite
   watch (S03).
4. `pilot watch --max-wait 5` on a stuck-running fixture exits 0 with
   `stillRunning: true` and heartbeat lines observed on stdout (S04).

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

- Detached handoff never depends on caller cwd for binary resolution.
- Agent teaching and `nextActions` lead with status polls; watch is optional.
- Status mid-flight answers "alive? how long? any commits?" without attaching
  watch.
- Watch either heartbeats or bounded-exits; silent infinite poll is gone.
- No second timeout system for deploy.

## Open questions

1. Should `--max-wait` default on agent-detected hosts, or stay explicit?
2. Is a remembered per-project ops idle/wall posture worth a slice, or is flag
   teaching enough?
3. Does IDLE-HF pgid progress already cover `wrangler` / `node` ship children in
   practice, or do we need one attributable heartbeat from the deploy script?

## Practical shape (operators, until shipped)

```text
alln pair pilot handoff --relay <id> --no-wait --json
# loop until awaitingPM / terminal:
alln pair pilot status --relay <id> --json
# do not treat a killed watch as round failure
```

For ship/reconcile turns today: raise budgets at start, e.g.
`pilot start … --idle-timeout 3600` (and wall override on the underlying run
when needed).
