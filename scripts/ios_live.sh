#!/usr/bin/env bash
# Build AllnighteriOS and launch on the booted simulator with relay env from .env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT/.env"
IOS_DIR="$ROOT/Apps/AllnighteriOS"
SCHEME="AllnighteriOS"
BUNDLE_ID="com.happymooseapps.AllnighteriOS"
DERIVED="${ALLNIGHTER_IOS_BUILD_DIR:-$HOME/Library/Developer/Allnighter/iOS-Build}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — run scripts/bootstrap_remote_env.sh first" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

DEVICE_NAME="${IOS_SIMULATOR_DEVICE:-}"
if [[ -z "$DEVICE_NAME" ]]; then
  DEVICE_NAME="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
for runtime in sorted(data["devices"], reverse=True):
    for device in data["devices"][runtime]:
        if device.get("isAvailable") and "iPhone" in device.get("name", ""):
            print(device["name"])
            raise SystemExit
print("iPhone 17")
')"
fi
DESTINATION="platform=iOS Simulator,name=${DEVICE_NAME}"

echo "==> Building $SCHEME for $DEVICE_NAME"
set +e
BUILD_LOG="$(mktemp)"
xcodebuild \
  -project "$IOS_DIR/AllnighteriOS.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  -destination "$DESTINATION" \
  build 2>&1 | tee "$BUILD_LOG"
BUILD_STATUS=${PIPESTATUS[0]}
set -e
if [[ "$BUILD_STATUS" -ne 0 ]]; then
  rg "error:" "$BUILD_LOG" | tail -20 >&2 || tail -30 "$BUILD_LOG" >&2
  rm -f "$BUILD_LOG"
  exit "$BUILD_STATUS"
fi
rm -f "$BUILD_LOG"

APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/AllnighteriOS.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build failed — expected $APP_PATH" >&2
  exit 1
fi

BOOTED="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((u["udid"] for devs in d["devices"].values() for u in devs if u.get("state")=="Booted"), ""))')"
if [[ -z "$BOOTED" ]]; then
  echo "==> Booting simulator: $DEVICE_NAME"
  xcrun simctl boot "$DEVICE_NAME" || true
  open -a Simulator
  sleep 2
  BOOTED="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((u["udid"] for devs in d["devices"].values() for u in devs if u.get("state")=="Booted"), ""))')"
fi

echo "==> Installing on $BOOTED"
xcrun simctl install "$BOOTED" "$APP_PATH"

echo "==> Launching with ALLNIGHTER_* env"
while IFS= read -r line; do
  key="${line%%=*}"
  value="${line#*=}"
  value="${value%\"}"
  value="${value#\"}"
  export "SIMCTL_CHILD_${key}=${value}"
done < <(grep -E '^ALLNIGHTER_' "$ENV_FILE")

xcrun simctl terminate "$BOOTED" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$BOOTED" "$BUNDLE_ID"
