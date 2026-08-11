#!/usr/bin/env bash
# Rebuild and refresh the agent-facing CLI outside a protected checkout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE="$ROOT/Packages/AllnighterCore"

# Fail fast when the sibling AgentOS path dependency is missing. Package.swift
# points at ../../../AgentOS; without it `swift package resolve` hangs with no
# output — the worst cold-clone failure mode for agents.
AGENTOS_EXPECTED="$(cd "$PACKAGE/../../.." && pwd)/AgentOS"
if [[ ! -d "$AGENTOS_EXPECTED" ]]; then
  cat >&2 <<EOF
rebuild_cli: AgentOS sibling missing.

  Expected: $AGENTOS_EXPECTED
  Package.swift depends on that local path. Resolve hangs if it is absent.

  Clone it next to this repo, then retry:
    git clone <your-AgentOS-url> "$AGENTOS_EXPECTED"

  (Ask the owner for the canonical remote if you do not have it.)
EOF
  exit 1
fi

# A checkout often lives in ~/Documents. SwiftPM's normal .build directory
# would leave the resident executable there, which can make macOS attribute
# later protected-folder access to Allnighter. Keep the executable image in an
# Allnighter-owned developer directory instead.
SCRATCH="${ALLNIGHTER_CLI_SCRATCH:-$HOME/Library/Developer/Allnighter/CLI}"
# Drop stale BuildInfo so incremental SPM builds cannot relink an old gitSha
# (BuildInfoPlugin buildCommand regenerates when inputs move; missing output
# forces a run even if mtimes are ambiguous after a scratch reuse).
find "$SCRATCH/plugins/outputs" -name 'BuildInfo.generated.swift' -delete 2>/dev/null || true

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

# Belt: leave a Documents/Desktop/Downloads checkout cwd before install-cli
# so the foreground `alln` never inherits a protected folder (CLI_Install_Documents_CWD_TCC).
PROBE_SCRATCH="$HOME/Library/Application Support/Allnighter/ProbeScratch"
if mkdir -p "$PROBE_SCRATCH" 2>/dev/null; then
  cd "$PROBE_SCRATCH"
else
  cd "$HOME"
fi

# Delegate install to install-cli (ASR-S01c). Only pass --path when the
# caller supplied an explicit override via ALLNIGHTER_CLI_INSTALL_DIR.
if [[ -n "${ALLNIGHTER_CLI_INSTALL_DIR:-}" ]]; then
  exec "$ALLN_BIN" install-cli --path "$ALLNIGHTER_CLI_INSTALL_DIR"
else
  exec "$ALLN_BIN" install-cli
fi
