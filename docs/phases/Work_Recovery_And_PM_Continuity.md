# Work Recovery and PM Continuity

Status: **OPEN — founder intake packet (incident-driven 2026-07-29)**
Owner: AllnighterEngine (relay/pilot) + AllnighterCLI + `GitObserver` /
`ProcessOwnershipSurface`
Created: 2026-07-29
Revised: 2026-07-29 (pre-build review: trim S03/S04, sharpen envelope, harden gates)
Origin: Founder outage during a pilot/relay run — PM agent (Opus) hit vendor API
500/529; dev agent (Terra) may still have been executing; work landed in git
(committed and uncommitted) but was hard to find and resume. Recovery required
forensic `git log` across repos, not `alln pair relay-status`.
Related shipped substrate (reuse, do not re-build):
[`Pilot_Relay.md`](../archive/phases/Pilot_Relay.md) (PL-S06 adopt),
[`Unattended_Round_Notification.md`](../archive/phases/Unattended_Round_Notification.md)
(URN-S01–S03), [`Round_Survives_The_Caller.md`](../archive/phases/Round_Survives_The_Caller.md).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations as needed; code remains SSOT for fields; archive this packet.

---

## Founder intake (SSOT_Founder_Input_Workflow)

```text
Founder intent:
  When any seat dies (PM outage, dev stall, session limit), any recovery agent
  can answer in 30 seconds: what work exists, where it is, whether it is
  committed, which run made it, and what command resumes. PM is always an AI
  agent — never a human seat. Recovery agents should be able to watch a relay,
  be notified when dev lands work, substitute a different PM model, and
  continue without bespoke forensic git.

Product value:
  Anti-loss for real mutating work. PM continuity across vendor outages and
  session death. Composes with shipped adopt/resume/detached-handoff — does not
  replace them.

Trusted workflow slice:
  PM agent dies mid-round → recovery agent finds relay + work → polls or is
  notified when parked → reads workRecovery envelope → resumes with substitute
  PM model.

Current state (verified 2026-07-29):
  Round log already carries baseline/head, devRunId, endReason, proofResults.
  adopt (session→spawned PM) and pilot adopt (spawned→session PM) work when
  PARKED. resume reuses state.pmModelId — no PM substitution. awaitingPM (pilot
  park after dev lands) does NOT notify. dirtyFiles is pilot handoff-only;
  spawned rounds do not snapshot uncommitted paths after dev. Work outside a
  relay (direct Claude Code session) has no index. Pilot Relay §8 already
  proved session-agent death recovery via pilot status --json + relay dir.

Truth owner:
  Relay round + git range: RelayState / RelayRound (RelayStateStore).
  Uncommitted tree: GitObserver at status-read time; durable stamp
  dirtyFilesAfterDev on RelayRound at dev-turn end (spawned path).
  Recovery envelope projection: RelayJSON / PilotStatusJSON (Core contract).
  PM substitution: RelayCoordinator.resumeGuard + state.pmModelId.
  Notifications: NotificationCandidateDetection + ServeDaemon (extend, not fork).
  (Deferred) Repo-level scan: separate packet WRC-B (was WRC-S03).
  (Deferred) Guard intent: separate packet WRC-B (was WRC-S04).

Blocking questions:
  None on product posture. Packet scope is v1 only (S00–S02). S03/S04 deferred
  to packet WRC-B after v1 ships and is dogfooded.
```

---

## Product promise

```text
When a relay seat dies, any recovery agent that can read alln status can answer
in 30 seconds — without git archaeology:
  what work exists, where it is, is it committed, which run made it,
  what exact command resumes (including substitute PM model).
```

Two co-equal halves — do not conflate:

| Half | Question | Primary surface | v1 slice |
| --- | --- | --- | --- |
| **Work recovery** | Where is the work? | git truth + uncommitted paths on status | WRC-S00 |
| **PM continuity** | Who judges next? | PM seat substitution + notification | WRC-S02, WRC-S01 |

Work recovery prevents **loss**. PM continuity prevents **stall**.

**Scope honesty:** v1 covers work **indexed by a relay**. Work that never touched a
relay is out of packet (deferred WRC-B / `alln work scan`). The incident's
forensic pain was mostly "I had a relay but status did not surface the work."

---

## Vocabulary (agent-native PM)

There is no human PM seat. Both modes are AI agents:

| Mode | `pmMode` | Who judges | `pmModelId` |
| --- | --- | --- | --- |
| **Session PM** (product: Pilot) | `external` | The agent session holding the relay (Claude Code, Cursor, Composer, …) | `"external"` (sentinel) |
| **Spawned PM** (product: Relay) | `spawned` | Allnighter-dispatched PM run | `model_opus`, `model_sonnet`, … |

