# Work Recovery and PM Continuity

Status: **OPEN — founder intake packet (incident-driven 2026-07-29)**
Owner: AllnighterEngine (relay/pilot) + AllnighterCLI + `GitObserver` /
`ProcessOwnershipSurface`
Created: 2026-07-29
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
  PM model (or guard registered the intent and acts automatically).

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
  Uncommitted tree: GitObserver at dev-turn end.
  Recovery envelope projection: RelayJSON / PilotStatusJSON (Core contract).
  Repo-level scan: new CLI surface (TBD — WRC-S03).
  PM substitution: RelayCoordinator.resumeGuard + state.pmModelId.
  Guard intent: durable file under Application Support (TBD — WRC-S04).
  Notifications: NotificationCandidateDetection + ServeDaemon (extend, not fork).

Blocking questions:
  None on product posture. WRC-S04 (relay guard) may defer auto-action and ship
  notify-only first if scope needs trimming.
```

---

## Product promise

```text
When any seat dies, any recovery agent can answer in 30 seconds:
  what work exists, where it is, is it committed, which run made it,
  what command resumes.
```

Two co-equal halves — do not conflate:

| Half | Question | Primary surface |
| --- | --- | --- |
| **Work recovery** | Where is the work? | git truth + uncommitted paths + repo scan |
| **PM continuity** | Who judges next? | PM seat substitution + guard + notifications |

Work recovery prevents **loss**. PM continuity prevents **stall**.

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

Three failure modes, one product gap:

1. **Work outside relay tracking** — session committed directly; no relay id on
   the phase doc.
2. **Uncommitted work invisible** — round log has `baseline`/`head` (commits) but
   not dirty paths after spawned dev turns.
3. **PM substitution missing** — `relay-resume` cannot swap `model_opus` →
   `model_sonnet` after PM death.

---

## State machine gate (unchanged — safety)

While a round is `.running`, no adopt, resume, or handoff is allowed
(`RELAY_ROUND_IN_FLIGHT`). Recovery agents must wait for dev to settle, then act.
This is intentional — not a bug.

```text
.running     → poll pilot status / alln ps; do NOT adopt or resume
.awaitingPM  → pilot handoff OR relay adopt (session → spawned)
.escalated  → relay-resume OR adopt OR pilot adopt
.stopped+orphan → relay-resume OR pilot adopt (after reconcile)
```

WRC adds: **what to poll for**, **when to notify**, **what to run when parked**.

---

## Slices (dependency order)

### WRC-S00 · Work recovery envelope on status JSON — **do first**

*Claim:* "I can see all work from one status read — commits and uncommitted."
*Truth owner:* `RelayJSON` / `PilotStatusJSON` projection from `RelayState` +
`GitObserver`.
*Adds `workRecovery` block:*

```json
{
  "phase": "devInFlight | awaitingReview | escalated | workUncommitted | done",
  "repoRoot": "/path/to/repo",
  "docPath": "Docs/phases/….md",
  "baseline": "e5cae21c",
  "head": "bcd15eca",
  "commitShas": ["e5cae21c", "2cfeb01e", "…"],
  "uncommitted": { "count": 5, "paths": ["packages/…/operation-log.mjs"] },
  "devRunId": "AD0446C6-…",
  "resumeCommands": [
    "alln pair pilot status --relay <id> --json",
    "alln pair relay-resume --relay <id> --pm-model model_sonnet --answer '…'"
  ]
}
```

*Also:* stamp `dirtyFilesAfterDev` on `RelayRound` for spawned relays (pilot
already snapshots `dirtyFiles` at handoff — extend to post-dev on spawned path).
*Proof:* unit test — dev turn leaves uncommitted files → status JSON lists paths
and `phase: workUncommitted`; committed-only round lists `commitShas`.
*Reuses:* `GitObserver`, `RelayRound.baselineHead`/`headAfterDev`, early
`devRunId` stamp (PLS-S02).

### WRC-S01 · `relayAwaitingPM` notification — **blocking for unattended recovery**

*Claim:* "When dev lands and the PM seat is empty, something tells a recovery
agent."
*Truth owner:* `NotificationCandidateDetection` + `NotificationEventKind`.
*Gap:* `relayEscalated` → `relayNeedsAnswer` notifies; **`awaitingPM` is silent**
(pilot park after dev completes). That is exactly when a dead PM needs a
substitute.
*Adds:* `relayAwaitingPM` event; `ServeDaemon` posts when thread projection shows
parked pilot relay with dev round finished.
*Proof:* harness — handoff completes → notification candidate with relay id +
suggested resume command in payload.
*Reuses:* URN pipeline; do not fork a second notifier.

### WRC-S02 · PM seat substitution on resume — **the Opus→Sonnet gap**

*Claim:* "A recovery agent can continue a spawned relay with a different PM
model."
*Truth owner:* `RelayCoordinator.resumeGuard` + `RelayState.pmModelId`.
*Adds:* `--pm-model <id>` on `pair relay-resume` (and contract registry). When
present and parked (`isResumable`), update `state.pmModelId` before loop
continues. Inject one-time `substitutionNote` on first PM turn (same pattern as
`adoptionNote` in adopt).
*Proof:* test — relay parked `escalated` with `pmModelId: model_opus`; resume
with `--pm-model model_sonnet` → state carries sonnet, loop dispatches sonnet PM,
note rendered once.
*Non-goal:* substitution while `.running`.

### WRC-S03 · Repo work scan — **anti-loss for non-relay work**

*Claim:* "Work that never touched a relay is still findable."
*Truth owner:* new CLI verb `alln work scan` (name TBD at implementation).
*Behavior per known project root:*
- unpushed commits (ahead of remote)
- dirty porcelain paths
- open relays on same root (correlate by time + doc)
- surface: "Ikiro.Studio: 19 unpushed commits (phase-102), 5 uncommitted files,
  no relay on `102_Dashboard_Backend_Slices.md`"
*Proof:* fixture repo with unpushed commits + dirty tree + parked relay → scan
JSON lists all three.
*Reuses:* `GitObserver`, `ProcessOwnershipSurface.list`, `RelayStateStore`.

### WRC-S04 · Relay guard — watch, notify, act — **compose, don't rearchitect**

*Claim:* "A recovery agent registers intent once; Allnighter watches and
resumes when parked."
*Truth owner:* `RelayCLI` + durable guard intent file under Application Support.
*Target CLI (refine at implementation):*

```bash
alln pair relay guard \
  --relay <id> \
  --until parked \
  --then resume \
  --pm-model model_sonnet \
  --answer "Prior PM session died. Continue from round log." \
  --notify \
  --json
