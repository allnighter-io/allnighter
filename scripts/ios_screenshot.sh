#!/usr/bin/env bash
# Capture an iOS simulator screenshot after launching preview AllnighteriOS.
#
# Agents use this to verify UI — do not ask the founder to eyeball the simulator.
#
# Usage:
#   scripts/ios_screenshot.sh              # home (default)
#   scripts/ios_screenshot.sh model-picker # after UI proof opens picker
#   scripts/ios_screenshot.sh pending      # pending queue sheet
#   scripts/ios_screenshot.sh pending-review
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/ios_sim_common.sh"

NAME="${1:-home}"
CAPTURE_DIR="$ROOT/docs/qa/ios/_captures"
OUT="$CAPTURE_DIR/${NAME}.png"
DERIVED="${ALLNIGHTER_IOS_BUILD_DIR:-$HOME/Library/Developer/Allnighter/iOS-Build}"
APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/AllnighteriOS.app"

mkdir -p "$CAPTURE_DIR"
rm -f "$OUT"

if [[ ! -d "$APP_PATH" ]]; then
  echo "==> Building preview app (first capture)…"
  bash "$ROOT/scripts/ios_preview.sh" >/dev/null
fi

FIXTURE_ARGS=(-ui_testing_preview)
case "$NAME" in
  model-picker)
    FIXTURE_ARGS+=(-ui_fixture_model_picker)
    ;;
  thread)
    FIXTURE_ARGS+=(-ui_fixture_thread=thread-1)
    ;;
  pending)
    FIXTURE_ARGS+=(-ui_fixture_pending)
    ;;
  pending-review)
    FIXTURE_ARGS+=(-ui_fixture_pending_review)
    ;;
esac

IOS_LAUNCH_ARGS="${FIXTURE_ARGS[*]}" bash "$ROOT/scripts/ios_sim_launch.sh" >/dev/null
case "$NAME" in
  model-picker|thread|pending)
    sleep 3
    ;;
  pending-review)
    sleep 5
    ;;
  *)
    sleep 2
    ;;
esac

UDID="$(ios_simulator_booted_udid)"
xcrun simctl io "$UDID" screenshot "$OUT"

echo "✓ screenshot: $OUT"
