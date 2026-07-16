# Field Reports 1 — the four remaining Opus dogfood findings

Status: SHIPPED — piloted delivery #5, relay_5a2894bc (PM = live Claude session; dev
= Cursor Grok 4.5). FR1 `3cc2728e` (run in top-level help + CLIHelpDriftTests
registry↔help gate, bite-verified), FR2 `e11d45c2` (RunIdentity: worker · lane ·
mutating|readOnly headline, "Default Team" honest display, preset id demoted to
provenance; additive TeamRunJSON fields), FR3 `430b5c8e` (RepoDelta via read-only
GitObserver range queries: baseline/head/commits/files in TeamRunJSON + "committed
<sha>: N files" human line; relay dev turns inherit through RunService with zero
relay code), FR4 `10fd73a4` (ProvenanceConvention trailer ask in RelayDevPrompt +
bare mutating runs, exactly once; convention-not-mechanism noted in PM_Relay.md).
PM independently verified: 260 tests green, contracts clean. **All seven Opus
dogfood field reports are now closed** (1/3/4 by Agent_Front_Door, 2/5/6/7 here).
Owner: AllnighterCore + CLI
Updated: 2026-07-16

Source: a real fresh-agent session driving `alln run` on another repo (2026-07-16).
Reports #1/#3/#4 were closed by `Agent_Front_Door.md`. These are #2/#5/#6/#7.

## FR1 — `run` visible in top-level help + a help/registry drift gate (#2)

Observed: `alln --help` lists `team` but not `run`. A frontier agent concluded the
product was READ-ONLY and routed around it — an identity mislabel, not a docs nit.

**Acceptance:** `run` (with its one-line description incl. `--try-fix`) appears in
the top-level help; a NEW drift test asserts every ContractRegistry command surfaces
in `printHelp` output OR is on an explicit, commented exclusion list (pattern:
the hello `nextCommandPlan` drift gate) — a registry/help gap can never recur
silently.

## FR2 — run identity tells the truth: worker + lane + write policy (#5)

Observed: `alln run "<slice>" --lane code --worker model_grok` labeled itself
`default_chat`. The run routed correctly (it committed), but the label leaked an
internal preset id as the run's identity, leaving the operator unable to tell
whether `--lane` routed anywhere.

**Decision (PM, per Unified Run Model):** with an explicit `--worker`, `--lane` is
context metadata, not a router — one worker was always going to run. Identity must
lead with what an auditor needs: worker, lane, and write policy. The preset id is
provenance detail, never the headline.

**Acceptance:** human output + `TeamRunJSON` lead with (or prominently include)
`worker <id> · lane <lane> · mutating|readOnly`; when no named team was chosen the
display name says "Default Team" (honest) with the preset id as a secondary field;
`alln docs run` / help text states plainly what `--lane` does with and without an
explicit worker/team. Existing envelope consumers must not break: additive fields +
display-name fix only unless a breaking change is genuinely required (justify if so).

## FR3 — repo delta in run truth: verify without shelling to git (#6)

Observed: after a mutating run, the operator had to `git log` manually to confirm
the commit. The pilot loop already pins `baseline..head` per round — a bare
`alln run` should give the same truth.

**Acceptance:** mutating runs capture (via GitObserver READS — Allnighter still does
no git): HEAD before and after, commit SHAs in the range, and a changed-files
summary (names + counts; no patch bodies). Surfaced in `TeamRunJSON` (additive
`repoDelta` block) and the human summary ("committed 2518718: 3 files"). No repo
change → stated honestly (`repoDelta.changed: false`). Non-mutating runs: no block
or explicit null. Schema regenerated; tests with a real temp git repo.

## FR4 — provenance by convention: the dev preamble asks for a trailer (#7)

Observed: dogfooded commits carry no marker that an Allnighter-dispatched worker
authored them. Allnighter does no git, so this CANNOT be mechanical — it is a
standing instruction, honestly labeled as convention.

**Acceptance:** the standing dev/execution preambles (RelayDevPrompt; the mutating
run wrapper if one exists) ask the worker to end commit messages with
`Co-Authored-By: <worker display name> via Allnighter` — worded once, tested in
prompt-assembly tests; PM_Relay.md notes it is convention-not-mechanism. No
enforcement, no git.

## Works test

`alln --help | grep run` non-empty; drift test fails if a future command skips
help; a real mutating run on a temp repo shows worker/lane/mutating identity +
`repoDelta` with the actual SHA; RelayDevPrompt assembly contains the trailer ask
exactly once. Filters `Relay|Pilot|Help|Run|FrontDoor` green; contracts regenerated.
