# Field Reports 4 — commit fidelity, proof surfacing, token truth

Status: In progress — piloted delivery #11 (PM = live Claude session; dev = Cursor Grok 4.5)
Owner: AllnighterCore + CLI
Updated: 2026-07-16

Source: founder field report from the first extended relay-rhythm usage (9 slices,
a full iOS surface + an isolated feature, zero scope violations — "the core loop
is genuinely excellent"). Three real items; three already closed.

## Already closed (verify + state in the report; reporter's binary predates them)

- **#1 lane routing** — FR7/FR3 (2402de6b): the header now appends `lane code
  (context — --team routes)`, the wiring truth is decided (lane never routes on
  `run`), and docs say so. Residual acceptance here: when `--team` IS given, the
  header must name the resolved team where "Default Team" appears today — verify,
  and fix if the resolved team name doesn't surface.
- **#3 machine-readable result** — FR3 `repoDelta` (sha, files) + FR5 `outcome`
  (status/committed/headline). buildStatus arrives via FR13 below.
- **#6 install-cli** — performs since F1 (`4c0d9c49`).

## FR12 — commit-message fidelity (instruct + verify, never perform)

Observed: with an exact commit message in the order, the worker reworded the
trailer on ~2/9 slices; only "use VERBATIM" wording made it reliable. The ask was
"alln applies the commit deterministically" — REFUSED: Allnighter does no git,
inviolable. The law-compatible version:

- `alln run --commit-message "<exact>"` (and the relay dev-prompt equivalent via
  the order): injects a strongly-worded verbatim block into the worker prompt
  ("commit message, byte-exact, do not reword, do not translate, append nothing")
  — the proven "use VERBATIM" wording, productized once.
- **Fidelity verification**: `repoDelta` already captures commit subjects — when
  `--commit-message` was given, `outcome` gains `commitMessageMatched: Bool`
  (prefix/subject comparison; state the exact comparison rule) and the headline
  flags a mismatch. Detection and surfacing, never enforcement.
- `--no-commit`: the injected order tells the worker to leave work uncommitted
  (the PM commits with their own hands); verification = repoDelta shows changed
  files with zero new commits; `outcome.committed=false` + headline "left
  uncommitted for PM review (as ordered)". Mutually exclusive with
  `--commit-message`.

**Acceptance:** both flags on `alln run` (+ CommandSpec/docs/help); prompt
injection exactly once (dispatch-capture tests); fidelity flag true/false paths
tested; no-commit verification path tested; contracts regenerated.

## FR13 — proof: run and surface, never gate git

Observed: the worker self-verified by building every time — trust-based. The ask
was "block the commit if proof fails" — commit-blocking is impossible under the
law (the worker commits). The honest version, with precedent (the old repo-declared
check principle: Allnighter runs the repo's check and surfaces the result):

- `alln run --proof "<cmd>"`: after the worker settles, Allnighter runs the
  DECLARED command as a bounded subprocess at the project root (timeout, captured
  exit code + tail — mirror the deleted ProjectVerificationService's bounded
  /bin/sh -c shape, rebuilt minimal and run-scoped).
- `outcome` gains `proof: {command, exitCode, passed, outputTail}`; headline
  appends `proof passed`/`PROOF FAILED (exit N)`. A failed proof NEVER un-commits
  or blocks anything — it tells the PM the truth loudly; the PM (or the relay's
  spawned PM next round) decides.
- The worker prompt, when --proof is given, names the command as the order's
  acceptance ("your work will be verified by: <cmd>") — alignment, not secrecy.
- Relay dev turns inherit automatically if the handover names a proof (already
  convention); the FLAG is for bare runs.

**Acceptance:** bounded execution (timeout test with a hanging fake), pass/fail
paths in outcome + headline, prompt naming test, works on a real temp-repo run.

## FR14 — token/cost truth where drivers report it (investigate + surface)

Observed: Grok quota is shared with product usage; the PM wants a token line to
decide route-vs-inline. Rule: surface ONLY what the driver actually reports —
never estimate, never fake.

**Acceptance:** investigate which warm/cold dialects report usage (claude
stream-json usage fields; codex/cursor/grok — name what each provides); where
available, `outcome` gains `usage: {inputTokens?, outputTokens?}` and one
headline suffix (`· 12.4k tok`); where unavailable, the field is ABSENT (never
zero). Report the per-driver truth table as fact. If nothing reliable exists
beyond claude, ship claude-only and say so.

## Works test

Temp-repo mutating run with `--commit-message` (exact match → matched:true; a
fake rewording worker → matched:false + flagged headline); `--no-commit` leaves
tree dirty + honest outcome; `--proof "exit 1"` yields PROOF FAILED without
touching the commit; usage line appears for a claude seat and is absent for one
that doesn't report. Filters `Run|Relay|Pilot` green; contracts regenerated.
