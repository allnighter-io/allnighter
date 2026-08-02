#!/bin/bash
# CAR-S00: build + sign + install + LaunchServices-register the harness app.
# Product-free, self-contained. Safe to re-run.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_ID="com.happymoose.allnighter.harness"
APP_NAME="AllnighterHarness"
INSTALL_DIR="$HOME/Applications"
APP="$INSTALL_DIR/$APP_NAME.app"
SIGN_IDENTITY="Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> Verifying signing identity"
security find-identity -v -p codesigning | grep -F "$SIGN_IDENTITY" >/dev/null \
    || { echo "ERROR: signing identity not found: $SIGN_IDENTITY" >&2; exit 1; }

echo "==> Building $APP_NAME"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/MacOS"

swiftc -O -o "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" \
    "$HERE/HarnessApp.swift" \
    -framework Foundation -framework Security

cat > "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSBackgroundOnly</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Signing with: $SIGN_IDENTITY"
codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
    "$BUILD_DIR/$APP_NAME.app"

echo "==> Verifying signature"
codesign --verify --deep --strict "$BUILD_DIR/$APP_NAME.app"

echo "==> Installing to $APP"
mkdir -p "$INSTALL_DIR"
# Kill any leftover instance from a previous probe before replacing the bundle.
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$APP"
ditto "$BUILD_DIR/$APP_NAME.app" "$APP"

echo "==> Registering with LaunchServices"
"$LSREGISTER" -f "$APP"

echo "==> Resolving bundle id via LaunchServices"
RESOLVED="$(osascript -e "id of app id \"$BUNDLE_ID\"" 2>/dev/null || true)"
echo "    osascript id lookup: ${RESOLVED:-<unresolved, trying mdfind>}"
mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" | head -3 || true

echo "==> Done. Installed: $APP"
