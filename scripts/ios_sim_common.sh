#!/usr/bin/env bash
# Shared simulator helpers for iOS dev scripts.
set -euo pipefail

ios_simulator_device() {
  if [[ -n "${IOS_SIMULATOR_DEVICE:-}" ]]; then
    echo "$IOS_SIMULATOR_DEVICE"
    return
  fi
  xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
for runtime in sorted(data["devices"], reverse=True):
    for device in data["devices"][runtime]:
        if device.get("isAvailable") and "iPhone" in device.get("name", ""):
            print(device["name"])
            raise SystemExit
print("iPhone 17 Pro")
'
}

ios_simulator_booted_udid() {
  xcrun simctl list devices booted -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
for devices in data["devices"].values():
    for device in devices:
        if device.get("state") == "Booted":
            print(device["udid"])
            raise SystemExit
'
}

ios_simulator_boot_if_needed() {
  local device_name="$1"
  local booted
  booted="$(ios_simulator_booted_udid || true)"
  if [[ -n "$booted" ]]; then
    echo "$booted"
    return
  fi
  echo "==> Booting simulator: $device_name" >&2
  xcrun simctl boot "$device_name" || true
  open -a Simulator
  sleep 2
  ios_simulator_booted_udid
}
