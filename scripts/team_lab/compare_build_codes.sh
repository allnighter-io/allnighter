#!/usr/bin/env bash
# Graded A/B for Code Build team #3: lean (4-seat overlay) as BASELINE/incumbent
# vs full (code_core, 7 seats) as CANDIDATE, per shared case. Full only "wins" a
# case if BOTH blind judges agree its deliverable is better; ties go to lean (the
# cheaper incumbent) — same rule that finalized Bug Hunter.
#
# Pairs runs by caseId (lab dir names don't encode the case), and only considers
# contract-GREEN runs. Reuses completed runs — spends judge quota only.
set -uo pipefail
cd "$(dirname "$0")/../.."

export ALLN_JUDGE1_CMD="${ALLN_JUDGE1_CMD:-claude -p --max-turns 1}"
export ALLN_JUDGE2_CMD="${ALLN_JUDGE2_CMD:-codex exec - --full-auto}"

OUT=".lab/macro-evidence/build_codes_compare.jsonl"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"

# Resolve latest GREEN lab dir per (variant, caseId).
pick() { # $1=variant
  python3 - "$1" <<'PY'
import json,sys,glob,os
variant=sys.argv[1]
best={}
for d in glob.glob(f".lab/code_core_{variant}_r1_*"):
    sc=os.path.join(d,"evaluation","run-contract-score.json")
    ex=os.path.join(d,"experiment.json")
    if not (os.path.exists(sc) and os.path.exists(ex)): continue
    try:
        c=json.load(open(sc)); e=json.load(open(ex))
    except Exception: continue
    if c.get("runContractScore",0)<0.95 or c.get("fsBypass"): continue
    cid=e.get("caseId")
    if not cid: continue
    if cid not in best or d>best[cid]: best[cid]=d  # lexical max = latest stamp
for cid,d in sorted(best.items()):
    print(f"{cid}\t{d}")
PY
}

declare -a CASES
LEAN_MAP=$(pick build_lean)
FULL_MAP=$(pick build_full)

echo "=== green lean runs ==="; echo "$LEAN_MAP"
echo "=== green full runs ==="; echo "$FULL_MAP"

rc=0
while IFS=$'\t' read -r CID LEAN_DIR; do
  [[ -z "$CID" ]] && continue
  FULL_DIR=$(printf '%s\n' "$FULL_MAP" | awk -F'\t' -v c="$CID" '$1==c{print $2}')
  if [[ -z "$FULL_DIR" ]]; then
    echo "no green FULL run for case $CID — skip" >&2; rc=1; continue
  fi
  echo "=== compare case=$CID  baseline(lean)=$LEAN_DIR  candidate(full)=$FULL_DIR ==="
  if python3 scripts/team_lab/compare.py "$LEAN_DIR" "$FULL_DIR"; then
    python3 - "$CID" "$FULL_DIR" >> "$OUT" <<'PY'
import json,sys
cid,full=sys.argv[1],sys.argv[2]
try: out=json.load(open(f"{full}/evaluation/compare-record.json"))
except FileNotFoundError: out={}
print(json.dumps({
  "caseId": cid,
  "deliverableOutcome": out.get("deliverableOutcome"),
  "bankedRoles": out.get("bankedRoles"),
  "interactionWarning": out.get("interactionWarning"),
  "judgeMode": out.get("judgeMode"),
  "evidenceValid": out.get("evidenceValid"),
}))
PY
  else
    echo "compare FAILED for $CID" >&2; rc=1
  fi
done <<< "$LEAN_MAP"

echo "=== VERDICTS ($OUT) ==="
cat "$OUT" 2>/dev/null || true
exit "$rc"
