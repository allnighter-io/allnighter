#!/usr/bin/env bash
# Build AllnighteriOS and launch on the booted simulator with relay env from .env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT/.env"
IOS_DIR="$ROOT/Apps/AllnighteriOS"
SCHEME="AllnighteriOS"
DERIVED="${ALLNIGHTER_IOS_BUILD_DIR:-$HOME/Library/Developer/Allnighter/iOS-Build}"
LOG="$DERIVED/last-ios-build.log"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/ios_sim_common.sh"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — run scripts/bootstrap_remote_env.sh first" >&2
  exit 1
fi

DEVICE_NAME="$(ios_simulator_device)"
DESTINATION="platform=iOS Simulator,name=${DEVICE_NAME}"

echo "==> Building $SCHEME for $DEVICE_NAME (live)"
mkdir -p "$DERIVED"
set +e
xcodebuild build \
  -project "$IOS_DIR/AllnighteriOS.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  -destination "$DESTINATION" \
  -quiet \
  >"$LOG" 2>&1
BUILD_STATUS=$?
set -e
if [[ "$BUILD_STATUS" -ne 0 ]]; then
  echo "✗ build failed:" >&2
  rg "error:" "$LOG" | tail -20 >&2 || tail -30 "$LOG" >&2
  echo "  (full log: $LOG)" >&2
  exit "$BUILD_STATUS"
fi

APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/AllnighteriOS.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build failed — expected $APP_PATH" >&2
  exit 1
fi

IOS_LAUNCH_ENV_FILE="$ENV_FILE" exec bash "$SCRIPT_DIR/ios_sim_launch.sh"
