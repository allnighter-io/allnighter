#!/usr/bin/env bash
# Allnighter — GUI Visual Proof Gate capture harness.
#
# Builds the Mac app, launches it in a deterministic, probe-free FIXTURE state,
# lets it self-capture its own window to a PNG (no Screen-Recording TCC), then
# exits. Prints the PNG path. An agent then LOOKS at that PNG (see the
# layout-watcher) before any GUI work may be called "fixed".
#
# Usage:
#   bash scripts/gui_proof.sh                       # default fixture
#   bash scripts/gui_proof.sh team-open-mixed       # named fixture
#   bash scripts/gui_proof.sh team-open-mixed /tmp/out.png
#
# Fixtures live in Apps/AllnighterMac/Sources/GUIFixture.swift.
set -euo pipefail

FIXTURE="${1:-team-open-mixed}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAC_APP="$ROOT/Apps/AllnighterMac"
# Same TCC-safe out-of-repo build dir as dev.sh (Launch Authority hotfix H4).
DERIVED="${ALLNIGHTER_BUILD_DIR:-$HOME/Library/Developer/Allnighter/Build}"
SCHEME="AllnighterMac"
APP="$DERIVED/Build/Products/Debug/Allnighter.app"
BIN="$APP/Contents/MacOS/Allnighter"
LOG="$DERIVED/last-build.log"

CAPTURE_DIR="$ROOT/docs/qa/gui/_captures"
OUT="${2:-$CAPTURE_DIR/$FIXTURE.png}"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"

# 1. Regenerate + build (incremental, quiet — surface errors only on failure).
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "gui_proof: xcodegen not found — run 'brew install xcodegen'" >&2
  exit 1
fi
( cd "$MAC_APP" && xcodegen generate >/dev/null )

echo "==> building ${SCHEME}…" >&2
mkdir -p "$DERIVED"
set +e
xcodebuild build \
  -project "$MAC_APP/AllnighterMac.xcodeproj" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -quiet >"$LOG" 2>&1
status=$?
set -e
if [ $status -ne 0 ]; then
  echo "✗ build failed:" >&2
  grep -E "error:" "$LOG" | head -40 || true
  echo "  (full log: $LOG)" >&2
  exit $status
fi

# 2. Launch the binary directly so we can pass fixture env. Self-capture writes
#    the PNG and terminates the app on its own.
pkill -x Allnighter 2>/dev/null || true
sleep 0.3
echo "==> launching fixture '$FIXTURE'…" >&2
ALLNIGHTER_GUI_FIXTURE="$FIXTURE" \
ALLNIGHTER_GUI_PROOF_OUT="$OUT" \
  "$BIN" >>"$LOG" 2>&1 &
APP_PID=$!

# 3. Poll for the PNG (self-capture fires ~1.5s after first paint).
deadline=$(( $(date +%s) + 25 ))
while [ ! -s "$OUT" ]; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "✗ timed out waiting for $OUT" >&2
    kill "$APP_PID" 2>/dev/null || true
    pkill -x Allnighter 2>/dev/null || true
    exit 1
  fi
  sleep 0.3
done

# 4. Clean up any lingering instance.
wait "$APP_PID" 2>/dev/null || true
pkill -x Allnighter 2>/dev/null || true

echo "✓ captured $FIXTURE" >&2
# Final line on stdout = the PNG path, for piping into the watcher.
echo "$OUT"
