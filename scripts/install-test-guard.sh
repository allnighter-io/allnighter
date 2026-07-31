#!/usr/bin/env bash
# Optional: install direnv + refresh .envrc for interactive shells.
# Agent sessions auto-activate via scripts/ensure-test-guard-path.sh on every
# test entry point — no human step required for the guard to bind.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENVRC="$ROOT/.envrc"
SHIM_DIR="$ROOT/scripts/bin"

# shellcheck source=ensure-test-guard-path.sh disable=SC1091
source "$ROOT/scripts/ensure-test-guard-path.sh"

echo "==> install test guard (PATH shim for swift/xcodebuild test)"

if ! command -v direnv >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "==> installing direnv via Homebrew (optional — entry points already prepend PATH)"
    brew install direnv
  else
    echo "install-test-guard: direnv not installed; PATH shim is active for this shell via ensure-test-guard-path." >&2
    echo "install-test-guard: install direnv manually if you want .envrc in interactive terminals." >&2
    exit 0
  fi
fi

if ! grep -q 'direnv hook' "$HOME/.zshrc" 2>/dev/null; then
  echo "install-test-guard: optional — add to ~/.zshrc for interactive terminals:" >&2
  echo '  eval "$(direnv hook zsh)"' >&2
fi

cat > "$ENVRC" <<'EOF'
# Prepends Allnighter test PATH shims (swift/xcodebuild test require scripts/swift-test.sh).
PATH_add scripts/bin
EOF

if command -v direnv >/dev/null 2>&1; then
  ( cd "$ROOT" && direnv allow )
  echo "==> direnv allow complete"
fi

resolved="$(command -v swift 2>/dev/null || true)"
echo "==> guard active: swift -> $resolved"
echo "==> test guard installed"
