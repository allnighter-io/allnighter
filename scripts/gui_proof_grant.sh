#!/usr/bin/env bash
# Allnighter — one-time Screen Recording grant for the GUI proof harness.
#
# Launches Allnighter through the real .app bundle (Launch Services) with a
# dedicated grant UI. Stay on this window until it shows the green checkmark,
# then quit. After that, overlay fixtures (compose-*) capture native popovers.
#
# Usage:
#   bash scripts/gui_proof_grant.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAC_APP="$ROOT/Apps/AllnighterMac"
DERIVED="${ALLNIGHTER_BUILD_DIR:-$HOME/Library/Developer/Allnighter/Build}"
SCHEME="AllnighterMac"
APP="$DERIVED/Build/Products/Debug/Allnighter.app"
LOG="$DERIVED/last-build.log"
DEV_ROOT="$HOME/Library/Developer/Allnighter"
REQ="$DEV_ROOT/gui-proof-request.json"
MARKER="$DEV_ROOT/gui-proof-screen-recording.ok"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "gui_proof_grant: xcodegen not found — run 'brew install xcodegen'" >&2
  exit 1
fi

( cd "$MAC_APP" && xcodegen generate >/dev/null )

echo "==> building ${SCHEME}…" >&2
mkdir -p "$DERIVED" "$DEV_ROOT"
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
  exit $status
fi

if [ ! -d "$APP" ]; then
  echo "✗ app not found at $APP" >&2
  exit 1
fi

pkill -x Allnighter 2>/dev/null || true
sleep 0.3
rm -f "$DERIVED/gui-proof-last-error.txt"

printf '%s\n' '{"fixture":"proof-grant"}' >"$REQ"

echo "==> opening Allnighter grant UI…" >&2
echo "    App: $APP" >&2
echo "    Stay on the grant window until Screen Recording shows granted, then Quit." >&2

open -n "$APP"

if [ -f "$MARKER" ]; then
  echo "✓ grant marker already present: $MARKER" >&2
else
  echo "    (grant marker will be written to $MARKER when macOS accepts the grant)" >&2
fi
