#!/usr/bin/env bash
# Autonomous writer iteration: replay + live compose + rollup summary.
# Usage: WRITER_SKILL=bug_packet_writer_v4 WRITER_TAG=writer_v4 bash scripts/team_lab/run_lab_loop.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
export ALLN_JUDGE1_CMD="${ALLN_JUDGE1_CMD:-claude -p --max-turns 1}"
export ALLN_JUDGE2_CMD="${ALLN_JUDGE2_CMD:-codex exec - --full-auto}"

SKILL="${WRITER_SKILL:-bug_packet_writer_v4}"
TAG="${WRITER_TAG:-writer_v4}"
MANIFEST_IN="${MANIFEST_IN:-.lab/macro-evidence/manifest.jsonl}"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
LOG=".lab/lab-loop-${TAG}-${STAMP}.log"

exec > >(tee -a "$LOG") 2>&1
echo "=== LAB_LOOP skill=$SKILL tag=$TAG $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

WRITER_SKILL="$SKILL" WRITER_TAG="$TAG" MANIFEST_IN="$MANIFEST_IN" \
  bash scripts/team_lab/run_writer_replay_bundle.sh

python3 - <<'PY'
import json, os
tag = os.environ.get("WRITER_TAG", "writer_v4")
path = f".lab/macro-evidence/rollup_{tag}_live.json"
r = json.load(open(path))
roll = r.get("rollup") or {}
print("LOOP_RESULT", json.dumps({
    "tag": tag,
    "verdict": r.get("verdict"),
    "deliverable": r.get("deliverableOutcome"),
    "counts": roll.get("deliverableCounts"),
    "winRate": roll.get("candidateWinRate"),
    "suppressed": roll.get("valueSuppressedTotal"),
    "gate": r.get("gateReason"),
}))
PY
