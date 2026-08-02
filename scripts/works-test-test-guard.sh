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
#   6. An innocent bystander whose cmdline merely MENTIONS the test name
#      (a `grep`, `git log --grep`, an editor, an `alln run` message body)
#      survives a sweep — regression test for the substring-matcher defect
#      that killed the supervising agent's own shell live during
#      verification.
#   7. The sweep's own ancestor chain (the process tree that launched it,
#      even indirectly) survives the sweep even when that ancestor itself
#      matches the runner shape — belt-and-braces on top of #6, proven with
#      a fixture that WOULD be a legitimate kill target but for its ancestry.
#   8. Wedge-detection latency is bounded (asserted, not assumed) — a
#      regression guard for the ~90s design intent silently taking
#      ~120-200s in practice.
#   9. A runner that exits immediately makes the wrapper return promptly,
#      with the runner's OWN exit code and no lock residue — never gated on
#      the wedge detector's sample interval. Regression test for the
#      zombie-liveness defect: `kill -0` on the wrapper's own child stays
#      true after that child has exited but before it is reaped, so the
#      wrapper never noticed a fast exit until the wedge detector
#      eventually fired on the frozen zombie (~120-200s, observed live).
#
# Cleans up after itself even on failure (trap on EXIT).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK_FILE="$ROOT/.alln-test.lock"
# shellcheck source=lib/test-guard-lib.sh disable=SC1091
source "$ROOT/scripts/lib/test-guard-lib.sh"

WORK_DIR=""
FAKE_PIDS=()
FAILURES=0

log()  { echo "works-test: $*"; }
pass() { echo "works-test: PASS — $*"; }
fail() { echo "works-test: FAIL — $*" >&2; FAILURES=$((FAILURES + 1)); }

