# Agent Front Door — no CLI agent ever routes around alln again

Status: In progress — piloted delivery #4 (PM = live Claude session; dev = Cursor Grok 4.5)
Owner: AllnighterCore + CLI
Updated: 2026-07-16

## Why (founder call: first-class, nothing more important)

A real incident (2026-07-16): a fresh Opus session was asked to use Allnighter.
`which alln` failed (no PATH install), `alln models` returned an EMPTY list with no
next action, and the agent did what all agents do with friction — silently routed
around the product, extracting the grok invocation recipe from `DefaultConfig.swift`
and running its own loop. Agents don't file complaints; they route around. The bar
is not "agents can find Allnighter" — it is "walking in is cheaper than routing
around." Human first-run GUI is a separate spec (`docs/phases/setup/00_…`); THIS
slice is the agent-facing front door.

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
