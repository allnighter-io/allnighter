#!/usr/bin/env bash
# Rerun Lite vs Lite+Trace on necessity bundle with hardened bug_packet_writer.
set -euo pipefail
cd "$(dirname "$0")/../.."
export ALLN_JUDGE1_CMD="${ALLN_JUDGE1_CMD:-claude -p --max-turns 1}"
export ALLN_JUDGE2_CMD="${ALLN_JUDGE2_CMD:-codex exec - --full-auto}"

MANIFEST=.lab/macro-evidence/manifest_hardened_writer_v1.jsonl
LOG=.lab/macro-hardened-writer-bundle.log
BASELINE=docs/team-lab/champions/bug_hunt_repo_regressions_v1/code_bug_hunt_lite.json
DONOR=docs/team-lab/champions/bug_hunt_repo_regressions_v1/code_bug_hunt.json
COMMON=(
  --suite bug_hunt_necessity_v1
  --baseline-overlay "$BASELINE"
  --donor-overlay "$DONOR"
  --add-role trace_mapper#0
  --round 2
  --fresh-input-count 1
  --evidence-manifest "$MANIFEST"
  --bundle-tag hardened_writer_v1
)

for CASE in floor_show_wrong_run_v1 mcp_fs_bypass_scoring_v1 cursor_composer_session_continuity_v1; do
  echo "=== HARDENED_CASE=$CASE $(date -u +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "$LOG"
  python3 scripts/team_lab/macro_advance.py --case "$CASE" "${COMMON[@]}" 2>&1 | tee -a "$LOG"
done

python3 scripts/team_lab/macro_rollup.py \
  --manifest "$MANIFEST" \
  --suite bug_hunt_necessity_v1 \
  --added-role trace_mapper#0 \
  --out .lab/macro-evidence/rollup_hardened_writer_v1.json \
  2>&1 | tee -a "$LOG"
