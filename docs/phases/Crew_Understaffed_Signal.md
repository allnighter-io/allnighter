# Crew Understaffed Signal

Status: **OPEN — Spec Review Min Ready (run `7FF03849`, 2026-08-07). CHS-S01
authorized after apply-to-doc edits below. Not coded.**
Owner: AllnighterCore (`TeamRunJSONMapper`, stream projector) + AllnighterCLI
teaching
Created: 2026-08-07
Origin: Founder dogfood — a PM agent (Opus in a CLI) staffed a multi-seat team
with `--seat`; one seat never ran; the panel reported as dispatched and kept
going 2/3. Nothing shouted. A human watching the Mac GUI would have seen a dead
row; CLI→CLI callers do not look that way. Related substrate:
[`One_Run_Surface.md`](One_Run_Surface.md) (`alln show`), archived
[`Ephemeral_Teams.md`](../archive/phases/Ephemeral_Teams.md) (`--seat`, no
silent reseat), code `VendorSubstitutionPolicy` (explicit → never silent hop),
code `SeatReseat` (team-preset seats only), archived
[`Rate_Limit_Continuity.md`](../archive/phases/Rate_Limit_Continuity.md)
(answer panels fail-soft; parked-seat / partial-board settlement deferred).

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
  → runs returned nextAction (alln show … --stream)
  → one seat fails to start or dies early
  → show --json / --stream surfaces a top-level understaffed warning naming the
    dead model + cause, while siblings still run (stream: on the seat-death
    frame, before terminal)
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
  - Queued-duration stall detection (inference from absence)
  - New NextAction.Kind cases (closed enum; kill stays in prose)
  - Persisting the warning into durable TeamRun.warnings (projection only)
```

---

## Product promise

```text
If any requested crew seat is terminal-dead while the team run is still live
(or finishes partial), alln show --json / --stream names that understaffing at
the top level — model id + honest cause — without digging answers[]. A PM who
attaches once with --stream sees the shout on a pre-terminal frame.
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

1. Count non-`skipped` **crew answer rows** only (scout/lead excluded) vs seats
   in `{failed, timedOut, cancelled, interrupted}`.
2. When any crew seat is dead and `expected > stillUseful` (live or done), emit
   a **top-level** `warnings[]` entry (one entry, length-capped):

```text
code:    crew_understaffed
message: crew 2/3 — model_gpt_sol: CLI not installed / wrong CLI
```

Multiple dead seats append as `; modelId: cause` pairs in that single message.

3. **Cause owner:** one **Core** helper (capacity observation wins when present;
   else `errorKind` / `errorReason`). Never invent a vendor limit you did not
   observe. Mac `WorkerFailurePresenter` is **not** imported — GUI adopts the
   Core helper at parity time.

4. Keep existing per-seat `answers[]` rows as the detail ledger. Warning is the
   shout; rows remain the proof.

5. **Never-spawned invariant:** a crew seat that fails to spawn must settle a
   terminal-`failed` `answers[]` row. CHS-S01 verifies this against `RunService`
   and fixes the boundary if it does not hold. Queued-duration stall detection
   is rejected.

6. **Live stream:** the frame that reports a crew seat entering a dead state
   must carry the top-level `crew_understaffed` warning (additive field on the
   existing seat-death frame; no new NDJSON event type). Snapshot-only delivery
   is insufficient — today full run projection rides only snapshot + terminal
   (`NDJSONStreamProjector`); an attach-once PM would otherwise first see the
   shout at terminal. Do not re-emit a second full snapshot (consumers assume
   one).

**Projection-only:** compute the warning in `TeamRunJSONMapper` from
`answers[]`. Do **not** persist it into durable `TeamRun.warnings` (no second
truth store).

### Action (still simple)

While the run is **non-terminal** and `crew_understaffed` is present:

- Label an existing `nextActions` entry of kind **`showRun`** so the label names
  the dead model and says to pick another / re-run with `--seat` (or kill the
  understaffed panel first).
- `alln kill` appears in the **label / teaching prose only** — no new
  `NextAction.Kind` case in v1 (`NextAction.Kind` is closed / contract-owned).
- Never emit a nextAction whose command is the same `alln show --json` call that
  produced the snapshot (no self-referential poll loop). Prefer the stream
  attach command the PM already holds, or omit a redundant show command when
  the warning itself is the signal.

When the run is **terminal** `outcome.status == partial`, the same warning must
still be present so end-state review cannot miss it.

### Teaching (same slice)

- `HelpTopicRegistry` / team-run help: **accepted ≠ fully staffed**; after
  `--no-wait`, read `warnings` for `crew_understaffed` the same way ORS taught
  reading `observation` (running ≠ progress). Teach that `--stream` surfaces
  the warning on seat death, before terminal.
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
| Stream frames | Full projection on snapshot + terminal only — seat-death frames need the additive warning field |
| `outcome.partial` | Terminal only — too late alone for a live PM |
| Per-seat failure presenter | GUI `WorkerFailurePresenter` — replace with Core helper at parity |
| Spawn-failure → `failed` row | **Verify in S01** — not assumed (founding incident was never-ran) |

Archived RLC deferred “parked-seat / partial-board settlement.” This packet is
**only** the shout + teaching. It does not settle the board or park siblings.