```

*Behavior:*
1. If `.running` → poll `pilot status` every `waitHintSeconds` (45s).
2. On park → fire notification (WRC-S01) + run `relay-resume` or `relay adopt`
   per `pmMode` and `--then` action.
3. `--no-wait` spawns detached (RSC-HF pattern).

*Proof:* harness — start relay, kill PM owner, dev completes, guard resumes
with substitute model.
*May defer:* auto-action in v1; ship notify-only guard that prints
`suggestedCommands` from WRC-S00 envelope.

---

## What already ships (reuse)

| Piece | Location | WRC builds on |
| --- | --- | --- |
| Round log (baseline, head, devRunId) | `RelayState`, `RelayJSON` | WRC-S00 |
| adopt / pilot adopt | `RelayCoordinator` | WRC-S04 actions |
| Detached handoff survival | `DetachedHandoff`, `DetachedDispatch` | guard `--no-wait` |
| pilot status recovery ladder | `PilotCLI.recoveryNextActions` | WRC-S00 envelope |
| macOS notifications | URN-S01–S03 | WRC-S01 extend |
| Early devRunId stamp | PLS-S02 | work linkage |
| Session-agent death recovery | Pilot_Relay §8 | proof the model works |

---

## Non-goals

- Durable "PM session" object separate from relay state (relay id + round log
  is enough for v1).
- Live attach while dev is `.running` (wait-then-act only).
- Full diff or transcript duplication in round log (use `devRunId` → RunStore).
- Push into IDE sessions (pull-based + notifications; Pilot_Relay §6 non-goal
  stands).
- Human-specific UX — all recovery paths are agent-first structured JSON.

---

## Exit gate

1. Simulated PM death (kill spawned PM owner or session limit): recovery agent
   reads `workRecovery` from status JSON without `git log` archaeology.
2. Dev lands uncommitted work: paths appear in envelope; `phase: workUncommitted`.
3. `relay-resume --pm-model` substitutes PM; loop continues from same relay id.
4. `awaitingPM` fires `relayAwaitingPM` notification when Mac app closed (`alln
   serve` running).
5. `alln work scan` surfaces unpushed/uncommitted work on a repo with no active
   relay on the target doc.
6. `swift test --package-path Packages/AllnighterCore` + `alln dev
   export-contracts --check` green for touched contracts.

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
- **Recovery commands must be copy-pasteable** — no prose-only "inspect the repo."
- **PM is always an agent** — `external` is session-bound agent, not human.
- **Do not attach mid-flight** — poll until parked, then act.
- **Git is truth; relay indexes it** — do not store diffs in relay state.
