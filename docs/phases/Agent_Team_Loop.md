# Agent Team Loop — Mac compose + CLI parity

Status: **OPEN — Ready for Implementation** (founder directed 2026-07-29)
Owner: AllnighterEngine (`RelayCoordinator`) + AllnighterCLI (`RelayCLI`) + Mac
(composer / thread / sidebar)
Created: 2026-07-29
Updated: 2026-07-29

Ephemeral build packet. At closeout: promote vocabulary into
`docs/workflows/Product_Vocabulary.md`, help topics, and retire the project-header
spinner; archive this packet. Code remains SSOT for fields and stop/status.

---

## Founder Intent

```text
Raw request:
  Surface Relay as a first-class run kind in the Mac app — not a hidden project
  spinner. Composer gains Model · Team · Loop. Loop starts an unattended Relay
  with a kickoff handoff message (same habit as briefing Opus in Claude Code).
  Opening a relay in the sidebar must offer Status + Stop with CLI parity.
  Pilot from the Mac app is impossible and must stay impossible.

Prior art:
  Claude Code / Cursor: user briefs the agent once, then the agent drives.
  git / gh / kubectl: start + status + kill are first-class verbs on one object.
  Recent Allnighter CLI work already made agent↔agent relay survivable and
  waitable (see §CLI substrate) — the Mac app did not catch up.

Product value:
  The killer feature the founder uses daily from CLI becomes usable from the app
  without teaching a second product. One Loop noun, one start path, honest stop.

Trusted workflow slice:
  Compose → Loop → handoff message (+ doc/seats) → Start
    → thread shows rounds
    → Status (same JSON as CLI)
    → Stop (same settlement as CLI)
    → Escalate → Answer & resume (already shipped R-S08)

Non-goals:
  - Pilot / supervised loop from the Mac app (CLI-only; app is not the PM seat).
  - Replacing pair pilot* verbs.
  - Capacity strip / utilization (orthogonal; CLI_Capacity_TUI_Sampling.md).
  - Full sidebar unread redesign (optional hygiene slice only — see ATL-S05).
```

---

## Product law (lock these)

1. **Loop (Mac) = unattended Relay.** Opus (PM) and Grok (dev) are both spawned.
   The human briefs once; does not author round handovers.
2. **Pilot = iterative / supervised** and lives only where a live agent CLI
   session *is* the PM (Claude Code, etc.). The Mac app must not offer Pilot.
3. **Kickoff handoff message** is round-0 context for the spawned PM — same role
   as the brief the founder already types to Opus before `pair pilot` / relay
   work in Claude. It is not an ongoing Chat channel.
4. **CLI-first.** Every Mac Loop action is a thin presenter over an `alln`
   contract. No GUI-only stop, no GUI-only status shape.
5. **After start, Compose is not the control surface.** Thread / Inbox owns
   Status, Stop, Answer & resume. Mid-flight injection stays escalate/resume.

### Naming

| Surface | Word | Meaning |
| --- | --- | --- |
| Mac composer mode | **Loop** | Start an Agent Team Loop (unattended Relay) |
| Longer label (help/docs) | **Agent Team Loop** | Same machine |
| CLI / durable type | **Relay** / `pair relay` | Existing substrate — do not rename the verb |
| CLI-only | **Pilot** / `pair pilot` | Supervised; Opus in the user's CLI session |

Hard cutover: retire teaching “Start relay” via the project-header **spinner**
(`arrow.triangle.2.circlepath`). Deny-list that affordance in GUI proofs once
Loop ships.

---

## CLI substrate to reuse (do not rebuild)

Recent CLI→CLI relay hardening is the floor this packet stands on:

| Shipped | What Loop/Mac must present |
| --- | --- |
| `pair relay --no-wait` + detached claim (`Round_Survives_The_Caller`) | Start must survive closing the sheet / app |
| `pair relay-status --wait-for parked\|terminal` + PM Turn embed (`PM_Turn_Delivery`) | Status affordance = this JSON, not a bespoke GUI DTO |
| Local notify on escalate/land (`Unattended_Round_Notification`) | Keep; Loop does not replace banners |
| `pair relay-resume` + GUI Answer & resume (R-S08) | Keep as-is |
| `alln kill` / Process Ownership | Stop may settle through ownership, but must stamp relay `stopped` with an honest founder reason — not leave a zombie “running” museum row |
| Work Recovery packet (open) | Orthogonal; Loop Stop must not invent a parallel recovery envelope |

Gap today: there is **no first-class `pair relay stop`**. Mac has **no Stop**.
Status exists on CLI; Mac thread open is mostly a log viewer.

---

## Current Mac state (lie-prone)

| Surface | Today | Problem |
| --- | --- | --- |
| Project header spinner | “Start relay” | Reads as refresh; buried; not next to Model/Team |
| `RelayLaunchView` sheet | Doc + PM + Dev + ceilings | Good form; wrong front door |
| Composer | Model / Team only | Missing the third run kind |
| Kickoff brief | None on `pair relay` | CLI and GUI both skip the founder’s habitual Opus brief |
| Sidebar thread open | Round history + escalate answer | No Status, no Stop |
| Amber rail dots | Generic “needs attention” | Every historical SPEC lights up; noise |

