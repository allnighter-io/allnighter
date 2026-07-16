# Panel — the pilot move applied to spec hardening (session as synthesizer)

Status: **Specced — approved concept (founder 2026-07-16); build on go**
Owner: AllnighterCore + CLI
Updated: 2026-07-16

> One line: **Panel hardens the spec, Pilot builds it, Relay runs the night
> shift.** Same product physics as Pilot: judgment stays in the live session;
> Allnighter contributes fan-out, mechanical safety, durable rounds, and the
> thread. This is the Pressure Test hero loop (`Pressure_Test.md` — challenger
> lenses, blind fan-out law, refutation gate) with the synthesizer seat moved
> OUT of a spawned plan-writer and INTO the session you already work in.

## 0. The copy-paste monkey, part two

Today the founder hardens specs by hand: paste the doc to N models with N
different challenge angles, collect the reports, synthesize, edit, repeat. The
loop is real and proven (Pressure Test); the transport is human. Panel is that
transport, mechanized — from inside any CLI, no app.

```text
alln pair panel start --doc docs/phases/X.md --project . \
  --seat grok45:security --seat sonnet:scope --seat codex:simplify

loop:  write challenge brief (scaffolded)
       alln pair panel round --panel <id> --brief round1.md    (BLOCKS)
       → N challenger reports return in-call, blind to each other
       session refutes/synthesizes → edits the spec (session's own hands)
       repeat · done-by-declaration
```

## 1. Decisions (locked by this doc)

1. **The session is the synthesizer.** No spawned synthesis seat, no scoring
   machinery — the refutation gate from Pressure Test v2 is the live session's
   judgment. Reports return verbatim; Allnighter never merges or ranks them.
2. **Blind fan-out is LAW** (from Pressure_Test.md): challengers never see each
   other's output within a round. Mechanically: N independent dispatches, no
   shared transcript.
3. **Lenses are declared at start** (`--seat <alias>:<lens>` + optional
   `--lens-file <lens>=<path>` for standing lens instructions). Per-round, the
   PM writes ONE brief; the assembled per-seat prompt = lens instruction + brief
   verbatim + doc path (re-read fresh — anchor, not payload). Judgment about
   WHAT to challenge stays in the brief; lens texts are reusable framing only.
4. **Read-only by MECHANISM — this is its natural home.** Unlike the relay
   (sequential, one mutating worker), a panel is N CONCURRENT seats on one repo:
   prompt-level read-only is banned here for real safety reasons, not doctrine.
   Per seat: drivers with a true read-only mode use it (`claude --permission-mode
   plan`, `codex --sandbox read-only` — the salvaged capability table in
   `Unified_Run_Model.md`); all other drivers run against an **ephemeral APFS
   clone** of the repo (cheap copy-on-write `clonefile`, deleted after the turn —
   a copy, not a git worktree; Allnighter still does no git). No seat is ever
   refused: enforce where the driver can, isolate where it can't.
5. **One substrate, no third system.** Round DISPATCH reuses the answer-team
   run substrate (TeamRun, N read-only workers — the "one team-run substrate"
   law) with one additive capability: per-seat messages (the blind lens
   prompts). Panel SESSION state (rounds over days) mirrors the relay pattern:
   `PanelState` + store beside RelayStateStore, `awaitingPM | running | done`,
   parked-unowned semantics identical to `awaitingPM` (orphan reconcile skips).
6. **No HandoverGate on briefs.** Nothing dispatched can mutate (decision 4);
   the danger classes don't apply to read-only seats. Cheaper and honest.
7. **Panel feeds memory.** Findings that survive the session's refutation are
   the highest-grade MEMORY.md candidates; the done-round convention may fold
   them (Folder_Native_Memory.md owns that convention).
8. **Thread projection for free:** a panel is a WorkThread; rounds are turns
   (PM brief = user turn; each challenger report = a worker turn); done settles.

## 2. Surface

- `alln pair panel start --doc <path> --project <id|path> --seat <alias>:<lens> …
  [--max-rounds N] [--json]` → panelId, scaffolded brief path, next command.
- `alln pair panel round --panel <id> --brief <md> [--seats a,b] [--no-wait] [--json]`
  → BLOCKS; returns all reports verbatim + per-seat status; `--seats` reruns a
  subset (a challenger that stalled) without a full round.
- `alln pair panel status|watch|scaffold-brief` — mirror the pilot verbs.
- `alln pair panel done --panel <id> --note "…"` — done-by-declaration.
- JSON envelopes registry-projected; NDJSON progress per seat settling (reports
  stream back as seats finish — the session can start reading early).

## 3. Slices

| Slice | Deliverable |
| --- | --- |
| PN-S01 | `PanelState` + store (+ parked/unowned semantics, orphan-reconcile guard) + tests |
| PN-S02 | Per-seat read-only dispatch: additive per-seat messages on the answer-run path; read-only mechanism per driver + ephemeral-clone isolation for non-enforcing drivers (clonefile, cleanup, tests with a fake mutating seat proving the real tree is untouched) |
| PN-S03 | `PanelCoordinator.runRound` — blind fan-out, verbatim capture, partial-seat rerun, ceilings (maxRounds) |
| PN-S04 | CLI verbs + envelopes + contracts + help topic (extend pm_relay topic family) |
| PN-S05 | Thread projection + works test (below) |

## 4. Works test

Harden a REAL phase doc (this one is a fine candidate) across 2 rounds with 3
seats on ≥2 different CLIs: start → round 1 (three blind reports return in one
call) → session refutes at least one finding and hardens the doc → round 2 shows
the survivors attacking the NEW text (fresh doc re-read proven) → done with a
note naming what survived refutation. Verify: no seat saw another's output
(transcripts), the real tree untouched by non-enforcing seats (clone isolation),
panel thread readable in the inbox, reports verbatim. Filters green; contracts
regenerated.

## 5. Non-goals

- Scoring/ranking machinery, (lens,model) scoreboards — Pressure_Test.md owns
  methodology; Panel is transport + safety. The session judges.
- Mutating panel seats, ever. A panel that edits is a pilot — use the pilot.
- Auto-synthesis. The day we spawn a synthesizer, that's Relay-for-specs — a
  separate future decision, not this phase.