Handoffs are **agent → agent**:

- Session PM → spawned PM: `alln pair relay adopt --pm-model <id>`
- Spawned PM → session PM: `alln pair pilot adopt --relay <id>`
- Spawned PM → different spawned PM: **not supported today** (WRC-S02)

`external` means session-bound agent PM, not founder/human.

---

## Why this exists (incident shape)

2026-07-29: PM agent (Opus) steering phase-102 slices on `Ikiro.Studio` hit
vendor API 500/529. Dev agent (Terra) likely finished; S0–S5 committed; S1b code
sat uncommitted in the working tree. Recovery required:

1. Guessing which repo held the work (not the Allnighter relay dir).
2. `git log` archaeology — no relay pointed at the parent phase doc.
3. Manual test run to confirm S1b was done.

Three failure modes, one product gap (v1 addresses 2 + 3 + PM sub; 1 deferred):

1. **Work outside relay tracking** — session committed directly; no relay id on
   the phase doc. → **deferred WRC-B (S03)**
2. **Uncommitted work invisible** — round log has `baseline`/`head` (commits) but
   not dirty paths after spawned dev turns. → **WRC-S00**
3. **PM substitution missing** — `relay-resume` cannot swap `model_opus` →
   `model_sonnet` after PM death. → **WRC-S02**
4. **Silent park** — `awaitingPM` does not notify; dead PM never hears. → **WRC-S01**

---

## State machine gate (unchanged — safety)

While a round is `.running`, no adopt, resume, or handoff is allowed
(`RELAY_ROUND_IN_FLIGHT`). Recovery agents must wait for dev to settle, then act.
This is intentional — not a bug.

```text
.running     → poll pilot status / alln ps; do NOT adopt or resume
.awaitingPM  → pilot handoff OR relay adopt (session → spawned)
.escalated   → relay-resume OR adopt OR pilot adopt
.stopped+orphan → relay-resume OR pilot adopt (after reconcile)
```

WRC v1 adds: **what the status envelope shows**, **when to notify on park**,
**how to resume with a different PM model**.

---

## Packet split

| Packet | Slices | Ship when |
| --- | --- | --- |
| **WRC v1 (this packet)** | S00 → S02 → S01 | This week / immediate |
| **WRC-B (deferred)** | S03 repo scan, S04 relay guard | After v1 dogfood; separate intake |

Order inside v1 is dependency + incident priority:

1. **WRC-S00** — envelope (find the work)
2. **WRC-S02** — PM substitution (continue the work) — no dep on S01
3. **WRC-S01** — `awaitingPM` notify (unattended discovery) — payload uses S00 fields

S02 before S01 because substitution is small, unblocks attended recovery without
`alln serve`, and notification without resume-with-model is incomplete.

---

## Slices (v1 — dependency order)

### WRC-S00 · Work recovery envelope on status JSON — **do first / MVP**

*Claim:* "I can see all work from one status read — commits and uncommitted."
*Truth owner:* `RelayJSON` / `PilotStatusJSON` projection from `RelayState` +
`GitObserver` (live dirty) + durable `dirtyFilesAfterDev` on `RelayRound`.
*Adds `workRecovery` block:*

```json
{
  "roundStatus": "running | awaitingPM | escalated | stopped",
  "workState": "devInFlight | commitsOnly | workUncommitted | clean",
  "repoRoot": "/path/to/repo",
  "docPath": "Docs/phases/….md",
  "baseline": "e5cae21c",
  "head": "bcd15eca",
  "commitCount": 3,
  "commitShas": ["e5cae21c", "2cfeb01e", "bcd15eca"],
  "uncommitted": { "count": 5, "paths": ["packages/…/operation-log.mjs"] },
  "dirtyAtDevEnd": { "count": 5, "paths": ["…"] },
  "devRunId": "AD0446C6-…",
  "resumeCommands": [
    "alln pair pilot status --relay RELAY_ID --json",
    "alln pair relay-resume --relay RELAY_ID --pm-model model_sonnet --answer '…'"
  ]
}
```

*Field rules (do not blur these):*

| Field | Meaning | Source |
| --- | --- | --- |
| `roundStatus` | Relay state machine (already known) | `RelayState.status` |
| `workState` | Work condition for recovery | Derived; **not** a machine state |
| `commitShas` | SHAs in `(baseline, head]` for this round | Round log; empty if no advance |
| `uncommitted` | **Live** dirty paths at status-read | `GitObserver` now |
| `dirtyAtDevEnd` | Durable stamp at post-dev (spawned) or handoff (pilot) | `RelayRound.dirtyFilesAfterDev` / existing pilot `dirtyFiles` |
| `docPath` | Phase/work doc if known | Relay start args / state; **null** if never set — never invent |
| `resumeCommands` | Fully expanded, copy-pasteable | Real relay id + allowed verbs for current status; no `<id>` placeholders |

