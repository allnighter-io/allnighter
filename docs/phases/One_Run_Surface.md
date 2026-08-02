# One Run Surface

Status: **IN FLIGHT — ORS-S00…S03 code/docs cutover shipped; ORS-S04 two-host
Works Test and archival remain. Not complete.**
Owner: Shared Core + CLI
Updated: 2026-08-01

Supersedes archived
[`Agent_Facing_Run_Observability.md`](../archive/phases/Agent_Facing_Run_Observability.md).
Amends the pull path shipped by archived
[`PM_Turn_Delivery.md`](../archive/phases/PM_Turn_Delivery.md) and
[`Completion_Delivery.md`](../archive/phases/Completion_Delivery.md): terminal
delivery remains required, but the one returned command must observe the middle
and deliver the end.

## Founder intent

Allnighter should be incredibly easy for agents to use as reliable project
managers for humans. An agent must not need to know which command owns result
truth, live status, process ownership, activity, or terminal delivery.

There are zero external users. Make a clean cold product now:

- one obvious single-run read surface;
- no aliases;
- no compatibility shims;
- no parallel JSON contracts;
- no public filesystem escape hatch;
- a hard cutover through code, contracts, help, fixtures, and living docs in one
  ship.

Founder summary:

> `alln menu` answers “what can I do?” One canonical run surface must answer
> “what is happening?”

## Product value

The current product contains much of the needed truth, but splits it across
`alln show`, `alln team status`, `alln team result`, `alln ps`, `alln run
--stream`, the detached terminal waiter, and private run files. Agents try one
surface, reasonably assume its answer is complete, and either miss available
truth or conclude Allnighter cannot observe the work.

This phase does not add another observability feature. It consolidates existing
capabilities behind one door and deletes the competing public doors.

## User-visible claim

```text
Start work once. Reattach anytime. One run view tells you what is true,
what Allnighter observed, whether you are needed, and what came back.
```

Trusted workflow slice:

```text
alln menu
-> alln run "…" --no-wait --json
-> run the one returned nextAction.command
-> see an immediate snapshot + live activity + terminal PM Turn
```

The observing process is disposable. Killing it never kills the run. Running
the same command later catches up from durable run truth and continues.

## Prior art

Mature CLIs keep background execution separate from observation, then make
observation reattachable:

- Docker starts detached work with `up --detach` and observes it later with a
  replayable/followable log surface (`logs --follow`, optionally bounded by
  `--tail`).
- GitHub CLI uses `gh run watch <id>` to show progress until terminal.
- Kubernetes exposes a resource snapshot and a followable log stream by stable
  resource identity.

Allnighter adopts the convention, not the command count: the existing `show`
verb owns both snapshot and follow behavior for one run.

References:

- <https://docs.docker.com/reference/cli/docker/compose/up/>
- <https://docs.docker.com/reference/cli/docker/compose/logs/>
- <https://cli.github.com/manual/gh_run_watch>
- <https://kubernetes.io/docs/reference/kubectl/generated/kubectl_logs/>

## Current state

The machinery is present but fragmented:

| Truth/capability | Current surface | Defect |
| --- | --- | --- |
| Durable run, answers, plan, terminal receipt | `alln show` / `TeamRunJSON` | Mid-run projection omits live reconciliation and activity truth. |
| Owner reconciliation, silence, `progressStale` | `alln team status` / `TeamStatusResponse` | A second schema and a non-obvious command. |
| Terminal result | `alln team result` | Third read path for the same run identity. |
| Attached narration | `alln run --stream` | Launch-time attachment; not a durable reattach command. |
| Detached completion | `delivery.command` → terminal waiter | Intentionally silent through the middle. |
| Process inventory | `alln ps` | Fleet/operator view; agents misuse it to reconstruct a single run. |
| Durable events | `RemoteRunEventJournal` | Replay machinery exists, but persistence depends on execution path and is not the canonical CLI read surface. |
| Private journal/audit | `Runs/run_<id>/run.json`, `events.jsonl` | Internal storage leaks when public commands omit truth. |

Code truth owners today:

- run semantics: `RunService.run`;
- durable run state: `RunStore` / `TeamRun`;
- public run contract: `TeamRunJSON` / `TeamRunJSONMapper`;
- owner reconciliation: `ProcessOwnership` / `RunStore.reconcileRun`;
- durable events and sequence: `RemoteRunEventJournal` / `RunEvent`;
- terminal PM boundary: `PMTurnStore` / `PMTurnStatusProjection`;
- command/help truth: `ContractRegistry` / `HelpTopicRegistry`.

## First-principles model

A project-managing agent needs four answers about delegated work:

1. **Lifecycle** — accepted, queued, running, or terminal?
2. **Health** — is the recorded owner alive, dead, contradictory, or unknown?
3. **Activity** — what did Allnighter actually observe, and when?
4. **Attention/result** — is caller action required, or what came back?

