#!/usr/bin/env bash
# Build AllnighteriOS and launch on the simulator without relay env (DEBUG preview).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/ios_sim_common.sh"

IOS_DIR="$ROOT/Apps/AllnighteriOS"
SCHEME="AllnighteriOS"
DERIVED="${ALLNIGHTER_IOS_BUILD_DIR:-$HOME/Library/Developer/Allnighter/iOS-Build}"
LOG="$DERIVED/last-ios-build.log"
DEVICE_NAME="$(ios_simulator_device)"
DESTINATION="platform=iOS Simulator,name=${DEVICE_NAME}"

echo "==> Building $SCHEME for $DEVICE_NAME (preview)"
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
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "✗ build failed:" >&2
  rg "error:" "$LOG" | head -40 >&2 || tail -30 "$LOG" >&2
  echo "  (full log: $LOG)" >&2
  exit $status
fi

IOS_LAUNCH_ENV_FILE="" exec bash "$SCRIPT_DIR/ios_sim_launch.sh"
