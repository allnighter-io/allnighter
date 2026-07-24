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
      printf 'ProjectMirror\n' >> "$fixture/Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift" ;;
    forbidden-living)
      printf 'ProjectMirror\n' >> "$fixture/docs/phases/guide.md" ;;
    resident-operation)
      # CR-S06 deleted the control plane, so this rule inverts: declaring the
      # operation union at its old path must be red.
      printf 'public enum ResidentExecutionOperation {\n    case rogue(String)\n}\n' \
        > "$fixture/Packages/AllnighterCore/Sources/AllnighterCore/ResidentExecution.swift" ;;
    resident-operation-renamed)
      # …and so must declaring it anywhere else, under any prefix. A rename is
      # how this would actually come back.
      printf 'public enum SneakyResidentExecutionOperation {\n    case rogue(String)\n}\n' \
        > "$fixture/Packages/AllnighterCore/Sources/AllnighterEngine/Sneaky.swift" ;;
    resident-file-returned)
      printf 'let probe = 1\n' \
        > "$fixture/Packages/AllnighterCore/Sources/AllnighterEngine/ResidentCoordinatorProbe.swift" ;;
    run-owner-count)
      printf 'public func run() {}\n' >> "$fixture/Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift" ;;
    canonical-root)
      sed -i '' 's/repoRoot/otherRoot/' "$fixture/Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift" ;;
    founder-path)
      rm "$fixture/docs/phases/CODE_RED_Core_Infrastructure_Repair.md" ;;
    phase-loc)
      # The declared resident file set is now empty, so the ceiling can only be
      # violated by a policy that readmits a file. Prove the LOC rule still
      # bites on the policy the validator actually reads.
      python3 - "$fixture" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
name = "Packages/AllnighterCore/Sources/AllnighterEngine/StillResident.swift"
(root / name).write_text("resident\n" * 2200)
policy_path = root / "config/architecture-policy.json"
policy = json.loads(policy_path.read_text())
policy["residentProductionFiles"] = [name]
policy_path.write_text(json.dumps(policy))
PY
      ;;
    adapter-missing-direct-run)
      printf 'public func run() {}\n' > "$fixture/Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift" ;;
    adapter-resident-operation)
      printf 'let service = RunService(\n)\nawait service.run(request)\nResidentExecutionOperation\n' > "$fixture/Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift" ;;
    alternate-root-field)
      sed -i '' 's/public struct RunRequest { var repoRoot: String }/public struct RunRequest { var repoRoot: String; var projectMirrorRoot: String }/' "$fixture/Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift" ;;
  esac
  if python3 "$VALIDATOR" --root "$fixture" --policy "$fixture/config/architecture-policy.json" >/dev/null 2>&1; then
    fail "self-test accepted violating fixture: $name"
  fi
}

valid="$tmp/valid"
write_fixture "$valid"
python3 "$VALIDATOR" --root "$valid" --policy "$valid/config/architecture-policy.json" >/dev/null
for category in forbidden-production forbidden-living resident-operation resident-operation-renamed resident-file-returned run-owner-count canonical-root founder-path phase-loc adapter-missing-direct-run adapter-resident-operation alternate-root-field; do
  assert_fails "$category"
done

echo "architecture-policy: self-test passed"
