# Crew Understaffed Signal

Status: **OPEN — founder intake / simple CLI→CLI packet. Not started.**
Owner: AllnighterCore (`TeamRunJSONMapper`) + AllnighterCLI teaching
Created: 2026-08-07
Origin: Founder dogfood — a PM agent (Opus in a CLI) staffed a multi-seat team
with `--seat`; one seat never ran; the panel reported as dispatched and kept
going 2/3. Nothing shouted. A human watching the Mac GUI would have seen a dead
row; CLI→CLI callers do not look that way. Related substrate:
[`One_Run_Surface.md`](One_Run_Surface.md) (`alln show`), archived
[`Ephemeral_Teams.md`](../archive/phases/Ephemeral_Teams.md) (`--seat`, no
silent reseat), `VendorSubstitutionPolicy` (explicit → never silent hop),
`SeatReseat` (team-preset seats only), archived RLC note that answer panels
fail-soft and “parked-seat / partial-board settlement” was deferred.

Phases are ephemeral. At closeout: promote one teaching line + vocabulary if
needed; code remains SSOT; archive this packet.

---

## Founder intake

```text
Founder intent:
  When a PM agent starts a judgment team (especially with custom --seat), a dead
  seat must be impossible to miss on the CLI surface that agent already uses.
  The agent should learn early enough to pick a different model — not at end-of-
  run when outcome is quietly "partial". Humans in the GUI already see per-seat
  rows; design for CLI→CLI first, keep GUI parity by sharing the same contract.

Product value:
  A dispatched panel is not necessarily a fully staffed one. Stop silent
  understaffing for agent PMs who treat "accepted / running" as "the jury is in."

Trusted workflow slice:
  PM agent: alln run … --seat A --seat B --seat C --no-wait
  → runs returned nextAction (alln show …)
  → one seat fails to start or dies early
  → show --json / --stream surfaces a top-level understaffed warning naming the
    dead model + cause, while siblings still run
  → PM picks another model and re-runs (or kills and re-staffs) — no forensics

Non-goals (push SIMPLE — reject these):
  - Mid-run reseat / hot-swap into the same run id
  - Parking the whole parallel panel on one dead seat
  - New commands (alln crew, alln reseat, …)
  - Expanding observation beyond ORS's three fields
  - --require-full-crew flags / policy knobs in v1
  - GUI-first Live Team Board work as a dependency
  - Silent auto-substitute of an explicit --seat (already banned; keep it)
  - Inventing progress prose or "Sol is thinking"
```

---

## Product promise

```text
If any requested crew seat is terminal-failed while the team run is still live
(or finishes partial), alln show --json names that understaffing at the top
level — model id + honest cause — without digging answers[].
```

One claim. No new lifecycle. Fail-soft stays the default; silence dies.

---

## Why CLI→CLI first

| Caller | How they watch | Today |
| --- | --- | --- |
| Human in Mac GUI | Per-seat board / Floor rows | Dead seat visible if they look |
| PM agent in another CLI | `alln show --json` / `--stream` after `--no-wait` | `running` looks fine; dead seat buried in `answers[]` |
| Same human via CLI | Same show surface | Same bury |

Humans do not staff custom `--seat` panels the way agent PMs do. Fix the
contract agents already poll. GUI parity = render the same warning later; do
not invent a second truth.

---

## Simple design (v1 = one projection)

Reuse what exists. Do not add a parallel status schema.

### Signal

On every `TeamRunJSON` projection (`show`, stream snapshot, terminal):

1. Count non-`skipped` seats vs seats in `{failed, timedOut, cancelled}`.
2. When any seat is dead and `expected > stillUseful` (live or done), emit a
   **top-level** `warnings[]` entry:

```text
code:    crew_understaffed
message: crew 2/3 — model_gpt_sol failed: CLI not installed / wrong CLI
```

Cause text reuses the honest one-liner path already used for worker failures
(capacity observation wins when present; else `errorKind` / `errorReason`).
Never invent a vendor limit you did not observe.

3. Keep existing per-seat `answers[]` rows as the detail ledger. Warning is the
   shout; rows remain the proof.

### Action (still simple)

While the run is **non-terminal** and `crew_understaffed` is present:

- Prefer a `nextActions` entry whose **label** names the dead model and says to
  pick another / re-run with `--seat`.
- **Command** stays something that already works: `alln show <id> --json` (inspect)
  or `alln kill <id>` when the PM must stop an understaffed panel before
  re-staffing. Do **not** invent `reseat` in v1.

When the run is **terminal** `outcome.status == partial`, the same warning must
still be present so end-state review cannot miss it.

### Teaching (same slice)

- `HelpTopicRegistry` / team-run help: **accepted ≠ fully staffed**; after
  `--no-wait`, read `warnings` for `crew_understaffed` the same way ORS taught
  reading `observation` (running ≠ progress).
