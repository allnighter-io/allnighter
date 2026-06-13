#!/usr/bin/env bash
# CLI Loci green wall — extend as Swift targets land.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -f "$ROOT/Packages/CLILociCore/Package.swift" ]]; then
  swift test --package-path "$ROOT/Packages/CLILociCore"
else
  echo "check: no Swift targets yet (docs-only bootstrap OK)"
fi
