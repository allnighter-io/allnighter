#!/usr/bin/env bash
# =============================================================================
# Allnighter — Codex workspace-git permission profile installer
# =============================================================================
#
# COPY-PASTE — install (run from repo root)
# -----------------------------------------------------------------------------
#   cd /path/to/Allnighter
#   bash scripts/install_codex_workspace_permissions.sh
#
# WHAT THIS DOES
#   Merges the workspace-git permission profile into ~/.codex/config.toml and
#   removes legacy sandbox blocks (sandbox_mode, [sandbox_workspace_write])
#   that prevent default_permissions from applying.
#
# REQUIREMENTS
#   - codex-cli >= 0.138.0 on PATH (brew upgrade codex)
#   - Do not pass --sandbox to codex exec; it overrides default_permissions
#   - Start a new Codex thread after install; existing threads stay read-only
# -----------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON3="${PYTHON3:-python3}"

if ! command -v "$PYTHON3" &>/dev/null; then
  echo "error: python3 not found" >&2
  exit 1
fi

exec "$PYTHON3" "$REPO_ROOT/scripts/install_codex_workspace_permissions.py" "$@"