---

## Target experience

### Start (Compose)

```text
Composer mode:  Model  |  Team  |  Loop
```

Selecting **Loop**:

1. Composer placeholder / send semantics become **handoff message only**
   (“Brief the PM — what should this loop deliver?”).
2. Same config the sheet already has must be reachable: **doc**, **PM seat**,
   **dev seat**, ceilings — either:
   - **ATL-A (preferred for v1):** Loop mode opens the existing `RelayLaunchView`
     (or an in-composer twin), with a required **Handoff** field at the top;
     primary button **Start loop** sends message + config into `pair relay`.
   - **ATL-B (later):** Fully inline composer chips for doc/seats; send = start.

Founder ruling lean: **reuse the modal** behind Loop — simpler, already proven.
Compose owns the mode entry + handoff text; modal owns doc/seats/ceilings if not
folded into the same sheet.

3. On success: dismiss, select the relay thread (`threadId == relayId`), show
   live rounds. Do not dump the user into Chat as if they were Pilot.

### Live control (thread / chrome)

When the open thread is a Relay:

| Affordance | Behavior | CLI twin |
| --- | --- | --- |
| **Status** | Show status pill + open/copy structured status (running / escalated / done / stopped + round + last PM Turn summary) | `alln pair relay-status --relay <id> --json` |
| **Stop** | Confirm → settle relay to `stopped` (founder stopped); kill owned process tree; thread shows terminal | New: `alln pair relay stop --relay <id> [--json]` |
| **Answer & resume** | Unchanged (escalated only) | `alln pair relay-resume` |

Optional: **Copy status command** for agent handoff (`relay-status --wait-for …`).

### Sidebar

- **Remove** the project-header relay spinner.
- Opening a Loop thread is how you get Status/Stop — not a second chrome glyph.
- (ATL-S05 hygiene) Prefer one project-level “N loops need you” over amber dots
  on every historical `PM Relay: SPEC` row — not blocking for S01–S04.

---

## SSOT

| Concern | Owner |
| --- | --- |
| Relay lifecycle / stop settlement | `RelayCoordinator` (+ `RelayStateStore`) |
| Kickoff brief on start | `RelayCoordinator.Config` / first PM prompt injection + durable field if needed |
| CLI verbs | `RelayCLI` + `ContractRegistry` |
| Mac start | Composer Loop mode → existing launch VM / `RelayGUIRuntime.makeCoordinator` |
| Mac status/stop | Thin wrappers calling CLI/Engine — **no parallel RelayDTO** |
| Teaching | `HelpTopicRegistry` + `MenuSelectionCopy` if menuAction |
| Vocabulary | `Product_Vocabulary.md` at closeout |

### Lie-prone layers

- SwiftUI inventing stop without stamping `RelayState.status = stopped`
- Status UI reading only thread turns while CLI status disagrees
- Calling Loop “Pilot” in copy or offering Pilot in the app
- Spinner left discoverable after Loop ships
- Kickoff message only in GUI (CLI must accept the same brief)

### New semantic rules

1. `pair relay` accepts an optional kickoff brief (`--message` and/or
   `--handoff-file`) passed into the first PM turn context.
2. `pair relay stop --relay <id>` is the founder stop verb: identity-checked
   kill of the relay owner tree **and** durable `stopped` + `stoppedReason`
   (e.g. `founder stopped`). Idempotent if already terminal.
3. Mac Loop start / status / stop are presenters over (1)–(2) and existing
   `relay-status` / `relay-resume`.

### Duplicate truth to delete

- Project-header “Start relay” spinner as a product entry point
- Any future GUI-only “cancel relay” that only kills the process

---

## CLI surface (ship first)

```text
# Start (extend)
alln pair relay --doc <path> --project <id|path> \
  --pm-model <id> --dev-model <id> \
  [--message <text> | --handoff-file <path>] \
  [--until HH:MM] [--max-rounds N] [--idle-timeout <sec>] \
  [--no-wait] [--json]

# Status (exists — GUI must use)
alln pair relay-status --relay <id> \
  [--wait-for parked|terminal --timeout <sec>] [--json]

# Stop (new)
alln pair relay stop --relay <id> [--json]
# → RelayJSON with status=stopped, stoppedReason=founder stopped
# → exit 0 if stopped or already terminal; usage/not-found per catalog

# Resume (exists)
alln pair relay-resume --relay <id> --answer <text> [--no-wait] [--json]
```

Errors (extend catalog as needed):

| Code | When |
| --- | --- |
| `RELAY_NOT_FOUND` | Unknown id (existing) |
| `RELAY_INVALID_STATE` | Stop refused for a state that cannot be killed safely — prefer settle + explain over silent no-op |
| `OWNERSHIP_*` / `KILL_*` | Reuse process-ownership codes when the tree cannot be signalled; still attempt durable stop stamp when owner is already dead |

Exit: stop of a live relay → 0 with JSON `stopped`. Already `done`/`stopped` → 0
idempotent. Escalated: stop is allowed (founder abandons) and must not require
resume first.

