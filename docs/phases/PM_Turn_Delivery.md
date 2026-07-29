# PM Turn Delivery

Status: **OPEN — implementation-ready, founder law (2026-07-29)**
Owner: AllnighterEngine (`RelayCoordinator`, `ServeDaemon`) + AllnighterCLI
(`PilotCLI`, `RelayCLI`)
Created: 2026-07-29
Revised: 2026-07-29 — v3 Sonnet review pass (agent PM experience: sharpened
moment-by-moment flow, default-path guidance, anti-patterns, Decision addendum)

## Product law

When an agent PM delegates through Allnighter — Pilot or Relay, attended or
unattended — Allnighter **must deliver a PM Turn** when work reaches a PM
boundary. A PM Turn contains the verbatim dev report and the exact next commands.

Delivery is not a Mac banner, a status-poll recipe, `answer.md` archaeology, or
a promise that the caller happened to remain alive. A banner is a parallel human
channel only. The agent-facing contract is one durable PM Turn and one of three
delivery paths below.

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

A founder or an agent PM starts a Pilot or Relay round, detaches with
`--no-wait` because the round will take a while, and moves on. The dev seat
finishes. Nothing is waiting for it. The terminal that dispatched the round is
gone or has moved to another task. The only documented "next step" was
"poll status" — which agents either skip (they don't spin their own poll loop
unless told to) or do badly (a tight loop that burns turns and still misses the
transition). The founder eventually notices the floor has gone quiet, opens a
fresh PM session, and has to reconstruct what happened by hand: read
`answer.md`, `git log`, or the relay directory, then re-paste the dev report
into a new PM turn as if Allnighter had never run the round at all. Every
minute of that reconstruction is a minute the "insanely good PM" story breaks —
the agent that should have been the reliable middle layer between founder and
dev seat instead became one more thing the founder had to babysit.

This is the same shape as the WRC incident (PM hit a vendor outage mid-round,
recovery required forensic git log), but PTD's version does not require a
seat to have *died* — it happens on every ordinary detached round today,
because there is no delivery contract, only a promise that whoever dispatched
the round is still around to notice completion. That promise is the bug.

## Agent PM experience

This is what an agent PM (Opus, Sonnet, or any other CLI-driving model) sees,
types, and decides at each moment of a delegated round. Read this section
before touching help/teaching copy — it is the standard those files are
graded against.

### 1. Dispatch — pick a delivery path *before* you detach

There are exactly three paths. Pick one at dispatch time, not after the round
is already running.

| Round shape | Path | What you do |
| --- | --- | --- |
| Short, you're staying at the terminal (~minutes) | **A — blocking** | Just run `pilot handoff` / `relay-resume` without `--no-wait`. The call returns the PM Turn when it lands. This is the default for a reason: it is the least that can go wrong. |
| Longer, you're staying in this session but want to do other things meanwhile | **B — status wait** | Dispatch with `--no-wait`. The ack hands you back one exact `status --wait-for` command. Go do other work; when you return to this thread, run that one command with a timeout sized to the round — it blocks until `parked`/`terminal` or the timeout, then hands you the same PM Turn. |
| This session may end before the round finishes (detached handoff, overnight, vendor-outage risk) | **C — wake** | Dispatch with `--no-wait --delivery wake`. Allnighter refuses up front if no receiver is configured — you find out *before* you commit to an unattended delegation, not after. |

A **5-minute round almost always wants path A.** Blocking on five minutes of
dev work is cheaper — in turns, in complexity, in things that can go wrong —
than orchestrating a detach-and-wait dance for it. Reach for B or C only when
the round is genuinely long or the session might not survive it.

