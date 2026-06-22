#!/usr/bin/env bash
# Run AllnighteriOS unit tests (no UI tests) with a stable simulator destination.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$ROOT/Apps/AllnighteriOS"
DERIVED="${ALLNIGHTER_IOS_BUILD_DIR:-$HOME/Library/Developer/Allnighter/iOS-Build}"

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
print("iPhone 17 Pro")
')"
fi

echo "==> Testing AllnighteriOSTests on $DEVICE_NAME"
xcodebuild test \
  -project "$IOS_DIR/AllnighteriOS.xcodeproj" \
  -scheme AllnighteriOS \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  -destination "platform=iOS Simulator,name=${DEVICE_NAME}" \
  -only-testing:AllnighteriOSTests \
  2>&1 | tee /tmp/allnighter-ios-unit-tests.log | tail -30
