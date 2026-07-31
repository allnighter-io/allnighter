#!/usr/bin/env bash
# Single-runner swift test wrapper: lock, timeout, stale-lock recovery, test token (S03).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK_FILE="$ROOT/.alln-test.lock"
PACKAGE_PATH="$ROOT/Packages/AllnighterCore"

# Default ~15 min for filtered iteration; check.sh sets ALLNIGHTER_SWIFT_TEST_TIMEOUT_SECONDS higher.
TIMEOUT_SECONDS="${ALLNIGHTER_SWIFT_TEST_TIMEOUT_SECONDS:-900}"
TOKEN_SCRIPT="$ROOT/scripts/allnighter_test_token.py"

usage() {
  echo "usage: $0 [--filter TestClass] [swift test args...]" >&2
  exit 2
}

fail_locked() {
  local holder_pid="${1:-unknown}"
  local started_at="${2:-unknown}"
  echo "swift-test: another run is in progress (holder pid=$holder_pid, started=$started_at)." >&2
  echo "swift-test: do not retry or wait-loop; stop and report (Test Infrastructure Rule 6)." >&2
  exit 1
}

recover_stale_lock() {
  [[ -f "$LOCK_FILE" ]] || return 0
  local holder_pid started_at
  read -r holder_pid started_at < "$LOCK_FILE" || holder_pid=""
  if [[ -z "$holder_pid" ]] || ! kill -0 "$holder_pid" 2>/dev/null; then
    rm -f "$LOCK_FILE"
    return 0
  fi
}

acquire_lock() {
  recover_stale_lock
  local started_at
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if ! ( set -o noclobber; echo "$$ $started_at" > "$LOCK_FILE" ) 2>/dev/null; then
    local holder_pid holder_started
    read -r holder_pid holder_started < "$LOCK_FILE" 2>/dev/null || holder_pid="" holder_started=""
    if [[ -n "$holder_pid" ]] && kill -0 "$holder_pid" 2>/dev/null; then
      fail_locked "$holder_pid" "$holder_started"
    fi
    recover_stale_lock
    if ! ( set -o noclobber; echo "$$ $started_at" > "$LOCK_FILE" ) 2>/dev/null; then
      read -r holder_pid holder_started < "$LOCK_FILE" 2>/dev/null || holder_pid="" holder_started=""
      fail_locked "${holder_pid:-unknown}" "${holder_started:-unknown}"
    fi
  fi
}

release_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    local holder_pid
    read -r holder_pid _ < "$LOCK_FILE" 2>/dev/null || holder_pid=""
    if [[ "$holder_pid" == "$$" ]]; then
      rm -f "$LOCK_FILE"
    fi
  fi
}

burn_token() {
  if [[ -n "${ALLNIGHTER_TEST_TOKEN:-}" ]] && [[ -f "$TOKEN_SCRIPT" ]]; then
    python3 "$TOKEN_SCRIPT" burn "$ROOT" "${ALLNIGHTER_TEST_TOKEN}" 2>/dev/null || true
  fi
  unset ALLNIGHTER_TEST_TOKEN
}

cleanup() {
  local status=$?
  if [[ -n "${SWIFT_TEST_CHILD_PID:-}" ]]; then
    kill -TERM "$SWIFT_TEST_CHILD_PID" 2>/dev/null || true
    wait "$SWIFT_TEST_CHILD_PID" 2>/dev/null || true
  fi
  burn_token
  release_lock
  exit "$status"
}

mint_token() {
  if [[ -f "$TOKEN_SCRIPT" ]]; then
    export ALLNIGHTER_TEST_TOKEN
    ALLNIGHTER_TEST_TOKEN="$(python3 "$TOKEN_SCRIPT" mint "$ROOT")"
  fi
}

run_with_timeout() {
  local -a cmd=(swift test --disable-sandbox --package-path "$PACKAGE_PATH" "$@")
  (
    "${cmd[@]}"
  ) &
  SWIFT_TEST_CHILD_PID=$!
  local waited=0
  while kill -0 "$SWIFT_TEST_CHILD_PID" 2>/dev/null; do
    if [[ "$waited" -ge "$TIMEOUT_SECONDS" ]]; then
      echo "swift-test: timeout after ${TIMEOUT_SECONDS}s — killing test run" >&2
      kill -TERM "$SWIFT_TEST_CHILD_PID" 2>/dev/null || true
      sleep 2
      kill -KILL "$SWIFT_TEST_CHILD_PID" 2>/dev/null || true
      wait "$SWIFT_TEST_CHILD_PID" 2>/dev/null || true
      SWIFT_TEST_CHILD_PID=""
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$SWIFT_TEST_CHILD_PID"
  local exit_code=$?
  SWIFT_TEST_CHILD_PID=""
  return "$exit_code"
}

acquire_lock
trap cleanup EXIT INT TERM

mint_token

status=0
run_with_timeout "$@" || status=$?

exit "$status"
