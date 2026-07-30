# PM Turn Delivery

Status: **Code Complete 2026-07-29 — PTD-1 + PTD-2 shipped** (orchestrated via
pilot relay `relay_acfc834b`, dev seat Terra). Proof: focused PMTurn suite 108
tests green; `alln dev export-contracts --check` green (contract 6.3.0).
Archive after closeout.
Owner: AllnighterEngine (`RelayCoordinator`, `RunService` / run completion) +
AllnighterCLI (`RunCLI`, `PilotCLI`, `RelayCLI`, `AllnighterCLI.runTeamStatus`) +
`ServeDaemon`
Created: 2026-07-29
Revised: 2026-07-29 — v5 Grok adversarial pass: cross-CLI robustness, failure/
resume boundaries, crash safety, simplification; no open TBDs

## Product law

When an agent PM delegates work through Allnighter — **`alln run`**, Pilot, or
Relay; single worker or team; attended or unattended — Allnighter **must deliver
a PM Turn** when the delegated work reaches a PM boundary (work landed, failed,
or needs a decision). A PM Turn contains the verbatim worker report and the exact
next commands.

The delegating agent **is always the PM**. There is no separate human PM seat.
Allnighter's job is to make that PM look great: never leave the floor silent,
never force forensic reconstruction, never teach fire-and-forget detach.

Delivery is not a Mac banner, a status-poll recipe, `answer.md` archaeology, or
a promise that the caller happened to remain alive. A banner is a parallel human
channel only. The agent-facing contract is one durable PM Turn and one of three
delivery paths below — **the same three paths for every delegation surface.**

This packet supersedes only deferred URN-S04's proposed wait verbs. It does not
reopen the archived notification packet. At closeout, promote the law and public
contract to help/vocabulary, then archive this packet; code remains the field
SSOT.

Related work, deliberately not duplicated:

