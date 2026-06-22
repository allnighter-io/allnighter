#!/usr/bin/env bash
# Enforce Allnighter's SwiftUI Observation state model.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failed=false

old_state_pattern='(^import Combine\b|\bObservableObject\b|@ObservedObject\b|@StateObject\b|@EnvironmentObject\b|@Published\b|\bobjectWillChange\b)'

echo "==> check SwiftUI Observation state rules"

if rg -n "$old_state_pattern" "$ROOT/Apps" "$ROOT/Packages" \
  --glob '*.swift' \
  --glob '!**/.build/**' \
  --glob '!**/DerivedData/**'; then
  echo "check: old SwiftUI/Combine observation state is not allowed in owned app code." >&2
  echo "       Use @Observable with @State, @Environment, and @Bindable." >&2
  failed=true
fi

if rg -n 'SWIFT_VERSION.*5\.' "$ROOT/Apps" \
  --glob '*.pbxproj' \
  --glob 'project.yml'; then
  echo "check: owned app targets must not be left in Swift 5 language mode." >&2
  failed=true
fi

if rg -n '^// swift-tools-version:\s*5\.' "$ROOT/Packages" --glob 'Package.swift'; then
  echo "check: owned Swift packages must use Swift tools version 6.0 or newer." >&2
  failed=true
fi

if [[ "$failed" == true ]]; then
  exit 1
fi
