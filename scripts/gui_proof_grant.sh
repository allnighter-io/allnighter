#!/usr/bin/env bash
# Allnighter — one-time Screen Recording grant for the GUI proof harness.
#
# Launches ONLY the grant UI (do not run `allapp` first — one instance only).
# Stay until the grant window shows green, then Quit.
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
  -allowProvisioningUpdates \
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
sleep 0.5
rm -f "$DERIVED/gui-proof-last-error.txt"

printf '%s\n' '{"fixture":"proof-grant"}' >"$REQ"

echo "==> opening Allnighter grant UI (do NOT run allapp first)…" >&2
echo "    App: $APP" >&2
echo "" >&2
echo "    If Allnighter is missing from Settings → Screen Recording:" >&2
echo "      1. In the grant window click **Register with macOS** (system dialog may appear)" >&2
echo "      2. Or Settings → + → ⌘⇧G → paste the path above → Open → toggle ON" >&2
echo "      3. Wait for GREEN check in grant window, then Quit" >&2
echo "" >&2

open "$APP"

if [ -f "$MARKER" ]; then
  echo "✓ grant marker already present: $MARKER" >&2
else
  echo "    (marker appears at $MARKER when preflight passes)" >&2
fi
