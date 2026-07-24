#!/usr/bin/env bash
# Founder-owned Code Red architecture gate. The Python validator is shared with
# this self-test so fixtures prove the same production enforcement path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POLICY="$ROOT/config/architecture-policy.json"
VALIDATOR="$ROOT/scripts/validate_architecture_policy.py"

fail() { echo "architecture-policy: $*" >&2; exit 1; }
[[ -f "$POLICY" ]] || fail "missing config/architecture-policy.json"
[[ -f "$VALIDATOR" ]] || fail "missing validator"

if [[ "${1:-}" != "--self-test" ]]; then
  exec python3 "$VALIDATOR" --root "$ROOT" --policy "$POLICY"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

write_fixture() {
  local fixture="$1"
  python3 - "$POLICY" "$fixture" <<'PY'
import json, pathlib, sys
policy = json.loads(pathlib.Path(sys.argv[1]).read_text())
root = pathlib.Path(sys.argv[2])

def write(name, text=""):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)

write("config/architecture-policy.json", json.dumps(policy))
write("scripts/check_architecture_policy.sh", "#!/usr/bin/env bash\n")
write("docs/phases/CODE_RED_Core_Infrastructure_Repair.md", "Code Red\n")
write("AGENTS.md", "routing\n")
write("docs/phases/guide.md", "living teaching\n")
write("docs/operations/guide.md", "operations\n")
operations = "\n".join(f"    case {name}(String)" for name in policy["allowedResidentOperations"])
write(
    "Packages/AllnighterCore/Sources/AllnighterCore/ResidentExecution.swift",
    f"public enum ResidentExecutionOperation {{\n{operations}\n}}\npublic struct PanelStart {{}}\n",
)
write(
    policy["runSemanticsOwnerFile"],
    "public final class RunService { public func run() {} }\n"
    "public struct RunRequest { var repoRoot: String }\n"
    "public enum RunServiceError {}\n",
)
write(
    policy["directAdapterFile"],
    "let service = RunService(\n)\nawait service.run(request)\n",
)
for name in policy["residentProductionFiles"]:
    path = root / name
    if not path.exists():
        write(name, "resident\n")
for name in policy["productionPaths"] + policy["livingTeachingPaths"]:
    path = root / name
    if not path.exists():
        if path.suffix:
            write(name, "teaching\n")
        else:
            path.mkdir(parents=True, exist_ok=True)
PY
}

assert_fails() {
  local name="$1"
  local fixture="$tmp/$name"
  write_fixture "$fixture"
  case "$name" in
    forbidden-production)
      printf 'ProjectMirror\n' >> "$fixture/Packages/AllnighterCore/Sources/AllnighterCore/ResidentExecution.swift" ;;
    forbidden-living)
      printf 'ProjectMirror\n' >> "$fixture/docs/phases/guide.md" ;;
    resident-operation)
      sed -i '' 's/public struct PanelStart/    case rogue(String)\npublic struct PanelStart/' "$fixture/Packages/AllnighterCore/Sources/AllnighterCore/ResidentExecution.swift" ;;
    run-owner-count)
      printf 'public func run() {}\n' >> "$fixture/Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift" ;;
    canonical-root)
      sed -i '' 's/repoRoot/otherRoot/' "$fixture/Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift" ;;
    founder-path)
      rm "$fixture/docs/phases/CODE_RED_Core_Infrastructure_Repair.md" ;;
    phase-loc)
      python3 - "$fixture/Packages/AllnighterCore/Sources/AllnighterEngine/ResidentCoordinator.swift" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text("resident\n" * 2200)
PY
      ;;
  esac
  if python3 "$VALIDATOR" --root "$fixture" --policy "$fixture/config/architecture-policy.json" >/dev/null 2>&1; then
    fail "self-test accepted violating fixture: $name"
  fi
}

valid="$tmp/valid"
write_fixture "$valid"
python3 "$VALIDATOR" --root "$valid" --policy "$valid/config/architecture-policy.json" >/dev/null
for category in forbidden-production forbidden-living resident-operation run-owner-count canonical-root founder-path phase-loc; do
  assert_fails "$category"
done

echo "architecture-policy: self-test passed"
