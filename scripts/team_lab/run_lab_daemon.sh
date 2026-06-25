#!/usr/bin/env bash
# Detached lab loop — survives IDE session end. Resumes partial manifests.
set -euo pipefail
cd "$(dirname "$0")/../.."

SKILL="${WRITER_SKILL:-bug_packet_writer_v4}"
TAG="${WRITER_TAG:-writer_v4}"
PIDFILE=".lab/lab-daemon-${TAG}.pid"
STATUS=".lab/lab-daemon-${TAG}.status"
LOG=".lab/lab-daemon-${TAG}.log"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "already running pid=$(cat "$PIDFILE") log=$LOG"
  exit 0
fi

export ALLN_JUDGE1_CMD="${ALLN_JUDGE1_CMD:-claude -p --max-turns 1}"
export ALLN_JUDGE2_CMD="${ALLN_JUDGE2_CMD:-codex exec - --full-auto}"
export WRITER_SKILL="$SKILL"
export WRITER_TAG="$TAG"

nohup bash -c "
  set -euo pipefail
  cd \"$(pwd)\"
  echo running > \"$STATUS\"
  CASES='floor_show_wrong_run_v1 mcp_fs_bypass_scoring_v1 cursor_composer_session_continuity_v1'
  MANIFEST='.lab/macro-evidence/manifest_${TAG}.jsonl'
  touch \"\$MANIFEST\"
  for CASE in \$CASES; do
    if grep -q \"\\\"caseId\\\": \\\"\$CASE\\\"\" \"\$MANIFEST\" 2>/dev/null; then
      echo \"skip \$CASE (already in manifest)\" >> \"$LOG\"
      continue
    fi
    echo \"=== CASE=\$CASE \$(date -u +%Y-%m-%dT%H:%M:%SZ) ===\" >> \"$LOG\"
    python3 scripts/team_lab/replay_writer_macro.py \
      --manifest .lab/macro-evidence/manifest.jsonl \
      --skill-id \"$SKILL\" \
      --variant-label \"$TAG\" \
      --skip-compose \
      --evidence-manifest \"\$MANIFEST\" \
      --case \"\$CASE\" \
      --timeout-seconds 1200 \
      >> \"$LOG\" 2>&1 || { echo failed=\$CASE >> \"$STATUS\"; exit 1; }
  done
  python3 scripts/team_lab/recompose_manifest.py \
    --manifest \"\$MANIFEST\" \
    --out-manifest \".lab/macro-evidence/manifest_${TAG}_live.jsonl\" \
    --bundle-tag \"${TAG}_live\" \
    >> \"$LOG\" 2>&1
  python3 scripts/team_lab/record_benchmark.py --tag \"$TAG\" --rollup \".lab/macro-evidence/rollup_${TAG}_live.json\" >> \"$LOG\" 2>&1 || true
  echo done > \"$STATUS\"
" >> "$LOG" 2>&1 &

echo $! > "$PIDFILE"
echo "started pid=$(cat "$PIDFILE") skill=$SKILL tag=$TAG log=$LOG"
