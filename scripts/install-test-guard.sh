#!/usr/bin/env bash
# One-time per clone: prepend scripts/bin to PATH via direnv and verify shims are active.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENVRC="$ROOT/.envrc"
SHIM_DIR="$ROOT/scripts/bin"

chmod +x "$SHIM_DIR/swift" "$SHIM_DIR/xcodebuild" 2>/dev/null || true

echo "==> install test guard (PATH shim for swift/xcodebuild test)"

if ! command -v direnv >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "==> installing direnv via Homebrew"
    brew install direnv
  else
    echo "install-test-guard: direnv is required but brew is unavailable." >&2
    echo "install-test-guard: install direnv, then re-run this script." >&2
    exit 1
  fi
fi

if ! grep -q 'direnv hook' "$HOME/.zshrc" 2>/dev/null; then
  echo "install-test-guard: add this line to your shell rc (~/.zshrc), then open a new shell:" >&2
  echo '  eval "$(direnv hook zsh)"' >&2
fi

cat > "$ENVRC" <<'EOF'
# Prepends Allnighter test PATH shims (swift/xcodebuild test require scripts/swift-test.sh).
PATH_add scripts/bin
EOF

if command -v direnv >/dev/null 2>&1; then
  ( cd "$ROOT" && direnv allow )
  echo "==> direnv allow complete"
else
  echo "install-test-guard: run 'direnv allow' in the repo root after enabling the direnv hook." >&2
fi

# Verify shim resolves ahead of the real toolchain when direnv is active in this shell.
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv export bash 2>/dev/null || true)"
fi

resolved="$(command -v swift 2>/dev/null || true)"
if [[ "$resolved" == "$SHIM_DIR/swift" ]]; then
  echo "==> guard active: swift -> $resolved"
else
  echo "install-test-guard: WARNING — shim is not first on PATH (swift -> ${resolved:-missing})." >&2
  echo "install-test-guard: run 'direnv allow' in $ROOT and start a new shell in this directory." >&2
  exit 1
fi

echo "==> test guard installed"
