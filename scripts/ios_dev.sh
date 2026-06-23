#!/usr/bin/env bash
# Allnighter iOS — fast build, launch, and test (simulator).
#
# Usage (wire `allios` in ~/.zshrc — see scripts/README-ios-dev.md):
#   allios           build + launch on simulator with ALLNIGHTER_* from .env
#   allios build     build only (no launch; no .env required)
#   allios test      AllnighteriOSTests unit tests
#   allios clean     drop the cached iOS DerivedData, then build + launch
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$ROOT/Apps/AllnighteriOS"
SCHEME="AllnighteriOS"
DERIVED="${ALLNIGHTER_IOS_BUILD_DIR:-$HOME/Library/Developer/Allnighter/iOS-Build}"
LOG="$DERIVED/last-ios-build.log"

ios_simulator_device() {
  if [[ -n "${IOS_SIMULATOR_DEVICE:-}" ]]; then
    echo "$IOS_SIMULATOR_DEVICE"
    return
  fi
  xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
for runtime in sorted(data["devices"], reverse=True):
    for device in data["devices"][runtime]:
        if device.get("isAvailable") and "iPhone" in device.get("name", ""):
            print(device["name"])
            raise SystemExit
print("iPhone 17 Pro")
'
}

cmd="${1:-run}"

case "$cmd" in
  test)
    exec bash "$ROOT/scripts/ios_unit_tests.sh"
    ;;
  clean)
    echo "==> clean ($DERIVED)"
    rm -rf "$DERIVED"
    cmd=run
    ;;
  build|run)
    ;;
  *)
    echo "usage: allios [run|build|test|clean]" >&2
    exit 1
    ;;
esac

if [[ "$cmd" == "run" ]]; then
  exec bash "$ROOT/scripts/ios_live.sh"
fi

# build only
DEVICE_NAME="$(ios_simulator_device)"
DESTINATION="platform=iOS Simulator,name=${DEVICE_NAME}"
start=$(date +%s)

echo "==> building $SCHEME for $DEVICE_NAME"
mkdir -p "$DERIVED"
set +e
xcodebuild build \
  -project "$IOS_DIR/AllnighteriOS.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  -destination "$DESTINATION" \
  >"$LOG" 2>&1
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "✗ build failed:" >&2
  rg "error:" "$LOG" | head -40 >&2 || tail -30 "$LOG" >&2
  echo "  (full log: $LOG)" >&2
  exit $status
fi
echo "✓ built in $(( $(date +%s) - start ))s"