- Help search hits: `understaffed`, `dead seat`, `seat failed`, `partial crew`,
  `custom seats`.
- One short bootstrap / recipe line for PM agents staffing with `--seat`.

### GUI parity (later, not blocking)

Mac Floor / Live Team Board may banner the same `crew_understaffed` warning.
No GUI-owned field. No slice until CLI projection + teaching ship.

---

## Current state (verified against code, 2026-08-07)

| Piece | State |
| --- | --- |
| Multi-seat fail-soft | Intentional — board continues with remaining answers |
| Explicit `--seat` | No silent `SeatReseat` (`CatalogRunCoordinator` skips explicit) |
| Single-worker explicit park + “Use another model” | Exists; **not** wired for one dead seat on a live multi-seat panel |
| `observation` | Three fields only (ORS) — do not stuff crew here |
| `warnings[]` / `nextActions[]` | Already on `TeamRunJSON`; underused for crew |
| `outcome.partial` | Terminal only — too late for a live PM |
| Per-seat failure presenter | GUI `WorkerFailurePresenter` — not on the agent shout path |

RLC already deferred “parked-seat / partial-board settlement.” This packet is
**only** the shout + teaching. It does not settle the board or park siblings.

---

## Truth owner / lie-prone layers

| Concern | Owner |
| --- | --- |
| When understaffed is true | `TeamRunJSONMapper` (pure projection from `TeamRun.answers`) |
| Cause string | Existing failure/capacity presenters — one shared helper if needed |
| Wire shape | `TeamRunJSON.warnings` (+ optional `nextActions` label) |
| Teaching | `HelpTopicRegistry`, menu/recipe copy |

Lie-prone: any path that says “dispatched” / “running” without the warning while
a crew seat is already terminal-failed; help that teaches agents to trust seat
count from the team preset alone.

---

## Inference bans

| Junction | Forbidden inference | Ban |
| --- | --- | --- |
| `teamRun.status == running` | Crew is fully staffed | Understaffing is a warning fact from answers |
| Missing `crew_understaffed` | All seats healthy | Absence means no terminal-failed crew seat yet — not “verified healthy” |
| One seat capacity-failed | Whole panel should park | Fail-soft remains; shout only |
| Explicit seat failed | Silent reseat / Auto hop | Still banned — PM chooses the next model |
| Warning message | Guessed vendor limit | Only observed `errorKind` / capacity / reason |

---

## Slices

### CHS-S01 — Shout + teach (authorize this)

- Project `crew_understaffed` warning whenever applicable (live + terminal partial).
- Name dead `modelId` + honest cause in the message.
- Non-terminal: label a `nextActions` entry so a PM sees “replace / re-run” without schema invention.
- Help + search + one PM-facing recipe line.
- Focused mapper tests + one CLI fixture Works Test.
- **No** new commands, flags, observation fields, reseat, or GUI work.

### CHS-S02 — deferred (do not start without founder)

Only if S01 dogfood still leaves PMs blind:

- Stronger live `nextAction` (e.g. paste-ready kill + reproduce with dead seat
  called out).
- Optional compact `crew: { expected, live, failed[] }` object if warnings prove
  too easy to ignore — still projected from the same answers, still no reseat.

Default plan: **ship S01 only.** Complexity belongs in the reject list until
proven necessary.

---

## Works Test

```text
Setup: ready bench; one deliberate bad or forced-fail seat id in a 3-seat
       judgment --seat crew (or fixture TeamRun with 1 failed + 2 running).
Gesture: alln show <id> --json   (and stream snapshot if live)
Assert:
  - warnings contains code crew_understaffed
  - message names the dead modelId and a non-empty honest cause
  - surviving seats still show running/done (fail-soft unchanged)
  - help search "dead seat" / "understaffed" hits the topic
Negative:
  - fully staffed running run → no crew_understaffed
  - explicit failed seat → no silent substitute modelId on that row
```

Host proof: one real `--no-wait` from inside a PM CLI (Cursor or Claude Code)
where a seat fails early; PM-visible JSON shows the warning before terminal.

---

## Done when

- User-visible: understaffed crew is named on `alln show` without reading
  `answers[]` first.
- CLI contract only (GUI may follow; not required to close).
- Teaching updated; search finds it.
- S01 Works Test green; S02 not opened by default.

---

## Sequencing

- Does **not** block Capacity / VSI / OpenCode packets.
- Composes with ORS: same `show` surface; do not reopen retired status verbs.
- Distinct from [`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md)
  (relay/git recovery) and [`Live_Team_Board.md`](Live_Team_Board.md) (GUI board).
- If teaching-only drift appears later, fold durable lines into
  `Agent_Teaching_Surface` / `Product_Vocabulary` at closeout — not a second
  live packet.
