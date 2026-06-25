#!/usr/bin/env bash
# Inner loop for detached lab daemon — do not invoke directly; use run_lab_daemon.sh.
set -uo pipefail
cd "$(dirname "$0")/../.."

SKILL="${WRITER_SKILL:-bug_packet_writer_v4}"
TAG="${WRITER_TAG:-writer_v4}"
STATUS=".lab/lab-daemon-${TAG}.status"
LOG=".lab/lab-daemon-${TAG}.log"

export ALLN_JUDGE1_CMD="${ALLN_JUDGE1_CMD:-claude -p --max-turns 1}"
export ALLN_JUDGE2_CMD="${ALLN_JUDGE2_CMD:-codex exec - --full-auto}"

echo running > "$STATUS"
CASES='floor_show_wrong_run_v1 mcp_fs_bypass_scoring_v1 cursor_composer_session_continuity_v1'
MANIFEST=".lab/macro-evidence/manifest_${TAG}.jsonl"
touch "$MANIFEST"

for CASE in $CASES; do
  if grep -q "\"caseId\": \"$CASE\"" "$MANIFEST" 2>/dev/null; then
    echo "skip $CASE (already in manifest)" >> "$LOG"
    continue
  fi
  echo "=== CASE=$CASE $(date -u +%Y-%m-%dT%H:%M:%SZ) ===" >> "$LOG"
  if ! python3 scripts/team_lab/replay_writer_macro.py \
    --manifest .lab/macro-evidence/manifest.jsonl \
    --skill-id "$SKILL" \
    --variant-label "$TAG" \
    --skip-compose \
    --evidence-manifest "$MANIFEST" \
    --case "$CASE" \
    --timeout-seconds 1200 \
    >> "$LOG" 2>&1; then
    echo "failed=$CASE $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG"
    echo "failed=$CASE" > "$STATUS"
    exit 1
  fi
done

python3 scripts/team_lab/recompose_manifest.py \
  --manifest "$MANIFEST" \
  --out-manifest ".lab/macro-evidence/manifest_${TAG}_live.jsonl" \
  --bundle-tag "${TAG}_live" \
  >> "$LOG" 2>&1

python3 scripts/team_lab/record_benchmark.py \
  --tag "$TAG" \
  --rollup ".lab/macro-evidence/rollup_${TAG}_live.json" \
  >> "$LOG" 2>&1 || true

python3 scripts/team_lab/lab_auto_advance.py --tag "$TAG" --spawn-next >> "$LOG" 2>&1 || true

echo done > "$STATUS"