cleanup() {
  local pid
  # bash 3.2 + set -u: empty `"${FAKE_PIDS[@]}"` is unbound.
  for pid in ${FAKE_PIDS[@]+"${FAKE_PIDS[@]}"}; do
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

# make_fake_xctest_runner WRAPPER_PATH FIFO_PATH BUNDLE_PATH
#
# Writes (and chmods +x) a script at WRAPPER_PATH that, when executed,
# becomes a process whose `ps` argv[0] is literally "xctest" and whose
# argument list includes BUNDLE_PATH — the exact shape
# scripts/lib/test-guard-lib.sh's matches_pattern() now requires for its
# case (a). `exec -a NAME` only survives across an execve of a REAL (non
# shebang) binary — a shebang script re-derives argv[0] from the
# interpreter the moment the kernel handles the `#!` line — so the wrapper
# `exec -a`s /bin/bash itself (a real binary) and hands it the blocking
# body script as an ordinary argument instead of exec'ing that script
# directly.
#
# The runner ignores SIGTERM and blocks by opening FIFO_PATH for reading
# (no writer ever connects), instead of `while true; do sleep 1; done`. A
# sleep-loop forks a brand-new `sleep` child every second, which changes
# the wedge detector's PID-based CPU signature every sample even though
# nothing is actually progressing — that false "progress" was caught live
# while writing the original version of this test (the detector never
# fired and fell through to the 60s backstop). The FIFO block is a single,
# stable, zero-CPU process for the whole fixture lifetime, exactly like a
# genuinely wedged xctest.
make_fake_xctest_runner() {
  local wrapper_path="$1" fifo_path="$2" bundle_path="$3"
  cat > "$wrapper_path" <<FAKE
#!/usr/bin/env bash
# WORKS-TEST FIXTURE ONLY — do not invoke directly.
exec -a xctest /bin/bash "$wrapper_path.body" -XCTest All "$bundle_path"
FAKE
  cat > "$wrapper_path.body" <<FAKE
#!/usr/bin/env bash
trap '' TERM
exec 3<"$fifo_path"
FAKE
  chmod +x "$wrapper_path" "$wrapper_path.body"
}

# make_fake_xctest_runner_with_child WRAPPER_PATH FIFO_PATH BUNDLE_PATH \
#   CHILD_SCRIPT CHILD_PID_FILE
#
# Same shape as make_fake_xctest_runner, but the spoofed xctest process
# forks CHILD_SCRIPT as its OWN child before blocking, and records the
# child's pid in CHILD_PID_FILE. Used to prove that a sweep launched from a
# DESCENDANT of a matching process still spares that ancestor (commit 2) —
# the fixture is deliberately built so it WOULD be a legitimate kill target
# under matches_pattern(), so the only thing that can save it is the
# ancestor-chain exclusion, not matcher precision.
make_fake_xctest_runner_with_child() {
  local wrapper_path="$1" fifo_path="$2" bundle_path="$3" child_script="$4" child_pid_file="$5"
  cat > "$wrapper_path" <<FAKE
#!/usr/bin/env bash
# WORKS-TEST FIXTURE ONLY — do not invoke directly.
exec -a xctest /bin/bash "$wrapper_path.body" -XCTest All "$bundle_path"
FAKE
  cat > "$wrapper_path.body" <<FAKE
#!/usr/bin/env bash
# Ignore TERM (simulates a wedged runner) AND CHLD — without ignoring CHLD,
# the forked child below exiting delivers SIGCHLD to this process, which
# interrupts the blocking FIFO open (\`exec 3<...\` fails with EINTR /
# "Interrupted system call") and this script falls through to EOF and exits
# on its own, instead of staying blocked like a genuinely wedged runner.
trap '' TERM CHLD
"$child_script" &
echo \$! > "$child_pid_file"
until exec 3<"$fifo_path" 2>/dev/null; do :; done
FAKE
  chmod +x "$wrapper_path" "$wrapper_path.body" "$child_script"
}

# --- Scenario A: swift-test.sh wedge detection + SIGKILL escalation ------
log "scenario A: swift-test.sh vs a SIGTERM-ignoring wedged runner"

SCENARIO_A_FIFO="$WORK_DIR/scenarioA.fifo"
mkfifo "$SCENARIO_A_FIFO"
SCENARIO_A_BUNDLE="$WORK_DIR/scenarioA-AllnighterCorePackageTests.xctest"
IGNORE_TERM_RUNNER="$WORK_DIR/scenarioA-xctest-wrapper.sh"
make_fake_xctest_runner "$IGNORE_TERM_RUNNER" "$SCENARIO_A_FIFO" "$SCENARIO_A_BUNDLE"

wrapper_out="$WORK_DIR/wrapper.out"
scenario_a_start="$(date +%s)"
ALLNIGHTER_SWIFT_TEST_CMD_OVERRIDE="$IGNORE_TERM_RUNNER" \
ALLNIGHTER_SWIFT_TEST_SAMPLE_INTERVAL_SECONDS=1 \
ALLNIGHTER_SWIFT_TEST_FLAT_SAMPLES=2 \
ALLNIGHTER_SWIFT_TEST_TIMEOUT_SECONDS=60 \
  "$ROOT/scripts/swift-test.sh" >"$wrapper_out" 2>&1
wrapper_status=$?
scenario_a_elapsed=$(( $(date +%s) - scenario_a_start ))

if [[ "$wrapper_status" -eq 0 ]]; then
  fail "swift-test.sh exited 0 against a wedged runner (expected non-zero)"
else
  pass "swift-test.sh exited non-zero ($wrapper_status) against a wedged runner"
fi

# Detection-latency bound: with SAMPLE_INTERVAL=1s and FLAT_SAMPLES=2, a
# genuinely wedged runner should be detected and killed within roughly
# (SAMPLE_INTERVAL * FLAT_SAMPLES) + a few seconds of TERM/KILL escalation
# — a handful of seconds, not the ~120-200s observed live for what was
# supposed to be a ~90s-worst-case (3 x 30s) design. 20s is a generous
# regression guard: comfortably above real worst-case, comfortably below
# what a reverted off-by-one-sample or zombie-spin bug would produce.
SCENARIO_A_LATENCY_BOUND_SECONDS=20
if [[ "$scenario_a_elapsed" -le "$SCENARIO_A_LATENCY_BOUND_SECONDS" ]]; then
  pass "wedged runner detected and killed in ${scenario_a_elapsed}s (bound: ${SCENARIO_A_LATENCY_BOUND_SECONDS}s)"
else
  fail "wedge detection took ${scenario_a_elapsed}s — exceeds the ${SCENARIO_A_LATENCY_BOUND_SECONDS}s regression-guard bound"
fi

if grep -qi "wedged" "$wrapper_out" && grep -qi "kill" "$wrapper_out"; then
  pass "wrapper output names the wedge and the kill"
else
  fail "wrapper output did not clearly report the wedge/kill — see below"
  sed 's/^/works-test:   | /' "$wrapper_out" >&2
fi

sleep 1  # let the process table settle after SIGKILL
survivors="$(LC_ALL=C ps -axo pid=,command= 2>/dev/null | grep -F "$SCENARIO_A_BUNDLE" | grep -v grep || true)"
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

SCENARIO_B_FIFO="$WORK_DIR/scenarioB.fifo"
mkfifo "$SCENARIO_B_FIFO"
SCENARIO_B_BUNDLE="$WORK_DIR/scenarioB-AllnighterCorePackageTests.xctest"
STALE_RUNNER="$WORK_DIR/scenarioB-xctest-wrapper.sh"
make_fake_xctest_runner "$STALE_RUNNER" "$SCENARIO_B_FIFO" "$SCENARIO_B_BUNDLE"

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

# --- Scenario C: an innocent bystander survives a sweep -------------------
log "scenario C: an innocent bystander that merely MENTIONS the test name survives a sweep"

# Two commands joined by `;` so bash cannot tail-call-exec into `sleep`
# (a single simple command in `bash -c 'cmd' args` exec-optimizes into that
# command directly, which would drop the original `bash -c '...'` argv —
# and the token in it — from what `ps` reports; a lone `sleep 20` would
# never even test the bug). With two commands, the parent `bash -c` process
# stays alive with its full original argv, unresolved, while a `sleep`
# child runs underneath it — this is the exact live incident: an agent
# shell running `grep AllnighterCorePackageTests ...` looked, to the OLD
# substring matcher, indistinguishable from a real runner.
bash -c "sleep 20; echo grepping for AllnighterCorePackageTests token" &
bystander_pid=$!
FAKE_PIDS+=("$bystander_pid")
sleep 0.3

if ! kill -0 "$bystander_pid" 2>/dev/null; then
  fail "bystander fixture died before the sweep even ran"
else
  sweep_matching_processes "$$" >/dev/null 2>&1
  if kill -0 "$bystander_pid" 2>/dev/null; then
    pass "innocent bystander (cmdline merely mentions the test name) survived the sweep"
  else
    fail "innocent bystander was KILLED by the sweep — matcher is still substring-based"
  fi
fi
kill -KILL "$bystander_pid" 2>/dev/null || true

# --- Scenario D: the sweep's own ancestor survives it ----------------------
log "scenario D: the caller/ancestor of a sweep survives it, even when that ancestor itself matches the runner shape"

SCENARIO_D_FIFO="$WORK_DIR/scenarioD.fifo"
mkfifo "$SCENARIO_D_FIFO"
SCENARIO_D_BUNDLE="$WORK_DIR/scenarioD-AllnighterCorePackageTests.xctest"
ANCESTOR_WRAPPER="$WORK_DIR/scenarioD-xctest-wrapper.sh"
CHILD_SCRIPT="$WORK_DIR/scenarioD-child-sweep.sh"
CHILD_PID_FILE="$WORK_DIR/scenarioD-child.pid"
SWEEP_OUT="$WORK_DIR/scenarioD-sweep.out"

cat > "$CHILD_SCRIPT" <<FAKE
#!/usr/bin/env bash
# WORKS-TEST FIXTURE ONLY — do not invoke directly.
source "$ROOT/scripts/lib/test-guard-lib.sh"
sweep_matching_processes "\$\$" > "$SWEEP_OUT" 2>&1
FAKE

make_fake_xctest_runner_with_child \
  "$ANCESTOR_WRAPPER" "$SCENARIO_D_FIFO" "$SCENARIO_D_BUNDLE" \
  "$CHILD_SCRIPT" "$CHILD_PID_FILE"

"$ANCESTOR_WRAPPER" &
ancestor_pid=$!
disown
FAKE_PIDS+=("$ancestor_pid")

child_pid=""
attempt=0
while [[ "$attempt" -lt 20 ]]; do
  if [[ -s "$CHILD_PID_FILE" ]]; then
    child_pid="$(cat "$CHILD_PID_FILE" 2>/dev/null)"
    [[ -n "$child_pid" ]] && break
  fi
  sleep 0.2
  attempt=$((attempt + 1))
done

if [[ -z "$child_pid" ]]; then
  fail "scenario D fixture never recorded its child pid — cannot prove ancestor safety"
else
  FAKE_PIDS+=("$child_pid")
  # Wait for the child's sweep to finish (it exits right after).
  attempt=0
  while kill -0 "$child_pid" 2>/dev/null && [[ "$attempt" -lt 20 ]]; do
    sleep 0.2
    attempt=$((attempt + 1))
  done

  if kill -0 "$ancestor_pid" 2>/dev/null; then
    pass "the sweep's own ancestor (a process that itself matches the runner shape) survived the sweep its child indirectly launched"
  else
    fail "the sweep killed its own ancestor — commit 2's ancestor-chain exclusion is missing or broken"
    [[ -f "$SWEEP_OUT" ]] && sed 's/^/works-test:   | /' "$SWEEP_OUT" >&2
  fi
fi

kill -KILL "$ancestor_pid" 2>/dev/null || true
[[ -n "$child_pid" ]] && kill -KILL "$child_pid" 2>/dev/null || true

# --- Scenario E: a runner that exits immediately is not falsely wedged ----
log "scenario E: a runner that exits immediately does not sit until the wedge detector rescues it"

# Regression test for the zombie-liveness defect: the wrapper's wait loop
# used to poll a bare `kill -0` on its own child, which stays true for a
# ZOMBIE (exited, not yet reaped by its parent) — so a runner finishing in
# microseconds was never noticed at the moment it finished; the wrapper
# just sat there (verified live, ~120-200s) until the wedge detector
# eventually fired on the frozen zombie and "rescued" it. A fixed wrapper
# must notice completion directly and exit promptly, using the runner's
# OWN exit code — never gated on SAMPLE_INTERVAL/FLAT_SAMPLES at all.
FAST_EXIT_RUNNER="$WORK_DIR/scenarioE-fast-exit.sh"
cat > "$FAST_EXIT_RUNNER" <<'FAKE'
#!/usr/bin/env bash
exit 7
FAKE
chmod +x "$FAST_EXIT_RUNNER"

scenario_e_out="$WORK_DIR/scenarioE.out"
scenario_e_start="$(date +%s)"
# Deliberately the SLOW default sample interval/timeout (no
# ALLNIGHTER_SWIFT_TEST_SAMPLE_INTERVAL_SECONDS/FLAT_SAMPLES override) —
# the whole point is proving completion does not wait on that machinery.
ALLNIGHTER_SWIFT_TEST_CMD_OVERRIDE="$FAST_EXIT_RUNNER" \
  "$ROOT/scripts/swift-test.sh" >"$scenario_e_out" 2>&1
scenario_e_status=$?
scenario_e_elapsed=$(( $(date +%s) - scenario_e_start ))

# Generous but meaningful: comfortably above real overhead (well under a
# second in practice), comfortably below the default 30s SAMPLE_INTERVAL —
# so this can only pass if completion is detected directly, not via the
# wedge detector's first sample.
SCENARIO_E_BOUND_SECONDS=10
if [[ "$scenario_e_elapsed" -le "$SCENARIO_E_BOUND_SECONDS" ]]; then
  pass "immediate-exit runner made the wrapper return in ${scenario_e_elapsed}s (bound: ${SCENARIO_E_BOUND_SECONDS}s)"
else
  fail "immediate-exit runner took ${scenario_e_elapsed}s to be noticed — exceeds the ${SCENARIO_E_BOUND_SECONDS}s bound; see scripts/lib/test-guard-lib.sh pid_running()"
  sed 's/^/works-test:   | /' "$scenario_e_out" >&2
fi

if [[ "$scenario_e_status" -eq 7 ]]; then
  pass "wrapper exited with the runner's own exit code (7)"
else
  fail "wrapper exited $scenario_e_status, expected the runner's own exit code (7)"
  sed 's/^/works-test:   | /' "$scenario_e_out" >&2
fi

if [[ -f "$LOCK_FILE" ]]; then
  fail "lock file still present after an immediate-exit run: $(cat "$LOCK_FILE" 2>/dev/null)"
else
  pass "lock file is gone after an immediate-exit run"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  log "ALL WORKS-TEST ASSERTIONS PASSED"
  exit 0
else
  log "$FAILURES ASSERTION(S) FAILED"
  exit 1
fi
