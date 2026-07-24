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
  python3 - "$POLICY" <<'PY'
import json, re, sys
p = json.load(open(sys.argv[1]))
source = "public enum ResidentExecutionOperation {\n case teamRun(X)\n case rogue(X)\n public struct X {}\n}"
actual = re.findall(r'^\s*case\s+(\w+)\(', source, re.M)
if actual == p['allowedResidentOperations']:
    raise SystemExit("self-test accepted a resident operation not declared by policy")
if p['runSemanticsOwner'] != 'RunService.run' or p['canonicalRootField'] != 'repoRoot':
    raise SystemExit("self-test policy fixture lost the owner/root invariant")
if p['residentProductionLineCeiling'] < p['residentCloseoutLineBudget']:
    raise SystemExit("self-test accepted an incoherent resident line ceiling")
if not all(pth.startswith(('config/', 'scripts/', 'docs/')) for pth in p['founderOwnedPaths']):
    raise SystemExit("self-test accepted an invalid founder-owned path")
PY
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

if [[ -z "$scan_override" ]]; then
  python3 - "$POLICY" "$ROOT" <<'PY'
import json, pathlib, re, sys
p = json.load(open(sys.argv[1]))
root = pathlib.Path(sys.argv[2])
def fail(message):
    raise SystemExit(f"architecture-policy: {message}")

resident = root / 'Packages/AllnighterCore/Sources/AllnighterCore/ResidentExecution.swift'
text = resident.read_text()
enum_text = text.split('public enum ResidentExecutionOperation', 1)[1].split('public struct PanelStart', 1)[0]
actual = re.findall(r'^\s*case\s+(\w+)\(', enum_text, re.M)
if actual != p['allowedResidentOperations']:
    fail(f"resident operation set differs from policy: actual={actual}")

owner = root / p['runSemanticsOwnerFile']
owner_text = owner.read_text()
if len(re.findall(r'public\s+func\s+run\s*\(', owner_text)) != 1:
    fail('RunService semantic owner must declare exactly one public run method')
adapter = root / p['directAdapterFile']
adapter_text = adapter.read_text()
if 'let service = RunService(' not in adapter_text or 'await service.run(request' not in adapter_text:
    fail('RunCLI is not a direct RunService adapter')
if 'ResidentExecutionOperation' in adapter_text:
    fail('RunCLI must not route foreground work through resident operations')

request_text = owner_text.split('public struct RunRequest', 1)[1].split('public enum RunServiceError', 1)[0]
if f'var {p["canonicalRootField"]}:' not in request_text:
    fail('RunRequest is missing the canonical root field declared by policy')
for field in p['forbiddenAlternateRootFields']:
    if field in request_text:
        fail(f'RunRequest contains alternate root field {field}')

for name in p['founderOwnedPaths']:
    if not (root / name).is_file():
        fail(f'founder-owned path is missing: {name}')

files = [root / name for name in p['residentProductionFiles']]
if not all(path.is_file() for path in files):
    fail('resident production file set is incomplete')
loc = sum(len(path.read_text().splitlines()) for path in files)
if loc > p['residentProductionLineCeiling']:
    fail(f'resident production LOC {loc} exceeds CR-S01 ceiling {p["residentProductionLineCeiling"]}')
if p['residentCloseoutLineBudget'] > p['residentProductionLineCeiling']:
    fail('closeout LOC target cannot exceed the current phase ceiling')
PY
fi

echo "architecture-policy: passed"
