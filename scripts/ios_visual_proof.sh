#!/usr/bin/env bash
# Agent-owned iOS visual proof — same contract as Mac gui_proof PNG capture.
#
# Builds/launches preview AllnighteriOS, writes PNGs under docs/qa/ios/_captures/.
# Agents read the images; never ask the founder to eyeball the simulator.
#
# Usage:
#   scripts/ios_visual_proof.sh           # home + model-picker
#   scripts/ios_visual_proof.sh home      # home only
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCOPE="${1:-all}"

capture() {
  local name="$1"
  local out="$ROOT/docs/qa/ios/_captures/${name}.png"
  bash "$SCRIPT_DIR/ios_screenshot.sh" "$name"
  if [[ ! -s "$out" ]]; then
    echo "✗ visual proof failed — missing capture: $out" >&2
    exit 1
  fi
  echo "✓ visual proof: $out"
}

case "$SCOPE" in
  home)
    capture home
    ;;
  model-picker)
    capture model-picker
    ;;
  all)
    capture home
    capture model-picker
    ;;
  *)
    echo "usage: ios_visual_proof.sh [home|model-picker|all]" >&2
    exit 1
    ;;
esac
