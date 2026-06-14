#!/usr/bin/env bash
# Allnighter green wall — extend as Swift targets land.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ran_any=false

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
