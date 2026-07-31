#!/usr/bin/env bash
# Guard-liveness probe — check-fast.sh (TIU-S01) will call this every run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHIM_DIR="$ROOT/scripts/bin"

resolved="$(command -v swift 2>/dev/null || true)"
if [[ "$resolved" != "$SHIM_DIR/swift" ]]; then
  echo "check-test-guard: WARNING — test guard is NOT active in this shell." >&2
  echo "check-test-guard: raw swift test / xcodebuild test may bypass the lock wrapper." >&2
  echo "check-test-guard: run scripts/install-test-guard.sh and 'direnv allow' in the repo root." >&2
  exit 1
fi

echo "check-test-guard: active (swift -> $resolved)"
