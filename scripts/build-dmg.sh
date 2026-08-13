#!/usr/bin/env bash
# Build a Developer ID–signed, notarized, stapled Allnighter.dmg.
#
# Usage:
#   scripts/build-dmg.sh
#
# Env:
#   ALLN_DMG_OUT          output path (default dist/Allnighter.dmg)
#   ALLN_SIGN_IDENTITY    default Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)
#   NOTARY_PROFILE        default xterminal-notary
#   ALLN_DMG_SKIP_ARCHIVE=1  reuse existing xcarchive under ALLN_DMG_WORK
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAC_APP="$ROOT/Apps/AllnighterMac"
OUT="${ALLN_DMG_OUT:-$ROOT/dist/Allnighter.dmg}"
SIGN_IDENTITY="${ALLN_SIGN_IDENTITY:-Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-xterminal-notary}"
WORK="${ALLN_DMG_WORK:-$ROOT/dist/.dmg-build}"

die() { echo "build-dmg: $*" >&2; exit 1; }

if [ -z "${DEVELOPER_DIR:-}" ] && ! xcodebuild -version >/dev/null 2>&1; then
  if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)"
command -v xcodebuild >/dev/null || die "xcodebuild not found"
security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY" \
  || die "signing identity not in Keychain: $SIGN_IDENTITY"

mkdir -p "$(dirname "$OUT")" "$WORK"
ARCHIVE="$WORK/Allnighter.xcarchive"
EXPORT_DIR="$WORK/export"
APP="$EXPORT_DIR/Allnighter.app"
STAGE="$WORK/dmgroot"

if [[ "${ALLN_DMG_SKIP_ARCHIVE:-}" == "1" ]]; then
  [[ -d "$ARCHIVE/Products/Applications/Allnighter.app" ]] \
    || die "ALLN_DMG_SKIP_ARCHIVE=1 but archive missing: $ARCHIVE"
  echo "build-dmg: skip archive (reusing $ARCHIVE)"
else
  echo "build-dmg: xcodegen"
  ( cd "$MAC_APP" && xcodegen generate )

  echo "build-dmg: archive (arm64)"
  xcodebuild -project "$MAC_APP/AllnighterMac.xcodeproj" \
    -scheme AllnighterMac \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    archive \
    DEVELOPMENT_TEAM=LP5YNK7A36 \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    EXCLUDED_ARCHS=x86_64 \
    SWIFT_COMPILATION_MODE=incremental
fi

echo "build-dmg: Developer ID re-sign"
# Apple forbids Sign in with Apple on Developer ID profiles, so Organizer
# Direct Distribution fails if the archive still carries SIWA. We copy the
# archived .app and re-sign with DeveloperID entitlements (network only).
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
ARCHIVE_APP="$ARCHIVE/Products/Applications/Allnighter.app"
[[ -d "$ARCHIVE_APP" ]] || die "archived app missing: $ARCHIVE_APP"
ditto "$ARCHIVE_APP" "$APP"
rm -f "$APP/Contents/embedded.provisionprofile"
ENTITLEMENTS="$MAC_APP/Sources/AllnighterMac.DeveloperID.entitlements"
[[ -f "$ENTITLEMENTS" ]] || die "missing $ENTITLEMENTS"
codesign --force --options runtime --timestamp \
  --sign "$SIGN_IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  "$APP"
codesign --verify --deep --strict "$APP" || die "codesign --verify failed"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Authority=|Identifier=|TeamIdentifier=|Signature=' || true

echo "build-dmg: package DMG"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Allnighter.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -volname "Allnighter" -srcfolder "$STAGE" -ov -format UDZO "$OUT"

echo "build-dmg: notarize ($NOTARY_PROFILE)"
xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait

echo "build-dmg: staple"
xcrun stapler staple "$OUT"
xcrun stapler validate "$OUT"

echo "build-dmg: OK"
echo "  dmg:     $OUT"
echo "  sha256:  $(shasum -a 256 "$OUT" | awk '{print $1}')"
echo "  version: $(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