*workState derivation (v1):*

```text
devInFlight      if roundStatus == running
workUncommitted  if uncommitted.count > 0 (or dirtyAtDevEnd when live git fails)
commitsOnly      if commitCount > 0 and uncommitted.count == 0
clean            otherwise
```

*Also:* stamp `dirtyFilesAfterDev` on `RelayRound` for spawned relays (pilot
already snapshots `dirtyFiles` at handoff — extend to post-dev on spawned path).
If live `GitObserver` fails, surface `uncommitted: null` + note; never `count: 0`.
*Proof:* unit test — (a) spawned dev turn leaves uncommitted files → status JSON
lists paths, `workState: workUncommitted`; (b) committed-only round lists
`commitShas` + `commitCount`; (c) pilot path still surfaces dirty at handoff;
(d) missing `docPath` is null, not guessed.
*Reuses:* `GitObserver`, `RelayRound.baselineHead`/`headAfterDev`, early
`devRunId` stamp (PLS-S02), `PilotCLI.recoveryNextActions`.

### WRC-S02 · PM seat substitution on resume — **the Opus→Sonnet gap**

*Claim:* "A recovery agent can continue a spawned relay with a different PM
model."
*Truth owner:* `RelayCoordinator.resumeGuard` + `RelayState.pmModelId`.
*Adds:* `--pm-model <id>` on `pair relay-resume` (and contract registry). When
present and parked (`isResumable`), update `state.pmModelId` before loop
continues. Inject one-time `substitutionNote` on first PM turn (same pattern as
`adoptionNote` in adopt).
*Eligibility:*

| Current status | `--pm-model` allowed? | Action |
| --- | --- | --- |
| `escalated`, resumable `stopped` | yes (spawned only) | update `pmModelId`, resume |
| `awaitingPM` (external pilot park) | no on `relay-resume` | use existing `relay adopt --pm-model` |
| `running` | no | `RELAY_ROUND_IN_FLIGHT` |
| `pmMode == external` | no on `relay-resume` | adopt path already owns model pick |

*Harden:*
- Unknown / retired model id → hard error before state write.
- Concurrent resume: existing in-flight / claim guards apply; second resume fails
  cleanly, does not double-dispatch PM.
