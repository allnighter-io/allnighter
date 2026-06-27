#!/usr/bin/env bash
# Expand and dispatch Phase 1 code-review packets (CR-01 … CR-10) via pair slice.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PROJECT="${1:-Allnighter}"
EXECUTOR_WORKER="${PAIR_CR_EXECUTOR_WORKER:-model_opencode_glm_5_2}"
shift || true
IDS=("$@")
if [[ ${#IDS[@]} -eq 0 ]]; then
  IDS=(01 02 03 04 05 06 07 08 09 10)
fi
for n in "${IDS[@]}"; do
  id="CR-${n}"
  src="docs/phases/code_review/packets/${id}.json"
  out="docs/phases/code_review/packets/${id}.expanded.json"
  echo "=== expand ${id} ==="
  python3 scripts/expand_cr_packet.py "$ROOT" "$src" "$out"
  echo "=== pair slice ${id} ==="
  swift run --package-path "$ROOT/Packages/AllnighterCore" alln pair slice "$out" \
    --project "$PROJECT" --executor-worker "$EXECUTOR_WORKER" --json || echo "WARN: ${id} did not pass"
done
