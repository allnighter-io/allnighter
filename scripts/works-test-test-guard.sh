#!/usr/bin/env bash
# Works Test for the test-runner guard (scripts/swift-test.sh +
# scripts/kill-stale-tests.sh + scripts/lib/test-guard-lib.sh).
#
# This is the proof that was missing when the guard shipped and then
# silently failed on first real use: a confirmed real orphan
# (AllnighterCorePackageTests.xctest, PPID=1, 2h17m elapsed, 0.0% CPU) sat
# next to a clean .alln-test.lock, and kill-stale-tests.sh always reported
# "sent TERM to 0 stale runner(s)" because its age probe was locale-broken.
#
# Asserts, without a human, self-contained and fast (seconds, not minutes):
#   1. A runner that IGNORES SIGTERM and sleeps forever is still reaped
#      (SIGKILL escalation works).
#   2. After the wrapper exits, ZERO matching runner processes survive.
#   3. After the wrapper exits, the lock file is gone.
#   4. The wedge detector fires fast and swift-test.sh exits non-zero.
#   5. kill-stale-tests.sh actually kills a stale runner — regression test
#      for defect E, the bug that has been silently broken until now.
#
# Cleans up after itself even on failure (trap on EXIT).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK_FILE="$ROOT/.alln-test.lock"

WORK_DIR=""
FAKE_PIDS=()
FAILURES=0

log()  { echo "works-test: $*"; }
pass() { echo "works-test: PASS — $*"; }
fail() { echo "works-test: FAIL — $*" >&2; FAILURES=$((FAILURES + 1)); }

