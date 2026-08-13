#!/usr/bin/env bash
# Upload a publish-release.sh layout to the get.allnighter.io R2 bucket.
#
# Ordering: versioned assets first, install script, latest.json LAST (law 4).
#
# Usage:
#   scripts/upload-release-to-r2.sh [publish_dir]
#   scripts/upload-release-to-r2.sh dist/releases
#
# Env:
#   ALLN_R2_BUCKET   default allnighter-releases
#   ALLN_SKIP_INSTALL_SCRIPT=1  skip install/get-alln.sh upload
#
# Requires: wrangler logged in, infra/get-faucet Worker deployed with RELEASES binding.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

die() {
  echo "upload-release-to-r2: $*" >&2
  exit 1
}

PUBLISH_DIR="${1:-$ROOT/dist/releases}"
BUCKET="${ALLN_R2_BUCKET:-allnighter-releases}"

[[ -d "$PUBLISH_DIR" ]] || die "publish dir not found: $PUBLISH_DIR"

put_object() {
  local key="$1"
  local file="$2"
  local content_type="${3:-application/octet-stream}"
  echo "upload-release-to-r2: → s3://$BUCKET/$key"
  wrangler r2 object put "$BUCKET/$key" \
    --file "$file" \
    --content-type "$content_type" \
    --remote
}

# --- versioned assets (immutable) --------------------------------------------
shopt -s nullglob
for version_dir in "$PUBLISH_DIR"/v*/; do
  [[ -d "$version_dir" ]] || continue
  version="$(basename "$version_dir")"
  for asset in "$version_dir"/*; do
    [[ -f "$asset" ]] || continue
    name="$(basename "$asset")"
    case "$name" in
      *.sha256) ctype="text/plain; charset=utf-8" ;;
      *.json) ctype="application/json; charset=utf-8" ;;
      *.dmg) ctype="application/x-apple-diskimage" ;;
      *) ctype="application/octet-stream" ;;
    esac
    put_object "$version/$name" "$asset" "$ctype"
  done
done
shopt -u nullglob

# --- install script (short TTL at edge) --------------------------------------
if [[ "${ALLN_SKIP_INSTALL_SCRIPT:-}" != "1" ]]; then
  INSTALL_SCRIPT="$ROOT/scripts/get-alln.sh"
  [[ -f "$INSTALL_SCRIPT" ]] || die "missing $INSTALL_SCRIPT"
  put_object "install/get-alln.sh" "$INSTALL_SCRIPT" "text/plain; charset=utf-8"
fi

# --- latest.json LAST ---------------------------------------------------------
LATEST="$PUBLISH_DIR/latest.json"
if [[ -f "$LATEST" ]]; then
  put_object "latest.json" "$LATEST" "application/json; charset=utf-8"
else
  echo "upload-release-to-r2: skip latest.json (not present in $PUBLISH_DIR)" >&2
fi

echo "upload-release-to-r2: OK"