A **multi-hour round wants B (if you're staying) or C (if you might not be).**
Never leave a multi-hour round on path A if you have other useful work to do —
that is "I blocked" when you could have "delegated and kept working."

### 2. Wait — one bounded call, not a loop

The mental model is the same discipline used for any long-running background
job: pick a single wait bounded to how long the thing actually takes, then
come back once. Never chain short polls to fake a long wait.

```bash
alln pair pilot status --relay relay_abc --wait-for parked --timeout 7200 --json
```

This call blocks *this one invocation*, not your whole session — that's what
makes "kept working" real. Dispatch, note the returned wait command, go do
something else with your turn budget, and only re-enter this thread to run the
wait command once, sized to your best guess of the round's duration. If it
expires (`RELAY_WAIT_TIMEOUT`, exit 3), the fix is a longer timeout on the same
command — never a switch to manual polling.

### 3. Land — read `pmTurn`, not prose

Whatever path you took, you land on the same shape. `devReport` and
`nextCommands` live under `pmTurn` in the status/handoff response — nowhere
else:

```json
{
  "pmTurn": {
    "sequence": 7,
    "reason": "awaitingPM",
    "devReport": "verbatim settledDevReport text",
    "nextCommands": [
      "alln pair pilot handoff --relay relay_abc --verdict continue --handover-file order.md --json"
    ]
  }
}
```

You never need to open `answer.md`, grep a log directory, or trust a Mac
banner to know what happened. If `devReport` is `null`, that's a real signal
(see `notes[]`) — not evidence to go dig for the report yourself.

### 4. Judge — the next command is already expanded

`nextCommands` are copy-paste-ready with the real relay id and a status-valid
verb for the current state — never a placeholder, never invented flags. Your
job as PM is to read the dev report, decide `continue`/`escalate`/`stop`, and
run the matching command from the array (or your own equivalent handoff). You
should never have to hand-assemble a relay id or guess which verb is legal for
the current state.

### Anti-patterns — never do these

- **Poll loop.** Calling `status --json` in a `while true; sleep N` shape
  instead of `status --wait-for … --timeout …`. It burns turns, it can miss a
  fast transition between polls, and it is exactly the behavior this packet
  exists to make unnecessary.
- **`--no-wait` with no follow-up.** Detaching and never running the returned
  wait command and never configuring wake delivery. This is the single mistake
  that causes the floor to go silent — the round completes and nobody is
  listening. If you use `--no-wait`, you have committed to running path B's
  wait command or having path C's wake configured. There is no third option.
- **Trusting a Mac banner as delivery.** The banner (WRC-S01/URN) is a human
  convenience notification. It is not agent-readable, not durable, not
  retried, and never satisfies `pmTurnDelivery`. If your plan for "how will I
  know the round finished" is "the founder will see a notification and tell
  me," that plan fails the moment the founder is away from the Mac.
- **Re-deriving the report.** Reading `answer.md`, a relay-directory file, or
  raw logs to reconstruct what the dev seat said, when `pmTurn.devReport` was
  the verbatim text the whole time.

### Success, from the PM's chair

Both of these must feel effortless — that is the actual bar, not just "delivery
works":

- **"I delegated and kept working."** Dispatch with `--no-wait`, do other
  useful work, come back once with the right wait command, land the report.
  No manual reconstruction, no second-guessing whether the round even
  finished.
- **"I blocked and got the report."** Dispatch without `--no-wait` on a short
  round, get the PM Turn back in the same call. No ceremony for a five-minute
  round.

If either of those requires reading a second file, trusting a banner, or
guessing a command, the contract has failed regardless of what the JSON
schema says.

## Decision

1. **One durable object; no inbox verb.** `pmTurn` is embedded in both status
   envelopes. A separate `relay inbox` would duplicate status/recovery surfaces
   and is out of scope.
2. **Extend status; do not add wait verbs.** The only detached waiter is
   `pair pilot status --wait-for …` or `pair relay-status --wait-for …`.
   `pilot watch` remains compatible but is legacy and is never taught.
3. **A detached PM chooses a delivery route.** Default dispatch blocks. A PM
   using `--no-wait` must either run the returned status waiter (attended
   detach) or request the configured wake route (unattended/dead-session).
   `--delivery wake` without a configured wake command fails before dispatch;
   Allnighter never accepts an unattended fire-and-forget delegation it cannot
   deliver.
4. **Wake delivery means an acknowledged hook invocation.** `alln serve` writes
   the PM Turn first, invokes the hook with the full JSON on stdin, and records
   success only on exit 0. Nonzero/launch failure is retried with durable,
   bounded backoff and remains visible as a delivery failure; it is never
   represented as delivered. The hook host owns the final IDE/session handoff.

### Decision addendum — v3 deltas

These resolve ambiguities the v2 review surfaced from the agent-PM lens. They
sharpen the same architecture in Decision 1–4 above; nothing here reopens it.

5. **`--no-wait` is not a complete instruction on its own.** It is only ever
   valid paired with a follow-up: run the returned status waiter, or supply
   `--delivery wake` with a working receiver. Help/teaching copy must present
   `--no-wait` and its follow-up as one unit, never as two independently
   optional flags. This is the codification of the incident in "Why users
   curse today" — the gap was never a missing feature, it was `--no-wait`
   being teachable in isolation.
6. **`--timeout` stays required on `--wait-for`, no default.** A silent
   default timeout would let a PM believe a bounded wait is happening when it
   picked a value blind. Failing loud on a missing `--timeout` is cheaper than
   a PM discovering thirty minutes in that it under-provisioned. Builders keep
   the existing PTD-1 scope; this only confirms it is not weakened in v3.
7. **Default-path guidance is a table, not a paragraph.** Help/Bootstrap
   teaching copy must reproduce the "Round shape → Path" table from the Agent
   PM experience section verbatim (or link to it), not restate it as prose
   each time. Agents pattern-match a table faster than they parse guidance
   sentences.
8. **The wake receiver is judged only by exit code and idempotency, never by
   IDE-specific behavior.** PTD does not know or care whether the receiver
   resumes a Claude Code session, opens Cursor, or pages a human — only that
   it exits 0 exactly once it has durably accepted the PM Turn for
   `(relayId, sequence)`. Keep the hook contract host-agnostic; do not add
   Allnighter-side knowledge of any specific agent host.

## Current gap

Blocking `pilot handoff` and `relay-resume` already return a report when their
round completes. `--no-wait` returns a dispatch acknowledgement, while help and
error guidance currently tell agents to poll status. Parked status has no report.
`pilot watch` can observe a settlement but is explicitly disposable. `alln serve`
can notify a human but cannot deliver a PM turn into an agent session.

The result was an agent PM that used the documented detached path and received
neither the report nor a next command. The implementation must remove that gap,
not move it into a custom watcher.

## Contract: `PMTurnJSON`

`RelayCoordinator` owns creation. At every transition that ends a dev/PM round
and leaves a PM boundary, it writes exactly one immutable record at:

```text
~/Library/Application Support/Allnighter/Relays/<relayId>/pm-turn.json
```

Write with temp-file + atomic rename in the same serialized transition that
persists `RelayState`. A new record increments `sequence` once per relay. A
re-read/retry of the same transition must not increment it or emit a duplicate.
The relay state remains run truth; this is the durable delivery projection.

```json
{
  "schemaVersion": 1,
  "relayId": "relay_abc",
  "sequence": 7,
  "round": 2,
  "createdAt": "2026-07-29T22:14:00Z",
  "reason": "awaitingPM",
  "pmMode": "external",
  "relayStatus": "awaitingPM",
  "devReport": "verbatim settledDevReport text",
  "devRunId": "AD0446C6-…",
  "workRecovery": null,
  "nextCommands": [
    "alln pair pilot handoff --relay relay_abc --verdict continue --handover-file order.md --json"
  ],
  "notes": []
}
```

| Field | Rule / source |
| --- | --- |
| `sequence` | Monotonic `Int64`, scoped to `relayId`; dedupe key for wait/wake/notification. |
| `reason` | Exactly `awaitingPM`, `escalated`, `stopped`, or `done`; never infer from copy. |
| `relayStatus`, `pmMode`, `round` | Snapshot from the just-persisted `RelayState`. |
| `devReport` | `RelayCoordinator.settledDevReport`; `null` with a `notes[]` explanation when unavailable, never `""`. |
| `devRunId` | Current/settled round id when known; otherwise `null` with a note. |
| `workRecovery` | The WRC-S00 projection, copied as one nested object. Before WRC-S00 ships it is `null` plus `"workRecovery unavailable until WRC-S00"`; PTD does not create a competing recovery shape. |
| `nextCommands` | Fully expanded, status-valid commands with the real relay id — no placeholders, prose, or invented flags. |

`reason` is emitted for `awaitingPM`, `escalated`, `stopped`, and `done`. Thus a
Relay PM's final `done` report is deliverable to the delegating agent just as a
Pilot's `awaitingPM` report is. `running` creates no PM Turn.

## Read contract and the three delivery paths

Both `PilotStatusJSON` and the `RelayJSON` status response gain an optional
`pmTurn: PMTurnJSON`. The read sites are `PilotCLI.makeStatusJSON` and
`RelayJSON.project` (or their common status projector). A status snapshot includes
the latest PM Turn when present, including terminal states. `devReport` and
`nextCommands` appear only under `pmTurn`; do not add duplicate top-level aliases.

### A. Blocking dispatch — default attended path

No new flag or protocol. Blocking `pilot handoff`, `relay-resume`, `relay`, and
`relay adopt` return the same PM Turn payload through their existing result
envelopes when their round reaches a PM boundary. This return is delivery.
Default here for any round short enough that the PM has nothing better to do
than wait — see "Agent PM experience" §1.

### B. Status `--wait-for` — attended detached path

Extend both status commands, mirroring the existing in-process team-status loop:

```bash
alln pair pilot status --relay <id> --wait-for parked --timeout 7200 --json
alln pair relay-status --relay <id> --wait-for terminal --timeout 7200 --json
```

`--timeout` is required whenever `--wait-for` is supplied, and is a
non-negative number of seconds. `--wait-for` is mutually exclusive with any
persisted-only observation flag if one is added later.

| Wait target | Match | Intended use |
| --- | --- | --- |
| `parked` | `awaitingPM` or `escalated` | A PM must make the next decision. |
| `terminal` | `done` or `stopped` | A delegated Relay finishes or stops. |

There is intentionally no `running` target: it delivers no PM Turn and would
teach a new polling milestone instead of delivery.

The loop reads live relay state plus `pmTurn.sequence`; it returns immediately
when the target is already true. Otherwise it uses the team-status cadence
(`min 50 ms`, `max 5 s`, honoring a future `nextPollAfterMs`) and returns the
normal status envelope with `pmTurn` intact. It does not spin an external process.

For a nonmatching terminal state, return the final snapshot and set
`waitOutcome: "terminalMismatch"`; classify process exit exactly as the team
waiter does (stopped is failure-class; done is success-class). On a match, set
`waitOutcome: "matched"`. On expiry, print the last snapshot with
`waitOutcome: "timedOut"`, then exit 3 with registered error
`RELAY_WAIT_TIMEOUT`. The error's `agentAction` must name the same status waiter
with a longer timeout — never "poll status."

The `--no-wait --json` acknowledgement gains:

```json
{
  "delivery": {
    "path": "wait",
    "command": "alln pair pilot status --relay relay_abc --wait-for parked --timeout 7200 --json"
  }
}
```

For Relay dispatch, choose `terminal` only when the caller needs final settlement;
choose `parked` when it expects to judge an escalation. The acknowledgement is a
route instruction, not a claim that delivery already occurred.

### C. Wake hook — unattended/dead-session path

The already auto-launched `ServeDaemon` is the independent delivery process. It
remains read-then-shell-out: it never resumes, dispatches, changes relay state,
or takes a write lock.

Configuration is local and explicit:

```json
{
  "pmTurnWake": {
    "command": ["/absolute/path/to/pm-turn-receiver"],
    "retryMaxSeconds": 300
  }
}
```

`ALLN_PM_TURN_WAKE_COMMAND` is an equivalent command-array override. The hook
receives exactly `PMTurnJSON` on stdin. Its exit 0 acknowledges this delivery;
the receiver must be idempotent on `(relayId, sequence)`. The daemon maintains a
durable receipt ledger keyed by that pair, records attempt count/last error, and
retries a failed invocation with bounded exponential backoff through
`retryMaxSeconds`. It attempts at least once after restart when no successful
receipt exists. A final failed receipt is surfaced in status as
`pmTurnDelivery: { "path": "wake", "state": "failed", "errorCode":
"PM_TURN_WAKE_FAILED" }` and causes the existing human notification channel to
carry a delivery-failed warning.

`--delivery wake` is valid only with `--no-wait`. Before creating the detached
round it must verify a valid configured command and a usable serve launch. If
not, fail `PM_TURN_WAKE_UNCONFIGURED` (or `PM_TURN_WAKE_UNAVAILABLE`) and do not
dispatch. Its acknowledgement has `delivery.path: "wake"` and the delivery id;
it must not print a fake status waiter. This is the fail-loud enforcement of the
unattended part of the product law.

Mac banners remain WRC-S01/URN territory. They may share `(relayId, sequence)`
for dedupe, but they never satisfy `pmTurnDelivery`.

## Build slices

| Slice | Scope and owner | Depends on |
| --- | --- | --- |
| **PTD-1 — durable pull delivery** | `PMTurnJSON`/atomic store in `RelayCoordinator`; embed `pmTurn` in pilot/relay status; shared `RelayStatusWait`; `--wait-for parked|terminal`; `RELAY_WAIT_TIMEOUT`; no-wait `delivery.path: wait`; teaching flip. Owners: `RelayCoordinator`, `PilotCLI`, `RelayCLI`, `RelayJSON`, contract/help surfaces. | — |
| **PTD-2 — unattended wake delivery** | Config validation, `--delivery wake`, durable receipt/retry ledger, `ServeDaemon` hook, delivery failure projection. Reuse URN serve launch and WRC-S01 notification event; do not reimplement either. | PTD-1; URN-S01/S02 already shipped |

PTD-1 and PTD-2 are deliberately two slices, not five: the object, snapshot,
waiter, acknowledgement, and teaching are one pull-delivery contract. The only
separate concern is an independent delivery process for a dead session.

## Teaching and contract flip (part of PTD-1)

Replace every primary instruction of the form "`--no-wait`, then poll status"
with the "Agent PM experience" §1 table (verbatim or linked, per Decision
addendum item 7), plus this one-liner as the default framing:

> Dispatch blocks by default — fine for a short round. If you detach with
> `--no-wait` because the round is long, you must do exactly one of two
> things: run the returned `status --wait-for` command once you're back, or
> have configured `--delivery wake` before you detached. `--no-wait` alone,
> with neither, is the mistake that leaves the floor silent.

Never teach, as a primary path: raw `poll status` loops, `pilot watch`, or
trusting a Mac banner as delivery proof (see Anti-patterns above).

Update these source files and regenerate derived contract/help artifacts; do not
hand-edit `docs/generated/alln/*`:

- `Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/HelpTopicRegistry.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/Bootstrap.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/TeachingSnippet.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/MenuSelectionCopy.swift`
- `Packages/AllnighterCore/Sources/AllnighterCLI/PilotCLI.swift` and
  `RelayCLI.swift` caller-facing `RELAY_ROUND_IN_FLIGHT` guidance

The in-flight action becomes a bounded status waiter appropriate to the command,
not poll/`pilot watch` prose. Keep `pilot watch` compatible, label it legacy,
and remove it from Bootstrap, recipes, help examples, and error actions.

New registered errors:

| Code | Exit class | Agent action |
| --- | --- | --- |
| `RELAY_WAIT_TIMEOUT` | 3 (`timeout`) | Re-run the returned `pair … status --wait-for … --timeout <longer> --json` command. |
| `PM_TURN_WAKE_UNCONFIGURED` | operational failure | Configure `pmTurnWake.command`, or use blocking/wait delivery; no round was dispatched. |
| `PM_TURN_WAKE_UNAVAILABLE` | operational failure | Start/repair the local serve delivery process, or use blocking/wait delivery; no round was dispatched. |
| `PM_TURN_WAKE_FAILED` | operational failure (status/notification) | Repair the receiver; daemon retry state and the PM Turn remain durable. |

## WRC boundary

PTD owns delivery of the report and commands. WRC owns recovery facts and its
Mac notification event. The composition rules are strict:

| WRC owner | PTD use |
| --- | --- |
| WRC-S00 `workRecovery` | Nest the exact projection under `pmTurn.workRecovery`; no PTD fields, derivation, or git reads. |
| WRC-S01 `relayAwaitingPM` | Add `(relayId, sequence)` to its payload/dedupe when PTD exists; WRC retains event detection and banner delivery. |
| WRC-S02 substitution | Its status-valid `resumeCommands` feed `pmTurn.nextCommands`; PTD does not add PM-model policy. |

PTD-1 may land before WRC-S00: use `null` plus `notes[]`, never a partial fork of
the recovery envelope. A one-line cross-link in WRC is sufficient if needed; no
WRC rewrite is authorized by this packet.

## Non-goals

- New `pair pilot wait`, `pair relay wait`, `relay inbox`, or a second PM-Turn
  storage model.
- Poll scripts/watchers as the documented happy path.
- Cloud push, third-party accounts, or direct Cursor/Claude API integration.
- A human PM seat; PMs are agents.
- Storing a transcript, diff, or a second git model in `PMTurnJSON`.
- Changing state-machine/write-lock safety; a `.running` relay still rejects a
  second mutating dispatch with `RELAY_ROUND_IN_FLIGHT`.
- Allnighter-side knowledge of what a wake receiver does with the PM Turn
  (resume a session, page a human, open an IDE) — see Decision addendum item 8.

## v1 exit gate

All gates are required; this product law is not met by PTD-1 alone. Read each
gate from the PM's chair (Agent PM experience §"Success"), not just as a
schema check — a gate that passes technically but still leaves a PM guessing
does not count.

1. A blocking Pilot and Relay round returns the PM Turn report and exact next
   commands without regression.
2. `--no-wait` followed by its returned `status --wait-for parked|terminal`
   command returns `pmTurn.devReport` and `pmTurn.nextCommands` in one process,
   with no external watcher or `answer.md` read.
3. A parked/terminal snapshot (`pilot status --json` and `relay-status --json`)
   embeds the same `pmTurn` object, including a null+note for unavailable data.
4. A no-wait request for `--delivery wake` without a valid receiver refuses before
   dispatch. With a receiver, killing the dispatching PM session still invokes it
   once with the correct JSON; a failed hook is durably retried and visibly failed,
   never marked delivered.
5. Help, Bootstrap, recipes/menu teaching, and `RELAY_ROUND_IN_FLIGHT` actions
   name blocking, status wait, or explicit wake — never polling/watch as primary
   — and the round-shape → path table from Agent PM experience §1 appears
   verbatim or linked in that teaching copy.
6. Hermetic tests cover atomic/deduped PM Turn write, every reason, snapshot and
   waiter match/mismatch/timeout, no-wait delivery acknowledgement, wake
   config refusal, hook receipt/retry/dedupe, and the WRC composition null case.
7. One dogfood Pilot and one dogfood Relay demonstrate the attended waiter and
   dead-session wake path — one run playing a five-minute round on path A and
   one playing a multi-hour round on path B or C, so both PM-chair success
   criteria are proven, not just the schema. Run `swift test --package-path
   Packages/AllnighterCore`, `alln dev export-contracts --check`, and the
   architecture policy check.

## Builder routing

| Concern | Start here |
| --- | --- |
| Park transitions/report source | `RelayCoordinator.runExternalRound`, spawned relay loop, `RelayCoordinator.settledDevReport` |
| Pilot status | `PilotCLI.makeStatusJSON`, `PilotStatusJSON` |
| Relay status wire projection | `RelayJSON.project`, `RelayCLI` |
| Wait-loop precedent | `AllnighterCLI.runTeamStatus`, `TeamStatusWaitTarget` |
| Detached dispatch/serve launch | `DetachedDispatch`, `ServeAutoLaunch` |
| Daemon scheduling/notifications | `ServeDaemon`, `NotificationCandidateDetection`, URN archive |
| Recovery fields | WRC-S00 in `Work_Recovery_And_PM_Continuity.md` |
