#!/usr/bin/env bash
# Allnighter iOS — fast build, launch, and test (simulator).
#
# Usage (wire `allios` in ~/.zshrc — see scripts/README-ios-dev.md):
#   allios           build + launch (.env → live relay, else DEBUG preview)
#   allios preview   build + launch DEBUG preview (no .env)
#   allios launch    install + relaunch only (simulator must be booted)
#   allios build     build only (no launch)
#   allios test      AllnighteriOSTests unit tests
#   allios clean     drop cached iOS DerivedData, then build + launch
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

case "$cmd" in
  test)
    exec bash "$ROOT/scripts/ios_unit_tests.sh"
    ;;
  launch)
    if [[ -f "$ENV_FILE" ]]; then
      IOS_LAUNCH_ENV_FILE="$ENV_FILE" exec bash "$ROOT/scripts/ios_sim_launch.sh"
    else
      IOS_LAUNCH_ENV_FILE="" exec bash "$ROOT/scripts/ios_sim_launch.sh"
    fi
    ;;
  preview)
    exec bash "$ROOT/scripts/ios_preview.sh"
    ;;
  clean)
    echo "==> clean ($DERIVED)"
    rm -rf "$DERIVED"
    cmd=run
    ;;
  build|run)
    ;;
  *)
    echo "usage: allios [run|preview|launch|build|test|clean]" >&2
    exit 1
    ;;
esac

if [[ "$cmd" == "run" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    exec bash "$ROOT/scripts/ios_live.sh"
  else
    echo "==> No .env — using DEBUG preview (scripts/bootstrap_remote_env.sh for live)"
    exec bash "$ROOT/scripts/ios_preview.sh"
  fi
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