`parked` is **loop/relay vocabulary**, not run lifecycle: `RunLifecycle`
(`RunLifecycle.swift:8`) is `queued | running | done | failed | timedOut |
cancelled`, and a vendor-limit wait is `queued` plus a sourced blocker. This
packet must never teach a run status the type system does not have.

These are separate axes. Do not compress them into a guessed `progress` boolean.
A process can be alive and silent. A repo can change while the agent is stuck.
Recent output does not prove semantic forward motion. Silence from a
terminal-only driver can be expected.

The product reports observed facts and one next action. It never asserts
“progressing” or “stuck” without an owned deterministic rule.

## Binding decision: one canonical single-run surface

```text
alln show <run-id|latest> [--json | --stream] [--full]
```

### Snapshot

```bash
alln show <run-id> --json
```

Emits exactly one canonical `TeamRunJSON`. Before mapping, the read path
reconciles process truth and attaches the live observation fields. It works for
queued, running, vendor-blocked, and terminal runs. The caller never chooses
between a status schema and a result schema.

Plain `alln show <run-id>` renders the same truth compactly for a human.
`--full` remains the explicit audit expansion for prompt snapshots. It is not a
progress mode and is mutually exclusive with `--stream`.

### Reattachable stream

```bash
alln show <run-id> --stream
```

Emits NDJSON and:

1. immediately emits the current run snapshot;
2. replays a bounded recent semantic activity window with durable sequence;
3. follows new run events;
4. emits exactly one terminal event containing the terminal `TeamRunJSON` and
   `pmTurn`, then exits with the run's terminal exit class;
5. if the run is already terminal, emits the snapshot + terminal event and exits
   immediately;
6. if the observer is killed, leaves the run untouched; a later invocation
   replays and reattaches.

`--stream` is already the product's NDJSON word. Do not add `watch`, `follow`,
`tail`, or `attach` synonyms. `show --stream` and `run --stream` share **one**
frame schema — the existing NDJSON events plus `teamRunCompleted` /
`teamRunFailed` terminal frames (`ContractRegistry+Milestone1.swift:502,1323`).
A second framing for the same events is a parallel contract and is banned.

**Bounded exit (required).** The stream ends at terminal **or** at an
attention-required boundary — a sourced blocker, a vendor wait, or an observer
budget expiring on a `terminalOnly` driver. It never blocks forever. The deleted
waiter carried the only timeout in this path (`--timeout 7200`,
`DetachedDispatch.swift:187`); an unbounded stream on a vendor-blocked run
recreates the silent-backgrounded-wait failure this repo has already suffered.

