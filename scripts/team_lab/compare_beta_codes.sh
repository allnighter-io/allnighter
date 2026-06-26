#!/usr/bin/env bash
# Graded head-to-head: code_bug_hunt_lite (baseline) vs code_bug_hunt (candidate)
# on the 3 shared beta_validate cases. Blind two-judge A/B on each deliverable.
# Reuses already-completed runs — no new worker quota, only judge calls.
set -uo pipefail
cd "$(dirname "$0")/../.."

export ALLN_JUDGE1_CMD="${ALLN_JUDGE1_CMD:-claude -p --max-turns 1}"
export ALLN_JUDGE2_CMD="${ALLN_JUDGE2_CMD:-codex exec - --full-auto}"

# case_id : lite_lab_dir : bug_hunt_lab_dir  (paired by case)
PAIRS="
composer_paste_dead_v1:.lab/code_bug_hunt_beta_validate_r1_20260626_133327:.lab/code_bug_hunt_beta_validate_r1_20260626_135618
mcp_fs_bypass_scoring_v1:.lab/code_bug_hunt_beta_validate_r1_20260626_134313:.lab/code_bug_hunt_beta_validate_r1_20260626_140706
floor_show_wrong_run_v1:.lab/code_bug_hunt_beta_validate_r1_20260626_135006:.lab/code_bug_hunt_beta_validate_r1_20260626_141440
"

OUT=".lab/macro-evidence/beta_codes_compare.jsonl"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"

rc=0
echo "$PAIRS" | while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  CASE="${line%%:*}"
  rest="${line#*:}"
  BASE="${rest%%:*}"
  CAND="${rest#*:}"
  echo "=== compare case=$CASE  baseline(lite)=$BASE  candidate(bug_hunt)=$CAND $(date -u +%H:%M:%SZ) ==="
  if [[ ! -d "$BASE" || ! -d "$CAND" ]]; then
    echo "MISSING lab dir for $CASE (base=$BASE cand=$CAND)" >&2
    rc=1
    continue
  fi
  if python3 scripts/team_lab/compare.py "$BASE" "$CAND"; then
    python3 - "$CASE" "$CAND" >> "$OUT" <<'PY'
import json,sys
case, cand = sys.argv[1], sys.argv[2]
try:
    out = json.load(open(f"{cand}/evaluation/compare-record.json"))
except FileNotFoundError:
    out = {}
dv = out.get("deliverableVerdicts") or []
votes = [v.get("resolved") for v in dv]
print(json.dumps({
    "caseId": case,
    "deliverableOutcome": out.get("deliverableOutcome"),
    "deliverableVotes": votes,
    "bankedRoles": out.get("bankedRoles"),
    "judgeMode": out.get("judgeMode"),
    "evidenceValid": out.get("evidenceValid"),
}))
PY
  else
    echo "compare FAILED for $CASE" >&2
    rc=1
  fi
done

echo "=== summary ($OUT) ==="
cat "$OUT" 2>/dev/null || true
exit "$rc"
