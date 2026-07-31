#!/usr/bin/env bash
# OPC-S00 — Lay out one release's CLI assets at an immutable versioned path.
#
# Local / dogfood only. Mirrors the public URL shape from
# docs/phases/One_Paste_Cold_Start.md, rooted at a directory instead of a host:
#
#   <base>/v<version>/alln-macos-universal
#   <base>/v<version>/alln-macos-universal.sha256
#
# Base directory: ${ALLN_PUBLISH_BASE_DIR:-dist/releases}
# (relative paths are resolved from the repo root).
#
# Does NOT write latest.json / any release manifest — that is OPC-S06.
# Does NOT upload, sign with Developer ID, or touch DNS.
#
# Immutability: if v<version>/ already exists, refuse (no --force).
# Republish = new version number.
#
# Usage:
#   scripts/publish-release.sh <version>
#   ALLN_PUBLISH_BASE_DIR=/tmp/scratch scripts/publish-release.sh 0.0.0-test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

die() {
  echo "publish-release: $*" >&2
  exit 1
}

usage() {
  die "usage: scripts/publish-release.sh <version>"
}

[[ $# -eq 1 ]] || usage
VERSION="$1"
[[ -n "$VERSION" ]] || usage
# Reject path separators so version never escapes the versioned directory.
case "$VERSION" in
  */*|*\\*|*..*) die "version must be a single path segment (got: $VERSION)" ;;
esac

BASE_RAW="${ALLN_PUBLISH_BASE_DIR:-dist/releases}"
case "$BASE_RAW" in
  /*) BASE="$BASE_RAW" ;;
  *)  BASE="$ROOT/$BASE_RAW" ;;
esac

VERSION_DIR="$BASE/v$VERSION"
ASSET_NAME="alln-macos-universal"
DEST="$VERSION_DIR/$ASSET_NAME"
SHA_FILE="$DEST.sha256"

BINARY="${ALLN_UNIVERSAL_BINARY:-${ALLN_UNIVERSAL_OUT:-$ROOT/dist/alln-macos-universal}}"

if [[ -e "$VERSION_DIR" ]]; then
  die "refusing to overwrite immutable release path: $VERSION_DIR (use a new version number)"
fi

if [[ ! -x "$BINARY" ]]; then
  echo "publish-release: no universal binary at $BINARY — building …" >&2
  "$SCRIPT_DIR/build-universal.sh"
  BINARY="${ALLN_UNIVERSAL_OUT:-$ROOT/dist/alln-macos-universal}"
fi
[[ -x "$BINARY" ]] || die "universal binary missing after build: $BINARY"

# Sanity: still look universal (don't publish a thin accidental rebuild).
LIPO_INFO="$(lipo -info "$BINARY" 2>/dev/null || true)"
echo "$LIPO_INFO" | grep -q arm64 || die "source binary missing arm64: $LIPO_INFO"
echo "$LIPO_INFO" | grep -q x86_64 || die "source binary missing x86_64: $LIPO_INFO"

mkdir -p "$VERSION_DIR"
# Stage then rename so a killed publish never leaves a half-written final name
# inside a version dir that would then permanently block republish.
STAGE="$DEST.tmp.$$"
cp "$BINARY" "$STAGE"
chmod 755 "$STAGE"
mv -f "$STAGE" "$DEST"

# shasum -a 256 format: "HASH  filename" (two spaces). Hash from the file
# content; name the asset basename so checksum files stay relocatable.
(
  cd "$VERSION_DIR"
  shasum -a 256 "$ASSET_NAME" >"$ASSET_NAME.sha256"
)

SHA256="$(awk '{print $1}' "$SHA_FILE")"
[[ ${#SHA256} -eq 64 ]] || die "unexpected sha256 length in $SHA_FILE"

# Absolute paths for the caller / proof paste.
ABS_DEST="$(cd "$VERSION_DIR" && pwd)/$ASSET_NAME"
ABS_SHA="$(cd "$VERSION_DIR" && pwd)/$ASSET_NAME.sha256"

echo "publish-release: OK"
echo "  binary:  $ABS_DEST"
echo "  sha256f: $ABS_SHA"
echo "  sha256:  $SHA256"
cat "$ABS_SHA"
