# Agent Team Loop — Mac compose + CLI parity

Status: **Ready for Implementation** (hardened 2026-07-29 — adversarial Grok 4.5
pass via `alln run --model model_grok`, run `A5832C88-3AC7-41CA-9BBE-7EE27E901BF7`;
all open questions resolved)
Owner: AllnighterEngine (`RelayCoordinator`, `RelayState` / `RelayStateStore`,
`RelayPMPrompt`) + AllnighterCLI (`RelayCLI`, `ContractRegistry`, process
ownership surface) + Mac (`RoutingComposer`, `RelayLaunchView` /
`RelayLaunchViewModel`, thread chrome, `HomeView` spinner removal)
Created: 2026-07-29
Revised: 2026-07-29 — adversarial review + full freeze

Ephemeral build packet. At closeout: promote Loop vocabulary into
`docs/workflows/Product_Vocabulary.md`, help topics, and retire the project-header
spinner; archive this packet. **Code remains SSOT** for fields, settlement, and
stop/status wire shape.

---

## A) Adversarial review (Grok 4.5)

### Verdict

The draft intent is right (Mac Loop = unattended Relay; Pilot CLI-only; CLI-first
Stop/Status; kill the spinner). **As written it was not Ready for Implementation.**
It left kickoff injection, stop settlement, Mac process survival, and Loop↔Relay
teaching underspecified enough that a competent implementer could ship a GUI that
dies when the Dock app quits, a Stop that races the loop process, or a kickoff
that never reaches the first PM turn.

### What was wrong / weak

1. **Mac start does not survive the app today.** `RelayLaunchViewModel.start`
   does `claimStart` then `Task { await coordinator.complete(...) }` **in the Mac
   app process**. Owner.pid is the app. Quitting the Dock app orphans the relay
   (`owner process died mid-round`). Packet waved at Round Survives without
   mandating detach for the Mac path. That breaks "unattended."
2. **Kickoff message was vapor.** "first PM prompt injection + durable field if
   needed" is not an owner. No field name, no clear/clear-not rule, no mutual
   exclusion with `founderNote`, no empty-trim refuse code.
3. **Stop vs `alln kill` was muddy.** `ProcessOwnershipSurface.killRelay` stamps
   `stoppedReason: "killed"`, may refuse already-terminal escalated, does **not**
   write a PM Turn, and targets turn trees — not a clean founder-stop product verb.
   Teaching `alln kill` as Loop Stop would violate PM Turn Delivery (failure/
   terminal still needs `pmTurn`) and resume eligibility law.
4. **Open questions + "Ready"** violated SSOT Feature Workflow. ATL-S00 as a
   "spec freeze" build slice is process theater — freeze in the packet or mark
   Blocked.
5. **Loop vs Relay dual naming** invited agents to invent `pair loop` or teach
   "Start relay" forever. No deny-list / teaching table.
6. **Composer integration** underspecified relative to Model | Team (which are
   send routes, not modal openers). Risk of Loop send becoming a Chat turn.
7. **Slice acceptance criteria** too soft for a sloppy implementer (no negative
   tests for spinner residual, Pilot entry, or stop without PM Turn).
