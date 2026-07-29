# PM Turn Delivery

Status: **OPEN — implementation-ready, founder law (2026-07-29)**
Owner: AllnighterEngine (`RelayCoordinator`, `RunService` / run completion) +
AllnighterCLI (`RunCLI`, `PilotCLI`, `RelayCLI`, `AllnighterCLI.runTeamStatus`) +
`ServeDaemon`
Created: 2026-07-29
Revised: 2026-07-29 — v4: universal delegation (`alln run` + pilot + relay);
one PM Turn contract, three delivery paths, one teaching model

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

### 2. Wait — one bounded call, not a loop

Never chain short polls to fake a long wait. One `status --wait-for` invocation,
timeout sized to the job:

```bash
alln team status run_abc --wait-for terminal --timeout 7200 --json
alln pair pilot status --relay relay_abc --wait-for parked --timeout 7200 --json
```

If it expires (`PM_TURN_WAIT_TIMEOUT`, exit 3), re-run the **same** command with
a longer `--timeout` — never switch to manual polling or `run resume` loops.

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
   `RelayJSON`). No separate inbox verb. `report` is the verbatim worker answer
   on all surfaces (relay rounds may still populate from `settledDevReport`
   internally — wire name is always `report`).
2. **Extend status; do not add wait verbs.** Detached waiters are only:
   `team status --wait-for …`, `pair pilot status --wait-for …`, and
   `pair relay-status --wait-for …`. `pilot watch` and `run resume` as primary
   detach paths are legacy — compatible, never taught.
3. **A detached PM chooses a delivery route.** Default dispatch blocks. `--no-wait`
   must pair with the returned status waiter or `--delivery wake`. Wake without
   a configured receiver fails before dispatch.
4. **Wake delivery means an acknowledged hook invocation.** Serve writes the PM
   Turn, invokes the hook with full JSON on stdin, records success only on exit 0.
   Dedupe key: `(kind, subjectId, sequence)`.
5. **Universal law — not a relay feature.** PTD ships for `alln run` and
   pilot/relay in the same slices. Partial ship (relay-only) does not satisfy
   the product law or v1 exit gate.

### Decision addendum — v3/v4 deltas

6. **`--no-wait` is never valid alone** — must pair with wait command or
   `--delivery wake`. Teach as one unit on every surface.
7. **`--timeout` required on every `--wait-for`** — no silent default.
8. **Path table is canonical teaching** — reproduce verbatim or link; do not
   paraphrase per surface.
9. **Wake receiver is host-agnostic** — judged by exit 0 + idempotency on
   `(kind, subjectId, sequence)`.
10. **`run resume` is not PM Turn delivery** — it remains for vendor-park /
    handoff re-attach only. Terminal run delivery is `team status --wait-for
    terminal` + embedded `pmTurn`, or blocking `alln run`.

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

Temp-file + atomic rename in the same transition that persists terminal relay
state or terminal run lifecycle. `sequence` is monotonic per `(kind, subjectId)`.
Re-read/retry of the same transition must not duplicate.

### Write sites

| Kind | Owner | When |
| --- | --- | --- |
| `run` | Run completion path (`RunService` / coordinator that settles `TeamRun`) | Run enters terminal lifecycle with a deliverable answer (or failure report) |
| `relay` | `RelayCoordinator` | `awaitingPM`, `escalated`, `stopped`, or `done` after a worker round |

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
| `report` | Verbatim answer — run: primary worker/team answer markdown; relay: `settledDevReport`. `null` + `notes[]` when unavailable, never `""`. |
| `workerRunId` | Linked worker run when known |
| `workRecovery` | WRC-S00 nested object when available; else `null` + note |
| `nextCommands` | Fully expanded, copy-paste commands — no placeholders |
| `round`, `pmMode` | Relay-only; omitted or `null` on runs |

`running` / `queued` create no PM Turn.

### Read sites

Embed `pmTurn: PMTurnJSON?` in:

- `TeamStatusResponse` (and blocking terminal `TeamRunJSON` when applicable)
- `PilotStatusJSON`
- `RelayJSON` status projection

`report` and `nextCommands` appear only under `pmTurn`.

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

| Surface | Wait targets | Match |
| --- | --- | --- |
| **Run** | `terminal`, or specific `done`/`failed`/`timedOut`/`cancelled` | Terminal lifecycle (existing `TeamStatusWaitTarget`) |
| **Pilot** | `parked` | `awaitingPM` or `escalated` |
| **Relay** | `parked`, `terminal` | Parked or `done`/`stopped` |

No `running` target on relay (unchanged). Runs may wait for `running` only when
observing in-flight work — **that wait does not deliver a PM Turn**; document as
observation-only, not PM delivery.

Shared wait implementation: generalize `RelayStatusWait` and the existing
`runTeamStatus` loop behind one helper (`PMTurnStatusWait`) — same cadence
(`min 50 ms`, `max 5 s`), same `waitOutcome` (`matched` | `timedOut` |
`terminalMismatch`), same exit classification.

On timeout: exit 3, `PM_TURN_WAIT_TIMEOUT` (rename from relay-only
`RELAY_WAIT_TIMEOUT` or alias both). `agentAction` names the same waiter with
longer timeout — never "poll status" or "poll resume."

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

