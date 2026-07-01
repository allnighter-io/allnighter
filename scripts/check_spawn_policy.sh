#!/usr/bin/env bash
# A1 (AgentOS relocation): AgentOS's SubprocessCommandRunner no longer
# hardcodes Allnighter's env guards (team-recursion depth increment +
# loopback tool-token scrub). Those behaviors now live in
# AllnighterSpawnEnvironmentPolicy and MUST be injected at every
# construction site, or a deep worker silently loses the recursion guard
# and/or leaks ALLNIGHTER_TOOL_TOKEN to a subprocess.
#
# This guards against a bare `SubprocessCommandRunner()` construction
# (which defaults to the identity policy) creeping back into product
# code. Test files are exempt — they legitimately exercise the runner's
# base mechanics with the identity policy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> check spawn environment policy is injected at every SubprocessCommandRunner() site"

hits=$(rg -n 'SubprocessCommandRunner\(\)' \
  "$ROOT/Packages/AllnighterCore/Sources" \
  "$ROOT/Apps/AllnighterMac/Sources" \
  --glob '*.swift' 2>/dev/null || true)

if [[ -n "$hits" ]]; then
  echo "check: bare SubprocessCommandRunner() found in Sources/ — this drops the" >&2
  echo "       team-recursion guard (ALLNIGHTER_TEAM_DEPTH) and the" >&2
  echo "       ALLNIGHTER_TOOL_TOKEN scrub. Construct it with" >&2
  echo "       SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy())" >&2
  echo "       instead (see Packages/AllnighterCore/Sources/AllnighterCore/AllnighterSpawnEnvironmentPolicy.swift)." >&2
  echo "$hits" >&2
  exit 1
fi

echo "check: no bare SubprocessCommandRunner() constructions in Sources/"
