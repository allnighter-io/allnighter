#!/usr/bin/env bash
# Allnighter — GUI Visual Proof Gate capture harness.
#
# Builds the Mac app, writes a proof request JSON, launches the **.app bundle**
# via `open` (Launch Services — required for Screen Recording TCC), waits for
# the PNG, then exits. Overlay fixtures (compose-*) need a one-time grant:
#   bash scripts/gui_proof_grant.sh
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
DERIVED="${ALLNIGHTER_BUILD_DIR:-$HOME/Library/Developer/Allnighter/Build}"
DEV_ROOT="$HOME/Library/Developer/Allnighter"
SCHEME="AllnighterMac"
APP="$DERIVED/Build/Products/Debug/Allnighter.app"
LOG="$DERIVED/last-build.log"
REQ="$DEV_ROOT/gui-proof-request.json"
ERR="$DERIVED/gui-proof-last-error.txt"
MARKER="$DEV_ROOT/gui-proof-screen-recording.ok"

CAPTURE_DIR="$ROOT/docs/qa/gui/_captures"
OUT="${2:-$CAPTURE_DIR/$FIXTURE.png}"
mkdir -p "$(dirname "$OUT")" "$DEV_ROOT"
rm -f "$OUT" "$ERR"

needs_overlays() {
  case "$FIXTURE" in compose-*) return 0 ;; esac
  return 1
}

if needs_overlays && [ ! -f "$MARKER" ]; then
  echo "⚠ overlay fixture '$FIXTURE' needs Screen Recording. Run once:" >&2
  echo "    bash scripts/gui_proof_grant.sh" >&2
fi

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
  -quiet >"$LOG" 2>&1
status=$?
set -e
if [ $status -ne 0 ]; then
  echo "✗ build failed:" >&2
  grep -E "error:" "$LOG" | head -40 || true
  echo "  (full log: $LOG)" >&2
  exit $status
fi

if [ ! -d "$APP" ]; then
  echo "✗ app not found at $APP" >&2
  exit 1
fi

pkill -x Allnighter 2>/dev/null || true
sleep 0.3

# Launch through the .app bundle (not the raw Mach-O) so macOS TCC binds Screen
# Recording to Allnighter. Env vars are NOT passed through `open`; the request
# file is the durable contract between this script and GUIFixture.bootstrap().
python3 - "$REQ" "$FIXTURE" "$OUT" <<'PY'
import json, sys
path, fixture, out = sys.argv[1:4]
with open(path, "w", encoding="utf-8") as f:
    json.dump({"fixture": fixture, "output": out}, f)
    f.write("\n")
PY

echo "==> launching fixture '$FIXTURE' via $APP …" >&2
open -n -g "$APP"

deadline=$(( $(date +%s) + 30 ))
while [ ! -s "$OUT" ] && [ ! -s "$ERR" ]; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "✗ timed out waiting for capture" >&2
    pkill -x Allnighter 2>/dev/null || true
    exit 1
  fi
  sleep 0.3
done

wait 2>/dev/null || true
pkill -x Allnighter 2>/dev/null || true

if [ -s "$ERR" ]; then
  echo "✗ GUI proof capture failed:" >&2
  cat "$ERR" >&2
  if needs_overlays; then
    echo "" >&2
    echo "  Run: bash scripts/gui_proof_grant.sh" >&2
  fi
  exit 1
fi

echo "✓ captured $FIXTURE" >&2
echo "$OUT"
