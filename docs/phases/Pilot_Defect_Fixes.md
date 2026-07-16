# Pilot Defect Fixes — the three works-test findings

Status: In progress — first real piloted delivery on the Allnighter repo itself
Owner: AllnighterCore + docs
Updated: 2026-07-16

The PL-S07 works test (Pilot_Relay.md §8) surfaced three defects. This doc is the
spec for fixing them. It is being delivered VIA the pilot loop it describes — the
piloting session is the PM, the dev seat is Grok 4.5 through Allnighter.

## D1 — dev-turn prompt gets the execution-playbook preamble injected twice (code)

Observed (works-test relay_47acbcce, run 67157A89): the dispatched dev prompt began
with the `ExecutionPlaybookPreset.prompt` text ("You are executing a product slice…
Follow the Execution Playbook…") repeated twice back-to-back, before the
`RelayDevPrompt` wrapper. Known injection sites: `SkillCatalog.swift` ("execution_playbook"
skill prompt) and `BuiltInTeams.swift` (starters). Root cause TBD by the dev — likely
the same preset text applied at two assembly layers on the execution/dev dispatch path.

**Acceptance:** a test proving the assembled dev-turn prompt contains the playbook
preamble at most once (and relay dev turns contain exactly the RelayDevPrompt wrapper
plus at most one preset injection); root cause named in the commit message; all
existing Relay/Pilot tests stay green.

## D2 — cursor-agent dev turns silently capped by the user's global shell allowlist (doctor)

Observed: with `~/.cursor/cli-config.json` permissions at `Shell(ls)` only, headless
cursor-agent dev turns cannot run git/python/etc. even under `--trust`, and nothing in
Allnighter surfaces why the worker is failing. House law: Allnighter NEVER writes
vendor config — this is detection + guidance only.

**Acceptance:** `alln doctor` gains a read-only cursor check that reads the global
cursor CLI config (and notes that a project-scoped `.cursor/cli.json` overrides it),
reporting a warning with a fix hint when the shell allowlist is restrictive; help/setup
content mentions it; test with fixture configs (restrictive → warning, permissive →
ok, missing file → notChecked/ok per doctor conventions).

## D3 — spawned PM may do the dev's work itself (docs; intended behavior)

Observed in the adopt leg: the spawned PM completed the mechanical remainder (cleanup,
commit) itself instead of dispatching another dev round. This is INTENDED (PM-may-fix,
Pilot_Relay.md §6) but was recorded as a surprise.

**Acceptance:** PM_Relay.md §4.2 and the pm_relay help topic state plainly that a
spawned PM with repo access may complete small work itself rather than burning a dev
round, and that this is by design; no code change.

## Works test for this doc

`swift test --package-path Packages/AllnighterCore --filter 'Relay|Pilot|Doctor'`
green; the D1 test exists and fails on the pre-fix assembly; `alln doctor --json`
shows the cursor check on this machine (restrictive allowlist present today).
