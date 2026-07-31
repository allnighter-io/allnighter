#!/usr/bin/env bash
# Single-runner swift test wrapper: lock, timeout, stale-lock recovery, test token (S03).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=ensure-test-guard-path.sh disable=SC1091
source "$ROOT/scripts/ensure-test-guard-path.sh"
# shellcheck source=lib/test-guard-lib.sh disable=SC1091
source "$ROOT/scripts/lib/test-guard-lib.sh"
LOCK_FILE="$ROOT/.alln-test.lock"
PACKAGE_PATH="$ROOT/Packages/AllnighterCore"

# Default ~15 min for filtered iteration; check.sh sets ALLNIGHTER_SWIFT_TEST_TIMEOUT_SECONDS higher.
TIMEOUT_SECONDS="${ALLNIGHTER_SWIFT_TEST_TIMEOUT_SECONDS:-900}"
TOKEN_SCRIPT="$ROOT/scripts/allnighter_test_token.py"

SWIFT_TEST_CHILD_PID=""
SWIFT_TEST_PGID=""
SWIFT_TEST_TAIL_PID=""

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

# Lock file format: "<wrapper-pid> <started-at-iso8601> <runner-pgid-or-'-'>"
# The pgid field starts as "-" (runner not spawned yet) and is rewritten by
# write_lock_pgid once the runner's process group is known. This is what
# fixes defect B: previously the lock only recorded the WRAPPER's pid, so
# if the wrapper died (timeout, harness reap, SIGKILL) the lock released
# and every record of what it had spawned vanished — exactly how an
# orphan xctest ends up at PPID=1 next to a clean lock file.
recover_stale_lock() {
  [[ -f "$LOCK_FILE" ]] || return 0
  local holder_pid started_at holder_pgid
  read -r holder_pid started_at holder_pgid < "$LOCK_FILE" 2>/dev/null || holder_pid=""
  if [[ -n "$holder_pid" ]] && kill -0 "$holder_pid" 2>/dev/null; then
    # Wrapper is alive — this is a genuine conflict, not a stale lock.
    # Leave it in place; the caller decides whether to fail_locked.
    return 0
  fi
  if [[ -n "${holder_pgid:-}" ]] && [[ "$holder_pgid" != "-" ]] && group_alive "$holder_pgid"; then
    echo "swift-test: wrapper pid=${holder_pid:-unknown} is dead but runner pgid=$holder_pgid is still alive — reaping orphan." >&2
    kill_process_group "$holder_pgid" || echo "swift-test: WARNING — orphan pgid=$holder_pgid survived SIGKILL" >&2
  fi
  rm -f "$LOCK_FILE"
  return 0
}

acquire_lock() {
  recover_stale_lock
  local started_at
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if ! ( set -o noclobber; printf '%s %s -\n' "$$" "$started_at" > "$LOCK_FILE" ) 2>/dev/null; then
    local holder_pid holder_started
    read -r holder_pid holder_started _ < "$LOCK_FILE" 2>/dev/null || holder_pid="" holder_started=""
    if [[ -n "$holder_pid" ]] && kill -0 "$holder_pid" 2>/dev/null; then
      fail_locked "$holder_pid" "$holder_started"
    fi
    recover_stale_lock
    if ! ( set -o noclobber; printf '%s %s -\n' "$$" "$started_at" > "$LOCK_FILE" ) 2>/dev/null; then
      read -r holder_pid holder_started _ < "$LOCK_FILE" 2>/dev/null || holder_pid="" holder_started=""
      fail_locked "${holder_pid:-unknown}" "${holder_started:-unknown}"
    fi
  fi
}

# write_lock_pgid PGID — rewrite the lock line to record the runner's
# process group once it's known (the lock is written before the runner
# starts, so there's a brief window where the pgid field is still "-").
# Only rewrites a lock this wrapper still owns.
write_lock_pgid() {
  local pgid="$1"
  [[ -f "$LOCK_FILE" ]] || return 0
  local holder_pid started_at
  read -r holder_pid started_at _ < "$LOCK_FILE" 2>/dev/null || return 0
  [[ "$holder_pid" == "$$" ]] || return 0
  printf '%s %s %s\n' "$holder_pid" "$started_at" "$pgid" > "$LOCK_FILE"
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

stop_tail() {
  if [[ -n "$SWIFT_TEST_TAIL_PID" ]]; then
    kill "$SWIFT_TEST_TAIL_PID" 2>/dev/null || true
    wait "$SWIFT_TEST_TAIL_PID" 2>/dev/null || true
    SWIFT_TEST_TAIL_PID=""
  fi
}

# reap_runner — kill the ENTIRE process group of the current test run, not
# just the top pid. Used by every exit path (timeout, trap, normal
# completion never calls this — it's already reaped). This is what fixes
# defect C: killing the runner's pgid reaches swift AND its xctest
# grandchild, instead of missing both because $! pointed at `tee`.
reap_runner() {
  stop_tail
  if [[ -n "$SWIFT_TEST_PGID" ]]; then
    kill_process_group "$SWIFT_TEST_PGID" || echo "swift-test: WARNING — runner pgid=$SWIFT_TEST_PGID survived SIGKILL" >&2
  fi
  SWIFT_TEST_CHILD_PID=""
  SWIFT_TEST_PGID=""
}

cleanup() {
  local status=$?
  reap_runner
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
  local log
  log="$(mktemp "${TMPDIR:-/tmp}/alln-swift-test.XXXXXX")"

  # `set -m` (job control) makes the backgrounded job its OWN process group
  # (pgid == its own pid) instead of inheriting this wrapper's group. This
  # is what fixes defect C: the old `(swift test) | tee log &` made `$!`
  # the pid of `tee` (last element of a pipeline), so the timeout path
  # killed `tee` and never touched `swift`/`xctest` — a wedged xctest never
  # even saw SIGPIPE and lived on as an orphan.
  set -m
  ( exec "${cmd[@]}" ) >"$log" 2>&1 &
  SWIFT_TEST_CHILD_PID=$!
  SWIFT_TEST_PGID=$SWIFT_TEST_CHILD_PID
  set +m
  write_lock_pgid "$SWIFT_TEST_PGID"

  # Live output, without putting `tee` in the runner's process group.
  tail -n +1 -f "$log" &
  SWIFT_TEST_TAIL_PID=$!

  local waited=0
  local exit_code=0
  while kill -0 "$SWIFT_TEST_CHILD_PID" 2>/dev/null; do
    if [[ "$waited" -ge "$TIMEOUT_SECONDS" ]]; then
      echo "swift-test: timeout after ${TIMEOUT_SECONDS}s — killing pgid=$SWIFT_TEST_PGID (pid=$SWIFT_TEST_CHILD_PID)" >&2
      reap_runner
      rm -f "$log"
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done

  stop_tail
  wait "$SWIFT_TEST_CHILD_PID" || exit_code=$?
  SWIFT_TEST_CHILD_PID=""
  SWIFT_TEST_PGID=""
  # SwiftPM may exit 0 when XCTest failed but Swift Testing had nothing to run.
  if rg -q 'with [1-9][0-9]* failures?' "$log" 2>/dev/null; then
    exit_code=1
  fi
  rm -f "$log"
  return "$exit_code"
}

acquire_lock
trap cleanup EXIT INT TERM

mint_token

status=0
run_with_timeout "$@" || status=$?

exit "$status"