---

## Truth owner / lie-prone layers

| Concern | Owner |
| --- | --- |
| When understaffed is true | `TeamRunJSONMapper` (pure projection from crew `answers[]`) |
| Cause string | One Core helper (capacity wins, else `errorKind` / reason) |
| Live stream delivery | NDJSON seat-death frame carries projected warning (additive) |
| Wire shape | `TeamRunJSON.warnings` (+ `showRun` nextAction **label**) |
| Teaching | `HelpTopicRegistry`, menu/recipe copy |

Lie-prone: any path that says “dispatched” / “running” without the warning while
a crew seat is already terminal-dead; stream that only shouts at terminal;
help that teaches agents to trust seat count from the team preset alone;
durable `TeamRun.warnings` as a second store for the same fact.

---

## Inference bans

| Junction | Forbidden inference | Ban |
| --- | --- | --- |
| `teamRun.status == running` | Crew is fully staffed | Understaffing is a warning fact from answers |
| Missing `crew_understaffed` | All seats healthy | Absence means no terminal-dead crew seat yet — not “verified healthy” |
| One seat capacity-failed | Whole panel should park | Fail-soft remains; shout only |
| Explicit seat failed | Silent reseat / Auto hop | Still banned — PM chooses the next model |
| Warning message | Guessed vendor limit | Only observed `errorKind` / capacity / reason |
| Seat stuck `queued` | Dead / understaffed | No duration heuristic; spawn must settle `failed` |

---

## Spec Review Min — Lead Call (2026-08-07)

Run `7FF03849-05B9-42E1-A45D-533B60491D0F` — **Ready**. Irony: the Proof Auditor
seat (`model_opencode_qwen_38_max`) failed to start; outcome `partial` — the
packet's own bug, live. Lead: stream delivery on seat-death frame; dead set
includes `interrupted`; never-spawned row invariant; projection-only + Core
cause helper; Works Test via fixture / process-kill (not bad seat id).

---

## Slices

### CHS-S01 — Shout + teach (**authorized**)

- Project `crew_understaffed` warning whenever applicable (live + terminal partial).
- Dead set `{failed, timedOut, cancelled, interrupted}`; crew answer rows only.
- Name dead `modelId` + honest Core cause in one capped message.
- Seat-death stream frame carries the warning (pre-terminal); mapper owns the
  predicate; projector attaches it.
- Verify never-spawned seats settle `failed`; fix boundary if not.
- Non-terminal: label existing `showRun` nextAction (kill in prose only).
- Help + search + one PM-facing recipe line.
- Mapper + stream fixture tests; host proof via process-kill mid-run.
- **No** new commands, flags, observation fields, reseat, Kind cases, or GUI work.

### CHS-S02 — deferred (do not start without founder)

Only if S01 dogfood still leaves PMs blind:

- Stronger live nextAction (paste-ready kill + reproduce with dead seat called out).
- Optional compact `crew: { expected, live, failed[] }` object if warnings prove
  too easy to ignore — still projected from the same answers, still no reseat.
- Optional early “staffing settled N/M” frame **only if** dogfood shows most
  deaths are at spawn (Premise rival absorbed as invariant in S01 first).

Default plan: **ship S01 only.** Complexity belongs in the reject list until
proven necessary.

---

## Works Test

```text
Setup (mapper): fixture TeamRun with 1 failed crew answer + 2 running
                (not a deliberate bad --seat id — ExactId readiness refuses
                before spawn, so no run exists to inspect).
Setup (host):   real --no-wait 3-seat judgment; kill one live seated process.
Gesture:        alln show <id> --json ; alln show <id> --stream (attach once)
Assert:
  - warnings contains code crew_understaffed
  - message names the dead modelId and a non-empty honest cause
  - streaming attachment sees crew_understaffed on a pre-terminal frame
  - surviving seats still show running/done (fail-soft unchanged)
  - help search "dead seat" / "understaffed" hits the topic
Negative:
  - fully staffed running run → no crew_understaffed
  - explicit failed seat → no silent substitute modelId on that row
  - lead/scout failure alone does not fire crew_understaffed
```

Proof commands (slice):

```text
scripts/swift-test.sh --filter TeamRunJSONMapper
scripts/swift-test.sh --filter OneRunSurfaceShowStream
scripts/swift-test.sh --filter HelpTopic
# host: kill a live seat mid --no-wait; stream shows warning before terminal
bash scripts/check.sh   # closeout ONLY
```

---

## Done when

- User-visible: understaffed crew is named on `alln show` / `--stream` without
  reading `answers[]` first, and before terminal for attach-once PMs.
- CLI contract only (GUI may follow; not required to close).
- Teaching updated; search finds it.
- S01 Works Test green; S02 not opened by default.

---

## Sequencing

- Does **not** block Capacity / VSI / OpenCode packets.
- Composes with ORS: same `show` surface; do not reopen retired status verbs;
  do not expand the three-field `observation`.
- Distinct from [`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md)
  (relay/git recovery) and [`Live_Team_Board.md`](Live_Team_Board.md) (GUI board).
- If teaching-only drift appears later, fold durable lines into
  `Agent_Teaching_Surface` / `Product_Vocabulary` at closeout — not a second
  live packet.