cleanup() {
  local pid
  for pid in "${FAKE_PIDS[@]:-}"; do
    [[ -n "$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
  done
  # Belt-and-braces: sweep anything under WORK_DIR by cmdline, in case a
  # fixture process escaped FAKE_PIDS tracking (e.g. a failed assertion
  # exited this script early via a code path that forgot to record it).
  if [[ -n "$WORK_DIR" ]]; then
    while read -r pid _; do
      [[ -n "$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
    done < <(LC_ALL=C ps -axo pid=,command= 2>/dev/null | grep -F "$WORK_DIR" | grep -v grep)
    rm -rf "$WORK_DIR"
  fi
  # Never leave a lock behind from this Works Test, even on failure —
  # but only if it's actually stale (holder dead), never someone else's
  # live run.
  if [[ -f "$LOCK_FILE" ]]; then
    local holder
    read -r holder _ < "$LOCK_FILE" 2>/dev/null || holder=""
    if [[ -z "$holder" ]] || ! kill -0 "$holder" 2>/dev/null; then
      rm -f "$LOCK_FILE"
    fi
  fi
}
trap cleanup EXIT

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/alln-worksTest.XXXXXX")"

# The fake runner's path deliberately contains "AllnighterCorePackageTests"
# so scripts/lib/test-guard-lib.sh's matches_pattern() recognizes it exactly
# like a real xctest bundle would — plus a "worksTestFakeRunner" marker so
# it can never be mistaken for real work and is trivially greppable for
# this script's own cleanup sweep.
#
# It blocks by opening a FIFO for reading (no writer ever connects) instead
# of `while true; do sleep 1; done`. A sleep-loop forks a brand-new `sleep`
# child every second, which changes the wedge detector's PID-based CPU
# signature every sample even though nothing is actually progressing — that
# false "progress" was caught live while writing this test (the detector
# never fired and fell through to the 60s backstop). The FIFO block is a
# single, stable, zero-CPU process for the whole fixture lifetime, exactly
# like a genuinely wedged xctest.
FIFO="$WORK_DIR/blocker.fifo"
mkfifo "$FIFO"
IGNORE_TERM_RUNNER="$WORK_DIR/AllnighterCorePackageTests.xctest-worksTestFakeRunner"
cat > "$IGNORE_TERM_RUNNER" <<FAKE
#!/usr/bin/env bash
# WORKS-TEST FIXTURE ONLY — do not invoke directly.
# Simulates a wedged xctest runner that ignores SIGTERM, so the guard's
# SIGKILL escalation path can be proven instead of assumed.
trap '' TERM
exec 3<"$FIFO"
FAKE
chmod +x "$IGNORE_TERM_RUNNER"

# --- Scenario A: swift-test.sh wedge detection + SIGKILL escalation ------
log "scenario A: swift-test.sh vs a SIGTERM-ignoring wedged runner"

wrapper_out="$WORK_DIR/wrapper.out"
ALLNIGHTER_SWIFT_TEST_CMD_OVERRIDE="$IGNORE_TERM_RUNNER" \
ALLNIGHTER_SWIFT_TEST_SAMPLE_INTERVAL_SECONDS=1 \
ALLNIGHTER_SWIFT_TEST_FLAT_SAMPLES=2 \
ALLNIGHTER_SWIFT_TEST_TIMEOUT_SECONDS=60 \
  "$ROOT/scripts/swift-test.sh" >"$wrapper_out" 2>&1
wrapper_status=$?

if [[ "$wrapper_status" -eq 0 ]]; then
  fail "swift-test.sh exited 0 against a wedged runner (expected non-zero)"
else
  pass "swift-test.sh exited non-zero ($wrapper_status) against a wedged runner"
fi

if grep -qi "wedged" "$wrapper_out" && grep -qi "kill" "$wrapper_out"; then
  pass "wrapper output names the wedge and the kill"
else
  fail "wrapper output did not clearly report the wedge/kill — see below"
  sed 's/^/works-test:   | /' "$wrapper_out" >&2
fi

sleep 1  # let the process table settle after SIGKILL
survivors="$(LC_ALL=C ps -axo pid=,command= 2>/dev/null | grep -F "worksTestFakeRunner" | grep -v grep || true)"
if [[ -z "$survivors" ]]; then
  pass "zero matching runner processes survive after the wrapper exits (SIGTERM was ignored; SIGKILL escalation reaped it)"
else
  fail "runner process(es) survived after the wrapper exited: $survivors"
fi

if [[ -f "$LOCK_FILE" ]]; then
  fail "lock file still present after the wrapper exited: $(cat "$LOCK_FILE" 2>/dev/null)"
else
  pass "lock file is gone after the wrapper exited"
fi

# --- Scenario B: kill-stale-tests.sh regression test for defect E --------
log "scenario B: kill-stale-tests.sh vs a real stale runner (defect E regression)"

STALE_RUNNER="$WORK_DIR/AllnighterCorePackageTests.xctest-worksTestStaleRunner"
cp "$IGNORE_TERM_RUNNER" "$STALE_RUNNER"
"$STALE_RUNNER" &
stale_pid=$!
disown
FAKE_PIDS+=("$stale_pid")

sleep 2  # give it real, non-zero age for the etime parse to measure
if ! kill -0 "$stale_pid" 2>/dev/null; then
  fail "fixture process died before kill-stale-tests.sh even ran"
else
  # --max-age-seconds is a test-only override added alongside the defect-E
  # fix. With the OLD locale-broken `lstart` parse, age always silently
  # came back 0 regardless of true elapsed time, so with any positive
  # threshold the process always looked "too young" and was skipped —
  # that is the exact bug this asserts against, not just a smoke check.
  kill_out="$("$ROOT/scripts/kill-stale-tests.sh" --max-age-seconds 1 2>&1)"
  sleep 1
  if kill -0 "$stale_pid" 2>/dev/null; then
    fail "kill-stale-tests.sh did not kill the stale runner (pid=$stale_pid): $kill_out"
  else
    pass "kill-stale-tests.sh killed the stale runner (pid=$stale_pid)"
  fi
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  log "ALL WORKS-TEST ASSERTIONS PASSED"
  exit 0
else
  log "$FAILURES ASSERTION(S) FAILED"
  exit 1
fi
