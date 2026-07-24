#!/usr/bin/env bash
# Founder-owned Code Red architecture gate. Keep this deliberately mechanical.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POLICY="$ROOT/config/architecture-policy.json"
cd "$ROOT"

fail() { echo "architecture-policy: $*" >&2; exit 1; }
[[ -f "$POLICY" ]] || fail "missing config/architecture-policy.json"

if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  for sample in ProjectMirror projectMirrorId projectMirrorRoot; do
    printf '%s\n' "$sample" > "$tmp/violation.swift"
    if "$0" --scan "$tmp" >/dev/null 2>&1; then
      fail "self-test accepted violating fixture: $sample"
    fi
    : > "$tmp/violation.swift"
    "$0" --scan "$tmp" >/dev/null
  done
  echo "architecture-policy: self-test passed"
  exit 0
fi

scan_override=""
if [[ "${1:-}" == "--scan" ]]; then
  scan_override="${2:-}"
  [[ -n "$scan_override" && -d "$scan_override" ]] || fail "--scan needs a directory"
fi

forbidden="$(python3 - "$POLICY" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
for value in p['forbiddenConcepts'] + p['forbiddenAlternateRootFields']:
    print(value)
PY
)"

if [[ -n "$scan_override" ]]; then
  targets=("$scan_override")
else
  targets=(
    "Packages/AllnighterCore/Sources"
    "scripts"
    "AGENTS.md"
    "docs/phases"
    "docs/operations"
  )
fi

excludes=(
  --glob '!docs/archive/**'
  --glob '!docs/operations/debugger/**'
  --glob '!docs/phases/CODE_RED_Core_Infrastructure_Repair.md'
  --glob '!config/architecture-policy.json'
  --glob '!scripts/check_architecture_policy.sh'
  --glob '!scripts/code_red_metrics.sh'
  --glob '!scripts/code_red_works_test.sh'
)

while IFS= read -r concept; do
  [[ -n "$concept" ]] || continue
  hits="$(rg -n -F "${excludes[@]}" -- "$concept" "${targets[@]}" 2>/dev/null || true)"
  [[ -z "$hits" ]] || fail "forbidden concept '$concept' found:\n$hits"
done <<< "$forbidden"

# CR-S01 has no resident foreground route. This checks the wire enum rather
# than a broad word search so unrelated use of 'foreground' remains valid.
if [[ -z "$scan_override" ]]; then
  resident="$ROOT/Packages/AllnighterCore/Sources/AllnighterCore/ResidentExecution.swift"
  [[ -f "$resident" ]] || fail "missing resident operation definition"
  if rg -n -F -- 'foregroundTeamRun' "$resident" >/dev/null; then
    fail "foreground resident operation is not allowed in CR-S01"
  fi
  if ! rg -n -F -- 'RunService.run' "$ROOT/docs/phases/Unified_Run_Model.md" >/dev/null; then
    fail "living run model no longer names the sole semantics owner"
  fi
fi

echo "architecture-policy: passed"