- [`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md)
  WRC-S00 owns `workRecovery`; WRC-S01 owns the `relayAwaitingPM` Mac event;
  WRC-S02 owns substituted-PM resume.
- [`Unattended_Round_Notification.md`](../archive/phases/Unattended_Round_Notification.md)
  URN-S01–S03 already supply the read-only `alln serve` notification substrate.
  Its deferred URN-S04 (`pair … wait`) is replaced here by status `--wait-for`.
- [`Round_Survives_The_Caller.md`](../archive/phases/Round_Survives_The_Caller.md)
  owns detached dispatch survival, not completion delivery.

## Why users curse today

A founder or an agent PM delegates work through Allnighter — a Pilot handoff, a
Relay round, or a plain `alln run "implement this"` — and detaches with
`--no-wait` because the job will take a while. The worker finishes. Nothing is
waiting for it. The session that dispatched the work is gone or has moved on.
The only documented "next step" was "poll status" or "poll `run resume`" —
which agents either skip (they don't spin their own poll loop unless told to)
or do badly (a tight loop that burns turns and still misses the transition).
The founder eventually notices the floor has gone quiet, opens a fresh PM
session, and reconstructs what happened by hand: read `answer.md`, `git log`, or
the relay directory, then re-paste the worker output as if Allnighter had never
run the job at all.

Every minute of that reconstruction is a minute the "insanely good PM" story
breaks — the agent that should have been the reliable middle layer between
founder and worker instead became one more thing the founder had to babysit.

This happens on **every delegation surface today**, not only pilot/relay:

| Surface | Detach today | Broken "next step" | Report when done |
| --- | --- | --- | --- |
| `alln run` | `--no-wait` | poll `run resume` | Fragmented across resume/show/export |
| Pilot | `handoff --no-wait` | poll `pilot status` | Not in status when `awaitingPM` |
| Relay | `relay --no-wait` | poll `relay-status` | Same gap |

`team status --wait-for` already exists for runs — but it is not wired to PM
Turn delivery, `--no-wait` does not route to it, and terminal status does not
embed the report + next commands in one shape. The machinery is half-built; the
**contract** is missing.

## Delegation surfaces (one contract)

| Surface | Dispatch | Status / waiter | PM boundary |
| --- | --- | --- | --- |
| **`alln run`** | `alln run "<order>" [--team …] [--model …]` | `alln team status <run-id> --wait-for terminal --timeout N --json` | Run reaches terminal lifecycle (`done`/`failed`/`timedOut`/`cancelled`) |
| **Pilot** | `alln pair pilot handoff …` | `alln pair pilot status --relay <id> --wait-for parked --timeout N --json` | `awaitingPM` or `escalated` |
| **Relay** | `alln pair relay` / `relay-resume` … | `alln pair relay-status --relay <id> --wait-for parked\|terminal --timeout N --json` | `awaitingPM`, `escalated`, `stopped`, or `done` |

Same three delivery paths (block / wait / wake). Same `pmTurn` object. Same
teaching. A PM learns **one** delegation discipline, not three.

**Wait-target footgun:** run waiters use `terminal`; pilot/relay park uses
`parked`. Agents must run the **returned** ack command, never invent a target.
`team status … --wait-for parked` and `pilot status … --wait-for terminal` are
usage errors — fail clear, do not silently map.

## Agent PM experience

This is what an agent PM (Opus, Sonnet, or any other CLI-driving model) sees,
types, and decides at each moment of delegated work. Read this section before
touching help/teaching copy — it is the standard those files are graded against.

### 1. Dispatch — pick a delivery path *before* you detach

There are exactly three paths. Pick one at dispatch time, not after the job is
already running. **Applies to `alln run`, pilot handoff, and relay alike.**

| Job shape | Path | What you do |
| --- | --- | --- |
| Short, you're staying at the terminal (~minutes) | **A — blocking** | Run dispatch **without** `--no-wait`. The call returns the PM Turn when work lands. Default for a reason. |
| Longer, you're staying in this session but want to do other things meanwhile | **B — status wait** | Dispatch with `--no-wait`. The ack hands you back one exact `status --wait-for` command (see Delegation surfaces table). Go do other work; when you return, run that command once with a timeout sized to the job. |
| This session may end before the job finishes | **C — wake** | Dispatch with `--no-wait --delivery wake`. Allnighter refuses up front if no receiver is configured. |

**Examples — path A (blocking, ~minutes):**

```bash
alln run "Implement the parser fix in src/foo.mjs" --team code_growth --json
alln pair pilot handoff --relay relay_abc --verdict continue --handover-file order.md --json
```

**Examples — path B (detach + one wait):**

```bash
alln run "…" --no-wait --json
# ack includes: alln team status <run-id> --wait-for terminal --timeout 7200 --json

alln pair pilot handoff --relay relay_abc … --no-wait --json
# ack includes: alln pair pilot status --relay relay_abc --wait-for parked --timeout 7200 --json
```

A **5-minute job almost always wants path A.** Blocking is cheaper in turns,
complexity, and failure modes than detach-and-wait for short work.

A **multi-hour job wants B (if you're staying) or C (if you might not be).**

**Non-TTY hosts (Cursor subagent, Codex tool, piped stdout):** prefer **A** only
when the host will keep the process alive for the whole job. If the host kills
idle children or caps wall time, use **B** or **C**. With `--json`, stdout is
**only** the contract JSON (human banners stay on stderr).

### 2. Wait — one bounded call, not a loop

Never chain short polls to fake a long wait. One `status --wait-for` invocation,
timeout sized to the job:

```bash
alln team status run_abc --wait-for terminal --timeout 7200 --json
alln pair pilot status --relay relay_abc --wait-for parked --timeout 7200 --json
```

If it expires (`PM_TURN_WAIT_TIMEOUT`, exit 3), re-run the **same** command with
a longer `--timeout` — never switch to manual polling or `run resume` loops.
Recovery ladder (only this):

1. Same waiter, longer `--timeout` (double, then job-scale; multi-hour jobs: hours).
2. Snapshot `status … --json` (no wait) to see lifecycle / `pmTurn` if already written.
3. Still not terminal/parked → inspect `alln ps`; do not invent a different verb.

### 3. Land — read `pmTurn`, not prose

Whatever path and surface you used, you land on the same shape. `report` and
`nextCommands` live under `pmTurn` — nowhere else:

```json
{
  "pmTurn": {
    "kind": "run",
    "subjectId": "run_abc",
    "sequence": 3,
    "reason": "done",
    "report": "Implemented the parser fix; added tests in …",
    "workRecovery": null,
    "nextCommands": [
      "alln show run_abc --json",
      "alln team result run_abc --json"
    ]
  }
}
```

```json
{
  "pmTurn": {
    "kind": "relay",
    "subjectId": "relay_abc",
    "sequence": 7,
    "reason": "awaitingPM",
    "report": "verbatim settled worker report",
    "nextCommands": [
      "alln pair pilot handoff --relay relay_abc --verdict continue --handover-file order.md --json"
    ]
  }
}
```

You never need to open `answer.md`, grep a log directory, or trust a Mac
banner. If `report` is `null`, see `notes[]` — do not go dig for the text
yourself.

**Failed / timedOut / cancelled is still a PM Turn.** Path A/B/C deliver the
same shape; `reason` and exit code carry failure. Do not treat non-`done` as
"no delivery."

### 4. Judge — the next command is already expanded

`nextCommands` are copy-paste-ready with real ids and status-valid verbs. Your
job as PM: read the report, decide what happens next, run a command from the
array (or your own equivalent). Never hand-assemble ids or guess legal verbs.

### Anti-patterns — never do these

- **Poll loop.** `while sleep; status` or repeated `run resume` instead of one
  `status --wait-for … --timeout …`.
- **`--no-wait` with no follow-up.** The single mistake that leaves the floor
  silent. You committed to path B's wait command or path C's wake — there is no
  third option.
- **Trusting a Mac banner as delivery.** Human convenience only; never satisfies
  `pmTurnDelivery`.
- **Re-deriving the report.** `answer.md`, relay dirs, raw logs when `pmTurn.report`
  was the verbatim text.
- **Treating surfaces differently.** If you know how to delegate a pilot round,
  you already know how to delegate an `alln run` — block, wait, or wake.
- **Confusing vendor park with PM Turn.** `alln run resume` is for vendor backoff
  / re-attach — not terminal delivery (see Decision §10).
- **Inventing wait targets.** Always paste the ack `delivery.command`.

### Success, from the PM's chair

- **"I delegated and kept working."** `--no-wait`, other work, one wait command,
  land the report.
- **"I blocked and got the report."** No `--no-wait` on a short job; PM Turn in
  the same call.

If either requires a second file, a banner, or guessing a command, the contract
failed.

## Decision

1. **One durable object; one field name; no inbox verb.** `pmTurn` is embedded
   in every status/result envelope (`TeamStatusResponse`, `PilotStatusJSON`,
   `RelayJSON`). No separate inbox verb. `report` is the verbatim primary answer
   on all surfaces (see report source table).
2. **Extend status; do not add wait verbs.** Detached waiters are only:
   `team status --wait-for …`, `pair pilot status --wait-for …`, and
   `pair relay-status --wait-for …`. `pilot watch` and `run resume` as primary
   detach paths are legacy — compatible, never taught for terminal delivery.
3. **A detached PM chooses a delivery route.** Default dispatch blocks. `--no-wait`
   must pair with the returned status waiter or `--delivery wake`. Wake without
   a configured receiver fails before dispatch.
4. **Wake delivery means an acknowledged hook invocation.** Serve writes nothing
   new for truth — it **reads** durable `pm-turn.json`, invokes the hook with full
   JSON on stdin, records success only on exit 0. Dedupe key:
   `(kind, subjectId, sequence)`.
5. **Universal law — not a relay feature.** PTD ships for `alln run` and
   pilot/relay in the same slices. Partial ship (relay-only) does not satisfy
   the product law or v1 exit gate.

### Decision addendum — v3–v5

6. **`--no-wait` is never valid alone** — must pair with wait command or
   `--delivery wake`. Teach as one unit on every surface.
7. **`--timeout` required on every `--wait-for`** — no silent default.
8. **Path table is canonical teaching** — reproduce verbatim or link; do not
   paraphrase per surface.
9. **Wake receiver is host-agnostic** — judged by exit 0 + idempotency on
   `(kind, subjectId, sequence)`. Configuration is **machine-level** (serve
   config), not per-CLI-host. Any agent session benefits once configured once.
10. **`run resume` is not PM Turn delivery** — remains for vendor-park claim and
    non-terminal re-attach only. Terminal run delivery is `team status --wait-for
    terminal` + embedded `pmTurn`, or blocking `alln run`. Enforce in teaching +
    contracts; do not remove the verb.
11. **Failure is delivery.** Terminal `failed` / `timedOut` / `cancelled` and
    relay `escalated` / `stopped` still write a PM Turn.
12. **Idempotency replay ≠ new PM Turn.** `--idempotency-key` that re-acks an
    existing run reuses that subject; at most one terminal sequence per settled
    transition.

## Current gap

| Surface | Blocking works? | Detached broken how? |
| --- | --- | --- |
| `alln run` | Yes — `TeamRunJSON` answer | `--no-wait` → "poll resume"; no `pmTurn` on status; wait exists but doesn't return report+commands |
| Pilot | Yes — `PilotHandoffJSON.devReport` | `--no-wait` → poll status; no report when parked |
| Relay | Yes — terminal envelope | Same as pilot |

Implementation must close all three in one contract, not move the gap to a
custom watcher.

## Contract: `PMTurnJSON`

One type for all delegation kinds. Written atomically when work reaches a PM
boundary.

### Storage

```text
~/Library/Application Support/Allnighter/Runs/<runId>/pm-turn.json      # kind: run
~/Library/Application Support/Allnighter/Relays/<relayId>/pm-turn.json # kind: relay
```

Temp-file + atomic rename **in the same transition** that persists terminal run
lifecycle or terminal/parked relay state. Order within the transition:

1. Build `PMTurnJSON` (sequence = last+1 for subject; durable counter on subject).
2. Atomic write `pm-turn.json`.
3. Persist subject terminal/parked state (`run.json` / `relay.json`).

Readers: if subject is terminal/parked but `pm-turn.json` is missing (crash
between steps), project `pmTurn: null` + note `pm_turn_missing` — **never invent
report**. Retry of the same transition must not bump `sequence` if the same
boundary was already recorded (dedupe on transition identity / last sequence for
that reason).

`sequence` is monotonic per `(kind, subjectId)`.

### Write sites

| Kind | Owner | When |
| --- | --- | --- |
| `run` | Run completion path (`RunService` / coordinator that settles `TeamRun`) | Run enters **any** terminal lifecycle (`done`/`failed`/`timedOut`/`cancelled`) |
| `relay` | `RelayCoordinator` | `awaitingPM`, `escalated`, `stopped`, or `done` after a worker round |

### Report source (no ambiguity)

| Kind | Shape | `report` is |
| --- | --- | --- |
| `run` | Single worker | That worker's answer markdown |
| `run` | Team / multi-seat | Primary team answer (synthesis / lead answer) — same text as today's blocking `TeamRunJSON` answer path |
| `run` | Terminal with no answer body | `null` + `notes[]` (warnings / failure reason if available) |
| `relay` | Any park/terminal above | `settledDevReport` when present; else `null` + note |

Do not embed every seat's raw answer in `pmTurn`. Deep dive stays `alln show` /
`team result` / artifact — listed in `nextCommands`.

### Shape

```json
{
  "schemaVersion": 1,
  "kind": "run",
  "subjectId": "run_abc",
  "sequence": 3,
  "round": null,
  "createdAt": "2026-07-29T22:14:00Z",
  "reason": "done",
  "lifecycleStatus": "done",
  "report": "verbatim worker or team answer markdown",
  "workerRunId": "AD0446C6-…",
  "workRecovery": null,
  "nextCommands": [
    "alln show run_abc --json",
    "alln team result run_abc --json"
  ],
  "notes": []
}
```

Relay example — same object, relay-specific `reason` / `round`:

```json
{
  "schemaVersion": 1,
  "kind": "relay",
  "subjectId": "relay_abc",
  "sequence": 7,
  "round": 2,
  "createdAt": "2026-07-29T22:14:00Z",
  "reason": "awaitingPM",
  "lifecycleStatus": "awaitingPM",
  "pmMode": "external",
  "report": "verbatim settled worker report",
  "workerRunId": "AD0446C6-…",
  "workRecovery": null,
  "nextCommands": [
    "alln pair pilot handoff --relay relay_abc --verdict continue --handover-file order.md --json"
  ],
  "notes": []
}
```

| Field | Rule |
| --- | --- |
| `kind` | `run` or `relay` — dedupe and wake routing |
| `subjectId` | `runId` or `relayId` |
| `sequence` | Monotonic per subject; dedupe for wait/wake/notify |
| `reason` | **Run:** `done`, `failed`, `timedOut`, `cancelled`. **Relay:** `awaitingPM`, `escalated`, `stopped`, `done`. Never infer from copy. |
| `lifecycleStatus` | Run: `RunLifecycle` value. Relay: `RelayState.Status` value. |
| `report` | Verbatim primary answer (see source table). `null` + `notes[]` when unavailable, never `""`. No truncation in durable store. |
| `workerRunId` | Linked worker run when known |
| `workRecovery` | WRC-S00 nested object when available; else `null`. **Never block** PM Turn write on WRC readiness. |
| `nextCommands` | Fully expanded, copy-paste commands — no placeholders. Prefer 1–3 status-valid verbs. |
| `round`, `pmMode` | Relay-only; omitted or `null` on runs |

`running` / `queued` create no PM Turn — including vendor-parked `queued` +
`waitingForVendor` (that is resume territory, not a PM Turn).

### Failed-run report content (minimum)

| Terminal reason | `report` preference | `nextCommands` preference |
| --- | --- | --- |
| `done` | Primary answer | show / result / artifact as applicable |
| `failed` | Error/warnings body if any, else `null` + note | `alln show <id> --json` |
| `timedOut` | Partial answer if any, else `null` + note | show; re-dispatch is PM judgment, not auto-retry |
| `cancelled` | `null` + note unless a partial answer exists | show |

Process exit for blocking path stays existing lifecycle mapping (`done` → 0;
failed/timedOut/cancelled → non-zero). Path B waiters: `matched` + `pmTurn` on
any terminal; non-zero exit when the matched lifecycle is a failure class.

### Read sites

Embed `pmTurn: PMTurnJSON?` in:

- `TeamStatusResponse` (and blocking terminal `TeamRunJSON` when applicable)
- `PilotStatusJSON`
- `RelayJSON` status projection

`report` and `nextCommands` appear only under `pmTurn`. Top-level answer fields
on `TeamRunJSON` may remain for back-compat; they must equal `pmTurn.report`
when both present.

## Read contract and the three delivery paths

Same paths for **every** surface. Surface-specific details are only the dispatch
verb and the waiter command in the `--no-wait` ack.

### A. Blocking dispatch — default attended path

No new flag. Blocking dispatch returns the PM Turn in the existing result envelope:

| Surface | Dispatch | Delivery return |
| --- | --- | --- |
| Run | `alln run "…" --json` (no `--no-wait`) | `TeamRunJSON` embeds `pmTurn` on terminal completion (or top-level `answer` remains; `pmTurn.report` is the same text) |
| Pilot | `pilot handoff` (no `--no-wait`) | `PilotHandoffJSON` → `pmTurn` |
| Relay | `relay` / `relay-resume` / `relay adopt` (no `--no-wait`) | Terminal relay envelope → `pmTurn` |

### B. Status `--wait-for` — attended detached path

Extend relay status waiters; **align run path** with existing `team status --wait-for`
(PO-F3) so terminal delivery includes `pmTurn`:

```bash
alln team status <run-id> --wait-for terminal --timeout 7200 --json
alln pair pilot status --relay <id> --wait-for parked --timeout 7200 --json
alln pair relay-status --relay <id> --wait-for terminal --timeout 7200 --json
```

`--timeout` required with `--wait-for`. Non-negative seconds.

| Surface | Wait targets | Match | Delivers `pmTurn`? |
| --- | --- | --- | --- |
| **Run** | `terminal` (primary); optional specific `done`/`failed`/`timedOut`/`cancelled` | Terminal lifecycle | **Yes** on match |
| **Run** | `running` (existing observation) | In-flight | **No** — observation only |
| **Pilot** | `parked` | `awaitingPM` or `escalated` | **Yes** |
| **Relay** | `parked`, `terminal` | Parked or `done`/`stopped` | **Yes** |

No `running` target on relay (unchanged).

Shared wait implementation: one helper (name optional: `PMTurnStatusWait`) —
same cadence (`min 50 ms`, `max 5 s`), same `waitOutcome` (`matched` |
`timedOut` | `terminalMismatch`), same exit classification. Do not invent a
second polling subsystem.

On timeout: exit 3, `PM_TURN_WAIT_TIMEOUT` (alias `RELAY_WAIT_TIMEOUT` during
migration). `agentAction` names the same waiter with longer timeout — never
"poll status" or "poll resume."

**`--no-wait --json` acknowledgement** on every detachable dispatch:

```json
{
  "delivery": {
    "path": "wait",
    "command": "alln team status run_abc --wait-for terminal --timeout 7200 --json"
  }
}
```

```json
{
  "delivery": {
    "path": "wait",
    "command": "alln pair pilot status --relay relay_abc --wait-for parked --timeout 7200 --json"
  }
}
```

Route instruction only — not a claim delivery already occurred. Prefer embedding
the **resolved `alln` executable path** used for dispatch when known (avoids PATH
skew); human line may still show bare `alln`.

### C. Wake hook — unattended/dead-session path

`ServeDaemon` remains read-then-shell-out. It must observe **both**:

```text
…/Allnighter/Runs/*/pm-turn.json
…/Allnighter/Relays/*/pm-turn.json
```

On new `(kind, subjectId, sequence)` not yet in the receipt ledger:

1. Mac notification (WRC-S01 / existing run-complete events where applicable)
2. Configured wake hook — stdin = full `PMTurnJSON` (stream stdin; never argv)

```json
{
  "pmTurnWake": {
    "command": ["/absolute/path/to/pm-turn-receiver"],
    "retryMaxSeconds": 300
  }
}
```

`--delivery wake` only with `--no-wait`. Valid on **`alln run`**, pilot handoff,
and relay dispatch. Fail `PM_TURN_WAKE_UNCONFIGURED` before dispatch if no
receiver. Receipt ledger keyed by `(kind, subjectId, sequence)`.

`pmTurnDelivery` failure projection on status when wake fails after retries.
Durable `pm-turn.json` remains the SSOT; wake failure does not erase the turn.

**Report size:** durable store is untruncated. Hook stdin is the full object;
receivers must stream stdin (not buffer as argv). If the OS/pipe cannot accept
the payload, exit non-zero → `PM_TURN_WAKE_FAILED`; agent recovers via path B
snapshot status (report still on disk). No second wire format in v1.

## Vendor park vs PM Turn (hard boundary)

| State | PM Turn? | Correct attach |
| --- | --- | --- |
| Run `running` / non-vendor `queued` | No | Path A hold, or path B wait for `terminal` |
| Run vendor park (`queued` + `waitingForVendor`) | No | `alln run resume <id>` (claim/continue) |
| Run terminal | Yes (written once) | `team status --wait-for terminal` or snapshot status; resume may **reprint** a finished run for back-compat but is **not** taught and must not write a second sequence |
| Relay `running` | No | Wait / poll status only |
| Relay `awaitingPM` / `escalated` / terminal | Yes | Pilot/relay status `--wait-for parked\|terminal` |

`run resume` must never be the documented happy path for "worker finished."
Contracts/help teach wait/wake; resume help stays vendor-continuity only.

## Concurrent delegation (write lock)

Existing product law is unchanged: **one mutating worker per repo root**.

| Scenario | Behavior | PTD impact |
| --- | --- | --- |
| Two mutating `alln run` same root | Second waits or fails under write lock | Two subjects when both run; each gets its own `pmTurn` when *it* terminals |
| Research/judgment team + mutating run | Allowed per run model | Independent PM Turns |
| Relay round + mutating run same root | Write lock / `RELAY_ROUND_IN_FLIGHT` already gate races | PTD does not add a second lock; waiters only observe their subject id |
| Two sessions wait on same run id | Both may block on status; one sequence, one durable file | Idempotent reads |

Agents must wait on the **id returned in their own ack**, not "the repo's run."

## Idempotency

`--idempotency-key` on `alln run`:

- Replay that re-acks the **same** run id before terminal: ack again with the
  same `delivery.command` (path B) — no second subject.
- After terminal: no second `pm-turn.json` write; status returns the existing
  `pmTurn` (same sequence).

## WRC / workRecovery timing

- Mutating runs that commit and research teams that do not: both write PM Turns
  at terminal; `workRecovery` is often `null` on pure runs.
- Relay parks: nest WRC-S00 when ready; if WRC lags, still write `pmTurn` with
  `workRecovery: null` + optional note. Delivery must not wait on git stamping.

## iOS / remote

**Explicit non-goal for this packet.** iOS companion and remote Project Manager
do not implement path B/C clients in PTD v1. No silent claim that remote gets
wake delivery. Future remote packet may consume the same durable `pm-turn.json`.

## Build slices

| Slice | Scope | Owner | Depends on |
| --- | --- | --- | --- |
| **PTD-1 — universal pull delivery** | `PMTurnJSON` + atomic store for **run and relay**; embed `pmTurn` in status/result envelopes; shared wait helper; run terminal wait returns `pmTurn`; `PM_TURN_WAIT_TIMEOUT`; `--no-wait` `delivery.path: wait` on **RunCLI, PilotCLI, RelayCLI**; teaching flip all surfaces | Run completion owner, `RelayCoordinator`, CLI, contracts/help | — |
| **PTD-2 — universal wake delivery** | `--delivery wake` on all three dispatch verbs; config validation; receipt/retry ledger; `ServeDaemon` scans Runs + Relays `pm-turn.json`; failure projection | `ServeDaemon`, dispatch CLIs | PTD-1; URN-S01/S02 |

PTD-1 is not done until **run, pilot, and relay** all pass the v1 exit gate.
PTD-2 is not done until wake works for run and relay.

**Simplified out of scope for v1 (do not build):**

- Separate inbox verb or PM Turn store outside Runs/Relays
- Report truncation / secondary wire shape for huge reports
- Per-CLI-host wake config
- iOS wake client
- Removing `run resume` (legacy keep; re-teach only)

## Teaching and contract flip (part of PTD-1)

Replace every "`--no-wait`, then poll …" instruction on **all surfaces** with
the Agent PM experience §1 table plus:

> Dispatch blocks by default — fine for a short job. If you detach with
> `--no-wait`, you must either run the returned `status --wait-for` command or
> have configured `--delivery wake`. `--no-wait` alone leaves the floor silent.

Never teach as primary: poll loops, `pilot watch`, `run resume` for terminal
delivery, Mac banners as proof.

Update and regenerate (do not hand-edit `docs/generated/alln/*`):

- `ContractRegistry+Milestone1.swift` — `run`, `team status`, pilot, relay
- `HelpTopicRegistry.swift` — `tool_selection`, `team_run_loop`, `no-wait`, `pm_relay`, `pilot`
- `Bootstrap.swift`, `TeachingSnippet.swift`, `MenuSelectionCopy.swift`
- `RunCLI.swift`, `PilotCLI.swift`, `RelayCLI.swift`
- `AsyncTeamContracts.swift` — retire `pollStatus` / resume-poll as primary
  `nextAction`; emit `delivery.path: wait` waiter instead
- Recipes: `get-another-model-to-implement-this.md` and any run-loop recipe cards

Registered errors (unified naming):

| Code | Exit | Agent action |
| --- | --- | --- |
| `PM_TURN_WAIT_TIMEOUT` | 3 | Re-run returned `… status --wait-for … --timeout <longer> --json`; then snapshot status; then `alln ps` |
| `RELAY_WAIT_TIMEOUT` | 3 | Alias of above for relay-only callers during migration |
| `PM_TURN_WAKE_UNCONFIGURED` | operational | Configure receiver or use block/wait; no dispatch |
| `PM_TURN_WAKE_UNAVAILABLE` | operational | Repair serve or use block/wait; no dispatch |
| `PM_TURN_WAKE_FAILED` | operational | Repair receiver; read durable status/`pmTurn`; path B still works |

## WRC boundary

Unchanged — PTD owns delivery; WRC owns recovery facts and `relayAwaitingPM`.
`pmTurn.workRecovery` nests WRC-S00. WRC-S01 dedupes on `(kind, subjectId,
sequence)` for relay parks. Run-complete Mac notifications may share the same
sequence for dedupe when both fire.

## Cross-CLI robustness

Practical rules for builders and dogfood (Claude Code, Cursor, Codex, Grok CLI,
Composer):

1. **PATH / binary identity.** Detached children and wait commands must invoke
   the same product binary the user installed (`alln` on PATH, or absolute path
   captured at dispatch). Multiple checkouts on PATH are a user env bug; ack
   should prefer the absolute path of the dispatching process when available.
2. **Wake is machine config, not CLI-host config.** One `pmTurnWake` under serve
   config. Claude/Cursor/Codex/Grok/Composer do not each register receivers.
   Founder/agent configures once; any session can choose path C.
3. **Concurrent sessions.** Two agents may delegate from different terminals.
   Each owns its returned `subjectId`. Mutating contention is write-lock /
   relay-in-flight — not a second PTD queue.
4. **Failed runs still deliver.** Hosts that only look for exit 0 will miss the
   report — teach reading `pmTurn` even when exit ≠ 0; JSON envelopes still carry
   the turn.
5. **Vendor park boundary.** If status shows vendor wait, use `run resume` — not
   `team status --wait-for terminal` as the only story (terminal wait eventually
   works after resume/ continuum, but resume is the claim verb). Do not write
   `pmTurn` on vendor park.
6. **Non-TTY / subagent hosts.** Pure `--json` on stdout; no progress spam on
   stdout. Prefer path B when the host may kill long blocks.
7. **Wrong wait target.** Validate surface-legal targets; refuse with usage error
   rather than hanging forever.
8. **Idempotent re-entry.** Same key / same id → one terminal `pmTurn` sequence;
   waiters and wake ledger are safe to retry.

## Non-goals

- Separate wait verbs (`pilot wait`, `run wait`, `relay inbox`)
- Poll scripts / `run resume` loops as documented happy path for terminal delivery
- Cloud push or IDE-specific integration inside Allnighter
- Human PM seat
- Second storage model per surface
- Relay-only partial ship
- iOS / remote PM Turn client (v1)
- Per-CLI wake registration
- Truncating or dual-encoding large reports (v1)
- Removing legacy `run resume` / `pilot watch`

## v1 exit gate

All gates required. **Run + pilot + relay** — partial pass fails the gate.

1. Blocking dispatch on all three surfaces returns `pmTurn.report` and
   `pmTurn.nextCommands` without regression (success **and** one failure-class
   run).
2. `--no-wait` + returned `status --wait-for` delivers `pmTurn` in one process —
   no watcher, no `answer.md` read — for **one run**, **one pilot round**, and
   **one relay round**.
3. Terminal/parked snapshot status embeds the same `pmTurn` on all three surfaces.
4. `--delivery wake` refuses before dispatch when unconfigured; succeeds with
   hook for run and relay dogfood paths; serve observes Runs + Relays paths.
5. Help/Bootstrap/recipes teach one path table; never poll/resume/watch as primary
   terminal delivery.
6. Hermetic tests: run + relay write/dedupe; crash-missing `pm-turn` → null + note;
   all wait outcomes; wrong wait target usage error; all `--no-wait` acks;
   idempotency replay no double sequence; wake refusal/retry; WRC null composition;
   vendor-park writes **no** PM Turn.
7. Dogfood: (a) 5-min blocking `alln run`, (b) multi-hour `alln run --no-wait`
   + wait, (c) pilot path B, (d) relay path B or C, (e) one failed run lands
   `pmTurn.reason=failed`. `swift test`, `export-contracts --check`, architecture
   policy green.

## Builder routing

| Concern | Start here |
| --- | --- |
| Run completion / answer | `RunService`, `CatalogRunCoordinator`, `TeamRunJSONMapper` |
| Relay park / report | `RelayCoordinator`, `settledDevReport` |
| Run status + wait | `AllnighterCLI.runTeamStatus`, `TeamStatusWaitTarget` |
| Relay status + wait | `PilotCLI`, `RelayCLI`, shared wait helper |
| Detached dispatch ack | `RunCLI`, `PilotCLI`, `RelayCLI` |
| Serve / notify | `ServeDaemon`, `NotificationCandidateDetection` (scan Runs + Relays) |
| Recovery fields | WRC-S00 in `Work_Recovery_And_PM_Continuity.md` |
| Vendor park / resume | `RunCLI.resume`, `RunService.resumeParkedRun` — **not** PM Turn write |

## Standing rules

- **One PM job, one contract** — delegate on any surface, get the turn back the same way.
- **Blocking is default** — `--no-wait` is exception; ack must name wait or wake.
- **Missing data is null + note** — never invent.
- **serve stays read-only** — hook shells out; no dispatch from serve.
- **Sequence dedupe** — one notify + one hook per `(kind, subjectId, sequence)`.
- **Failure is still a turn** — silence is the bug, not a non-zero exit.
- **Resume is not delivery** — vendor park / re-attach only.

## Adversarial review (resolved)

Grok adversarial pass (2026-07-29). Each attack → resolution. No open TBDs.

| # | Finding | Resolution |
| --- | --- | --- |
| 1 | Cross-CLI: who configures wake? Multiple `alln` on PATH? | **Accept.** Wake is machine-level serve config (once). Ack prefers absolute dispatch binary when known. Documented in Cross-CLI §1–2. |
| 2 | Concurrent delegation / write lock / relay+run race | **Accept / non-goal.** Existing write lock + `RELAY_ROUND_IN_FLIGHT` own races. PTD is per-subject; wait only on returned id. Concurrent section added. |
| 3 | Failed / timedOut / cancelled still a PM Turn? | **Accept fix.** Yes — always write on any terminal reason; report/nextCommands table; exit codes unchanged. Decision §11. |
| 4 | Team synthesis vs single-worker report | **Accept fix.** Report source table: primary/synthesis answer only; seats via show/result. |
| 5 | Vendor park / `run resume` collides with delivery? | **Accept fix.** Hard boundary table; no PM Turn on vendor park; resume never taught for terminal; resume may reprint finished run without new sequence. |
| 6 | `pm-turn.json` vs `run.json` crash / stale sequence | **Accept fix.** Write order 1→2→3; missing file → null + `pm_turn_missing`; no sequence bump on same-transition retry. |
| 7 | Blocking + `--json` non-TTY hosts | **Accept fix.** Pure JSON stdout; prefer B/C when host kills long blocks. |
| 8 | Serve knowledge of Runs/ `pm-turn` paths | **Accept fix.** Serve scans Runs + Relays; explicit in path C + exit gate. |
| 9 | Wrong wait target (parked vs terminal) | **Accept fix.** Surface-legal targets only; refuse invented targets; footgun callout on delegation table. |
| 10 | Idempotency key → duplicate pmTurn? | **Accept fix.** Replay reuses subject; one terminal sequence; Decision §12. |
| 11 | Mutating commit vs research / workRecovery lag | **Accept fix.** Never block PM Turn on WRC; null workRecovery OK. |
| 12 | iOS / remote silent lie? | **Explicit non-goal.** iOS section; Non-goals list. |
| 13 | Short timeout / recovery ladder | **Accept fix.** Ladder: longer timeout → snapshot status → `alln ps`; agentAction text. |
| 14 | Hook stdin size / report truncation | **Accept / simplify.** Durable untruncated; stdin full JSON stream; wake fail → durable still readable. No dual wire format v1. |
| 15 | Over-complexity: drop what? | **Accept simplify.** No inbox verb, no per-CLI wake, no report dual-encoding, no resume removal, no iOS client. Shared wait helper only (no second subsystem). Optional specific run wait statuses kept as thin existing targets, primary remains `terminal`. |

**Deferred (one line, not TBD for implementers):** remote/iOS PM Turn consumer packet after Mac dogfood; optional absolute-path-only teaching if PATH skew shows up in week-2.