8. **`RELAY_INVALID_STATE` explain** today is resume-only ("Only an escalated
   relay can be resumed"). Stop must not reuse that string blindly.

### What changed and why

| Change | Why |
| --- | --- |
| Resolved all open questions in-packet | Ready means no TBD for implementers |
| Specified kickoff owner: `Config.kickoffMessage` → durable `RelayState.kickoffMessage` → `RelayPMPrompt.Context.kickoffMessage` | One injection path; survives detach; not resume's `founderNote` |
| CLI flags: `--message` / `--message-file` (mutex), required non-empty | Matches resume altitude; avoids overloaded "handoff" (PM→dev term) |
| New public `RelayCoordinator.stop(relayId:reason:)` + `pair relay stop` | Product verb; settlement order fixed; not a thin alias of `alln kill` |
| Stable `RelayState.founderStoppedReason = "founder stopped"` | Resume eligibility, teaching, Works Tests |
| Mac Loop start **must** detach (same survival as CLI `--no-wait`) | Unattended law; app quit must not orphan the loop |
| ATL-A modal locked; composer Loop text = kickoff prefills sheet | No Chat send; no ATL-B in v1 |
| Inference bans, error codes, per-slice acceptance | Fail sloppy implementers |
| Contradiction section vs PTD / RSC / Product Vocabulary | No silent law drift |
| Dropped ATL-S00 as code slice | Packet freeze is the freeze |
| Status remains Ready only after above | Honest readiness |

### Residual risk (accepted, not Blocked)

- Moving or wrapping `DetachedDispatch` so the Mac (Engine-linked, not CLI-linked)
  can detach without inventing a second spawn stack is an **engineering choice
  inside ATL-S03**, constrained by "one detach primitive, same argv contract as
  CLI `--no-wait`." Not a product TBD.
- Sidebar amber-dot noise (old S05) stays optional hygiene.

---

## B) Finalized packet

### Founder Intent

```text
Raw request:
  Surface Relay as a first-class run kind in the Mac app — not a hidden project
  spinner. Composer gains Model · Team · Loop. Loop starts an unattended Relay
  with a kickoff brief (same habit as briefing Opus in Claude Code). Opening a
  Loop/Relay thread offers Status + Stop with CLI parity. Pilot from the Mac
  app is impossible and must stay impossible.

Prior art:
  Claude Code / Cursor: brief once, then the agent drives.
  git / gh / kubectl: start + status + stop/kill are first-class on one object.
  Allnighter CLI already: detached relay survival (Round Survives), PM Turn
  delivery + waiters (PM Turn Delivery), Answer & resume (R-S08).

Product value:
  Founder's daily unattended PM↔dev loop is usable from the Dock app without a
  second product language — and without depending on the app process staying
  alive.

Trusted workflow slice:
  Compose → Loop → kickoff brief (+ doc / PM / dev / ceilings) → Start loop
    → thread shows rounds
    → Status (RelayJSON / same as CLI)
    → Stop (founder stopped settlement)
    → Escalate → Answer & resume (shipped; unchanged)

Non-goals:
  - Pilot / supervised loop from the Mac app (CLI-only; app is never the PM seat).
  - Renaming CLI verbs from `pair relay*` to `pair loop*`.
  - Replacing `pair pilot*` verbs.
  - Capacity strip / utilization (orthogonal).
  - Full sidebar unread redesign (optional ATL-S05 only).
  - iOS Loop surface.
  - Work Recovery envelope (open WRC packet — do not fork).
  - Making `alln kill` the taught founder Stop (it remains process-ownership).
```

### Product law (locked)

1. **Loop (Mac noun) = unattended spawned Relay.** Both PM and dev seats are
   spawned CLI agents. The human briefs once; does not author round handovers.
2. **Pilot = supervised / external PM** and lives only where a live agent CLI
   session *is* the PM. The Mac app must not offer Pilot start, handoff, or
   "continue as PM in Chat."
3. **Kickoff brief** is round-1 context for the **spawned PM** only. It is not
   Chat, not a mid-flight injection channel, and not the PM→dev handover.
4. **CLI-first.** Every Mac Loop action presents an `alln` / Engine contract.
   No GUI-only stop, no GUI-only status DTO, no second JSON schema.
5. **Unattended means process-independent.** A Loop started from the Mac must
   outlive closing the launch sheet **and** quitting the Mac app, same as
   `pair relay --no-wait` outlives a killed CLI caller.
6. **After start, Compose is not the control surface.** Thread owns Status,
   Stop, Answer & resume. Mid-flight founder input stays escalate → resume.
7. **Stop is founder abandonment.** Durable `stopped` + reason
   `founder stopped`. Not resumable. Allowed from `running` and `escalated`.
   Idempotent on already-terminal `done` / `stopped`.

### Naming (teaching rules — hard cutover)

| Surface | Word | Allowed? | Meaning |
| --- | --- | --- | --- |
| Mac composer mode | **Loop** | Yes | Start an unattended Agent Team Loop |
| Help / docs longer form | **Agent Team Loop** | Yes | Same machine as unattended Relay |
| CLI / durable / JSON | **Relay**, `pair relay*` | Yes | Existing substrate — **do not rename** |
| CLI-only supervised | **Pilot**, `pair pilot*` | Yes | External PM; never in Mac compose |
| GUI entry | ~~Start relay~~ spinner | **No after ship** | Retired affordance |
| Invented CLI | `pair loop`, `--loop` | **No** | Deny-list / never teach |

**Teaching one-liner (reproduce or link, do not paraphrase into a second product):**

> Mac **Loop** starts an unattended **Relay** (`alln pair relay`). Status and
> Stop use `pair relay-status` / `pair relay stop`. **Pilot** stays CLI-only.

At closeout, add a short **Loop** row to `Product_Vocabulary.md` human layer
pointing at Relay machine substrate — no alias that renames the CLI.

### CLI substrate to reuse (do not rebuild)

| Shipped | Loop/Mac obligation |
| --- | --- |
| `pair relay --no-wait` + detach claim (RSC) | Mac start uses **the same survival contract** (detached child, ack after durable accept) |
| `pair relay-status --wait-for parked\|terminal` + `pmTurn` (PTD) | Status surface = `RelayJSON` (+ embedded `pmTurn`), not a bespoke GUI DTO |
| Local notify on escalate/land (URN) | Keep; Loop does not replace banners |
| `pair relay-resume` + GUI Answer & resume | Keep; Stop must not break resume eligibility rules for *other* reasons |
| `alln kill` / Process Ownership | Mechanism for trees; **not** the taught founder Stop; stop must still stamp relay terminal + PM Turn |
| WRC (open) | Orthogonal; Stop does not invent a recovery envelope |

**Gaps this packet closes:**

- No kickoff brief on `pair relay` (CLI or GUI).
- No first-class `pair relay stop`.
- Mac has no Status/Stop chrome; start is spinner + in-process `complete`.
- Project-header spinner is the wrong front door.

---

### Current Mac / Engine state (lie-prone)

| Surface | Today | Problem |
| --- | --- | --- |
| Project header spinner | "Start relay" (`arrow.triangle.2.circlepath`) | Reads as refresh; buried; dual entry after Loop |
| `RelayLaunchView` | Doc + PM + Dev + ceilings | Good form; no kickoff; wrong front door; in-process loop |
| Composer | Model / Team only | Missing Loop run kind |
| Kickoff | Missing on Config / State / Prompt | Founder's Opus brief habit unsupported |
| Thread open | Round history + Answer & resume | No Status, no Stop |
| `alln kill` on relay | Process stamp path | Not founder-stop product law; no PM Turn write in that path |
| Amber rail dots | Generic attention | Historical SPEC noise (optional S05) |

---

### Target experience

#### Start (Compose) — ATL-A locked for v1

```text
Composer mode tabs:  Model  |  Team  |  Loop
```

| Mode | Send means |
| --- | --- |
| **Model** | Chat / Default Team turn (unchanged) |
| **Team** | Send to team (unchanged) |
| **Loop** | **Never** a Chat/run send. Opens / drives the Loop launch sheet |

**Loop mode behavior:**

1. Placeholder: `Brief the PM — what should this loop deliver?`
2. Composer text = kickoff brief body (may be empty until sheet; sheet enforces).
3. Primary control (Send / Return) opens existing `RelayLaunchView` (or identical
   twin) with:
   - **Kickoff** field at top — required, prefilled from composer text, editable
   - Doc, PM seat, Dev seat, ceilings (existing)
   - Primary button label: **Start loop** (not "Start" / not "Start relay")
4. Success:
   - Dismiss sheet
   - Select thread where `threadId == relayId`
   - Reload threads
   - Do **not** focus Chat as if the user were Pilot
   - Prefer clearing Loop composer text after successful start
5. Failure: keep sheet open; show validation / refusal (including
   `RELAY_ALREADY_ACTIVE` cause-specific copy — already partially done).

**ATL-B (inline chips) is out of v1.** Do not implement.

#### Live control (relay thread chrome)

When the open thread is a Relay (`threadId` maps to a `RelayState` id):

| Affordance | Behavior | Contract twin |
| --- | --- | --- |
| **Status** | Pill from durable status + panel/popover with structured fields: `status`, `rounds`, `note`, `stoppedReason`, last `pmTurn.reason` / report summary | `RelayJSON` via Engine project of `RelayCoordinator.status` / store load — same fields as `alln pair relay-status --relay <id> --json` |
| **Stop** | Confirm dialog → `RelayCoordinator.stop` (same settlement as CLI) | `alln pair relay stop --relay <id> [--json]` |
| **Answer & resume** | Unchanged; only when `isResumable` | `pair relay-resume` |
| Optional | **Copy status command** | Paste-ready `alln pair relay-status --relay <id> --json` (and optionally the PTD waiter when status is non-terminal) |

Stop confirm copy must say the loop will not resume; work in flight is abandoned.

#### Sidebar / header

- **Remove** project-header relay spinner in the same slice that ships Loop entry.
- No second chrome glyph required to start a Loop.
- Opening the Loop thread is how you get Status/Stop.
- ATL-S05 (optional): prefer one project-level "N loops need you" over amber on
  every historical `PM Relay: SPEC` row.

---

### SSOT

| Concern | Owner |
| --- | --- |
| Relay lifecycle + stop settlement | `RelayCoordinator.stop` + `RelayStateStore` |
| Kickoff brief | `RelayCoordinator.Config.kickoffMessage` → durable `RelayState.kickoffMessage` → `RelayPMPrompt.Context.kickoffMessage` |
| CLI verbs / flags / errors | `RelayCLI` + `ContractRegistry+Milestone1` |
| Detached survival | Same detach/accept path as `pair relay --no-wait` (CLI: `DetachedDispatch` / `DetachedHandoff`; Mac must not invent a second one) |
| Mac start presenter | Composer Loop mode + `RelayLaunchView(Model)` |
| Mac status/stop presenter | Thread chrome → Engine (`stop` / status project) — **no parallel RelayDTO** |
| Teaching | `HelpTopicRegistry`, recipes, `MenuSelectionCopy` if menuAction, `RetiredVocabulary` |
| Vocabulary closeout | `docs/workflows/Product_Vocabulary.md` |

#### Lie-prone layers

- SwiftUI Stop that kills a process but leaves `status == running`
- Status UI that invents lifecycle from thread turn prose
- Calling Loop "Pilot" or offering Pilot in the app
- Spinner still discoverable after Loop ships
- Kickoff only in GUI (CLI must accept the same brief)
- Mac `complete` still running inside the app process after this packet
- Teaching `alln kill` as the Loop Stop
- Reusing `founderNote` for kickoff (resume semantics would clear/re-inject wrong)

#### New semantic rules

1. **Kickoff brief (required on start for Mac Loop; optional on CLI only if empty
   refused when flag present — see CLI).** Durable on the relay; injected into
   **first PM turn only**; not the PM→dev handover.
2. **`pair relay stop`** is the founder stop verb: identity-checked teardown of
   the relay **owner process** and in-flight turn trees, durable
   `status=stopped`, `stoppedReason=founder stopped`, PM Turn write, thread
   sync. Idempotent if already `done`/`stopped`. Allowed on `escalated`
   (abandon). **Not resumable.**
3. Mac Loop start / status / stop present (1)–(2) and existing status/resume.

#### Duplicate truth to delete

- Project-header "Start relay" spinner as product entry
- Any GUI-only cancel that only kills a process
- In-process Mac `complete` as the production Loop run path

---

### Kickoff brief — exact field / owner (no ambiguity)

#### Data flow

```text
CLI:  --message TEXT | --message-file PATH
        ↓
RelayCoordinator.Config.kickoffMessage: String?
        ↓  (claimStart / first persist)
RelayState.kickoffMessage: String?     // durable, Codable
        ↓  (first PM prompt assemble only)
RelayPMPrompt.Context.kickoffMessage: String?
        ↓
Section in assembled prompt:
  ## Kickoff brief (founder)
  <verbatim text>
```

#### Rules

| Rule | Detail |
| --- | --- |
| **Required** | After trim, non-empty. Empty / whitespace-only → refuse start (`CLI_USAGE_ERROR` on CLI; validation issue id `kickoff` on Mac). |
| **Mutex** | `--message` and `--message-file` mutually exclusive. Both → usage error. File missing/unreadable → usage/operational fail before claim. |
| **Size** | No silent truncation in durable store. If a future cap is needed, refuse loud — do not clip. v1: no artificial cap beyond process argv/file practicality; prefer `--message-file` for long briefs. |
| **Not `founderNote`** | `founderNote` remains **resume-only** (escalation answer). Kickoff must not write `founderNote`. |
| **Injection timing** | Inject when assembling the PM prompt for the first PM turn of this relay that has a non-nil `kickoffMessage` — practically: `roundNumber == 1` and no prior completed PM turn, **or** simply "include while `state.kickoffMessage != nil` and this is the first PM assemble," then **clear `kickoffMessage` after that PM turn is durably recorded** (mirrors consume-once of `founderNote`). Later rounds never re-inject. |
| **Resume / adopt** | Resume does not re-require kickoff. Adopt does not invent a kickoff. If first PM turn never ran and kickoff still on state, first PM after resume-from-orphan may still see it (consume-once still applies). |
| **Wire** | Optional on `RelayJSON` as `kickoffMessage` only while still pending consume **or** omit after clear — implementers: **omit or null after consume**; do not leave stale brief as if live mid-flight chat. Status need not show the full brief after start; durable audit may remain in prompt logs of the PM run. Prefer not bloating forever status: clear on consume is enough. |
| **Mac** | Sheet field label: **Kickoff** (subtitle: "Brief the PM once — not a chat"). Prefill from Loop composer text. |

#### Prompt placement

In `RelayPMPrompt.assemble`, after the standing PM identity / doc / rounds-left
blocks and **before** "Round 1 — no dev report yet" / dev-report blocks:

```markdown
## Kickoff brief (founder)
<verbatim kickoffMessage>
```

Only when `context.kickoffMessage` is non-nil non-empty. Never paraphrase.

---

### Stop settlement — exact order

**Truth owner:** `RelayCoordinator.stop(relayId: String, reason: String = RelayState.founderStoppedReason) -> Result<RelayState, StopRefusal>`

Add:

```swift
// RelayState
public static let founderStoppedReason = "founder stopped"
```

#### Eligibility

| Prior status | Behavior |
| --- | --- |
| `running` | Full stop settlement (below) |
| `escalated` | Stamp founder stop (abandon); no process required; PM Turn; **not resumable** after |
| `awaitingPM` | CLI may stop (abandon pilot park); Mac will not create these. Stamp founder stop; PM Turn |
| `done` | Idempotent success: return current state; **do not** rewrite `stoppedReason`; **do not** bump PM Turn sequence |
| `stopped` | Idempotent success: return current state; leave existing `stoppedReason` (ceiling / orphan / founder) unchanged; no second PM Turn |

#### Settlement order for `running` (and any status with a live owner / turn tree)

Within one critical section (prefer relay dispatch flock for the id so stop cannot
race a concurrent resume/adopt claim):

1. **Load** durable state; if missing → `RELAY_NOT_FOUND`.
2. **If already terminal** per table → idempotent return (no kill storm).
3. **Signal relay owner process** (identity-checked via `owner.pid` / store owner
   marker) — this is the detached `alln` (or app-era) loop process. Prefer TERM
   then short grace; do not invent recycled pids.
4. **Signal in-flight turn trees** (turn-owner file, then last-round owner) —
   same identity-checked helpers orphan reconcile / kill path already use.
5. **Clear** turn-owner file + `laneBlocked`.
6. **Stamp round in flight** if open: `outcome = stopped`, `devTurnEndReason =
   killed` when a turn was signalled, `finishedAt = now`.
7. **Stamp relay:** `status = stopped`, `stoppedReason = founder stopped`
   (only when transitioning into founder stop; never overwrite a prior terminal
   reason on idempotent path).
8. **Write PM Turn** via the same `persistPMBoundary` path as ceiling stop
   (`reason = stopped`, report = settled dev report if any, `nextCommands` =
   at least `alln pair relay-status --relay <id> --json`). Failure to write PM
   Turn is a hard failure of stop (same severity as other PM boundaries — do not
   publish undeliverable terminal without receipt; match existing
   `persistPMBoundary` policy).
9. **Persist** state + **threadProjector.sync** (stopped system event).
10. **Return** projected state / `RelayJSON`.

#### Stop vs `alln kill`

| | `pair relay stop` | `alln kill <relayId>` |
| --- | --- | --- |
| Product intent | Founder abandoned the Loop | Process-ownership red button |
| `stoppedReason` | `founder stopped` | often `killed` |
| PM Turn | **Required** on transition | Not a PM Turn product path today — do not teach as delivery |
| Escalated | Allowed (abandon) | May refuse already-terminal |
| Taught in Mac Stop | **Yes** | **No** |
| Resumable after | **No** | Orphan/`killed` semantics differ; do not merge |

Implementers may **reuse** identity-checked terminate helpers from Process
Ownership inside `RelayCoordinator.stop`, but must **not** call
`ProcessOwnershipSurface.kill` as the whole product path without fixing PM Turn
+ founder reason + escalated abandon.

#### Stop vs resume eligibility

After founder stop: `isResumable == false` (status stopped, reason ≠ orphan
reconciled). Answer & resume UI must hide/disable.

#### Concurrent stop + in-flight round

- `RELAY_ROUND_IN_FLIGHT` is for **start/resume/adopt dispatch**, not for stop.
- Stop must win: founder abandonment preempts the round. Do not refuse stop
  because a round is in flight.
- After stop stamps terminal, a racing resume/adopt must fail not-resumable /
  invalid state — not restart work.

---

### CLI surface (ship first)

```text
# Start (extend)
alln pair relay --doc <path> --project <id|path> \
  --pm-model <id> --dev-model <id> \
  [--message <text> | --message-file <path>] \
  [--until HH:MM] [--max-rounds N] [--idle-timeout <sec>] \
  [--no-wait] [--delivery wake] [--json]

# Status (exists — GUI must use the same fields)
alln pair relay-status --relay <id> \
  [--wait-for parked|terminal --timeout <sec>] [--json]

# Stop (new nested verb — grammar matches `pair relay adopt`)
alln pair relay stop --relay <id> [--json]
# → RelayJSON status=stopped, stoppedReason="founder stopped" (on transition)
# → exit 0 on success including idempotent terminal

# Resume (exists)
alln pair relay-resume --relay <id> --answer <text> [--no-wait] [--json]
```

#### Kickoff flags

| Flag | Rule |
| --- | --- |
| `--message <text>` | Kickoff brief body |
| `--message-file <path>` | Read UTF-8 file as brief |
| Mutex | Both set → `CLI_USAGE_ERROR` |
| Empty after trim | `CLI_USAGE_ERROR` ("kickoff brief is required when --message/--message-file is set" **and** Mac always requires it). **CLI without either flag:** v1 **allows** omit for back-compat with existing scripts/tests — but **Mac Loop always supplies `--message`**. Teaching: "always pass a brief." Optional later hard-require is out of scope. |

Rationale for CLI-optional / Mac-required: do not break existing automation in the
same slice; product habit is enforced where the founder types (Loop sheet).

#### Stop command

| Item | Spec |
| --- | --- |
| Grammar | `pair relay stop` (nested, like `pair relay adopt`) — **not** `pair relay-stop` |
| Args | `--relay <id>` required; `--json` optional |
| Exit 0 | Transitioned to founder stop, **or** already `done`/`stopped` (idempotent) |
| Exit non-0 | not found; usage; ownership signal failure that left state non-terminal (must not claim success) |

If kill of live trees fails and state cannot be honestly terminal → non-zero +
error code; never stamp `stopped` over known-live work (same honesty class as
`KILL_PARTIAL` / refuse-to-lie). Prefer: if owner already dead, still stamp
founder stop (or leave orphan reason if already reconciled — idempotent path).

#### Errors (catalog)

| Code | When | Agent action |
| --- | --- | --- |
| `RELAY_NOT_FOUND` | Unknown id | Status with valid id or start new |
| `CLI_USAGE_ERROR` | Bad flags, empty message, mutex, missing `--relay` | Fix invocation |
| `RELAY_STOP_FAILED` | Could not settle (e.g. signal refused and process still identity-alive) | `alln ps --json`; retry stop; do not invent resume |
| `OWNERSHIP_*` / `KILL_*` | Only if stop surfaces ownership sub-errors | Existing agentActions; stop still attempts durable founder stamp when owner already dead |
| `RELAY_ALREADY_ACTIVE` | Unchanged start guard | Unchanged |
| `RELAY_INVALID_STATE` | Keep for resume/adopt mismatches — **update explain** so it is not stop-specific; stop does not use this for escalated abandon |

Do **not** map escalated stop to `RELAY_INVALID_STATE`.

#### Contract / version

Additive flags + new nested command + errors → bump
`ContractRegistry.contractVersion` per house rules; regenerate
`alln dev export-contracts` (never hand-edit generated docs). Binary version bump
with the shipping batch.

#### Detached start ack (unchanged PTD)

`--no-wait` still returns `delivery.path: wait` + exact
`pair relay-status --relay <id> --wait-for terminal --timeout … --json`.
Kickoff flags must be included in the child argv (parent strips only `--no-wait`
/ delivery flags per existing detach law).

---

### Mac start survival (mandatory)

**Production Loop start must not run `RelayCoordinator.complete` inside the Mac
app process.**

Required outcome:

1. Durable claim / first `.running` persist happens under the same guards as CLI
   (`RELAY_ALREADY_ACTIVE`, start lock).
2. Round loop runs in a **detached OS child** of the registered `alln pair relay`
   verb (blocking child path), owner.pid = child, not the Dock app.
3. Mac navigates only after durable accept (id known), same honesty as RSC-HF
   ack-after-accept.
4. Quitting the Mac app does **not** orphan a healthy Loop.

**Allowed implementations (pick one in ATL-S03; do not invent a third):**

- **A (preferred):** Resolve the installed/running `alln` executable and spawn
  the same argv a user would run:
  `alln pair relay --doc … --project … --pm-model … --dev-model … --message … [--ceilings…] --no-wait --json`,
  parse ack JSON, select thread. Reuse Engine-visible resolve/spawn helpers;
  if `DetachedDispatch` stays CLI-internal, either move the shared spawn to
  Engine or shell with the same environment policy — **one primitive**.
- **B:** Engine API that performs claim + detach of the registered verb without
  the GUI linking AllnighterCLI — still must end with child-owned loop.

**Forbidden:**

- `Task { await coordinator.complete(...) }` as the production path after this
  packet.
- Hidden unregistered verbs for "relay continue."
- Double claim (GUI claimStart + child claimStart) that races
  `RELAY_ALREADY_ACTIVE` — child must be the claimer **or** parent claims and
  child attaches by id only if such a registered path exists. **v1 recommendation:
  do not pre-claim in GUI; let the detached `pair relay --no-wait` child claim**
  (matches CLI). GUI only validates form, spawns, waits for accept, navigates.

Update `RelayLaunchViewModel` accordingly; keep pure `validate` for form + kickoff.

---

### Teaching surface

| Item | Content |
| --- | --- |
| New / extended topic | **Agent Team Loop** — Mac Loop = unattended Relay; Pilot CLI-only; kickoff brief; Stop vs kill |
| Search aliases | loop, agent team loop, start loop, stop relay, kickoff brief, handoff message (alias → kickoff), relay from app |
| `pm_relay` | Mac entry = Compose → Loop; spinner retired; `pair relay stop`; `--message` / `--message-file` |
| PTD path table | Unchanged; stop is a terminal reason already covered by PM Turn `stopped` |
| Recipe | "Start an unattended loop from the app or CLI with a kickoff brief" |
| Retirement | Deny teaching project-header spinner / "Start relay" glyph as entry; add residual strings to proof gates |
| Menu | `pair relay stop` in live menu / `MenuSelectionCopy` if menuAction catalog lists nested verbs |

**Never teach:**

- `pair loop`
- Mac Pilot
- `alln kill` as the Loop Stop button twin
- Poll loops instead of `relay-status --wait-for` for delivery (PTD law stands)

---

### Mac app impact

| Area | Change |
| --- | --- |
| `RoutingComposer` | Third tab **Loop**; Loop send opens launch sheet (no `sendRouting` chat/run) |
| `RelayLaunchView` / VM | Kickoff field; **Start loop**; detached start; validate kickoff |
| `HomeView` project header | Remove spinner `onStartRelay` / `arrow.triangle.2.circlepath` Start relay |
| `RootView` / fixtures | Loop compose / sheet entry replaces spinner-only deep link; update `GUIFixture.opensRelayLaunch` path to Loop-driven entry |
| Relay thread chrome | Status + Stop; wire Engine stop + status project |
| `RelayResumeController` | Unchanged escalate path; ensure founder-stopped hides resume |
| Copy | No "Pilot" in Loop UI strings |

iOS: out of scope.

---

### Implementation slices

Order: **ATL-S01 → S02 → S03 → S04**. CLI before GUI. Optional S05 anytime after S03.

| Slice | Claim | Acceptance (must fail sloppy work) |
| --- | --- | --- |
| **ATL-S01** | Kickoff on CLI + Engine | See below |
| **ATL-S02** | `pair relay stop` + coordinator stop | See below |
| **ATL-S03** | Mac Loop entry + detached start + spinner removed | See below |
| **ATL-S04** | Mac Status + Stop chrome | See below |
| **ATL-S05** | Optional sidebar quieting | Non-blocking |

#### ATL-S01 — Kickoff brief (CLI + Engine)

**Ship:**

- `Config.kickoffMessage`, `RelayState.kickoffMessage`, prompt context + assemble section
- CLI `--message` / `--message-file` mutex + empty refuse when flag present
- Detached child argv preserves message flags
- Consume-once after first PM turn recorded
- Contracts + help mention kickoff; Mac not required yet

**Acceptance / Works Tests:**

```bash
# Prompt contains brief
alln pair relay --doc <doc> --project "$PWD" --pm-model <pm> --dev-model <dev> \
  --message "Ship the parser fix; do not touch UI" --max-rounds 1 --json
# Hermetic: unit test RelayPMPrompt.assemble includes "## Kickoff brief (founder)"
# and verbatim text; second-round assemble after consume does not.

# Mutex / empty
alln pair relay … --message "" …          # → CLI_USAGE_ERROR
alln pair relay … --message x --message-file y  # → CLI_USAGE_ERROR

# Detach preserves flags
alln pair relay … --message "Ship X" --no-wait --json
# child accepts; first PM run input/log contains Ship X
```

**Negative:**

- Kickoff written only into GUI state → fail slice
- Kickoff stored in `founderNote` → fail slice
- Silent truncation → fail slice

#### ATL-S02 — Stop (CLI + Engine)

**Ship:**

- `RelayCoordinator.stop`
- `pair relay stop`
- PM Turn on founder stop transition
- Errors + help + contract export
- `RelayState.founderStoppedReason`
- `isResumable` remains false for founder stop

**Acceptance / Works Tests:**

```bash
# Live stop
alln pair relay … --message "Ship X" --no-wait --json   # → id
alln pair relay stop --relay <id> --json
# → status=stopped, stoppedReason="founder stopped", pmTurn.reason=stopped (or lifecycle stopped)
alln pair relay-status --relay <id> --json              # agrees
alln ps --json                                          # no live tree for id (or terminal)

# Idempotent
alln pair relay stop --relay <id> --json                # exit 0; reason unchanged

# Escalated abandon
# given escalated relay:
alln pair relay stop --relay <id> --json
# → stopped / founder stopped; relay-resume refused

# Not found
alln pair relay stop --relay relay_nope --json          # RELAY_NOT_FOUND, non-zero
```

**Negative:**

- Stop that only kills process without durable `stopped` → fail
- Stop without PM Turn on transition → fail
- Teaching `alln kill` as the verb in help for this slice → fail
- Founder stop remaining `isResumable` → fail

#### ATL-S03 — Mac Loop entry + survival + spinner death

**Ship:**

- Composer Model | Team | Loop
- Loop → sheet with Kickoff + Start loop
- Detached start (mandatory survival)
- Spinner removed from project header
- Fixture / visual proof path updated
- Copy never says Pilot

**Acceptance:**

- GUI proof: Loop tab visible; spinner absent from project header capture
- Start loop with brief → thread selected with `threadId == relayId`
- **Kill Mac app** (or terminate app process) after start →
  `pair relay-status` still `running` advancing (or parked terminal), **not**
  immediate orphan `owner process died` solely because the app died
- Loop send does not create a normal Chat/Default Team run

**Negative:**

- Spinner still present → fail
- In-process `complete` still production path → fail
- Loop mode calling `sendRouting` as Team/Model → fail

#### ATL-S04 — Mac Status + Stop

**Ship:**

- Status chrome bound to `RelayJSON` / store status
- Stop confirm → Engine `stop` (same durable outcome as S02)
- Resume hidden when founder-stopped

**Acceptance:**

- Status fields match `alln pair relay-status --relay <id> --json` for the same id
  (status, rounds, stoppedReason, note) after refresh
- Stop in UI → CLI status shows `founder stopped`
- Escalated thread: Stop available; after stop, Answer & resume unavailable

**Negative:**

- Status invented from last thread markdown → fail
- GUI stop without going through coordinator stop settlement → fail

#### ATL-S05 (optional)

Quiet historical relay amber; escalate-only attention. No start/stop behavior change.

---

### Inference bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Mac Stop → state | `RelayCoordinator.stop` | Process died ⇒ UI shows stopped | Must persist `stopped` + `founder stopped` + PM Turn on transition | Kill-only double that leaves `running` fails |
| Mac Status → JSON | `RelayState` / `RelayJSON.project` | Thread turns invent lifecycle | Status reads store/projection only | Fixture: divergent turn prose; UI still shows store status |
| Compose Loop → Chat | `RoutingComposer` | Loop Return = Chat send | Loop never calls Model/Team send path | Integration: Loop send creates zero `alln run` chat turns |
| Compose Loop → Pilot | Product copy / navigation | User continues as PM in Chat | No Pilot entry; no external pmMode from Mac | Proof: no Pilot UI; started relay `pmMode=spawned` |
| Spinner → Loop | GUI | Both entries remain | Spinner deleted same slice as Loop entry | Capture: no Start-relay spinner control |
| Kickoff → `founderNote` | `RelayState` | Reuse resume field | Separate `kickoffMessage`; resume path untouched | Resume still injects founderNote only |
| Mac start → owner.pid | Detached child | App is loop owner | Child owns running relay | Quit app; owner not app pid; no instant orphan |
| Stop → resume | `isResumable` | Founder stop is like orphan reconcile | Founder stop not resumable | `relay-resume` after founder stop fails |
| Stop → `alln kill` | Teaching | Same verb | Teach `pair relay stop` only for Loop Stop | Help corpus must not pair Mac Stop with `alln kill` as primary |
| Wait target | PTD | Invent `wait-for running` on relay | Unchanged PTD targets only | Existing usage error tests stay green |

---

### Proof / Done when

**User-visible claim:** From the Mac app I can start an Agent Team Loop from
Compose with a kickoff brief, watch rounds on its thread, see Status, and Stop it
— same durable outcomes as CLI — without a project spinner, without Pilot-in-app,
and without the loop dying when I quit the app.

**CLI contract:** `pair relay` kickoff flags + `pair relay stop` shipped, helped,
contract-tested, PM Turn on founder stop.

**Supporting checks:**

```bash
swift test --package-path Packages/AllnighterCore \
  --filter 'Relay|Detached|PMTurn|RetiredVocabulary|HelpTopic|ContractRegistry|VersionIdentity'
alln dev export-contracts --check
scripts/check_architecture_policy.sh
# Mac: RelayLaunch / Loop / Stop / spinner absence proofs per GUI_Workflow / Visual_Proof_Gate
```

**Teaching:** help finds "loop" / "stop relay" / "kickoff"; spinner not taught;
no `pair loop`.

**Closeout:**

1. Promote Loop vocabulary row + stop/kickoff law pointers to standing docs /
   help (behavior stays code-owned).
2. Archive this packet under `docs/archive/phases/`.
3. Update `docs/phases/README.md` row.

---

## B2) ATL-S01 + ATL-S02 SHIPPED (2026-07-30)

Built by an **unattended relay** — the first real dogfood of this packet's own
machine. PM seat **Sonnet 5** (Claude Code), dev seat **Grok 4.5**, three rounds,
terminal `done`. `alln pair relay --doc docs/phases/atl/ATL_S01_S02_execution.md
--pm-model model_sonnet --dev-model model_grok --no-wait`.

There is a pleasing recursion here: the loop's first task was to build
`--message`, the kickoff flag the relay that built it could not use.

| Commit | Slice |
| --- | --- |
| `0be33988` | ATL-S01 — kickoff brief: Config → RelayState → PM prompt, `--message` / `--message-file`, mutex, empty-refuse, consume-once, detach argv preservation |
| `517f0ef3` | ATL-S02 — `pair relay stop` + `RelayCoordinator.stop`, founder settlement, PM Turn on transition, `RELAY_STOP_FAILED` |
| `9ceec486` | ATL-S01 fix — register the kickoff FlagSpecs (see below) |

Contract 6.4.0 → 6.5.0 → 6.6.0 → 6.7.0. Wall: **2544 tests, 0 failures**;
`export-contracts --check` clean.

### Live acceptance (run against the real binary)

```text
pair relay --help                     → lists --message, --message-file
                                        "Mutually exclusive: --message, --message-file."
--message ""                          → CLI_USAGE_ERROR
--message a --message-file b          → CLI_USAGE_ERROR
start --message "PROBE2 kickoff text" → relay.json kickoffMessage = "PROBE2 kickoff text"
                                        (durable through the DETACHED path)
pair relay stop --relay <id>          → status=stopped, stoppedReason="founder stopped",
                                        pmTurn present, reason=stopped
pair relay stop --relay relay_nope    → RELAY_NOT_FOUND
```

Consume-once confirmed by accident and then on purpose: a relay read *after* its
first PM turn shows `kickoffMessage` absent; read immediately after start it is
present. That is the specified behaviour, not a loss.

### The gap the loop shipped, and why the tests missed it

`0be33988` built the entire Engine half correctly — Config, `RelayState`, prompt
section, consume-once, mutex, empty-refuse, and a passing test that detach
preserves the flags in child argv. But it never added `FlagSpec`s for
`--message` / `--message-file` to the `pair relay` `CommandSpec`. The
registry-driven allowlist therefore rejected both with `UNKNOWN_FLAG` **before**
`parseStartConfig` ran. The feature was unreachable from the CLI while its own
`usage()` string advertised it.

The tests passed because they exercised the parse helper directly, bypassing the
allowlist. **A helper-level test cannot catch an unreachable flag.**
`9ceec486` adds `testKickoffFlagsPassCommandEntryAllowlist` on the command-entry
path so the class of gap cannot recur.

This is the standing "allowlists are where gates die" lesson, and a Code Audit
rubric-5 miss (proof must match the owner-visible claim, not a convenient
helper). Worth carrying into ATL-S03/S04 review.

## B3) ATL-S03 + ATL-S04 SHIPPED (2026-07-30) — packet complete

Implemented by **Composer 2.5** via `alln run --model model_cursor_composer_25`,
with the Visual Proof Gate run separately (the building agent may not be its own
watcher). All four slices are now done; only optional ATL-S05 remains.

| Commit | What |
| --- | --- |
| `6437bf94` | ATL-S03 — composer `Model \| Team \| Loop`, Kickoff sheet, `RelayDetachedLauncher`, project-header spinner retired |
| `cfada75a` | ATL-S03 fixture fix (see below) |
| `18a952e4` | ATL-S03 proof packet sealed |
| `67f4b563` | ATL-S04 — relay thread Status + Stop chrome |
| `e14947b1` | Two P1 layout fixes in Boost Window (unrelated surface, found by the sweep) |
| `88ef7635` | ATL-S04 chrome + capture-path fixes |
| `abfc89d8` | ATL-S04 + Boost Window proof packets sealed |

**Proof:** `check_gui_proof.sh` ok (47 views), wall 2544 tests / 0 failures,
`export-contracts --check` clean.

Packet requirements verified directly in code, not from a report: no in-process
`coordinator.complete` remains anywhere in the Mac app; `RelayDetachedLauncher`
spawns the registered `alln pair relay … --no-wait` argv; Stop routes through
`RelayCoordinator.stop` (never `ProcessOwnershipSurface.kill`); Status loads from
`RelayStateStore` and projects `RelayJSON` rather than inferring lifecycle from
thread prose; the word "Pilot" appears in no Loop UI string.

### What the visual gate caught that nothing else did

Three separate defects survived a green build, 2544 passing tests, and code
review — and were only caught by looking at rendered pixels.

1. **`compose-loop` proved nothing.** The fixture captured the route picker
   *collapsed*, so Model | Team | Loop were never simultaneously visible. The
   slice's core claim was unproven by its own fixture.
2. **`RelayThreadChrome` never rendered — a real user-facing bug.** Its body was
   a `Group` that produced nothing while `relayJSON` was nil, and the `.task` /
   `.onAppear` that *populate* `relayJSON` were attached to that empty view. The
   chrome could not escape its own initial state, so **Status and Stop would
   never have appeared in production**, not merely in fixtures. Diagnosed by
   confirming the state file existed and `alln pair relay-status --json` returned
   a full envelope — data and load path were both fine.
3. **`.confirmationDialog` is a child window** the in-process snapshot cannot
   see, so the stop-confirm fixture captured a plain thread twice before the
   fixture was routed to the window-list composite path.

A fourth, on an unrelated surface swept at the same time: **Boost Window** had a
clipped status pill and a slider label rendering on top of its own header. The
first fix for the overlap **failed** — enlarging the container does not recentre
content because `GeometryReader` top-aligns its child. Both the failure and the
correction are recorded in `docs/qa/gui/boost-window/2026-07-30-p1-fixes/`.

> Standing lesson for future GUI slices: **a fixture that does not actually show
> the thing being proved is worse than no fixture**, because it manufactures
> false confidence. Two of the three ATL failures were of exactly that shape.

### Still open

- **ATL-S05** (optional sidebar amber-dot quieting) — non-blocking, never started.
- Closeout chores from §Proof: promote the **Loop** vocabulary row into
  `docs/workflows/Product_Vocabulary.md`, add the help topic, and archive this
  packet.

---

## C) Open questions — resolved

| # | Question | Resolution |
| --- | --- | --- |
| 1 | Flag names | **`--message` + `--message-file`**, mutually exclusive. Not `--brief`, not `--handoff-file` (handoff = PM→dev). |
| 2 | Stop vs kill naming | **`pair relay stop`** is product; ownership kill helpers are mechanism. Do not teach `alln kill` as Loop Stop. |
| 3 | Escalated + Stop | **Allowed** (abandon). Leaves `founder stopped`, not resumable. |
| 4 | Empty handoff | **Required non-empty after trim** on Mac always; on CLI when flags present. CLI with neither flag remains allowed for back-compat (documented). |
| 5 | Mac start process model | **Detached child**; no production in-process `complete`. |
| 6 | ATL-A vs ATL-B | **ATL-A only** (modal). |
| 7 | Kickoff field owner | **`kickoffMessage`** on Config → State → PM prompt; consume-once after first PM turn. |
| 8 | Stop settlement vs PM Turn | **Must write PM Turn** on founder-stop transition (PTD). |
| 9 | Nested grammar | **`pair relay stop`** (space), like adopt — not `relay-stop`. |
| 10 | Pilot from Mac | **Impossible**; no UI, no deep link, no compose path. |

No remaining Blocked product TBDs for v1.

---

## D) Contradictions vs standing law

### PM Turn Delivery (`docs/archive/phases/PM_Turn_Delivery.md`)

| Topic | Stance |
| --- | --- |
| `stopped` is a PM boundary | **Align.** Founder stop writes `pmTurn` with reason/lifecycle `stopped`. |
| Wait targets | **Align.** No new wait target; stop is terminal → existing `terminal` waiter matches. |
| `--no-wait` delivery ack | **Align.** Unchanged; message flags must ride to child. |
| Report source | **Align.** Stop may have partial/null report; null + notes OK. |
| Contradiction risk | Draft Stop that only killed without PM Turn — **fixed in this packet.** |

### Round Survives the Caller (`docs/archive/phases/Round_Survives_The_Caller.md`)

| Topic | Stance |
| --- | --- |
| Detached dispatch | **Align and extend to Mac.** Draft ignored Mac in-process hole — **fixed.** |
| No hidden verbs | **Align.** Mac spawns registered `pair relay` (with `--no-wait`), not a private continue verb. |
| Ack after accept | **Align.** Navigate only after durable accept. |
| Guards in coordinator | **Align.** Start guards stay in Engine; stop uses coordinator not CLI-only. |

### Product Vocabulary (`docs/workflows/Product_Vocabulary.md`)

| Topic | Stance |
| --- | --- |
| Team / Chat / Delegate | Loop is a **third compose entry** for unattended Relay — not a craft, not a team depth. Closeout adds **Loop** as Mac noun over Relay substrate. |
| No aliases for retired words | Spinner "Start relay" retired as entry; CLI stays `pair relay*`. Do **not** rename Relay→Loop in CLI. |
| Worker retired | Keep model/seat language (`--pm-model` / `--dev-model`); no worker flags. |
| Contradiction risk | Teaching `pair loop` or calling Loop "Pilot" — **banned explicitly.** |

### SSOT Feature Workflow readiness

| Requirement | Met? |
| --- | --- |
| CLI surface first | Yes (S01–S02 before GUI) |
| Teaching surface in slices | Yes |
| Truth owner named | Yes |
| Works Tests | Yes per slice |
| Inference bans | Yes |
| Open TBD | None for v1 |

---

## E) Builder routing

| Concern | Start here |
| --- | --- |
| Kickoff fields + prompt | `RelayCoordinator.Config`, `RelayState`, `RelayPrompts.swift` / `RelayPMPrompt` |
| Stop settlement | `RelayCoordinator` (new `stop`), reuse ProcessOwnership terminate helpers; PM Turn via `persistPMBoundary` |
| CLI | `RelayCLI.swift`, `ContractRegistry+Milestone1.swift` |
| Detach | `DetachedDispatch` / `DetachedHandoff` — extend/share for Mac |
| Mac launch | `RelayLaunchView`, `RelayLaunchViewModel`, `RoutingComposer` |
| Spinner | `HomeView` project header `onStartRelay` |
| Thread chrome | Thread view / relay system rows; `RelayResumeController` for resume gating |
| Status project | `RelayJSON.project`, `RelayCLI.runStatus` |

---

## Related docs

- Substrate: `docs/archive/phases/PM_Relay.md`, `Pilot_Relay.md`,
  `Round_Survives_The_Caller.md`, `PM_Turn_Delivery.md`,
  `Unattended_Round_Notification.md`
- Open orthogonal: `Work_Recovery_And_PM_Continuity.md`
- Vocabulary closeout: `docs/workflows/Product_Vocabulary.md`
- Feature workflow: `docs/workflows/SSOT_Feature_Workflow.md`
- GUI proofs: `docs/gui/GUI_Workflow.md`, `docs/gui/Visual_Proof_Gate.md`

---

## Standing rules (this packet)

- **Loop is Mac; Relay is machine.** Never rename the CLI for the Mac noun.
- **Unattended means detached.** App quit ≠ loop death.
- **Kickoff is founder→PM once.** Not Chat, not handover, not `founderNote`.
- **Stop is founder abandonment.** Durable, PM Turn, not resumable.
- **CLI before GUI.** S01→S02→S03→S04.
- **Missing data is null + note.** Never invent status or report.
- **Pilot stays CLI-only.** Any Mac Pilot entry fails the slice.

---

*Adversarial review and packet freeze: Grok 4.5 via Allnighter, 2026-07-29.*
