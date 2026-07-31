#!/usr/bin/env bash
# Activate test PATH shims in the current shell (agent-safe; no human step).
# Sourced by check.sh, check-fast.sh, swift-test.sh, and install-test-guard.sh.
set -euo pipefail

_ensure_guard_repo_root() {
  if [[ -n "${ALLNIGHTER_ROOT:-}" ]]; then
    printf '%s' "$ALLNIGHTER_ROOT"
    return 0
  fi
  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
    return 0
  fi
  cd "$(dirname "$0")/.." && pwd
}

ROOT="$(_ensure_guard_repo_root)"
SHIM_DIR="$ROOT/scripts/bin"

chmod +x "$SHIM_DIR/swift" "$SHIM_DIR/xcodebuild" 2>/dev/null || true

if [[ "$(command -v swift 2>/dev/null || true)" != "$SHIM_DIR/swift" ]]; then
  export PATH="$SHIM_DIR:$PATH"
fi

# Keep direnv in sync when present — best-effort for shells that load .envrc.
if [[ -f "$ROOT/.envrc" ]] && command -v direnv >/dev/null 2>&1; then
  ( cd "$ROOT" && direnv allow >/dev/null 2>&1 ) || true
fi
