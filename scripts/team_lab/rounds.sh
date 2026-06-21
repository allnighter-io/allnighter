#!/usr/bin/env bash
# Run N calibration rounds for one team/suite via MCP-only lab driver.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SUITE="${1:?suite id}"
ROUNDS="${2:-4}"
TEAM="${3:-}"
VARIANT="${4:-baseline}"

ALLN="${ALLN_BIN:-$ROOT/Packages/AllnighterCore/.build/debug/alln}"
if [[ ! -x "$ALLN" ]]; then
  (cd "$ROOT/Packages/AllnighterCore" && swift build -c debug)
fi

for r in $(seq 1 "$ROUNDS"); do
  echo "=== team-lab round $r / $ROUNDS suite=$SUITE variant=$VARIANT ==="
  args=(python3 "$ROOT/scripts/team_lab/run.py" --suite "$SUITE" --round "$r" --variant "$VARIANT")
  [[ -n "$TEAM" ]] && args+=(--team "$TEAM")
  "${args[@]}"
done
