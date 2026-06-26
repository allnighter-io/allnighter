#!/usr/bin/env bash
# Run ONE suite case for one team arm, and exit non-zero unless the run is
# contract-GREEN (runContractScore >= 0.95, no fsBypass). A non-green run means a
# worker silently stalled/emptied — the supervisor's retry/backoff then re-runs
# this same case until a truthful green run exists, which is what compare.py needs.
#
#   bash scripts/team_lab/run_case_green.sh <suite> <case> <variant> <overlay.json|team:ID>
#
set -uo pipefail
cd "$(dirname "$0")/../.."

SUITE="${1:?suite id}"
CASE="${2:?case id}"
VARIANT="${3:?variant}"
TEAM_SEL="${4:?overlay path or team:ID}"
ROUND="${5:-1}"

ALLN="${ALLN_BIN:-Packages/AllnighterCore/.build/debug/alln}"
if [[ ! -x "$ALLN" ]]; then
  echo "building alln (debug)..."
  (cd Packages/AllnighterCore && swift build -c debug)
fi

TEAM_ARGS=()
case "$TEAM_SEL" in
  team:*) TEAM_ARGS=(--team "${TEAM_SEL#team:}") ;;
  *)      TEAM_ARGS=(--champion-overlay "$TEAM_SEL") ;;
esac

echo "=== run_case_green suite=$SUITE case=$CASE variant=$VARIANT sel=$TEAM_SEL $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
OUT="$(python3 scripts/team_lab/run.py \
  --suite "$SUITE" \
  --case "$CASE" \
  --round "$ROUND" \
  --variant "$VARIANT" \
  --alln "$ALLN" \
  "${TEAM_ARGS[@]}" 2>&1)"
status=$?
echo "$OUT"
if [[ $status -ne 0 ]]; then
  echo "run.py exited $status for $CASE/$VARIANT" >&2
  exit "$status"
fi

LAB_DIR="$(printf '%s\n' "$OUT" | sed -n 's/^LAB_DIR=//p' | tail -1)"
if [[ -z "$LAB_DIR" || ! -d "$LAB_DIR" ]]; then
  echo "could not resolve LAB_DIR for $CASE/$VARIANT" >&2
  exit 1
fi

SCORE_JSON="$LAB_DIR/evaluation/run-contract-score.json"
GREEN="$(python3 - "$SCORE_JSON" <<'PY'
import json,sys
try:
    c=json.load(open(sys.argv[1]))
except Exception as e:
    print(f"0 (no score: {e})"); raise SystemExit(0)
score=c.get("runContractScore",0)
fs=c.get("fsBypass")
print("1" if (score>=0.95 and not fs) else f"0 (score={score} fsBypass={fs})")
PY
)"
if [[ "$GREEN" == "1" ]]; then
  echo "GREEN $CASE/$VARIANT -> $LAB_DIR"
  exit 0
fi
echo "NOT GREEN $CASE/$VARIANT $GREEN (lab_dir=$LAB_DIR) — supervisor will retry" >&2
exit 1