- Omit `--pm-model` → keep prior `pmModelId` (today's behavior).

*Proof:* test — relay parked `escalated` with `pmModelId: model_opus`; resume
with `--pm-model model_sonnet` → state carries sonnet, loop dispatches sonnet PM,
note rendered once; second concurrent resume rejected.
*Non-goal:* substitution while `.running`; session-PM model swap (use adopt).

### WRC-S01 · `relayAwaitingPM` notification — **blocking for unattended recovery**

*Claim:* "When dev lands and the PM seat is empty, something tells a recovery
agent."
*Truth owner:* `NotificationCandidateDetection` + `NotificationEventKind`.
*Gap:* `relayEscalated` → `relayNeedsAnswer` notifies; **`awaitingPM` is silent**
(pilot park after dev completes). That is exactly when a dead session PM needs a
substitute (via `relay adopt`).
*Adds:* `relayAwaitingPM` event; `ServeDaemon` posts when thread projection shows
parked pilot relay with dev round finished.
*Payload must include (from S00, not prose):* relay id, `repoRoot`, `workState`,
`commitCount`, uncommitted count, one suggested resume/adopt command.
*Harden:*
- Dedup: one candidate per relay park transition (do not re-fire every serve tick).
- Do not double-notify the same park as both `relayAwaitingPM` and
  `relayNeedsAnswer` — one kind per terminal park reason.
- If `alln serve` is not running: no notification (existing URN posture); status
  envelope + poll remain the attended path. Document this; do not fake delivery.
*Proof:* harness — handoff completes → single notification candidate with relay
id + suggested command + work counts; second poll does not duplicate.
*Reuses:* URN pipeline; do not fork a second notifier.

---

## Deferred slices (packet WRC-B — not in v1 exit gate)

### WRC-S03 · Repo work scan — **anti-loss for non-relay work** (defer)

*Claim:* "Work that never touched a relay is still findable."
*Why defer:* New CLI product surface; "known project roots" and time/doc
correlation are lie-prone without a clear project registry. Incident primary
pain was status fog on an existing relay, not pure non-relay work.
*When reopen:* After S00 dogfood; define project-root source of truth first.

### WRC-S04 · Relay guard — watch, notify, act — (defer)

*Claim:* "A recovery agent registers intent once; Allnighter watches and
resumes when parked."
*Why defer:* Auto-action doubles resume race surface (guard + recovery agent +
serve). Notify-only guard is mostly S01 + a poll loop the agent can already do
with `waitHintSeconds`. Build after S00–S02 prove the manual recovery ladder.
*If reopened first:* notify-only + `suggestedCommands` from S00; no auto-resume
until claim/idempotency design is explicit (single actor, durable intent, cancel).

---

## What already ships (reuse)

| Piece | Location | WRC builds on |
| --- | --- | --- |
| Round log (baseline, head, devRunId) | `RelayState`, `RelayJSON` | WRC-S00 |
| adopt / pilot adopt | `RelayCoordinator` | WRC-S02 eligibility, WRC-S01 action hint |
| Detached handoff survival | `DetachedHandoff`, `DetachedDispatch` | round survives caller |
| pilot status recovery ladder | `PilotCLI.recoveryNextActions` | WRC-S00 envelope |
| macOS notifications | URN-S01–S03 | WRC-S01 extend |
| Early devRunId stamp | PLS-S02 | work linkage |
| Session-agent death recovery | Pilot_Relay §8 | proof the model works |
| Resume claim / in-flight guard | `RelayCoordinator` (`claimStart` / resume) | WRC-S02 double-dispatch |

---

## Non-goals

- Durable "PM session" object separate from relay state (relay id + round log
  is enough for v1).
- Live attach while dev is `.running` (wait-then-act only).
- Full diff or transcript duplication in round log (use `devRunId` → RunStore).
- Push into IDE sessions (pull-based + notifications; Pilot_Relay §6 non-goal
  stands).
- Human-specific UX — all recovery paths are agent-first structured JSON.
- Repo-wide archaeology / `alln work scan` (WRC-B / S03).
- Auto-resume guard (WRC-B / S04).
- Inventing `docPath` or phase name from commit messages.

---

## Exit gate (v1 only)

1. Simulated PM death while dev finishes: recovery agent reads `workRecovery`
   from `pilot status --json` / relay status **without** `git log` archaeology;
   sees `repoRoot`, `commitShas` or `commitCount`, uncommitted paths when dirty.
2. Dev lands uncommitted work (spawned path): `dirtyAtDevEnd` stamped;
   live `uncommitted` on status; `workState: workUncommitted`.
3. `relay-resume --pm-model model_sonnet` on parked escalated relay substitutes
   PM; loop continues from same relay id; concurrent second resume fails cleanly.
4. `awaitingPM` fires **one** `relayAwaitingPM` notification when `alln serve`
   is running; payload includes relay id + suggested command + work counts.
5. Missing git/doc fields are `null` + note — never zero-filled invent.
6. `swift test --package-path Packages/AllnighterCore` + `alln dev
   export-contracts --check` green for touched contracts.

**Not in v1 exit gate:** `alln work scan`, relay guard auto-action.

---

## Routing

| Work | Read first |
| --- | --- |
| Relay state machine | `RelayCoordinator.swift`, `RelayState.swift` |
| Status / recovery ladder | `PilotCLI.swift` |
| Wire contracts | `RelayJSON.swift`, `PilotStatusJSON` |
| Git observation | `GitObserver.swift` |
| Notifications | `NotificationCandidateDetection.swift`, `ServeDaemon.swift` |
| Adopt / substitution notes | `RelayCoordinator.adoptGuard`, `RelayPMPrompt` |
| Process floor | `ProcessOwnershipSurface.swift` |
| Prior adopt proof | `docs/archive/phases/Pilot_Relay.md` §8 |
| Prior notification proof | `docs/archive/phases/Unattended_Round_Notification.md` |

---

## Standing rules

- **Missing data is null + note. Failed query is error, never zeros.**
- **Recovery commands must be copy-pasteable** — no prose-only "inspect the repo";
  no `<id>` placeholders in emitted JSON.
- **PM is always an agent** — `external` is session-bound agent, not human.
- **Do not attach mid-flight** — poll until parked, then act.
- **Git is truth; relay indexes it** — do not store diffs in relay state.
- **`roundStatus` ≠ `workState`** — never overload one enum for both.
- **Live dirty vs stamped dirty** — both may appear; do not collapse them.
- **One resume actor** — substitution and future guard must share claim semantics;
  never silent double PM dispatch.
- **Notify is best-effort** — attended recovery via status envelope must work
  when serve is down.
- **Do not invent doc/phase linkage** from commit messages or heuristics in v1.
