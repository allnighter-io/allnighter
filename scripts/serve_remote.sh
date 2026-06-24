#!/usr/bin/env bash
# Start alln serve with cloud relay env from repo-root .env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — run scripts/bootstrap_remote_env.sh first" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

ALLN_BIN="${ALLN_BIN:-$(swift build --package-path "$ROOT/Packages/AllnighterCore" --disable-sandbox --product alln --show-bin-path 2>/dev/null)/alln}"
if [[ ! -x "$ALLN_BIN" ]]; then
  echo "Building alln..."
  ALLN_BIN="$(swift build --package-path "$ROOT/Packages/AllnighterCore" --disable-sandbox --product alln --show-bin-path)/alln"
fi

exec "$ALLN_BIN" serve "$@"
