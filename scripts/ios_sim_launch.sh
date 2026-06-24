#!/usr/bin/env bash
# Install + launch AllnighteriOS on the booted simulator (no build).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/ios_sim_common.sh"

BUNDLE_ID="com.happymooseapps.AllnighteriOS"
DERIVED="${ALLNIGHTER_IOS_BUILD_DIR:-$HOME/Library/Developer/Allnighter/iOS-Build}"
APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/AllnighteriOS.app"
ENV_FILE="${IOS_LAUNCH_ENV_FILE:-}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing $APP_PATH — run: allios build" >&2
  exit 1
fi

DEVICE_NAME="$(ios_simulator_device)"
BOOTED="$(ios_simulator_boot_if_needed "$DEVICE_NAME")"

echo "==> Installing on $BOOTED"
xcrun simctl install "$BOOTED" "$APP_PATH"

if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  echo "==> Launching with ALLNIGHTER_* env"
  while IFS= read -r line; do
    key="${line%%=*}"
    value="${line#*=}"
    value="${value%\"}"
    value="${value#\"}"
    export "SIMCTL_CHILD_${key}=${value}"
  done < <(grep -E '^ALLNIGHTER_' "$ENV_FILE")
else
  echo "==> Launching (DEBUG preview — no ALLNIGHTER_* env)"
  unset SIMCTL_CHILD_ALLNIGHTER_SUPABASE_URL
  unset SIMCTL_CHILD_ALLNIGHTER_SUPABASE_ANON_KEY
  unset SIMCTL_CHILD_ALLNIGHTER_DEVICE_ACCESS_TOKEN
  export SIMCTL_CHILD_ALLNIGHTER_UI_TESTING_PREVIEW=1
fi

xcrun simctl terminate "$BOOTED" "$BUNDLE_ID" 2>/dev/null || true
if [[ -z "${ENV_FILE:-}" || ! -f "${ENV_FILE:-}" ]]; then
  read -r -a LAUNCH_ARGS <<< "${IOS_LAUNCH_ARGS:--ui_testing_preview}"
  xcrun simctl launch "$BOOTED" "$BUNDLE_ID" "${LAUNCH_ARGS[@]}"
else
  xcrun simctl launch "$BOOTED" "$BUNDLE_ID"
fi
