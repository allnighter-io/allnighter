#!/usr/bin/env bash
# OPC-S00 + OPC-S06c — Lay out one release's CLI assets at an immutable
# versioned path, then write latest.json LAST (assets-then-manifest).
#
# Local / dogfood only. Mirrors the public URL shape from
# docs/phases/One_Paste_Cold_Start.md, rooted at a directory instead of a host:
#
#   <base>/v<version>/alln-macos-universal
#   <base>/v<version>/alln-macos-universal.sha256
#   <base>/latest.json                         # ONLY mutable object; written last
#
# Base directory: ${ALLN_PUBLISH_BASE_DIR:-dist/releases}
# (relative paths are resolved from the repo root).
#
# Public asset URLs inside latest.json use:
#   ${ALLN_PUBLIC_BASE_URL:-https://get.allnighter.io}
# so a local layout can still name the canonical fetch URLs.
#
# Does NOT upload, sign with Developer ID, or touch DNS (OPC-S05).
#
# Immutability: if v<version>/ already exists, refuse (no --force).
# Republish = new version number. latest.json is rewritten on each publish.
#
# Env:
#   ALLN_PUBLISH_BASE_DIR   layout root (default dist/releases)
#   ALLN_UNIVERSAL_BINARY   prebuilt universal CLI path
#   ALLN_PUBLIC_BASE_URL    URL prefix for assets in latest.json
#   ALLN_APP_VERSION        appVersion field (default = cli version)
#   ALLN_RELEASE_NOTES      optional notes (human-only; never agent-projected)
#   ALLN_APP_DMG_SHA256     if set with a DMG present, emit app block
#   ALLN_SKIP_LATEST_JSON=1 asset-only (tests); default writes latest.json
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
ABS_BASE="$(cd "$BASE" && pwd)"

# --- latest.json LAST (OPC-S06c / law 4: assets before manifest) ------------
# Ordering: versioned assets already on disk above; only then flip the mutable
# pointer. Never rewrite a versioned path; only latest.json moves forward.
LATEST_PATH=""
if [[ "${ALLN_SKIP_LATEST_JSON:-}" != "1" ]]; then
  PUBLIC_BASE="${ALLN_PUBLIC_BASE_URL:-https://get.allnighter.io}"
  PUBLIC_BASE="${PUBLIC_BASE%/}"
  APP_VERSION="${ALLN_APP_VERSION:-$VERSION}"
  NOTES="${ALLN_RELEASE_NOTES:-}"
  # installCommand is informational in the manifest only (law 9); always the
  # canonical public one-liner, never a dogfood-base cousin.
  INSTALL_CMD="curl -fsSL https://get.allnighter.io | sh"
  CLI_URL="$PUBLIC_BASE/v$VERSION/$ASSET_NAME"
  RELEASED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # Optional app DMG block when the founder stages a DMG + hash.
  DMG_NAME="Allnighter.dmg"
  DMG_PATH="$VERSION_DIR/$DMG_NAME"
  APP_URL_FOR_PY=""
  APP_SHA_FOR_PY=""
  if [[ -f "$DMG_PATH" && -n "${ALLN_APP_DMG_SHA256:-}" ]]; then
    APP_URL_FOR_PY="$PUBLIC_BASE/v$VERSION/$DMG_NAME"
    APP_SHA_FOR_PY="$ALLN_APP_DMG_SHA256"
  fi

  # Build latest.json via Python so notes/urls are valid JSON (no hand-escaping).
  MANIFEST_STAGE="$BASE/latest.json.tmp.$$"
  ALLN_PUBLISH_VERSION="$VERSION" \
  ALLN_PUBLISH_APP_VERSION="$APP_VERSION" \
  ALLN_PUBLISH_RELEASED_AT="$RELEASED_AT" \
  ALLN_PUBLISH_NOTES="$NOTES" \
  ALLN_PUBLISH_INSTALL_CMD="$INSTALL_CMD" \
  ALLN_PUBLISH_CLI_URL="$CLI_URL" \
  ALLN_PUBLISH_CLI_SHA="$SHA256" \
  ALLN_PUBLISH_APP_URL="$APP_URL_FOR_PY" \
  ALLN_PUBLISH_APP_SHA="$APP_SHA_FOR_PY" \
  ALLN_PUBLISH_OUT="$MANIFEST_STAGE" \
  python3 - <<'PY'
import json, os
from pathlib import Path

doc = {
    "schemaVersion": 1,
    "cliVersion": os.environ["ALLN_PUBLISH_VERSION"],
    "appVersion": os.environ["ALLN_PUBLISH_APP_VERSION"],
    "releasedAt": os.environ["ALLN_PUBLISH_RELEASED_AT"],
    "notes": os.environ.get("ALLN_PUBLISH_NOTES", ""),
    "installCommand": os.environ["ALLN_PUBLISH_INSTALL_CMD"],
    "cli": {
        "url": os.environ["ALLN_PUBLISH_CLI_URL"],
        "sha256": os.environ["ALLN_PUBLISH_CLI_SHA"],
    },
}
app_url = os.environ.get("ALLN_PUBLISH_APP_URL", "").strip()
app_sha = os.environ.get("ALLN_PUBLISH_APP_SHA", "").strip()
if app_url and app_sha:
    doc["app"] = {"url": app_url, "sha256": app_sha}

out = Path(os.environ["ALLN_PUBLISH_OUT"])
out.write_text(json.dumps(doc, indent=2, sort_keys=False) + "\n", encoding="utf-8")
PY
  # Atomic rename — concurrent readers never see a torn latest.json.
  mv -f "$MANIFEST_STAGE" "$BASE/latest.json"
  LATEST_PATH="$ABS_BASE/latest.json"

  # Sanity: manifest must name the asset we just published.
  grep -q "$SHA256" "$LATEST_PATH" || die "latest.json missing cli sha256"
  grep -q "\"cliVersion\": \"$VERSION\"" "$LATEST_PATH" || die "latest.json cliVersion mismatch"
fi

echo "publish-release: OK"
echo "  binary:  $ABS_DEST"
echo "  sha256f: $ABS_SHA"
echo "  sha256:  $SHA256"
if [[ -n "$LATEST_PATH" ]]; then
  echo "  latest:  $LATEST_PATH"
fi
cat "$ABS_SHA"
