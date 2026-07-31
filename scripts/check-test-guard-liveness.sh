#!/usr/bin/env bash
# Guard-liveness probe — check-fast.sh calls this every run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHIM_DIR="$ROOT/scripts/bin"

# shellcheck source=ensure-test-guard-path.sh disable=SC1091
source "$ROOT/scripts/ensure-test-guard-path.sh"

resolved="$(command -v swift 2>/dev/null || true)"
if [[ "$resolved" != "$SHIM_DIR/swift" ]]; then
  echo "check-test-guard: ERROR — test guard is NOT active in this shell." >&2
  echo "check-test-guard: expected swift -> $SHIM_DIR/swift, got ${resolved:-missing}" >&2
  exit 1
fi

echo "check-test-guard: active (swift -> $resolved)"
