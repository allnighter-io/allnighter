#!/usr/bin/env bash
# Allnighter green wall — extend as Swift targets land.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ran_any=false

# Launch Authority TCC hotfix (H4/H6): the dev build/launch output must stay
# OUTSIDE the repo. The checkout lives under ~/Documents and macOS attributes a
# child's TCC prompts to the .app's location, so building/launching from the
# repo re-opens the launch-permission code red. Guard against a regression that
# points DERIVED back inside the repo (e.g. $ROOT/.build).
echo "==> assert dev.sh build path is TCC-safe"
if grep -E '^DERIVED=' "$ROOT/scripts/dev.sh" | grep -qE '\$ROOT|\.build/'; then
  echo "check: scripts/dev.sh DERIVED points inside the repo — dev launch would" >&2
  echo "       run from ~/Documents and trigger TCC prompts. Keep it under" >&2
  echo "       ~/Library (see docs/archive/phases/Launch_Authority_TCC_Hotfix.md, slice H4)." >&2
  exit 1
fi
ran_any=true

# GUI Visual Proof Gate (S05): a visible SwiftUI surface cannot land without a
# proof packet or an explicit waiver. Cheap (git + grep) so it runs first and
# fails fast. See docs/phases/GUI_Visual_Proof_Gate.md.
echo "==> check GUI visual proof gate"
bash "$ROOT/scripts/check_gui_proof.sh"
ran_any=true

echo "==> check SwiftUI Observation state rules"
bash "$ROOT/scripts/check_swiftui_state.sh"
ran_any=true

# ThreadStore hardening (TSH-S06): app runtime must use explicit mutation APIs,
# not fixture/import saves. See docs/archive/phases/05_ThreadStore_Hardening.md.
echo "==> check ThreadStore caller allowlist"
if rg -n '\.saveForImport\(' "$ROOT/Apps" --glob '*.swift' 2>/dev/null; then
  echo "check: Apps/ must not call ThreadStore.saveForImport (fixture/test gate only)" >&2
  exit 1
fi
if rg -n 'testPersistCursor' "$ROOT/Apps" --glob '*.swift' 2>/dev/null; then
  echo "check: Apps/ must not call ThreadStore test-only cursor hooks" >&2
  exit 1
fi
ran_any=true

bash "$ROOT/scripts/check_spawn_policy.sh"
ran_any=true

# ASF-S06: embed git SHA + build timestamp before compiling the CLI / running tests.
echo "==> generate BuildInfo (gitSha / buildTime)"
bash "$ROOT/scripts/generate_build_info.sh"
ran_any=true

if [[ -f "$ROOT/Packages/AllnighterCore/Package.swift" ]]; then
  echo "==> swift test AllnighterCore"
  swift test --package-path "$ROOT/Packages/AllnighterCore"
  ran_any=true
fi

# Mac app (XcodeGen-generated project; regenerate so .xcodeproj need not be committed).
MAC_APP="$ROOT/Apps/AllnighterMac"
if [[ -f "$MAC_APP/project.yml" ]] && command -v xcodegen >/dev/null 2>&1; then
  echo "==> xcodegen generate (AllnighterMac)"
  ( cd "$MAC_APP" && xcodegen generate >/dev/null )
  echo "==> xcodebuild test AllnighterMac"
  xcodebuild test \
    -project "$MAC_APP/AllnighterMac.xcodeproj" \
    -scheme AllnighterMac \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO | tail -3
  ran_any=true
elif [[ -f "$MAC_APP/project.yml" ]]; then
  echo "check: xcodegen not installed; skipping Mac app (run: brew install xcodegen)"
fi

if [[ "$ran_any" == false ]]; then
  echo "check: no Swift targets yet (docs-only bootstrap OK)"
fi
