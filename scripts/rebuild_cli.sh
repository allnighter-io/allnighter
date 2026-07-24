#!/usr/bin/env bash
# Rebuild and refresh the agent-facing CLI outside a protected checkout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE="$ROOT/Packages/AllnighterCore"

# A checkout often lives in ~/Documents. SwiftPM's normal .build directory
# would leave the resident executable there, which can make macOS attribute
# later protected-folder access to Allnighter. Keep the executable image in an
# Allnighter-owned developer directory instead.
SCRATCH="${ALLNIGHTER_CLI_SCRATCH:-$HOME/Library/Developer/Allnighter/CLI}"
INSTALL_DIR="${ALLNIGHTER_CLI_INSTALL_DIR:-$HOME/.local/bin}"

swift build \
  --disable-sandbox \
  --package-path "$PACKAGE" \
  --scratch-path "$SCRATCH" \
  --product alln

BIN_DIR="$(swift build \
  --disable-sandbox \
  --package-path "$PACKAGE" \
  --scratch-path "$SCRATCH" \
  --show-bin-path)"
ALLN_BIN="$BIN_DIR/alln"

if [[ ! -x "$ALLN_BIN" ]]; then
  echo "rebuild failed: expected executable at $ALLN_BIN" >&2
  exit 1
fi

"$ALLN_BIN" install-cli --path "$INSTALL_DIR"
