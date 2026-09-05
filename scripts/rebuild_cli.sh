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

# Give the dogfood binary the SAME code identity as the shipped CLI. macOS keys
# every TCC answer (Documents, Local Network, ...) to the code identity, and an
# ad-hoc signature's identity IS its CDHash — which churns on every rebuild, so
# each rebuild re-asks and no Allow ever sticks
# (archived CLI_Install_Documents_TCC_Adhoc_Waive.md). Signing with the release
# Developer ID + `com.allnighter.cli` gives dogfood a stable anchor, so an Allow
# survives the next rebuild. Falls back to ad-hoc when the identity is absent
# (CI, a fresh clone) — the build must not depend on a private key.
SIGN_IDENTITY="${ALLN_SIGN_IDENTITY:-Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)}"
if [[ "${ALLNIGHTER_CLI_SKIP_SIGN:-}" == "1" ]]; then
  echo "rebuild_cli: skip signing (ALLNIGHTER_CLI_SKIP_SIGN=1) — ad-hoc identity, TCC will re-ask"
elif security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY"; then
  # No --timestamp: the designated requirement (identifier + team) is what TCC
  # keys on, and a timestamp costs a network round trip on every rebuild.
  codesign --force --options runtime --timestamp=none \
    --sign "$SIGN_IDENTITY" \
    --identifier com.allnighter.cli \
    "$ALLN_BIN"
  codesign --verify --strict "$ALLN_BIN" \
    || { echo "rebuild_cli: codesign --verify failed for $ALLN_BIN" >&2; exit 1; }
  echo "rebuild_cli: signed com.allnighter.cli ($SIGN_IDENTITY)"
else
  echo "rebuild_cli: signing identity not in Keychain, staying ad-hoc — TCC prompts will repeat" >&2
  echo "  wanted: $SIGN_IDENTITY" >&2
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
