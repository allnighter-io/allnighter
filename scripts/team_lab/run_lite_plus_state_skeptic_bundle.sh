#!/usr/bin/env bash
# Lite vs Lite+State Skeptic — 3-case necessity bundle (reuse R1 genesis baselines).
set -euo pipefail
cd "$(dirname "$0")/../.."
export ALLN_JUDGE1_CMD="${ALLN_JUDGE1_CMD:-claude -p --max-turns 1}"
export ALLN_JUDGE2_CMD="${ALLN_JUDGE2_CMD:-codex exec - --full-auto}"

MANIFEST=.lab/macro-evidence/manifest_lite_plus_state_skeptic_v1.jsonl
LOG=.lab/macro-lite-plus-state-skeptic-bundle.log
BASELINE=docs/team-lab/champions/bug_hunt_repo_regressions_v1/code_bug_hunt_lite.json
DONOR=docs/team-lab/champions/bug_hunt_repo_regressions_v1/code_bug_hunt.json
ROUND=1
TAG=lite_plus_state_skeptic_v1

baseline_lab_for_case() {
  case "$1" in
    floor_show_wrong_run_v1)
      echo ".lab/code_bug_hunt_genesis-lite_r1_20260623_181339"
      ;;
    mcp_fs_bypass_scoring_v1)
      echo ".lab/code_bug_hunt_genesis-code_bug_hunt_lite_r1_20260623_211909"
      ;;
    cursor_composer_session_continuity_v1)
      echo ".lab/code_bug_hunt_genesis-code_bug_hunt_lite_r1_20260623_213536"
      ;;
    *)
      echo "unknown case: $1" >&2
      return 1
      ;;
  esac
}

: >"$MANIFEST"

for CASE in floor_show_wrong_run_v1 mcp_fs_bypass_scoring_v1 cursor_composer_session_continuity_v1; do
  echo "=== CASE=$CASE $(date -u +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "$LOG"
  BASE_LAB="$(baseline_lab_for_case "$CASE")"
  python3 scripts/team_lab/macro_advance.py \
    --case "$CASE" \
    --suite bug_hunt_necessity_v1 \
    --baseline-overlay "$BASELINE" \
    --donor-overlay "$DONOR" \
    --add-role state_skeptic#0 \
    --round "$ROUND" \
    --fresh-input-count 1 \
    --baseline-lab "$BASE_LAB" \
    --evidence-manifest "$MANIFEST" \
    --bundle-tag "$TAG" \
    2>&1 | tee -a "$LOG"
done

python3 scripts/team_lab/macro_rollup.py \
  --manifest "$MANIFEST" \
  --suite bug_hunt_necessity_v1 \
  --added-role state_skeptic#0 \
  --out ".lab/macro-evidence/rollup_${TAG}.json" \
  2>&1 | tee -a "$LOG"
