# PM Turn Delivery

Status: **OPEN — founder intake packet (incident-driven 2026-07-29)**
Owner: AllnighterEngine (`RelayCoordinator`) + AllnighterCLI (`PilotCLI`, `RelayCLI`) +
`ServeDaemon`
Created: 2026-07-29
Revised: 2026-07-29 (initial draft from founder incident + PM notification brainstorm)
Origin: Founder delegated pilot work to Opus; agent used `pilot handoff --no-wait` per
help text; Opus was never notified when dev rounds landed; dev report required forensic
`answer.md` recovery. Mac app notifications not used. Custom poll watcher worked but is
unacceptable friction.
Related shipped substrate (reuse, do not re-build):
[`Unattended_Round_Notification.md`](../archive/phases/Unattended_Round_Notification.md)
(URN-S01–S03), [`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md)
(WRC-S00/S01/S02), [`Round_Survives_The_Caller.md`](../archive/phases/Round_Survives_The_Caller.md),
[`Pilot_Relay.md`](../archive/phases/Pilot_Relay.md). Deferred URN-S04 (`pilot wait`) is
**superseded by this packet** — ship here instead.

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
`ContractRegistry`; code remains SSOT for fields; archive this packet.

---

## Founder intake (SSOT_Founder_Input_Workflow)

```text
Founder intent:
  If an agent PM (Opus, Sonnet, Composer, …) delegates through Allnighter — pilot
  OR relay, attended OR unattended — Allnighter MUST deliver the PM Turn when work
  finishes. No custom poll watchers. No Mac-banner-only delivery. No answer.md
  archaeology. Blocking dispatch is the default; detached dispatch must have a
  first-class wait primitive that returns devReport + next commands.

Product value:
  The 10x for Allnighter: super basic plumbing that just works. Delegation without
  delivery is fire-and-forget, not a PM loop. This is the control-loop contract.

Trusted workflow slice:
  Opus calls `pilot handoff` → dev works ~5 min → Opus gets dev report verbatim +
  copy-paste next command — in the same session (blocking) or via `--wait-for parked`
  (detached). Session dead → recovery agent reads pm-turn inbox or gets wake hook.

Current state (verified 2026-07-29):
  Blocking `pilot handoff` / `relay-resume` returns devReport (works).
  `--no-wait` returns dispatch ack only; help/recipes teach poll `pilot status` (broken:
  status JSON has no devReport when awaitingPM).
  `pilot watch` returns devReport when settled but is documented optional/disposable.
  `team status --wait-for` exists for async team runs; pilot/relay status do not.
  `alln serve` auto-launches (URN-S02); macOS notifications fire for escalation/stop
  but NOT for `awaitingPM` (WRC-S01 gap). No push into IDE sessions.
  NotificationCandidateDetection has no `relayAwaitingPM` event.

Truth owner:
  PM Turn durable record: new `PMTurnStore` (or relay-dir file) written by
  `RelayCoordinator` at park transitions.
  Session delivery: `--wait-for` on `pilot status` + `relay-status` (CLI).
  Out-of-band wake: `ServeDaemon` hook on new pm-turn sequence.
  devReport text: `RelayCoordinator.settledDevReport` (existing).
  workRecovery envelope: WRC-S00 projection (compose, do not fork).

Blocking questions:
  None on product posture. Host-specific wake scripts (Cursor automation vs Claude
  hook) are configuration, not Allnighter core — serve fires hook with pm-turn JSON
  on stdin.
```

---

## Product law

```text
Every transition to "PM must act" produces a PM Turn.
Every PM Turn must be deliverable to the PM agent without invention.
```

**PM must act** means:

| Mode | `pmMode` | Park reasons (`reason` field) |
| --- | --- | --- |
| **Pilot** (session PM) | `external` | `awaitingPM` (dev landed, judge next round); `escalated` |
| **Relay** (spawned PM) | `spawned` | `escalated` (needs answer); `stopped` / `done` (settled) |

Mac Notification Center banners are a **parallel human channel**, not the PM contract.
Poll loops built by agents are **not** acceptable as the documented happy path.

---

## Why today fails (verified)

| Channel | Works? | Gap |
| --- | --- | --- |
| Blocking `handoff` / `relay-resume` | Yes | Docs teach agents to avoid it (`--no-wait` for "long jobs") |
| Poll `pilot status` / `relay-status` | Partial | No `devReport` when parked; 45s `waitHintSeconds` only while `.running` |
| `pilot watch` | Yes | Called optional/disposable; non-TTY capped at 30 min |
| `alln serve` + macOS notify | Partial | Wrong seat for IDE PM; `awaitingPM` silent |
| `team status --wait-for` | Yes (team runs) | Never extended to pilot/relay |

Incident shape: ~5 min rounds; blocking would have been fine. Agent took `--no-wait`
escape hatch per `ContractRegistry`, `HelpTopicRegistry`, and
`get-another-model-to-implement-this` recipe → lost in-session delivery.

---

## Architecture: one object, three delivery paths

### PM Turn (durable)

On every park transition, atomically write:

```text
~/Library/Application Support/Allnighter/Relays/<relayId>/pm-turn.json
```

```json
{
  "schemaVersion": 1,
  "relayId": "relay_abc",
  "sequence": 7,
  "round": 2,
  "landedAt": "2026-07-29T22:14:00Z",
  "reason": "awaitingPM",
  "pmMode": "external",
  "relayStatus": "awaitingPM",
  "devReport": "…verbatim from settledDevReport…",
  "workRecovery": {
    "workState": "workUncommitted",
    "repoRoot": "/path/to/repo",
    "baseline": "e5cae21c",
    "head": "bcd15eca",
    "commitCount": 3,
    "uncommitted": { "count": 1, "paths": ["packages/foo.mjs"] }
  },
  "nextCommands": [
    "alln pair pilot handoff --relay relay_abc --verdict continue --handover-file order.md --json"
  ]
}
```

**Write site:** `RelayCoordinator` when setting `status` to `awaitingPM`, `escalated`,
`stopped`, or `done` after a dev turn completes. Same transaction as state persist.
**Sequence:** monotonic per relay; increment on each new PM Turn (dedup key for notify +
wait).

**Read site:** `pilot status --json`, `relay-status --json` when parked include latest
pm-turn fields inline (or `pmTurn` sub-object). Optional dedicated verb:
`alln pair relay inbox --relay <id> --json` for recovery agents (PTD-1b, optional if
status embed is sufficient).

### Delivery path A — Blocking dispatch (default, attended)

No change to semantics. **Change teaching only** — blocking IS the notification:

```bash
alln pair pilot handoff --relay <id> --verdict continue --handover-file order.md --json
```

Returns `PilotHandoffJSON` with `devReport` when dev lands. Same for blocking
`relay-resume` / `relay` / `relay adopt`.

### Delivery path B — `--wait-for` (detached, attended)

Extend **both** status commands (mirror `team status --wait-for`):

```bash
alln pair pilot status --relay <id> --wait-for parked --timeout 7200 --json
alln pair relay-status --relay <id> --wait-for parked --timeout 7200 --json
```

**Wait targets:**

| Target | Matches | Use when |
| --- | --- | --- |
| `parked` | `awaitingPM` OR `escalated` | PM must act (primary) |
| `terminal` | `done` OR `stopped` | Unattended relay run to completion |
| `running` | `.running` | Rare; round dispatched (symmetry only) |

**Behavior:**

- Blocks in-process; polls relay state + pm-turn sequence (same cadence as team wait:
  min 50ms, max 5s, respect `nextPollAfterMs` if added).
- On match: return full envelope — `devReport`, `workRecovery`, `nextCommands`,
  `reason`, `relay` — same shape whether arrived via wait or snapshot read.
- Timeout: exit `3` (`RELAY_WAIT_TIMEOUT`); response includes last-known state.
- Terminal mismatch (waited for `parked`, got `done` without passing `parked`): exit
  per lifecycle class (mirror team wait).

**`--no-wait` ack must emit:**

```json
{
  "status": "dispatched",
  "nextAction": {
    "kind": "relayWait",
    "command": "alln pair pilot status --relay <id> --wait-for parked --timeout 7200 --json"
  }
}
```

Not "poll status." **Wait.**

`pilot watch` becomes **deprecated alias** for `--wait-for parked` (keep working;
stop teaching).

### Delivery path C — Wake hook (unattended / dead session)

When `pm-turn.json` `sequence` advances, `ServeDaemon` (already auto-launched via
URN-S02):

1. Posts macOS notification (extend WRC-S01 `relayAwaitingPM` for `awaitingPM`; existing
   events for `escalated`/`stopped`).
2. Invokes configurable wake hook once per new sequence (debounced):

```json
// ~/.allnighter/config.json (or env ALLN_PM_TURN_WAKE_COMMAND)
{
  "pmTurnWake": {
    "command": ["/path/to/script"],
    "debounceSeconds": 5
  }
}
```

Hook stdin = pm-turn JSON. Host-specific (Cursor automation, paste bridge) — Allnighter's
job is fire-once with full payload.

Recovery without hook: any session runs status with `--json` when parked, or
`relay inbox` if implemented.

---

## Teaching flip (ship with PTD-3)

| Old (broken) | New |
| --- | --- |
| Long jobs: `handoff --no-wait` then poll status | **Default: blocking handoff** |
| `pilot watch` optional/disposable | **`--wait-for parked`** is the detached waiter |
| `alln serve` = you don't have to watch | Serve = out-of-band wake when session is gone |
| Relay: poll `relay-status` | Block, or `--wait-for parked\|terminal` |

Agent one-liner:

> Dispatch blocks. If you must detach, the next command is `--wait-for parked`, not poll.

Files to update at PTD-3: `ContractRegistry+Milestone1.swift`, `HelpTopicRegistry.swift`,
`get-another-model-to-implement-this.md`, `Bootstrap.swift` routed teaching, error
`agentAction` strings on `RELAY_ROUND_IN_FLIGHT`.

---

## Packet split

| Slice | Claim | Owner | Deps |
| --- | --- | --- | --- |
| **PTD-1** | PM Turn durable write + parked status includes devReport | `RelayCoordinator`, `PMTurnStore` | — |
| **PTD-2** | `--wait-for parked\|terminal` on pilot status + relay-status | `PilotCLI`, `RelayCLI` | PTD-1 |
| **PTD-3** | `--no-wait` nextAction + teaching flip | CLI + help + recipes | PTD-2 |
| **PTD-4** | Serve wake hook on pm-turn sequence | `ServeDaemon` | PTD-1 |
| **PTD-5** | WRC-S01 `relayAwaitingPM` notify + pm-turn payload | `NotificationCandidateDetection` | PTD-1 |

**v1 exit gate:** PTD-1 + PTD-2 + PTD-3 (attended Opus never builds a watcher).
PTD-4 + PTD-5 = unattended parity.

URN-S04 (`pair pilot wait` / `pair relay wait`) — **do not build separately**; ship as
`status --wait-for` in PTD-2.

---

## Slices (dependency order)

### PTD-1 · PM Turn durable write — **do first**

*Claim:* "When dev lands, one file + status read gives devReport and next commands."

*Write:* `pm-turn.json` at park transitions (`awaitingPM`, `escalated`, `stopped`,
`done`). Fields above. `devReport` from `settledDevReport`. `workRecovery` from WRC-S00
projection when that slice ships; stub null + note until then (honest reporting).

*Read:* `pilot status --json` and `relay-status --json` embed `pmTurn` (or top-level
fields) when `relayStatus` is parked/terminal.

*Harden:*
- Atomic write (write temp + rename).
- Sequence monotonic; same park transition does not double-write same sequence.
- Missing devReport → null + note, never empty string pretending success.

*Proof:* unit — coordinator parks pilot relay → pm-turn file exists with devReport;
status JSON includes it. Integration — no read of `Runs/.../answer.md` required.

*Optional PTD-1b:* `alln pair relay inbox --relay <id> --json` — read latest pm-turn;
only if status embed insufficient for recovery agents.

### PTD-2 · `--wait-for` on status — **v1 core**

*Claim:* "One command blocks until PM Turn; returns full payload."

*Implement:* shared `RelayStatusWait` helper (mirror `TeamStatusWaitTarget` /
`AllnighterCLI.runTeamStatus` loop). Both `PilotCLI.runStatus` and `RelayCLI.runStatus`
gain `--wait-for <parked|terminal|running>` + `--timeout <seconds>` (required pair).

*Contract:* extend `PilotStatusJSON` / `RelayJSON` response wrapper with `pmTurn`,
`waitOutcome` (`matched` | `timedOut` | `terminalMismatch`), `devReport`, `nextCommands`.

*Error:* `RELAY_WAIT_TIMEOUT` → exit 3.

*Proof:* hermetic — mock state transitions; wait returns on sequence change; timeout
exits 3.

*Deprecate teaching:* `pilot watch` documented as legacy alias only.

### PTD-3 · nextAction + teaching flip

*Claim:* "Agents cannot learn the broken path from our own docs."

*Change:* all `--no-wait` dispatch acks (`pilot handoff`, `relay`, `relay-resume`,
`relay adopt`) emit `nextAction.command` with `--wait-for parked` (or `terminal` when
appropriate).

*Files:* see Teaching flip table above.

*Proof:* `HelpTopicRegistryTests`, recipe snapshot, `DetachedDispatchJSON` contract test.

### PTD-4 · Serve wake hook

*Claim:* "Session dead; something still fires with full pm-turn payload."

*Implement:* `ServeDaemon` scheduler tick reads pm-turn sequences (or thread projection);
on new sequence since last seen, run `pmTurnWake.command` with stdin JSON. Debounce per
relay. No-op when config absent.

*Constraints:* serve still read-then-shell-out only (URN inference bans). No dispatch
from serve.

*Proof:* harness — write pm-turn → hook invoked once; second tick same sequence → silent.

### PTD-5 · `relayAwaitingPM` notification

*Claim:* "Mac banner when `awaitingPM` parks (human parallel channel)."

*Reuse:* WRC-S01 spec — `NotificationEventKind.relayAwaitingPM`; payload from pm-turn
(relay id, work counts, suggested command). Dedup on sequence. Do not double-fire with
`relayNeedsAnswer` for same transition.

*Proof:* `NotificationCandidateDetectionTests` + serve harness.

---

## Relationship to WRC

| WRC slice | PTD relationship |
| --- | --- |
| WRC-S00 workRecovery envelope | Composed into pm-turn + status; PTD-1 reads it |
| WRC-S01 relayAwaitingPM | **PTD-5** — same event, pm-turn payload |
| WRC-S02 PM substitution | Independent; pm-turn `nextCommands` may include `--pm-model` |

Build order: PTD-1/2 can ship before WRC-S00; workRecovery fields null until WRC-S00
lands. Do not block PTD on WRC.

---

## Non-goals

- Cloud push / third-party notification services.
- Push directly into Cursor/Claude APIs (hook is config; host owns integration).
- Replacing blocking dispatch as default.
- Separate `pilot wait` / `relay wait` verbs (use `status --wait-for`).
- Storing full diffs/transcripts in pm-turn (devRunId → RunStore remains SSOT for depth).
- Human PM seat — PM is always an agent.

---

## Exit gate (v1 — PTD-1/2/3)

1. Blocking `pilot handoff` still returns devReport (no regression).
2. `handoff --no-wait` → `status --wait-for parked` returns devReport within one
   command (hermetic + one dogfood round).
3. Parked `pilot status --json` includes devReport without `--wait-for` (snapshot path).
4. `--no-wait` ack includes `nextAction` with wait command (not poll-only).
5. Help/recipe no longer teach "poll status until awaitingPM" as primary path.
6. `swift test --package-path Packages/AllnighterCore` + `alln dev export-contracts --check`
   green for touched contracts.

**Not in v1 exit gate:** wake hook (PTD-4), macOS `relayAwaitingPM` (PTD-5), `relay inbox`
(PTD-1b).

---

## Success test (founder Works Test)

```bash
# Detached path — the incident reproduction
alln pair pilot handoff --relay <id> --verdict continue --handover-file order.md --no-wait --json
alln pair pilot status --relay <id> --wait-for parked --timeout 3600 --json
# → blocks; returns devReport + nextCommands when dev lands; no custom watcher

# Snapshot path — recovery agent
alln pair pilot status --relay <id> --json
# → when awaitingPM: devReport present in response
```

Same for `pair relay` / `relay-status --wait-for terminal`.

---

## Routing

| Work | Read first |
| --- | --- |
| Park transitions | `RelayCoordinator.runExternalRound`, `resume`, spawned loop |
| devReport | `RelayCoordinator.settledDevReport` |
| Team wait pattern | `AllnighterCLI.runTeamStatus`, `TeamStatusWaitTarget` |
| Serve schedulers | `ServeDaemon.swift` |
| Notifications | `NotificationCandidateDetection.swift`, URN archive |
| Status projection | `PilotCLI.makeStatusJSON`, `RelayJSON.project` |
| Prior deferred wait | URN-S04 in `Unattended_Round_Notification.md` |

---

## Standing rules

- **PM Turn is the contract** — not poll hints, not banners alone.
- **Blocking is default** — `--no-wait` is exception; ack must name wait command.
- **Missing data is null + note** — never zero-filled invent.
- **One wait primitive** — pilot status and relay-status share implementation.
- **serve stays read-only** — hook shells out; no dispatch from serve.
- **Sequence dedup** — one notify + one hook per PM Turn.
