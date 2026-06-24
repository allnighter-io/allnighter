#!/usr/bin/env bash
# Agent-owned iOS visual proof — same contract as Mac gui_proof PNG capture.
#
# Builds/launches preview AllnighteriOS, writes PNGs under docs/qa/ios/_captures/.
# Agents read the images; never ask the founder to eyeball the simulator.
#
# Usage:
#   scripts/ios_visual_proof.sh           # MVP: home + thread + pending + model-picker
#   scripts/ios_visual_proof.sh home
#   scripts/ios_visual_proof.sh thread
#   scripts/ios_visual_proof.sh model-picker
#   scripts/ios_visual_proof.sh pending
#   scripts/ios_visual_proof.sh pending-review
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCOPE="${1:-mvp}"

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
  thread)
    capture thread
    ;;
  model-picker)
    capture model-picker
    ;;
  pending)
    capture pending
    ;;
  pending-review)
    capture pending-review
    ;;
  mvp|all)
    capture home
    capture thread
    capture pending
    capture model-picker
    ;;
  *)
    echo "usage: ios_visual_proof.sh [home|thread|model-picker|pending|pending-review|mvp]" >&2
    exit 1
    ;;
esac
