#!/usr/bin/env bash
# Expand and dispatch Phase 1 code-review packets (CR-01 … CR-10).
# PM RULE: parallel fan-out ONLY when touch allowlists are disjoint (findings-scoped).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PROJECT="${1:-Allnighter}"
EXECUTOR_WORKER="${PAIR_CR_EXECUTOR_WORKER:-model_opencode_glm_5_2}"
VERIFY="${PAIR_CR_VERIFY:-1}"
PARALLEL="${PAIR_CR_PARALLEL:-1}"
MAX_PARALLEL="${ALLNIGHTER_REVIEW_SPAWN_LIMIT:-4}"
shift || true
IDS=("$@")
if [[ ${#IDS[@]} -eq 0 ]]; then
  IDS=(01 02 03 04 05 06 07 08 09 10)
fi

ALLN=(swift run --package-path "$ROOT/Packages/AllnighterCore" alln)

run_slice() {
  local expanded="$1"
  local label="$2"
  echo "=== pair slice ${label} ==="
  "${ALLN[@]}" pair slice "$expanded" \
    --project "$PROJECT" --executor-worker "$EXECUTOR_WORKER" --json \
    || echo "WARN: ${label} did not pass"
}

run_verify() {
  local base_id="$1"
  local review_expanded="docs/phases/code_review/packets/${base_id}.expanded.json"
  local verify_expanded="docs/phases/code_review/packets/${base_id}.verify.expanded.json"
  if [[ ! -f "docs/phases/code_review/findings/${base_id}.md" ]]; then
    echo "SKIP verify ${base_id}: no findings file"
    return 0
  fi
  echo "=== expand verify ${base_id} ==="
  python3 scripts/expand_cr_packet.py --verify "$ROOT" "$review_expanded" "$verify_expanded"
  run_slice "$verify_expanded" "${base_id}-verify"
}

process_one() {
  local n="$1"
  local id="CR-${n}"
  local src="docs/phases/code_review/packets/${id}.json"
  local out="docs/phases/code_review/packets/${id}.expanded.json"
  echo "=== expand ${id} ==="
  python3 scripts/expand_cr_packet.py "$ROOT" "$src" "$out"
  run_slice "$out" "$id"
  if [[ "$VERIFY" == "1" ]]; then
    run_verify "$id"
  fi
}

# Expand all review packets first (for parallel planning).
EXPANDED_PATHS=()
for n in "${IDS[@]}"; do
  id="CR-${n}"
  src="docs/phases/code_review/packets/${id}.json"
  out="docs/phases/code_review/packets/${id}.expanded.json"
  python3 scripts/expand_cr_packet.py "$ROOT" "$src" "$out"
  EXPANDED_PATHS+=("$out")
done

if [[ "$PARALLEL" != "1" ]]; then
  for n in "${IDS[@]}"; do
    id="CR-${n}"
    run_slice "docs/phases/code_review/packets/${id}.expanded.json" "$id"
    [[ "$VERIFY" == "1" ]] && run_verify "$id"
  done
  exit 0
fi

PLAN="$(python3 scripts/cr_parallel_plan.py "${EXPANDED_PATHS[@]}")"
echo "$PLAN"
if ! printf '%s' "$PLAN" | python3 -c 'import sys,json; sys.exit(0 if json.load(sys.stdin)["safe"] else 1)'; then
  echo "ERROR: parallel safety check failed — falling back to serial" >&2
  for n in "${IDS[@]}"; do
    id="CR-${n}"
    run_slice "docs/phases/code_review/packets/${id}.expanded.json" "$id"
    [[ "$VERIFY" == "1" ]] && run_verify "$id"
  done
  exit 0
fi

export ALLNIGHTER_REVIEW_SPAWN_LIMIT="$MAX_PARALLEL"
export ROOT PROJECT PAIR_CR_VERIFY PAIR_CR_EXECUTOR_WORKER

printf '%s' "$PLAN" | python3 -c '
import json, subprocess, os, sys
plan = json.load(sys.stdin)
root = os.environ.get("ROOT", ".")
verify = os.environ.get("PAIR_CR_VERIFY", "1") == "1"
for batch in plan["batches"]:
    procs = []
    for slice_id in batch:
        expanded = f"docs/phases/code_review/packets/{slice_id}.expanded.json"
        cmd = [
            "swift", "run", "--package-path", f"{root}/Packages/AllnighterCore", "alln",
            "pair", "slice", expanded,
            "--project", os.environ.get("PROJECT", "Allnighter"),
            "--executor-worker", os.environ.get("PAIR_CR_EXECUTOR_WORKER", "model_opencode_glm_5_2"),
            "--json",
        ]
        print("=== parallel pair slice", slice_id, "===")
        procs.append((slice_id, subprocess.Popen(cmd)))
    for slice_id, proc in procs:
        code = proc.wait()
        if code != 0:
            print(f"WARN: {slice_id} exit {code}")
    if verify:
        for slice_id in batch:
            findings = f"docs/phases/code_review/findings/{slice_id}.md"
            if not os.path.isfile(findings):
                print(f"SKIP verify {slice_id}: no findings")
                continue
            review_exp = f"docs/phases/code_review/packets/{slice_id}.expanded.json"
            verify_exp = f"docs/phases/code_review/packets/{slice_id}.verify.expanded.json"
            subprocess.check_call([
                "python3", "scripts/expand_cr_packet.py", "--verify", root, review_exp, verify_exp
            ])
            cmd = [
                "swift", "run", "--package-path", f"{root}/Packages/AllnighterCore", "alln",
                "pair", "slice", verify_exp,
                "--project", os.environ.get("PROJECT", "Allnighter"),
                "--executor-worker", os.environ.get("PAIR_CR_EXECUTOR_WORKER", "model_opencode_glm_5_2"),
                "--json",
            ]
            print("=== parallel verify", slice_id, "===")
            subprocess.call(cmd)
'
