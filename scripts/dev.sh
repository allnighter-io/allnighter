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

clear_build_lane() {
  local killed=0

  if pkill -f "derivedDataPath $DERIVED" 2>/dev/null; then
    killed=1
  fi

  local pid
  for pid in $(pgrep -f "$ROOT/scripts/dev.sh" 2>/dev/null || true); do
    [ "$pid" = "$$" ] && continue
    if kill -9 "$pid" 2>/dev/null; then
      killed=1
    fi
  done

  if [ "$killed" -eq 1 ]; then
    echo "==> cleared stale build lane" >&2
    pkill -9 XCBBuildService 2>/dev/null || true
    pkill -9 SWBBuildService 2>/dev/null || true
    sleep 1
  fi
}

start_build_heartbeat() {
  (
    local elapsed=0
    while true; do
      sleep 30
      elapsed=$((elapsed + 30))
      echo "… still building (${elapsed}s) — tail -f $LOG" >&2
    done
  ) &
  echo $!
}

stop_build_heartbeat() {
  kill "$1" 2>/dev/null || true
  wait "$1" 2>/dev/null || true
}

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
# Always clear our DerivedData lane first — orphaned xcodebuild locks build.db
# when a terminal dies mid-build or gui_proof races allapp.
clear_build_lane
echo "==> building ${SCHEME}… (log: $LOG)"
mkdir -p "$DERIVED"
heartbeat_pid=$(start_build_heartbeat)
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
stop_build_heartbeat "$heartbeat_pid"
if [ $status -ne 0 ]; then
  echo "✗ build failed:" >&2
  grep -E "error:" "$LOG" | head -40 || true
  echo "  (full log: $LOG)" >&2
  exit $status
fi
echo "✓ built in $(( $(date +%s) - start ))s"

[ "$cmd" = "build" ] && exit 0

# 3. Relaunch: kill any running instance, wait for teardown, then open.
if [ ! -d "$APP" ]; then
  echo "✗ app not found at $APP" >&2
  exit 1
fi
pkill -x Allnighter 2>/dev/null || true
deadline=$(( $(date +%s) + 10 ))
while pgrep -x Allnighter >/dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "✗ Allnighter did not exit after pkill" >&2
    exit 1
  fi
  sleep 0.05
done
open "$APP"
echo "✓ launched $APP"
