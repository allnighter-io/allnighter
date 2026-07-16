# Field Reports 3 — lane-label truth, JSON stream discipline, retry idempotency, unattended vocabulary

Status: In progress — piloted delivery #10 (PM = live Claude session; dev = Cursor Grok 4.5)
Owner: AllnighterCore + CLI
Updated: 2026-07-16

Sources: a repeat founder field report (lane labeling), three PM-verified anomalies
from piloted deliveries #7–#9, and the pre-launch nocturnal-language audit.

## FR7 — the lane label still reads like a silent fallback (repeat report)

Observed (second report of the same confusion, POST-FR2): runs with `--lane code`
still label `default_chat · Default Team`; the run behaved correctly (mutating,
committed), but the label makes a careful PM wonder whether `--lane code` routes
to a code-execution team or silently falls back. FR2's locked decision: with an
explicit `--worker`, `--lane` is context metadata, NOT a router. The decision is
right; the OUTPUT still doesn't answer the question a PM actually asks.

**Acceptance:** (1) VERIFY the wiring truth and state it in the report: what does
`--lane code` do today with an explicit worker (expected: tags), and without one
(name exactly what resolves — if a bare `--lane` run silently lands on
`default_chat` where a lane execution team plausibly should route, surface the
truth, don't redesign routing in this slice — report it as a decision candidate).
(2) The human footer and `outcome.headline`, when `--lane` was given with an
explicit worker, append a clarifier: `lane code (context — --team routes)`. (3)
When the preset is the default on a mutating run, the footer leads with the
identity, and the preset id moves to provenance position so `default_chat` never
reads as the thing that did the work. (4) `alln docs run` says all of this in one
sentence. A PM reading only the run output can answer "did --lane route?" — that
is the test.

## FR8 — one law for --json stdout: streams are line-JSON, whole

Observed twice by the PM (panel round, and the pilot --no-wait case below): when a
command STREAMS progress in `--json` mode, stdout mixes one-line NDJSON events
with a PRETTY multi-line final envelope. Line-oriented agent parsers choke; the PM
resorted to find-the-last-brace surgery twice in one week.

**Law:** if a `--json` command emits progress events, EVERY stdout emission is
exactly one line of JSON — including the final envelope (last line, complete
object). Commands that emit a single envelope and no stream may keep pretty
output. Apply to `panel round`, `pilot handoff`, `pilot watch`, and any surviving
streaming emitter. Breaking change acceptable pre-launch (agent-first). Tests
assert every stdout line parses independently.

## FR9 — stall-retry must check for delivered work before re-dispatching

Observed (memory seed relay): the dev committed, the settlement signal was
missed, the classifier said stalled, the bounded retry re-ran the turn, and the
work was committed twice (e545a289 + 061b1a1b — harmless there, not in general).

**Acceptance:** before a stall/empty retry of a MUTATING turn, re-observe
evidence of delivery: if HEAD moved past the turn's baseline (GitObserver read),
classify delivered-not-stalled and settle with the observed repoDelta instead of
re-dispatching. If evidence is ambiguous (no commit but output exists), the retry
prompt must state that a prior attempt may have partially completed and instruct
verify-before-redo. Test: fake runner that commits then reports a stall → exactly
one commit, round settles delivered.

## FR10 — small envelope nits

- `pilot handoff --no-wait --json` printed non-JSON (possibly empty) stdout in
  one observed case: guarantee a single-line JSON ack `{relayId, status,
  roundInFlight…}` on the detach path. Test.
- `panel start --json` roster echo: the per-seat isolation mode field the works
  test expected read as absent — name the field consistently (`isolation`:
  `driverReadOnly|clone`), assert in tests, regenerate schema.

## FR11 — unattended, not nocturnal (pre-launch vocabulary)

Relay is unattended, not overnight — the mode is about who holds the clock, not
the time of day. Sweep with word-boundary care:
- User-facing: the adopt help section title "Night shift: …" → "Adopt: hand the
  SAME relay to a spawned PM (unattended)". Regenerate help artifacts.
- Code comments: "night-shift handover" in RelayCLI.swift / RelayCoordinator.swift
  → "adopt (unattended handover)".
- Live phase docs: Pilot_Relay.md §5 "night-shift" framing → adopt/unattended;
  Folder_Native_Memory.md "night-2" → "second-run" (the conversion insight keeps
  its meaning: the second UNATTENDED run opens by citing what the first learned).
- **EXEMPT:** Boost Window's "overnight quiet band (22:00–06:00)"
  (BoostWindowSettings/BoostWindowJSON/UtilizationSeedExecutor) — genuinely
  time-of-day quota semantics, not relay framing. Do not touch.

## Works test

A streamed `panel round --json` and a `pilot handoff --json` parse line-by-line
with a dumb `while read line; jq` loop; a fake commit-then-stall run yields one
commit; run output with `--lane code --worker X` answers the routing question on
its face; `alln help get pm_relay` contains no nocturnal words; Boost Window
untouched. Filters `Panel|Relay|Pilot|Run|Help` green; contracts regenerated.