Route instruction only — not a claim delivery already occurred.

### C. Wake hook — unattended/dead-session path

`ServeDaemon` remains read-then-shell-out. On new `(kind, subjectId, sequence)`:

1. Mac notification (WRC-S01 / existing run-complete events where applicable)
2. Configured wake hook — stdin = full `PMTurnJSON`

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

## Build slices

| Slice | Scope | Owner | Depends on |
| --- | --- | --- | --- |
| **PTD-1 — universal pull delivery** | `PMTurnJSON` + atomic store for **run and relay**; embed `pmTurn` in `TeamStatusResponse`, `TeamRunJSON` (terminal), `PilotStatusJSON`, `RelayJSON`; shared `PMTurnStatusWait`; relay `--wait-for parked\|terminal`; run `--wait-for` returns `pmTurn` on terminal; `PM_TURN_WAIT_TIMEOUT`; `--no-wait` `delivery.path: wait` on **RunCLI, PilotCLI, RelayCLI**; teaching flip all surfaces | `RelayCoordinator`, run completion owner, `AllnighterCLI`, CLI surfaces, contracts/help | — |
| **PTD-2 — universal wake delivery** | `--delivery wake` on all three dispatch verbs; config validation; receipt/retry ledger; `ServeDaemon` hook for run + relay PM Turns; failure projection | `ServeDaemon`, dispatch CLIs | PTD-1; URN-S01/S02 |

PTD-1 is not done until **run, pilot, and relay** all pass the v1 exit gate.
PTD-2 is not done until wake works for run and relay.

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
- `AsyncTeamContracts.swift` — retire `pollStatus` as primary `nextAction`; emit
  `delivery.path: wait` waiter instead
- Recipes: `get-another-model-to-implement-this.md` and any run-loop recipe cards

Registered errors (unified naming):

| Code | Exit | Agent action |
| --- | --- | --- |
| `PM_TURN_WAIT_TIMEOUT` | 3 | Re-run returned `… status --wait-for … --timeout <longer> --json` |
| `RELAY_WAIT_TIMEOUT` | 3 | Alias of above for relay-only callers during migration |
| `PM_TURN_WAKE_UNCONFIGURED` | operational | Configure receiver or use block/wait; no dispatch |
| `PM_TURN_WAKE_UNAVAILABLE` | operational | Repair serve or use block/wait; no dispatch |
| `PM_TURN_WAKE_FAILED` | operational | Repair receiver; PM Turn remains durable |

## WRC boundary

Unchanged — PTD owns delivery; WRC owns recovery facts and `relayAwaitingPM`.
`pmTurn.workRecovery` nests WRC-S00. WRC-S01 dedupes on `(kind, subjectId,
sequence)` for relay parks. Run-complete Mac notifications may share the same
sequence for dedupe when both fire.

## Non-goals

- Separate wait verbs (`pilot wait`, `run wait`, `relay inbox`)
- Poll scripts / `run resume` loops as documented happy path for terminal delivery
- Cloud push or IDE-specific integration inside Allnighter
- Human PM seat
- Second storage model per surface
- Relay-only partial ship

## v1 exit gate

All gates required. **Run + pilot + relay** — partial pass fails the gate.

1. Blocking dispatch on all three surfaces returns `pmTurn.report` and
   `pmTurn.nextCommands` without regression.
2. `--no-wait` + returned `status --wait-for` delivers `pmTurn` in one process —
   no watcher, no `answer.md` read — for **one run**, **one pilot round**, and
   **one relay round**.
3. Terminal/parked snapshot status embeds the same `pmTurn` on all three surfaces.
4. `--delivery wake` refuses before dispatch when unconfigured; succeeds with
   hook for run and relay dogfood paths.
5. Help/Bootstrap/recipes teach one path table; never poll/resume/watch as primary.
6. Hermetic tests: run + relay write/dedupe; all wait outcomes; all `--no-wait`
   acks; wake refusal/retry; WRC null composition.
7. Dogfood: (a) 5-min blocking `alln run`, (b) multi-hour `alln run --no-wait`
   + wait, (c) pilot path B, (d) relay path B or C. `swift test`, `export-contracts
   --check`, architecture policy green.

## Builder routing

| Concern | Start here |
| --- | --- |
| Run completion / answer | `RunService`, `CatalogRunCoordinator`, `TeamRunJSONMapper` |
| Relay park / report | `RelayCoordinator`, `settledDevReport` |
| Run status + wait | `AllnighterCLI.runTeamStatus`, `TeamStatusWaitTarget` |
| Relay status + wait | `PilotCLI`, `RelayCLI`, new `PMTurnStatusWait` |
| Detached dispatch ack | `RunCLI`, `PilotCLI`, `RelayCLI` |
| Serve / notify | `ServeDaemon`, `NotificationCandidateDetection` |
| Recovery fields | WRC-S00 in `Work_Recovery_And_PM_Continuity.md` |

## Standing rules

- **One PM job, one contract** — delegate on any surface, get the turn back the same way.
- **Blocking is default** — `--no-wait` is exception; ack must name wait or wake.
- **Missing data is null + note** — never invent.
- **serve stays read-only** — hook shells out; no dispatch from serve.
- **Sequence dedupe** — one notify + one hook per `(kind, subjectId, sequence)`.
