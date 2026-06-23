#!/usr/bin/env bash
# Allnighter — fast build & launch for local UI iteration.
#
# Usage (wire `allapp` to this in your shell — see scripts/README-dev.md):
#   allapp           regenerate project, incremental build, relaunch the app
#   allapp build     build only (no launch)
#   allapp test      run the green wall (swift + xcodebuild tests)
#   allapp clean     drop the cached build, then build & launch fresh
#
# Design notes (why this script looks the way it does):
#   - The progress heartbeat is a FOREGROUND poll tied to the real build PID — it
#     physically cannot outlive the build. (The old detached `while true` subshell
#     survived `kill -9` of its parent, reparented to launchd, and printed
#     "still building (Ns)" FOREVER — a zombie that made fast builds look hung.)
#   - A `trap` tears everything down on any exit, error, or Ctrl-C: no orphans.
#   - A single-build lock keeps two `allapp`s from building into one DerivedData at
#     once — concurrent builds corrupt `build.db` and force full rebuilds.
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
LOCK="$DERIVED/.allapp-build.lock"

# --- teardown: nothing this script starts survives it ---------------------------
BUILD_PID=""
cleanup() {
  if [ -n "$BUILD_PID" ] && kill -0 "$BUILD_PID" 2>/dev/null; then
    kill "$BUILD_PID" 2>/dev/null || true
  fi
  # Release our lock (only if we own it).
  if [ "$(cat "$LOCK/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -rf "$LOCK" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# --- single-build lock ----------------------------------------------------------
# Only one build per DerivedData at a time. If another live allapp holds it, wait;
# if the holder is dead (a crash/Ctrl-C left a stale lock + maybe an orphaned
# xcodebuild still on build.db), steal it and clear the orphan.
acquire_lock() {
  mkdir -p "$DERIVED"
  while ! mkdir "$LOCK" 2>/dev/null; do
    local owner
    owner="$(cat "$LOCK/pid" 2>/dev/null || true)"
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
      echo "==> another allapp build is running (pid $owner) — waiting…" >&2
      sleep 2
    else
      # Stale lock (holder dead). Steal it ATOMICALLY: rename the lock dir aside — only ONE
      # contender's mv can succeed (a dir renames once), so two simultaneous stealers can't
      # both "win" and run concurrent builds. The winner kills only the stale lock's OWN
      # recorded xcodebuild (never a broad `pkill derivedDataPath`, which would also kill a
      # concurrent gui_proof/agent build sharing this DerivedData), then drops the graveyard.
      local graveyard="$LOCK.dead.$$"
      if mv "$LOCK" "$graveyard" 2>/dev/null; then
        echo "==> clearing stale build lock (owner ${owner:-none} gone)" >&2
        local stale_build
        stale_build="$(cat "$graveyard/build_pid" 2>/dev/null || true)"
        [ -n "$stale_build" ] && kill -9 "$stale_build" 2>/dev/null || true
        rm -rf "$graveyard"
      fi
      # Whether or not we won the steal, loop and retry the atomic `mkdir "$LOCK"`.
    fi
  done
  echo "$$" >"$LOCK/pid"
}

cmd="${1:-run}"

case "$cmd" in
  test)
    exec bash "$ROOT/scripts/check.sh"
    ;;
  clean)
    echo "==> clean ($DERIVED)"
    rm -rf "$DERIVED"
    # fall through: build & launch fresh
    ;;
esac

start=$(date +%s)

# 1. Regenerate the Xcode project so new Sources/ files are always picked up.
#    (Deterministic — regenerating an unchanged project does NOT force a rebuild.)
if command -v xcodegen >/dev/null 2>&1; then
  ( cd "$MAC_APP" && xcodegen generate >/dev/null )
else
  echo "dev: xcodegen not found — run 'brew install xcodegen'" >&2
  exit 1
fi

# 2. Incremental build (quiet; errors surfaced on failure), with a live heartbeat
#    that ends exactly when the build process does.
acquire_lock
echo "==> building ${SCHEME}… (log: $LOG)"
mkdir -p "$DERIVED"
xcodebuild build \
  -project "$MAC_APP/AllnighterMac.xcodeproj" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -configuration Debug \
  -quiet >"$LOG" 2>&1 &
BUILD_PID=$!
# Record the xcodebuild pid in the lock so a future stale-lock steal can kill exactly THIS
# build (if we crash) — never a broad pkill that would hit other builds on this DerivedData.
echo "$BUILD_PID" >"$LOCK/build_pid" 2>/dev/null || true

elapsed=0
while kill -0 "$BUILD_PID" 2>/dev/null; do
  sleep 5
  elapsed=$((elapsed + 5))
  if [ $((elapsed % 30)) -eq 0 ]; then
    echo "… still building (${elapsed}s) — tail -f $LOG" >&2
  fi
done
wait "$BUILD_PID" && status=0 || status=$?
BUILD_PID=""

if [ "$status" -ne 0 ]; then
  echo "✗ build failed:" >&2
  grep -E "error:" "$LOG" | head -40 || true
  echo "  (full log: $LOG)" >&2
  exit "$status"
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