An attention exit emits one recovery `nextAction` that is never `showRun`
itself — a self-referential next action is a poll loop with better manners.
**Exception — `terminalOnly` observer-budget exit:** emit **no** `nextAction`
(see [PM ruling — terminalOnly](#pm-ruling--terminalonly-observer-budget-exit)
below). Sourced blocker and vendor wait still recover via `inspectBlocker`
(`alln ps` / `alln capacity`).

Exit-class propagation is **unconditional and documented**: `show --stream`
exits with the run's terminal exit class, so agents chain with `;`, not `&&`.
(`gh run watch` makes this opt-in via `--exit-status`; we are choosing the other
default deliberately, not inheriting a convention.)

### Detached acknowledgement

Default pull delivery returns one recommended command:

```json
{
  "kind": "run",
  "id": "run_123",
  "status": "dispatched",
  "nextAction": {
    "kind": "showRun",
    "command": "alln show run_123 --stream"
  }
}
```

The returned command is both observation and terminal delivery. There is no
separate waiter decision for the agent to remember.

`--delivery wake` remains an orthogonal notification receipt. It does not create
another run read surface, and the acknowledgement still carries the canonical
`show --stream` next action for optional inspection.

## Canonical live projection

Add one `observation` section to every `TeamRunJSON`; do not mint a parallel
`RunObservationJSON`, `TeamStatusResponse`, or GUI-only model.

**Three fields. That is the whole block.**

```json
{
  "teamRun": { "id": "run_123", "status": "running" },
  "observation": {
    "ownerState": "alive",
    "activityMode": "incremental",
    "lastActivityAt": "2026-08-01T20:14:00Z"
  },
  "nextActions": [
    { "kind": "showRun", "command": "alln show run_123 --stream" }
  ]
}
```

Binding semantics:

- `ownerState`: `alive | dead | unknown`; identity checked, never inferred from
  output recency.
- `activityMode`: `incremental | terminalOnly | unknown`; known from the resolved
  driver/runtime capability. This preserves the strongest finding from the
  superseded observability packet: expected silence must be distinguishable from
  missing measurement.
- `lastActivityAt`: the one observed clock fact. Named for the field that already
  exists on `TeamRun` and is already read by `StreamLiveness`
  (`StreamLiveness.swift:22-31`). Rename away from `lastProgressAt` /
  `progressStale`; those names claim more than is measured.
- all three are present with explicit states; an unsupported or unobserved value
  never silently masquerades as “fine.”

**Deliberately cut** (each was in the first draft; none survives its own
justification):

| Cut field | Why it dies |
| --- | --- |
| `silenceSeconds` | Arithmetic on `lastActivityAt` and now. `StreamLiveness.silenceAgeSeconds` already owns that math; publishing the derivative invites two answers. |
| `activityState` | A threshold verdict (`recent`/`silent`) over the same clock. The caller's budget is the caller's; shipping ours as truth is the `progressStale` mistake wearing a new noun. |
| `phase` | Duplicates `teamRun.status` plus `blocker`. A third lifecycle word agents must reconcile. |
| `lastActivityKind` | Decides nothing at snapshot time. The stream carries kinds where they are actionable. |
| `recentActivity` | The stream replays activity — that is its entire job. A bounded window in the snapshot is a second, weaker log. |
| `blocker`, `contradiction` | Already live on `TeamRunJSON.RunInfo`. Re-homing them into `observation` ships two blocker fields forever. |

Constraint on this section: a fourth field is added only when a **named host
Works Test decision failure** shows an agent could not choose its next move
without it. Additive fields are cheap after a cutover; speculative ones are
permanent. This packet exists to remove surface — its own contract must obey
that.

Terminal `repoDelta`, `outcome`, `answer`, `plan`, `pmTurn`, and artifacts remain
on the same `TeamRunJSON` contract. No feature is lost by consolidating the live
fields into it.

## New always-on bounded activity journal

This is the one slice that adds machinery, and the packet says so plainly: today
only the `run --stream` CLI branch appends events, so a `--no-wait` launch
records nothing to reattach to. Without this slice, reattachment is hollow and
the rest of the packet is a rename. "This phase does not add another
observability feature" is true of every section except this one.

Binding rules:

1. `RunService.run` produces one event sequence regardless of CLI output mode.
2. **Minimal event set**: status/blocker transitions, terminal settlement, and
   bounded tool summaries on `incremental` drivers only. Not a transcript.
   Exact durable kind string: **`worker.tool`** (payload: `runId`, `workerId`,
   `tool` title/name only — never args, file contents, or tool output).
   `terminalOnly` drivers produce none (expected silence). Past the journal
   retention cap (512 lines / 256 KiB) further tool appends are refused and
   swallowed; the run settles from `RunStore` (rule 8 — degrade, never block).
   Shipped as ORS-S02a2.
3. `alln run --stream` may render live high-frequency deltas, but choosing that
   flag must not decide whether the durable run is observable later.
4. Persist bounded summaries under an explicit retention/byte bound, not
   unlimited accumulated reasoning/output.
5. `RemoteRunEventJournal` remains internal storage. No public `eventsPath`.
6. The journal is a history of the same run truth, never a second run owner.
7. Sequence gaps and corruption raise typed errors on the **stream** path.
8. **Degrade, never block.** An append failure or corrupt journal drops
   `activityMode` to `unknown` and the activity window to unavailable; it never
   fails `alln show --json`. Run truth lives in `RunStore`, so a broken history
   must not be able to hide a finished run.

Proof obligation for this slice: a `--no-wait` launch (no stream flag anywhere)
produces a replayable event sequence. That is the assertion that makes reattach
real, and it is not satisfied by any test that launches with `--stream`.

## Hard cutover and deletion manifest

There are no external users. Replace the public grammar in one ship; do not
deprecate it gradually.

| Delete from the public product | Replacement | Cutover rule |
| --- | --- | --- |
| `alln team status <id>` | `alln show <id> --json` | Remove command registration, parser branch, help, examples, fixtures, and generated contracts. No forwarding alias. |
| `alln team result <id>` | `alln show <id> --json` | Same hard deletion. Terminal and non-terminal use one command. |
| `team status --wait-for terminal --timeout …` pull waiter | `alln show <id> --stream` | Replace detached acknowledgement atomically. No old waiter field. |
| Public `TeamStatusResponse` / `PersistedTeamStatusResponse` schemas | `TeamRunJSON.observation` | Delete or internalize after all consumers cut over. No dual public schema. |
| `delivery.path=wait` + `delivery.command` **on `alln run`** | one `nextAction.command` | Scoped to run dispatch (`DetachedDispatch.swift:187`). Loop/relay waiters are out of scope for this packet. |
| Proposed `alln ps --wait-for-change` | `alln show <id> --stream` | Do not build. `ps` stays fleet/operator inventory. |
| Private `run.json` / `events.jsonl` instructions | documented `alln show` | Remove from agent teaching and recovery text. Paths remain audit internals only. |
| Public `audit.runJournalPath` | `alln show <id> --json` | It is a **required** field in the public contract (`ContractSchema.swift:219`, `TeamRunJSONMapper.swift:17`). Publishing a support-directory path is the filesystem escape hatch this packet bans; deleting it is a contract break and belongs in this cutover. |
| `STATUS_WAIT_TIMEOUT`, `RESULT_NOT_READY` error codes | typed `show` errors | Deleted with their commands (`ContractRegistry+Milestone1.swift:1120,1135`). Their `agentAction` text teaches the dead waiter. |
| `team status --persisted` | `alln show <id> --json` | Deleted. The read path always reconciles; "non-live journal observation" was a mode that existed because the live path was untrusted. Forensics = `ownerState: unknown` + typed journal errors. |

Every `nextAction` that points at a **run id** flips to `show` — including
`PilotCLI.swift:964` and `:979`, which still emit `alln team status <devRunId>
--json`. A surviving teacher inside the product is the same defect as a
surviving alias.

Also remove and deny-list any retired grammar in:

- `ContractRegistry` and generated schemas/examples;
- `HelpTopicRegistry`, `TeachingSnippet`, bootstrap, menu next actions, doctor,
  error `agentAction` / `fixCommand` text;
- living operation/phase docs and scripts;
- CLI tests and fixtures;
- Mac/iOS command consumers;
- `RetiredVocabulary`, so the old commands cannot be re-taught accidentally.

Old invocations fail with `CLI_USAGE_ERROR` and may name the one replacement in
the error explanation. They never execute, forward, or alias.

Two more cutover obligations, named so no implementer has to guess:

- **AGENTS.md First Routing** gains a row for "run started, what is happening,
  where is the result" → `alln show`. A cutover that leaves the router pointing
  at deleted verbs has not shipped.
- **Mac/iOS sequencing is a decision, not a sweep.** Either they cut over in the
  same ship, or iOS is explicitly deferred behind the internal schema. Say which
  in ORS-S01; do not discover it at closeout.
- `latest` and `--full` stay for humans but are **banned from agent teaching and
  `nextActions`**. `latest` is racy under parallel Teams, and `--full` is a
  second snapshot shape. The acknowledgement already returns the exact run id.

### Mac/iOS sequencing decision (ORS-S01)

**Decision: both cut over in the same ship. No iOS deferral.**

Evidence (re-verified 2026-08-01): `Apps/AllnighteriOS` has zero references to
`TeamRunJSON`, `TeamStatusResponse`, `team status`, or `team result` — there is
no iOS consumer to defer. The only Mac consumer of `TeamRunJSON` is
`TeamRunJSONPresenter` (`Apps/AllnighterMac/Sources/TeamRunJSONPresenter.swift`
+ `Tests/TeamRunJSONPresenterTests.swift`). Additive `observation` decodes
without a Mac presenter change. The sole app-side `runJournalPath` mention is
the fixture argument at `TeamRunJSONPresenterTests.swift:52`; update it in the
same ORS-S03 commit that deletes the public field. Status schemas live only in
CLI/Core/Engine (see ORS-S03 worklist).

Contract/binary versions bump in the cutover. Public backward compatibility is
explicitly waived. Persisted journal decoding is an internal storage concern,
not permission to keep the old public commands or schemas.

## Surfaces that remain distinct

Consolidation does not mean forcing unrelated jobs into `show`:

- `alln menu --json`: what is available and runnable;
- `alln run`: start one run. `alln run --stream` survives as the **attended**
  surface — the constitution says attended is the hero and detach is not the
  product story — but it is banned from agent `nextActions`, so the
  attach-vs-reattach choice never reaches an agent;
- `alln show`: inspect, observe, and receive one run;
- `alln history`: find prior run IDs;
- `alln ps`: operator/fleet inventory and ownership control, not routine
  single-run supervision;
- `alln artifact show|export`: polished terminal receipt handling;
- `alln floor show`: human/GUI floor visualization, not the agent's live truth
  source;
- `alln kill`: explicit destructive process control;
- `alln loop`: durable multi-round PM↔dev object.

No capability above becomes an alias for `show`.

## Explicit non-goals

- No `delivery.eventsPath` or documented support-directory path.
- No legal `--no-wait --stream` launch combination as the solution. Detach and
  observation compose through reattachment.
- No new `watch`, `follow`, `tail`, `activity`, `logs`, or `attach` verb.
- No raw stdout dump in the default contract.
- No required free-text progress label written by the delegated agent.
- No prompt-only checkpoint law or requirement to write reports incrementally.
- No semantic “progressing” inference from process existence, output bytes, CPU,
  repository changes, or elapsed time.
- No mid-run object named `repoDelta`. Terminal `repoDelta` retains its existing
  meaning.
- No new daemon, cloud transport, or change to `RunService` ownership.
- No broad `ps` redesign in this phase.

## Deferred evidence, only if the hero proof still needs it

The following feedback is useful but must not inflate the first ship:

1. **Repository activity.** A later additive field may compare a run-start
   worktree snapshot with the current worktree and report
   `changedDuringRunWindow`, bounded paths, and `attribution: notProven`.
   It is supplementary evidence, never liveness or progress. This is not free:
   uncommitted/untracked files require a real baseline, and other local actors
   can change the repo.
2. **Richer activity excerpts.** If normalized recent activity remains too thin,
   extend the existing event summaries. Do not expose arbitrary stdout or add a
   second log protocol.
3. **Worker-authored checkpoints.** May be displayed when voluntarily emitted,
   but never become required reliability truth.

Do not authorize these until the hero Works Test proves the consolidated surface
and identifies a remaining concrete decision gap.

## Inference bans

| Junction | Owner | Possible bad inference | Ban | Negative proof |
| --- | --- | --- | --- | --- |
| owner identity → activity | `ProcessOwnership` + observation mapper | alive means advancing | Owner state and activity truth remain separate fields. | Alive terminal-only fixture stays `ownerState=alive` with `activityMode=terminalOnly` and a null `lastActivityAt`. |
| stream silence → stuck | activity projection | silence means dead/stalled | Surface `activityMode`; never derive semantic stuck from silence alone. | Terminal-only run remains healthy without fabricated activity. |
| repo change → agent progress | terminal `RepoDelta` / future repo observation | changed files prove agent advancement | Repository evidence is supplementary and unattributed. | External fixture change cannot flip activity/owner state. |
| event journal → run truth | `RunStore` / `RunService` | replay becomes a second state machine | Events project the journal; reconciliation and terminal state come from run/ownership owners. | Dropped event cannot change terminal run truth. |
| observer process → run ownership | `show --stream` adapter | watcher death means run death | Observer is read-only and disposable. | Kill watcher; run remains live and reattach succeeds. |
| old command → new command | CLI parser / retired vocabulary | compatibility forwarding preserves convenience | Old grammar fails; no alias or shim. | Old commands exit usage error without touching a run. |

## Implementation slices

### ORS-S00 — contract and red deletion gates

Before production edits:

Deletion first. It is the certain half of this packet, and with zero external
users it is also the cheap half.

1. Add contract tests for the canonical grammar and the absence of `team status`,
   `team result`, proposed `ps --wait-for-change`, and any `watch|follow|tail`
   alias.
2. Add a hostile teaching test: every generated/help/bootstrap/error command
   resolves, and retired single-run read grammar is denied.
3. Lock `show --stream` framing: immediate snapshot, replay, live events, exactly
   one terminal event, bounded attention exit, correct exit class.

No observation fixture matrix here. Fixtures written before the projection
exists freeze an imagined schema and then argue for it; the three-field
contract's fixtures land in S01 with the code that produces them.

Truth owner: `ContractRegistry` + `TeamRunJSON`.

### ORS-S01 — one snapshot projection

1. Make `alln show` reconcile ownership before mapping.
2. Project the three observation fields (`ownerState`, `activityMode`,
   `lastActivityAt`) once, in `TeamRunJSONMapper`. `blocker` and `contradiction`
   stay at their existing `TeamRunJSON` homes.
3. Land the observation fixtures with the code: incremental, terminal-only,
   unknown-owner, and terminal.
4. Cut Mac/iOS/shared consumers to that contract, and record the iOS sequencing
   decision named in the cutover rules.
5. Delete/internalize the public status projection and duplicate mapping paths.

Truth owner: `RunStore`/`ProcessOwnership` facts projected once by
`TeamRunJSONMapper`.

### ORS-S02 — always-on event record + reattach

1. Make accepted runs durably record the bounded semantic event sequence
   regardless of output mode — proven from a `--no-wait` launch, not a
   `--stream` one.
2. Implement `alln show <id> --stream` replay/follow/terminal behavior.
3. Prove observer cancellation cannot signal or settle the run.
4. Prove reattachment after observer death and after run terminal.

Truth owner: `RunService.run` + `RemoteRunEventJournal` as derived history.

### ORS-S03 — detached delivery flip + hard deletion

1. Replace the pull acknowledgement with one `nextAction.command` pointing to
   `alln show <id> --stream`.
2. Remove `team status`, `team result`, their flags/schemas/error codes, public
   `audit.runJournalPath`, and the old waiter from all public and teaching
   surfaces.
3. Add retired-vocabulary gates; regenerate contracts.
4. Add a **no-surviving-teacher gate**: `PilotCLI`, `HelpTopicRegistry`,
   `TeachingSnippet`, bootstrap, `CLI_Product_Spine.md`, and every error
   `agentAction` / `fixCommand` string must be free of the retired grammar.
5. Bump contract/binary versions; add the AGENTS.md First Routing row.
6. Sweep living docs and scripts in the same slice. No mixed old/new release.

Truth owner: `DetachedDispatch`/`RunCLI` acknowledgement + `ContractRegistry`.

### ORS-S03 deletion worklist (verified 2026-08-01)

One replacement read path for every entry below:

```text
alln show <run-id> --json
  → AllnighterCLI.runShow / showReadPath
  → TeamRunJSONMapper.map → TeamRunJSON (+ observation)

alln show <run-id> --stream
  → reattach + bounded terminal/attention delivery
  (replaces team status --wait-for and the pull waiter)
```

**Cross-reference, do not restate:** teaching/help/bootstrap/error `agentAction`
and related string offenders are owned by the ORS-S00b/S00c teaching gate
(`OneRunSurfaceTeachingTests`) plus the cutover deletion manifest above
(including `PilotCLI.swift:964,979`, `DetachedDispatch.swift:187`,
`HelpTopicRegistry`, `KILL_VERIFICATION_UNAVAILABLE` agentAction text, and
living-doc sweeps). S03 must clear that gate. This worklist is the **code
read/mapping surface** grep finds beyond that teaching set.

| Action | File · symbol · line | Notes |
| --- | --- | --- |
| **DELETE** | `AllnighterCLI.swift:82` — `case "team" where args.first == "status"` | Parser branch for public status command. |
| **DELETE** | `AllnighterCLI.swift:83` — `case "team" where args.first == "result"` | Parser branch for public result command. |
| **DELETE** | `AllnighterCLI.teamStatusSnapshot` `:1202` | CLI snapshot hop into `AsyncTeamService.status`. |
| **DELETE** | `AllnighterCLI.runTeamStatus` `:1212`–`:1320` | Full `team status` path: plain / `--persisted` / `--wait-for` + timeout exits. |
| **DELETE** | `AllnighterCLI.runTeamResult` `:1323`–`:1351` | Second terminal read path; maps `TeamRun` via `TeamRunJSONMapper` only when ready. |
| **DELETE** | `AsyncTeamService.status(runId:)` `:567`–`:630` | Public dual projection (reconcile + `TeamStatusResponse` + wait guidance). |
| **DELETE** | `AsyncTeamService.waitForStatus` `:635`–`:670` | In-process status waiter; replaced by `show --stream`. |
| **DELETE** | `AsyncTeamService.ResultOutcome` `:693`–`:697` | Ready/not-ready/notFound split that exists only for `team result`. |
| **DELETE** | `AsyncTeamService.result(runId:)` `:699`–`:718` | Terminal-gated second read; emits `RESULT_NOT_READY`. |
| **DELETE** | `AsyncTeamStatusMapper.statusResponse(for:)` `:115`–`:144` | Public status body builder. |
| **DELETE** | `AsyncTeamStatusMapper.withWaitGuidance` `:88`–`:99` | Status-only nextAction/waitHint stamping. |
| **DELETE** | `AsyncTeamStatusMapper.nextAction(for: TeamStatusResponse)` `:72`–`:86` | Status-projection decision matrix. |
| **DELETE** | `AsyncTeamStatusMapper.nextAction(for: RunLifecycle)` `:64`–`:69` | Emits `fetchResult` / `waitForStatus` nextActions. |
| **DELETE** | `AsyncTeamStatusMapper.workers(for:)` `:101`–`:113` | `TeamStatusWorker` rows; not on canonical `TeamRunJSON`. |
| **DELETE** | `AsyncTeamStatusMapper.nextPollAfterMs` / `waitHintSeconds` / `resultAvailable` `:41`–`:58` | Poll-loop vocabulary for status/result envelopes. |
| **DELETE** | `AsyncTeamStatusMapper.currentStage(for:)` `:26`–`:39` | Status-only stage string; cancel/show do not need it. |
| **INTERNALIZE** | `AsyncTeamStatusMapper.liveStatus(for:)` `:14`–`:24` | Keep as non-public lifecycle projection for cancel/reconcile/`StalledWorkDetector` — **not** a public read surface. |
| **DELETE** | `AsyncTeamContracts.TeamStatusResponse` `:212` | Public dual schema. |
| **DELETE** | `AsyncTeamContracts.PersistedTeamStatusResponse` `:355` | `--persisted` envelope. |
| **DELETE** | `AsyncTeamContracts.TeamStatusWorker` `:193` | Nested status-only type. |
| **DELETE** | `AsyncTeamContracts.TeamStatusBlocker` `:117` | Status-projection blocker shape; run blocker stays on `TeamRun` / existing `TeamRunJSON` home. |
| **DELETE** | `AsyncTeamContracts.TeamStatusWaitTarget` `:383` | `--wait-for` parse/match. |
| **DELETE** | `AsyncTeamContracts.TeamStatusWaitOutcome` `:410` | In-process wait outcome. |
| **DELETE** | `AsyncTeamContracts.TeamResultNotReady` `:426` | `team result` not-ready envelope. |
| **DELETE** | `AsyncTeamNextAction.waitForTerminal` `:73`, `fetchResult` `:81`, `waitForStatus` `:89` | Factories that hard-code retired commands (also teaching-gate offenders). |
| **DELETE** | `ContractRegistry.OutputSchema.teamStatusResponse` / `.persistedTeamStatusResponse` (`ContractRegistry.swift:124`) | Registry schema cases for deleted outputs. |
| **DELETE** | `ContractRegistry+Milestone1` `CommandSpec("team status")` `:406`–`:416` | Command registration, flags (`--persisted`, `--wait-for`, `--timeout`), `outputSchema`. |
| **DELETE** | `ContractRegistry+Milestone1` `CommandSpec("team result")` `:418`–`:422` | Command registration. |
| **DELETE** | `ContractRegistry+Milestone1` `ErrorSpec("STATUS_WAIT_TIMEOUT")` `:1120` | Error code deleted with the waiter. |
| **DELETE** | `ContractRegistry+Milestone1` `ErrorSpec("RESULT_NOT_READY")` `:1135` | Error code deleted with `team result`. |

Not on this list (out of scope or already covered elsewhere): `team cancel` /
`team reconcile` (not single-run *read* surfaces); `TeamStartResponse` (launch
ack — nextAction command strings flip with the teaching/ack sweep, not a second
snapshot schema); public `audit.runJournalPath` (deletion manifest row; Mac
fixture at `TeamRunJSONPresenterTests.swift:52` updates in the same S03
commit).

### ORS-S04 — live host Works Test and closeout

Run the complete flow from inside at least Codex and one other supported host.
Promote keepable vocabulary/help law, archive this packet, and do not claim
completion from fixture-only proof. Closeout fails if any Mac/iOS consumer still
decodes the deleted schema.

## Works Test

Hero scenario:

1. From a supported host agent, dispatch a real mutating run:

   ```bash
   alln run "<bounded work>" --project . --model <id> --no-wait --json
   ```

2. Execute **only** the returned `nextAction.command`.
3. Assert an immediate snapshot identifies lifecycle, owner state, activity mode,
   last activity, and any blocker.
4. Observe at least one normalized activity event **of `kind=worker.tool`**
   (dotted family; packet shorthand was `kind=tool`), on work guaranteed to call
   tools — durable in `events.jsonl`, projected on `show --stream` as
   `workerActivity` with `activityKind: "tool"`. A status-transition event alone
   would pass a weaker assertion while proving nothing about activity capture.
   (ORS-S02a2)
5. Kill only the `show --stream` observer. Verify the agent seat remains alive
   **via `ProcessOwnership` directly** — asking `show` whether `show`'s death
   mattered is a proof that cannot fail.
6. Execute the same command again. Verify bounded replay, no duplicate terminal,
   and continued observation.
7. Receive the terminal `TeamRunJSON` + `pmTurn` with the correct exit class.
8. Repeat with a genuinely terminal-only/silent fixture. Verify silence is
   explicitly expected, owner truth remains separate, and no progress is
   fabricated.
9. Repeat with a vendor-blocked/attention-required run. Verify the stream exits
   bounded, with a recovery `nextAction` that is not `showRun`.
10. Run the old commands and assert usage failure without execution or
    forwarding.
11. Confirm no step uses `ps`, `git status`, a private journal path, a polling
    loop, or a packet-specific checkpoint instruction.

Focused proof commands must use the repository wrappers:

```text
scripts/swift-test.sh --filter OneRunSurface        # created red-first in ORS-S00
scripts/swift-test.sh --filter RetiredVocabulary    # old grammar denied, teaching clean
scripts/swift-test.sh --filter DetachedDispatch     # ack flips to show --stream
bash scripts/check.sh                               # closeout only
```

`OneRunSurface` is created red-first in ORS-S00 — a filter that matches nothing
reports success. `RunCLIStreamAdapter` is a launch-stream suite and must not be
cited as reattach proof; reattachment is a different code path.

## Proof gap

Not waived: a real host-boundary run is required. Fixtures prove framing,
deletion, and projection; they cannot prove that an actual vendor CLI emits,
detaches, survives observer death, reattaches, and terminal-delivers from inside
a supported host.

## Done when

- [x] An agent learns only `alln menu`, `alln run`, and `alln show` for the hero
  single-run workflow. (ORS-S00–S03 teaching + deletion gates)
- [x] `alln show --json` is the complete snapshot for every lifecycle state, and its
  `observation` block is three fields. (ORS-S01)
- [x] `alln show --stream` replays, follows, terminal-delivers, and always exits —
  at terminal or at an attention boundary. (ORS-S02)
- [x] Detached acknowledgement returns one canonical observe-and-deliver action. (ORS-S03)
- [x] Observer death cannot affect run ownership. (ORS-S02 ownership proofs)
- [x] `team status`, `team result`, old wait flags/schema, and private-path teaching
  are deleted from every public/living surface. (ORS-S03a–e)
- [x] No alias, shim, dual schema, or transition period exists.
- [x] Unknown and expected silence are explicit; liveness and activity are not
  conflated. (incl. terminalOnly PM ruling — no fabricated recovery nextAction)
- [ ] The owner-visible host Works Test passes from two real agent hosts. (**ORS-S04**)
- [ ] Keepable law is promoted to code/standing docs and this packet is archived. (**ORS-S04 closeout**)

## Blocking questions

None. The founder authorized the hard-cutover posture and the packet chooses the
canonical command, contract, deletion set, and proof boundary.

## PM ruling — terminalOnly observer-budget exit

**PM ruling — founder review at closeout** (recorded ORS-S03e).

The packet requires the attention exit to emit one recovery `nextAction` that is
never `showRun`. For a sourced blocker and a vendor wait that resolves cleanly,
that recovery is `inspectBlocker` → the holder/FIFO (`alln ps`) and capacity
(`alln capacity`) surfaces.

For the `terminalOnly` observer-budget expiry there is **no honest non-circular
recovery**: nothing is wrong, nothing needs the caller, and the only real next
move is to observe again — which is exactly the self-referential action the
packet bans.

**RULING:** emit **no** `nextAction` for the terminalOnly budget exit; label the
silence expected (`silenceExpected: true`, `activityMode: terminalOnly`).

**Rationale:** inventing an action where none is warranted is the action-shaped
form of fabricating a verdict, which is the failure mode this packet exists to
prevent. Code: `AllnighterCLI.emitObserverBudgetAttention` (nextAction nil).

## Out-of-packet defects found by the ORS gates

Hostile gates paid for themselves beyond the cutover deletion set:

- **`MenuCatalog` authored-copy crash** — `model_gpt_luna` `useWhen` length 54 >
  48. Fixed in `236fdf37`; runtime now degrades and a build-time gate was added.
- **Seven undeclared `alln loop` verbs** — implemented in CLI but missing from
  `ContractRegistry`; declared in `9baefbed` (contract 9.1.0 additive).

## Spec Review record (2026-08-01)

Reviewed by `code_spec_review` (5 seats). The deletion half was upheld
unanimously; the addition half was cut. Call: *ship the three-command cutover,
but reuse the liveness dialect we already built.*

Amendments applied above:

1. `observation` cut 9 fields → 3, in the shipped `StreamLiveness` dialect. The
   first draft banned "minting a parallel model" and then minted one.
2. `show --stream` gains a bounded attention-required exit. The deleted waiter
   carried the only timeout in this path; removing it without a replacement
   bound would have reintroduced a known silent-wait failure.
3. The journal slice is relabeled honestly as new machinery, with a minimal
   event set, retention bound, and degrade-never-block rule.
4. Delete-first re-slice; the speculative six-state fixture matrix is dropped.
5. Six verified manifest gaps named: `audit.runJournalPath`, `PilotCLI`
   teaching, `STATUS_WAIT_TIMEOUT` / `RESULT_NOT_READY` / `--persisted` fates,
   `parked` lifecycle wording, AGENTS.md routing, Mac/iOS sequencing.
6. Works Test hardened where three steps could have passed without proving the
   hero.

Standing flags, not resolved by this packet:

- The premise ("agents conclude Allnighter cannot observe the work") cites no
  recorded incident; this repo's failures here were liveness *lies*, not verb
  confusion. If the two-host Works Test shows agents never read the observation
  fields, **cut further — do not defend them**.
- Two seats voted to delete `alln run --stream` outright. Rejected on
  constitutional grounds (attended is the hero), not on evidence.

## Live Works Test record (2026-08-01)

Host 1 = Claude Code. VERIFIED only; two-host proof remains open (ORS-S04).

- Binary **0.12.0** / contract **9.2.0** installed.
- Detached ack returns one `nextAction.command` `alln show <id> --stream`; no delivery block.
- `alln team status` and `alln team result` exit `CLI_USAGE_ERROR` (exit 2), naming `alln show`, executing nothing.
- Real `--no-wait` launch (no stream flag) wrote `events.jsonl` with `run.status_changed`, `worker.status_changed`, `stage.started`, `stage.completed` and **no** transcript kinds.
- `show --stream` emitted snapshot → bounded replay (`replayed: true`) → live follow → exactly one `teamRunCompleted`, exit 0.
