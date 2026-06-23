#!/usr/bin/env bash
# Allnighter iOS — fast build, launch, and test (simulator).
#
# SSOT: docs/operations/ios-testing-loop.md
#
# Usage (wire `allios` in ~/.zshrc):
#   allios                 preview build + launch (DEFAULT — use this)
#   allios launch          preview relaunch only (fast loop)
#   allios live            live Mac: auto-start relay + build + launch (one command)
#   allios live launch     live relaunch only (relay still auto-started)
#   allios live stop       stop background Mac relay agent
#   allios build           build only
#   allios test            unit tests
#   allios clean           wipe DerivedData, then preview build + launch
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/ios_sim_common.sh"

IOS_DIR="$ROOT/Apps/AllnighteriOS"
SCHEME="AllnighteriOS"
DERIVED="${ALLNIGHTER_IOS_BUILD_DIR:-$HOME/Library/Developer/Allnighter/iOS-Build}"
LOG="$DERIVED/last-ios-build.log"
ENV_FILE="$ROOT/.env"

cmd="${1:-run}"
subcmd="${2:-}"

case "$cmd" in
  test)
    exec bash "$ROOT/scripts/ios_unit_tests.sh"
    ;;
  launch)
    IOS_LAUNCH_ENV_FILE="" exec bash "$ROOT/scripts/ios_sim_launch.sh"
    ;;
  live)
    if [[ "$subcmd" == "setup" ]]; then
      shift
      exec bash "$ROOT/scripts/bootstrap_remote_env.sh" "$@"
    fi
    if [[ "$subcmd" == "stop" ]]; then
      exec bash "$ROOT/scripts/ios_live_mac_agent.sh" stop
    fi
    if [[ ! -f "$ENV_FILE" ]]; then
      echo "==> First-time live setup (writes .env, one time only)…"
      bash "$ROOT/scripts/bootstrap_remote_env.sh"
    fi
    bash "$ROOT/scripts/ios_live_mac_agent.sh" ensure
    if [[ "$subcmd" == "launch" ]]; then
      IOS_LAUNCH_ENV_FILE="$ENV_FILE" exec bash "$ROOT/scripts/ios_sim_launch.sh"
    fi
    exec bash "$ROOT/scripts/ios_live.sh"
    ;;
  preview|run)
    exec bash "$ROOT/scripts/ios_preview.sh"
    ;;
  clean)
    echo "==> clean ($DERIVED)"
    rm -rf "$DERIVED"
    exec bash "$ROOT/scripts/ios_preview.sh"
    ;;
  build)
    ;;
  *)
    echo "usage: allios [run|launch|live|live launch|live stop|live setup|build|test|clean]" >&2
    echo "  docs/operations/ios-testing-loop.md" >&2
    exit 1
    ;;
esac

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
echo "✓ built in $(( $(date +%s) - start ))s"
