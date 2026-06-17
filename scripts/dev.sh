#!/usr/bin/env bash
# Allnighter — fast build & launch for local UI iteration.
#
# Usage (wire `allapp` to this in your shell — see scripts/README-dev.md):
#   allapp           regenerate project, incremental build, relaunch the app
#   allapp build     build only (no launch)
#   allapp test      run the green wall (swift + xcodebuild tests)
#   allapp clean     drop the cached build, then build & launch fresh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAC_APP="$ROOT/Apps/AllnighterMac"
# Build/launch OUT of the repo. The checkout lives under ~/Documents, and macOS
# attributes a child's TCC prompts to the .app's location — launching from
# ~/Documents made cold launch raise a Documents permission dialog. ~/Library is
# not a TCC-protected folder, persists across reboots, and keeps logs findable.
# (Launch Authority TCC hotfix, slice H4. Override with ALLNIGHTER_BUILD_DIR.)
DERIVED="${ALLNIGHTER_BUILD_DIR:-$HOME/Library/Developer/Allnighter/Build}"
SCHEME="AllnighterMac"
APP="$DERIVED/Build/Products/Debug/Allnighter.app"
LOG="$DERIVED/last-build.log"

cmd="${1:-run}"

case "$cmd" in
  test)
    exec bash "$ROOT/scripts/check.sh"
    ;;
  clean)
    echo "==> clean ($DERIVED)"
    rm -rf "$DERIVED"
    ;;
esac

start=$(date +%s)

# 1. Regenerate the Xcode project so new Sources/ files are always picked up.
if command -v xcodegen >/dev/null 2>&1; then
  ( cd "$MAC_APP" && xcodegen generate >/dev/null )
else
  echo "dev: xcodegen not found — run 'brew install xcodegen'" >&2
  exit 1
fi

# 2. Incremental build (quiet; surface errors only on failure).
echo "==> building ${SCHEME}…"
mkdir -p "$DERIVED"
set +e
xcodebuild build \
  -project "$MAC_APP/AllnighterMac.xcodeproj" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -configuration Debug \
  -quiet >"$LOG" 2>&1
status=$?
set -e
if [ $status -ne 0 ]; then
  echo "✗ build failed:" >&2
  grep -E "error:" "$LOG" | head -40 || true
  echo "  (full log: $LOG)" >&2
  exit $status
fi
echo "✓ built in $(( $(date +%s) - start ))s"

[ "$cmd" = "build" ] && exit 0

# 3. Relaunch: kill any running instance, then open the fresh build.
pkill -x Allnighter 2>/dev/null || true
open "$APP"
echo "✓ launched $APP"
