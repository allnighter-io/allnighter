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

# Mac app scheme (added in MVP Phase 03).
if xcodebuild -list -workspace "$ROOT/Allnighter.xcworkspace" >/dev/null 2>&1; then
  echo "==> xcodebuild test AllnighterMac"
  xcodebuild test -scheme AllnighterMac -destination 'platform=macOS' | tail -5
  ran_any=true
fi

if [[ "$ran_any" == false ]]; then
  echo "check: no Swift targets yet (docs-only bootstrap OK)"
fi
