#!/usr/bin/env bash
# Writer-only replay on R1 Lite+Trace labs, then live deliverable compose.
set -euo pipefail
cd "$(dirname "$0")/../.."
export ALLN_JUDGE1_CMD="${ALLN_JUDGE1_CMD:-claude -p --max-turns 1}"
export ALLN_JUDGE2_CMD="${ALLN_JUDGE2_CMD:-codex exec - --full-auto}"

SKILL="${WRITER_SKILL:-bug_packet_writer_v3}"
TAG="${WRITER_TAG:-writer_v3}"
MANIFEST_IN="${MANIFEST_IN:-.lab/macro-evidence/manifest.jsonl}"
MANIFEST_OUT=".lab/macro-evidence/manifest_${TAG}.jsonl"
LOG=".lab/writer-replay-${TAG}.log"

echo "=== writer replay skill=$SKILL tag=$TAG $(date -u +%Y-%m-%dT%H:%M:%SZ) ===" | tee "$LOG"

python3 scripts/team_lab/replay_writer_macro.py \
  --manifest "$MANIFEST_IN" \
  --skill-id "$SKILL" \
  --variant-label "$TAG" \
  --skip-compose \
  --evidence-manifest "$MANIFEST_OUT" \
  2>&1 | tee -a "$LOG"

python3 scripts/team_lab/recompose_manifest.py \
  --manifest "$MANIFEST_OUT" \
  --out-manifest ".lab/macro-evidence/manifest_${TAG}_live.jsonl" \
  --bundle-tag "${TAG}_live" \
  2>&1 | tee -a "$LOG"