---

## Teaching surface

- Help topic: **Agent Team Loop** — Mac Loop = unattended Relay; Pilot stays CLI.
- Search aliases: loop, agent team loop, start relay, stop relay, handoff message,
  kickoff brief, relay from app.
- Update `pm_relay` topic: Mac entry is Compose → Loop; spinner retired.
- Recipe: “Start an unattended loop from the app or CLI with a brief.”
- `MenuSelectionCopy` if any new `menuAction` commands (`pair relay stop`).
- Retirement: GUI proof + deny teaching of project-header spinner as Start relay.

---

## Mac app impact

| Area | Change |
| --- | --- |
| Composer | Third mode **Loop**; handoff-only send copy |
| `RelayLaunchView` / VM | Add required handoff field; entry from Loop (keep sheet reusable) |
| `HomeView` project header | Remove spinner `onStartRelay` |
| Relay thread chrome | Status + Stop buttons; wire to Engine/CLI |
| `RelayResumeController` | Unchanged escalate path |
| GUI fixtures / Visual Proof | Replace `opensRelayLaunch` spinner path with Loop compose proof |

iOS: out of scope (parked companion); no parallel JSON.

---

## Implementation slices

| Slice | Claim | Proof |
| --- | --- | --- |
| **ATL-S00** | Spec freeze: vocabulary + stop semantics + handoff field name | This packet + founder ack on open questions below |
| **ATL-S01** | CLI: `--message` / `--handoff-file` on `pair relay`; first PM prompt includes brief | Unit + `alln pair relay … --message … --dry` or fixture prompt assert |
| **ATL-S02** | CLI: `pair relay stop` settles state + kills tree | Works Test: start `--no-wait`, stop, `relay-status` shows `stopped` / founder reason; `alln ps` clear |
| **ATL-S03** | Mac: Loop mode → launch sheet with handoff; remove spinner | GUI proof fixture; spinner absent from project header |
| **ATL-S04** | Mac: thread Status + Stop present CLI contract | Stop in UI → same durable state as S02; Status mirrors `relay-status --json` fields |
| **ATL-S05** | (Optional) Sidebar: quiet historical relays; escalate-only amber | Visual proof; no behavior change to Loop start/stop |

Order: **S01 → S02 → S03 → S04** (CLI before GUI). S05 anytime after S03.

---

## Open questions (resolve in ATL-S00)

1. **Handoff field flag names:** `--message` vs `--brief` vs `--handoff-file` only?
   Recommendation: `--message` + `--handoff-file` (mutually exclusive), matching
   resume’s `--answer` altitude.
2. **Stop vs kill naming:** `pair relay stop` (product) wrapping ownership kill
   (mechanism) — confirm; do not teach raw `alln kill` as the Loop stop in Mac copy.
3. **Escalated + Stop:** Allowed (abandon) — confirm.
4. **Empty handoff:** Refuse start (required) vs optional with a default prompt
   line — recommendation: **required** non-empty trim (matches founder habit).

---

## Inference bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Mac Stop → state | `RelayCoordinator` | Process died ⇒ UI shows stopped without stamp | Stop must persist `stopped` + reason | Kill tree only in test double → status still `running` fails |
| Mac Status → JSON | `RelayCLI` / projector | Thread turns invent status | Status reads `RelayState` / `RelayJSON` only | Fixture with divergent turn text still shows store status |
| Compose Loop → Pilot | Product copy | Loop check-in in Chat | No Pilot entry; no “continue as PM” in Chat composer | Proof: Loop start never focuses Chat as PM seat |
| Spinner → Loop | GUI | Both entry points remain | Spinner deleted in same slice as Loop entry | Proof capture: no `arrow.triangle.2.circlepath` start affordance |

---

## Proof / Done when

**User-visible claim:** From the Mac app I can start an Agent Team Loop from
Compose with a handoff message, watch it, see Status, and Stop it — same
outcomes as CLI — without a project spinner and without Pilot-in-app.

**CLI contract:** `pair relay` kickoff brief + `pair relay stop` shipped, helped,
contract-tested.

**Works Tests:**

```text
# S02
alln pair relay --doc … --pm-model … --dev-model … --message "Ship X" --no-wait --json
# → delivery.command includes relay-status waiter
alln pair relay stop --relay <id> --json
# → status=stopped, stoppedReason mentions founder
alln pair relay-status --relay <id> --json
# → agrees

# S03/S04 (Mac)
# Loop mode → handoff + Start → thread selected
# Stop → same status as CLI
# Project header has no relay spinner
```

**Teaching:** help finds “loop” / “stop relay”; spinner not taught.

---

## Related docs

- Archived substrate: `docs/archive/phases/PM_Relay.md`, `Pilot_Relay.md`,
  `Round_Survives_The_Caller.md`, `PM_Turn_Delivery.md`,
  `Unattended_Round_Notification.md`
- Open: `Work_Recovery_And_PM_Continuity.md` (recovery envelope — do not fork)
- Vocabulary closeout target: `docs/workflows/Product_Vocabulary.md`
