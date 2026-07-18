# Panel Polish — first-real-use fixes from panel_753613c7

Status: **Specced** (PP-S01–S03; seeded by the five improvement notes from the
first five-seat panel, 2026-07-16 — Agent Onboarding hardening, 21 findings,
4 vendors, both isolation modes)
Owner: AllnighterCore + CLI
Updated: 2026-07-16

> One line: the panel substrate held on its first real five-seat run; these are
> the burrs the operator's hand actually caught. Small, mechanical, no new nouns.

## 0. Provenance (the five notes, and one correction)

The PM session that ran panel_753613c7 recorded five improvement notes. Grounding
them against the shipped code (2026-07-16) corrects one:

1. **Unstructured seats read as "zero findings"** unless the synthesizer inspects
   the per-seat `reason`. Real: `PanelFindingsParser.seatResult` keeps the seat
   `.done` with `findings: nil` and a reason string — correct storage law, but the
   round envelope buries it. The PM initially misread model_agy_opus as silent.
2. **"Teach the schema with an example"** — STALE AS REMEMBERED.
   `PanelSeatPrompt.schemaContract` already ships a full sample fenced block, and
   the seat failed anyway: it wrote prose and claimed "the JSON block is in the
   artifact" (receipt: MEMORY.md seat line, panel_753613c7 r1). The gap is not
   the example — it is **placement**: nothing forbids delegating the block to an
   artifact/file the transport never returns. Fix is a placement law, not a
   bigger example.
3. **Stranded parked panels** from operator fumbles (parse-error restarts) litter
   the state dir. There is no warning at start time and no way to close a stray
   without faking a `done`.
4. **Convergence deserves surfacing** — three blind lenses hit the consent
   boundary independently; the strongest accept signal of the round was
   discovered by hand-diffing seat reports.
5. **The FR8 line-JSON law made panel parsing trivial** (shipped 4dfe97db hours
   before the run, immediately load-bearing). No code — recorded as locked below.

## 1. Decisions (locked)

1. **`unstructuredSeats` is envelope-top truth.** Done-but-unstructured storage
   law is untouched (verbatim report kept, findings nil — never discard). The
   projection must scream: `PanelRoundJSON` and `PanelRoundLogEntry` each gain
   `unstructuredSeats: [String]` (worker ids; always present, `[]` when clean),
   derived from `status == done && findings == nil` — a projection, never stored
   state, so no migration. Human (non-`--json`) round output prints one warning
   line per unstructured seat: read `seatResults[].report`, the content may be
   real. No synthesizer should ever be able to mistake unstructured for silent.
2. **Placement law in the schema contract.** `PanelSeatPrompt.schemaContract`
   gains explicit rules: the fenced block must appear **in the report text
   itself, as the last thing in it** — never "in an artifact", a file, an
   attachment, or described in prose. The report text is the only channel
   Allnighter reads. (The RelayVerdict lesson already gave us the example block;
   this closes the escape hatch model_agy_opus actually used.)
3. **Stray-parked advisory + `panel abandon`.** `panel start` emits an ADVISORY
   (never a refusal — same physics as the dirty-target advisory, Pilot_Panel.md
   decision 8) when another panel with the same `projectId` + `targetPath` is
   parked at `awaitingPM`: names the panel id(s) and the two exits (resume with
   `panel round`, or `panel abandon`). New verb `alln panel abandon --panel <id>
   [--note …] [--json]` settles a panel to `done` with note `"abandoned"` (or
   `"abandoned: <note>"`). **No fourth status** — done-by-declaration extends to
   done-by-abandonment; the note carries the distinction. Refusals mirror
   `done`: in-flight round with a live owner → `PANEL_ROUND_IN_FLIGHT`; already
   done → `PANEL_NOT_AWAITING`; dead-owner running panels reconcile first (the
   existing orphan path), then abandon.
4. **Convergence is a flag, never a rank.** Pilot_Panel.md decision 1 (the
   session is the synthesizer; no ranking) stands. The round envelope gains
   `convergence: [{anchor, seats}]` — mechanically extracted overlap only:
   file-path-shaped tokens (normalized, line numbers stripped) pulled from each
   finding's `evidence`/`claim`; an entry exists when ≥2 **distinct seats** cite
   the same anchor. Sorted lexically by anchor for determinism. No scores, no
   ordering by importance, no topic inference in v1 — path overlap is the cheap
   90% (the consent-boundary convergence was three seats citing the same spec
   section/file). Always present, `[]` when no overlap.
5. **FR8 line-JSON law is KEEP FOREVER.** Streaming `--json` = NDJSON progress
   lines + one single-line terminal envelope. Load-bearing for panel synthesis
   from real use. Recorded here so nobody "improves" it into pretty-printed
   multi-line JSON; no code in this phase.

## 2. Surface deltas

- `PanelRoundJSON` += `unstructuredSeats: [String]`, `convergence:
  [PanelConvergenceJSON]` (both always present).
- `PanelRoundLogEntry` += `unstructuredSeats: [String]` (status/watch/done
  readers get the same truth).
- `PanelStartJSON` += `strayPanelAdvisory: String?` (nil when clean).
- New verb: `alln panel abandon --panel <id> [--note …] [--json]` → the existing
  done envelope (`PanelJSON` projection). CommandSpec + help + error catalog
  entries; contracts regenerated.
- `PanelSeatPrompt.schemaContract` += placement rules (report text itself, last
  thing, never an artifact).

## 3. Slices

| Slice | Deliverable |
| --- | --- |
| PP-S01 | **Envelope truth**: `unstructuredSeats` projection on round envelope + round log + human warning lines; schema-contract placement law; parser-level test proving an agy-style prose report (real content, no block) surfaces at envelope top |
| PP-S02 | **State-dir hygiene**: stray-parked advisory on `panel start` (same project + target, `awaitingPM`) + `alln panel abandon` verb (note-stamped done; in-flight/already-done refusals; dead-owner reconcile-then-abandon) + contracts/help + tests |
| PP-S03 | **Convergence flag**: anchor extraction (path-shaped tokens, normalized) + `convergence` on the round envelope + determinism tests (lexical order; ≥2 distinct seats; single-seat repeat ≠ convergence) |

## 4. Works test

Rerun the panel bootstrap recipe against a real doc with a 3-seat roster where
one seat is prompted (via lens instruction, test-only) to answer in prose without
the block: the round envelope's `unstructuredSeats` names it at top level and the
human output warns; a second `panel start` on the same doc while the first is
parked prints the stray advisory naming the first panel id; `alln panel abandon`
on the stray settles it done with the abandoned note and `panel status` agrees;
a round where two seats cite the same file path yields exactly one `convergence`
entry naming both seats. Filters green; contracts regenerated.

## 5. Non-goals

- Scoring, ranking, weighting, or any synthesis hint beyond the raw overlap flag
  (the session judges; Pilot_Panel.md decision 1).
- Topic/semantic convergence (embeddings, keyword clustering) — path overlap
  only in v1; measure the miss rate in use before buying more.
- A relay/pilot `abandon` mirror — separate decision on those state machines
  (relay has adopt/ownership semantics panel does not).
- Storing derived warnings in `PanelState` — projections stay projections.
- Retrying/re-prompting an unstructured seat automatically — the session decides
  (`--seats <id>` rerun already exists).
