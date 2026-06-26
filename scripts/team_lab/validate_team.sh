#!/usr/bin/env bash
# Validate one team across every case in a suite (deploys the team via its champion
# overlay, runs each case once). Used by the campaign supervisor for beta team checks.
#
#   bash scripts/team_lab/validate_team.sh <champion-overlay.json> <suite-id> [variant]
#
# Each case is an independent run.py invocation, so a single bad case fails only that
# case; the supervisor's retry/backoff wraps the whole script.
set -euo pipefail
cd "$(dirname "$0")/../.."

OVERLAY="${1:?champion overlay path}"
SUITE="${2:?suite id}"
VARIANT="${3:-beta_validate}"
ROUND="${4:-1}"

export ALLN_JUDGE1_CMD="${ALLN_JUDGE1_CMD:-claude -p --max-turns 1}"
export ALLN_JUDGE2_CMD="${ALLN_JUDGE2_CMD:-codex exec - --full-auto}"

ALLN="${ALLN_BIN:-Packages/AllnighterCore/.build/debug/alln}"
if [[ ! -x "$ALLN" ]]; then
  echo "building alln (debug)..."
  (cd Packages/AllnighterCore && swift build -c debug)
fi

# bash 3.2 (macOS default) has no mapfile; read newline-separated case ids portably.
CASE_IDS="$(python3 -c "
import json
s=json.load(open('docs/team-lab/suites/${SUITE}.json'))
print('\n'.join(c['caseId'] for c in s['cases']))
")"

echo "=== validate_team overlay=$OVERLAY suite=$SUITE $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
rc=0
while IFS= read -r CASE; do
  [[ -z "$CASE" ]] && continue
  echo "--- case=$CASE ---"
  if ! python3 scripts/team_lab/run.py \
      --suite "$SUITE" \
      --case "$CASE" \
      --round "$ROUND" \
      --variant "$VARIANT" \
      --champion-overlay "$OVERLAY"; then
    echo "case FAILED: $CASE" >&2
    rc=1
  fi
done <<< "$CASE_IDS"
exit "$rc"
