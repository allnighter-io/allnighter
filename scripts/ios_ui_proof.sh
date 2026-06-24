#!/usr/bin/env bash
# UI proof for AllnighteriOS — XCTest drives the simulator; agents read pass/fail.
#
# Usage:
#   scripts/ios_ui_proof.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/ios_sim_common.sh"

IOS_DIR="$ROOT/Apps/AllnighteriOS"
DERIVED="${ALLNIGHTER_IOS_BUILD_DIR:-$HOME/Library/Developer/Allnighter/iOS-Build}"
DEVICE_NAME="$(ios_simulator_device)"
LOG="/tmp/allnighter-ios-ui-proof.log"
CAPTURE_DIR="$ROOT/docs/qa/ios/_captures"

mkdir -p "$CAPTURE_DIR"

# UITest must hit preview, not live relay — strip relay env inherited from shell/.env.
unset ALLNIGHTER_SUPABASE_URL ALLNIGHTER_SUPABASE_ANON_KEY ALLNIGHTER_DEVICE_ACCESS_TOKEN
unset ALLNIGHTER_SUPABASE_PUBLISHABLE_KEY ALLNIGHTER_SUPABASE_ACCESS_TOKEN
unset ALLNIGHTER_SUPABASE_DEVICE_ACCESS_TOKEN ALLNIGHTER_REMOTE_ACCOUNT_ID
unset SIMCTL_CHILD_ALLNIGHTER_SUPABASE_URL SIMCTL_CHILD_ALLNIGHTER_SUPABASE_ANON_KEY
unset SIMCTL_CHILD_ALLNIGHTER_DEVICE_ACCESS_TOKEN

export ALLNIGHTER_UI_TESTING_PREVIEW=1

echo "==> UI uitest on $DEVICE_NAME"
set +e
ALLNIGHTER_UI_TESTING_PREVIEW=1 xcodebuild test \
  -project "$IOS_DIR/AllnighteriOS.xcodeproj" \
  -scheme AllnighteriOS \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  -destination "platform=iOS Simulator,name=${DEVICE_NAME}" \
  -only-testing:AllnighteriOSUITests/AllnighteriOSUITests/testPreviewHomeAndModelPicker \
  2>&1 | tee "$LOG"
status=$?
set -e

if [[ $status -ne 0 ]]; then
  echo "✗ UI uitest failed — log: $LOG" >&2
  exit "$status"
fi

# Best-effort still capture for agent eyes (home frame after tests).
bash "$SCRIPT_DIR/ios_screenshot.sh" home >/dev/null 2>&1 || true

echo "✓ UI uitest passed"
