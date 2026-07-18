# Agent Front Door — no CLI agent ever routes around alln again

Status: SHIPPED — piloted delivery #4, relay_c1e3c087 (PM = live Claude session; dev
= Cursor Grok 4.5). F1+F2 `4c0d9c49`: install-cli PERFORMS (installed/repaired/
alreadyInstalled, --path/--print, INSTALL_CLI_TARGET_UNWRITABLE guidance),
`binary.onPath` doctor check, bootstrap self-heals (binaryPath/onPath + fallback
line + install step off-PATH). F3+F4+version `94bd9251`: models --json empty root
cause = CatalogRoots/ModelCatalogPaths ignored ALLNIGHTER_SUPPORT_DIR while
SetupStore honored it (roster in a different tree → --bench filtered empty);
unified via AllnighterSupportRoot; counsel+nextActions on empty models/teams/doctor
(hello was already fine); `alln version`; help/AGENTS.md coherent. PM independently
verified: real temp-dir install runs, isolated-context models now populated,
contracts clean. Closes Opus field reports #1, #3, #4.
Owner: AllnighterCore + CLI
Updated: 2026-07-18

Related (the three agent gates): this doc = gate 1 (findable, SHIPPED) ·
`Agent_Onboarding.md` = gate 2 (suggested) · `Agent_Intent_Router.md` = gate 3
(routes intent → the right killer team). The no-empty-silence law (F3) extends to
the router's `team hello --for` mode: it too must return a concrete command or an
honest fallback, never a bare "pick a team."

## Why (founder call: first-class, nothing more important)

A real incident (2026-07-16): a fresh Opus session was asked to use Allnighter.
`which alln` failed (no PATH install), `alln models` returned an EMPTY list with no
next action, and the agent did what all agents do with friction — silently routed
around the product, extracting the grok invocation recipe from `DefaultConfig.swift`
and running its own loop. Agents don't file complaints; they route around. The bar
is not "agents can find Allnighter" — it is "walking in is cheaper than routing
around." Human first-run GUI is a separate spec (`docs/phases/setup/00_…`); THIS
slice is the agent-facing front door.

## The trust guarantees (SSOT — cite from Onboarding + Intent Router)

The isolation/liveness/GC/honesty work is not just reliability plumbing; it is
the reason an experienced agent trusts walking in. Named once here so the other
gate docs cite one source instead of re-listing:

- **Requested worker or loud failure** — never a silent model swap.
- **No fake success** — completion is real or it escalates.
- **No concurrent writers** — one mutating worker per repo/lane; two `alln`s
  isolate like two `claude`s.
- **Durable recovery** — a run that loses its terminal is recoverable, not lost.
- **Exact commit range** — the work's footprint is named precisely.
- **Preserved transcript** — nothing is invented after the fact.
- **Explicit escalation** — a blocked run stops and says so.

Marketing-compressed: *it never swaps your model, fakes completion, or lets two
agents edit the same repo behind your back.* That is a differentiator, not a
footnote — surface it as product value wherever agents and users first meet alln.

## F1 — `alln install-cli` performs the install (CLI)

Today `install-cli` only PRINTS instructions. Running the command IS consent —
it should DO the install:
- Create the symlink (default `/usr/local/bin/alln` if writable, else
  `~/.local/bin/alln`; `--path <dir>` override; `--print` keeps today's print-only
  behavior). Idempotent: re-running fixes a stale/wrong symlink and says so.
- Reports exactly what it did/found, `--json` envelope included.
- New doctor check `binary.onPath`: is `alln` resolvable on PATH and pointing at
  this binary? Degraded with `fixCommand: alln install-cli` when not.

## F2 — the bootstrap snippet is self-healing (activation)

`alln bootstrap` output currently assumes `alln` resolves. Fix:
- The snippet's first line carries the ABSOLUTE path of the running binary as a
  fallback: agents that find the snippet before the symlink still find the product
  (e.g. "Allnighter is available via `alln` (fallback: `<abs-path>`)").
- When the binary is NOT on PATH at `bootstrap` time, the snippet includes the
  one-time `alln install-cli` step and says why.
- `--json` gains `binaryPath` + `onPath` fields so an agent can self-install.

## F3 — no empty silence, ever (agent surfaces)

`alln models` returning `[]` with exit 0 and no guidance is the sharpest failure in
the incident. Rules:
- Investigate WHY models could resolve empty in a fresh context (config dir absent?
  detection cache empty? wrong cwd?) and name the cause in the delivery report.
- Empty models (human + `--json`) must state what's missing and the next command
  (`alln doctor --json`, then setup guidance) — a `nextActions` block in the JSON,
  never a bare empty array without counsel.
- Sweep the other first-contact surfaces for the same rule: `team hello` with zero
  ready teams, `teams` with an empty bench, `doctor` when config dir is missing.
  Fix what violates it; list what was already fine.

## F4 — help/docs coherence

- `bootstrap` help topic + `alln bootstrap` snippet mention `install-cli` (F1) as
  step zero.
- `quickstart` topic: first line = ensure on PATH.
- AGENTS.md routing table row for the front door.

## Works test (the incident, replayed)

From a shell where `alln` is NOT on PATH: resolve the built binary by absolute path
→ `alln bootstrap --json` names the fallback path + install step → `alln
install-cli` performs the symlink (idempotent on second run) → `which alln`
resolves → `alln team hello --json` next plan runnable → `alln models --json`
non-empty on this machine; then simulate the empty case (fixture/temp config home)
and confirm counsel appears instead of silence. All Relay/Pilot/Help/Doctor filters
green; contracts regenerated.
