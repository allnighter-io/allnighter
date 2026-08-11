#!/usr/bin/env bash
# Works Test for alln serve host continuity (ASR-S06a gate 3, ASR-S06c gate 4 update half,
# ASR-S06d gate 4 rollback half, ASR-S06f gates 2 and 5, ASR-S06g gate 5 idle classification).
#
# Default: inspect-only — reads `alln serve status --json`, reports host state,
# never signals or mutates. Exit non-zero only when the host is not healthy.
#
# Destructive (founder approval):
#   --mutate-product-agent crash-restart — TERM then KILL; assert §4.2 restart contract.
#   --mutate-product-agent update — real vA→vB rebuild via rebuild_cli.sh; assert §8 item 4 update half.
set -uo pipefail

FAILURES=0
MUTATING=false
REPAIR_ATTEMPTED=false

THROTTLE_INTERVAL_SEC=30
HEALTH_BUDGET_SEC=15
RESPAWN_DEADLINE_SEC=90
HEALTH_AFTER_RESPAWN_DEADLINE_SEC=20
# Matches ServeStatusJSON.activeHealthStartupCeiling (ASR-S03f4).
STARTING_CEILING_SEC=10
POLL_INTERVAL_SEC=1

# Diagnostics go to stderr, never stdout. Several helpers below return their
# payload (a pid, a duration, a JSON blob) on stdout and are captured with
# $(...); if log/pass wrote to stdout too, the caller would parse a log line as
# data. That is exactly how the first gate 3 run lost the replacement pid and
# then waited for health on an empty one.
log()  { echo "works-test-serve-continuity: $*" >&2; }
pass() { echo "works-test-serve-continuity: PASS — $*" >&2; }
fail() { echo "works-test-serve-continuity: FAIL — $*" >&2; FAILURES=$((FAILURES + 1)); }

usage() {
  echo "Usage: $(basename "$0")" >&2
  echo "       $(basename "$0") --assert identity-and-receipts" >&2
  echo "       $(basename "$0") --assert cold-install" >&2
  echo "       $(basename "$0") --mutate-product-agent crash-restart" >&2
  echo "       $(basename "$0") --mutate-product-agent update" >&2
  echo "       $(basename "$0") --mutate-product-agent update-rollback" >&2
  exit 2
}

require_alln() {
  if ! command -v alln >/dev/null 2>&1; then
    fail "alln not found on PATH"
    return 1
  fi
}

# Emit JSON from `alln serve status --json` on stdout.
# Accepts non-zero CLI exit when JSON is still present (degraded mid-restart).
fetch_serve_status_json() {
  local out_file err_file ec
  out_file="$(mktemp "${TMPDIR:-/tmp}/alln-serve-status-out.XXXXXX")"
  err_file="$(mktemp "${TMPDIR:-/tmp}/alln-serve-status-err.XXXXXX")"
  ec=0
  alln serve status --json >"$out_file" 2>"$err_file" || ec=$?
  if ! python3 -c "import json; json.load(open('$out_file'))" 2>/dev/null; then
    log "alln serve status --json did not return valid JSON (exit=$ec): $(tr '\n' ' ' <"$err_file")"
    rm -f "$out_file" "$err_file"
    return 1
  fi
  cat "$out_file"
  rm -f "$out_file" "$err_file"
}

# python3 helper: read field from JSON string argument. Prints value or exits 3 for null.
json_field() {
  local field="$1"
  local json="$2"
  python3 - "$field" "$json" <<'PY'
import json, sys
field = sys.argv[1]
try:
    data = json.loads(sys.argv[2])
except json.JSONDecodeError as exc:
    print(f"json decode error: {exc}", file=sys.stderr)
    sys.exit(2)

def walk(obj, parts):
    cur = obj
    for part in parts:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(part)
    return cur

value = walk(data, field.split("."))
if value is None:
    sys.exit(3)
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (int, float)):
    print(value)
else:
    print(value)
PY
}

read_status_fields() {
  local json="$1"
  STATUS_JSON="$json"
  STATUS_STATE="$(json_field state "$json" 2>/dev/null || true)"
  STATUS_DAEMON_PID="$(json_field daemon.pid "$json" 2>/dev/null || true)"
  STATUS_DAEMON_ID="$(json_field daemon.daemonId "$json" 2>/dev/null || true)"
  STATUS_STARTED_AT="$(json_field daemon.startedAt "$json" 2>/dev/null || true)"
  STATUS_HEALTH_AT="$(json_field daemon.activeHealthRespondedAt "$json" 2>/dev/null || true)"
  STATUS_SUPERVISOR_LOADED="$(json_field supervisor.loaded "$json" 2>/dev/null || true)"
  STATUS_SUPERVISOR_PID="$(json_field supervisor.pid "$json" 2>/dev/null || true)"
  STATUS_SUPERVISOR_LABEL="$(json_field supervisor.label "$json" 2>/dev/null || true)"
  STATUS_BINARY_PATH="$(json_field binary.path "$json" 2>/dev/null || true)"
}

host_is_healthy() {
  local json="$1"
  read_status_fields "$json"
  [[ "$STATUS_STATE" == "healthy" ]] \
    && [[ -n "$STATUS_DAEMON_PID" ]] \
    && [[ -n "$STATUS_HEALTH_AT" ]] \
    && [[ "$STATUS_SUPERVISOR_LOADED" == "true" ]]
}

host_is_starting() {
  local json="$1"
  read_status_fields "$json"
  [[ "$STATUS_STATE" == "starting" ]]
}

# ASR-S03f4: `starting` is a bounded transient, not unhealthy. Wait out the
# ceiling before declaring the host failed (cleanup after repair / respawn).
wait_for_host_healthy() {
  local label="$1"
  local budget_sec="${2:-$((STARTING_CEILING_SEC + HEALTH_BUDGET_SEC))}"
  local deadline=$((SECONDS + budget_sec))
  local json

  while [[ $SECONDS -lt $deadline ]]; do
    if ! json="$(fetch_serve_status_json)"; then
      sleep "$POLL_INTERVAL_SEC"
      continue
    fi
    if host_is_healthy "$json"; then
      return 0
    fi
    if host_is_starting "$json"; then
      sleep "$POLL_INTERVAL_SEC"
      continue
    fi
    return 1
  done

  if json="$(fetch_serve_status_json)" && host_is_healthy "$json"; then
    return 0
  fi
  if [[ -n "${json:-}" ]] && host_is_starting "$json"; then
    fail "$label: still starting after ${budget_sec}s ceiling"
  fi
  return 1
}

count_daemon_processes() {
  local binary_path="$1"
  python3 - "$binary_path" <<'PY'
import subprocess, sys
path = sys.argv[1]
serve_cmd = f"{path} serve"
try:
    out = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True)
except subprocess.CalledProcessError:
    print(0)
    raise SystemExit(0)
count = 0
for line in out.splitlines():
    parts = line.strip().split(None, 1)
    if len(parts) < 2:
        continue
    cmd = parts[1]
    if cmd == serve_cmd:
        count += 1
print(count)
PY
}

count_loaded_agents() {
  local label="$1"
  if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    echo 1
  else
    echo 0
  fi
}

count_dock_allnighter_processes() {
  local count
  count="$(pgrep -lf 'Allnighter.app/Contents/MacOS/Allnighter' 2>/dev/null | wc -l | tr -d ' ')"
  echo "${count:-0}"
}

assert_singularity() {
  local label="$1"
  local json="$2"
  read_status_fields "$json"

  if [[ -z "$STATUS_BINARY_PATH" ]]; then
    fail "$label: missing binary.path in status JSON"
    return 1
  fi
  if [[ -z "$STATUS_SUPERVISOR_LABEL" ]]; then
    fail "$label: missing supervisor.label in status JSON"
    return 1
  fi

  local daemon_count agent_count dock_count
  daemon_count="$(count_daemon_processes "$STATUS_BINARY_PATH")"
  agent_count="$(count_loaded_agents "$STATUS_SUPERVISOR_LABEL")"
  dock_count="$(count_dock_allnighter_processes)"

  if [[ "$daemon_count" -ne 1 ]]; then
    fail "$label: expected exactly one daemon process for $STATUS_BINARY_PATH, saw $daemon_count"
  else
    pass "$label: exactly one daemon process ($STATUS_BINARY_PATH)"
  fi

  if [[ "$agent_count" -ne 1 ]]; then
    fail "$label: expected exactly one loaded LaunchAgent ($STATUS_SUPERVISOR_LABEL), saw $agent_count"
  else
    pass "$label: exactly one loaded LaunchAgent ($STATUS_SUPERVISOR_LABEL)"
  fi

  if [[ -z "$STATUS_DAEMON_PID" || -z "$STATUS_SUPERVISOR_PID" ]]; then
    fail "$label: missing daemon or supervisor pid in status JSON"
  elif [[ "$STATUS_DAEMON_PID" != "$STATUS_SUPERVISOR_PID" ]]; then
    fail "$label: daemon pid ($STATUS_DAEMON_PID) != supervisor pid ($STATUS_SUPERVISOR_PID)"
  else
    pass "$label: daemon pid == supervisor pid ($STATUS_DAEMON_PID)"
  fi

  if [[ "$dock_count" -ne 0 ]]; then
    fail "$label: expected zero Dock Allnighter processes, saw $dock_count"
  else
    pass "$label: zero Dock Allnighter processes"
  fi
}

report_host_state() {
  local json="$1"
  read_status_fields "$json"
  log "state=$STATUS_STATE desired supervisor.loaded=$STATUS_SUPERVISOR_LOADED"
  log "daemon pid=$STATUS_DAEMON_PID daemonId=$STATUS_DAEMON_ID startedAt=$STATUS_STARTED_AT"
  log "daemon activeHealthRespondedAt=$STATUS_HEALTH_AT"
  log "supervisor pid=$STATUS_SUPERVISOR_PID label=$STATUS_SUPERVISOR_LABEL"
  log "binary path=$STATUS_BINARY_PATH"
}

inspect_only() {
  local json
  if ! json="$(fetch_serve_status_json)"; then
    fail "could not read serve status"
    return 1
  fi

  report_host_state "$json"

  if host_is_healthy "$json"; then
    pass "host is healthy (inspect-only; no mutation performed)"
    return 0
  fi

  fail "host is not healthy (state=$STATUS_STATE supervisor.loaded=$STATUS_SUPERVISOR_LOADED activeHealth=$STATUS_HEALTH_AT)"
  return 1
}

ensure_healthy_or_fail() {
  local label="$1"
  local json
  if ! json="$(fetch_serve_status_json)"; then
    fail "$label: could not read serve status"
    return 1
  fi
  if ! host_is_healthy "$json"; then
    fail "$label: host must start healthy before crash-restart proof (state=$STATUS_STATE)"
    return 1
  fi
  printf '%s' "$json"
}

attempt_host_repair() {
  if [[ "$REPAIR_ATTEMPTED" == true ]]; then
    return 0
  fi
  REPAIR_ATTEMPTED=true
  log "CLEANUP: host is not healthy on exit — running alln serve repair"
  if ! alln serve repair >/dev/null 2>&1; then
    log "CLEANUP: alln serve repair returned non-zero"
  else
    log "CLEANUP: alln serve repair completed"
  fi
  if wait_for_host_healthy "CLEANUP after repair"; then
    local json
    json="$(fetch_serve_status_json)"
    log "CLEANUP: host is healthy after repair"
    report_host_state "$json"
  else
    log "CLEANUP: host is still not healthy after repair — manual intervention required"
    local json
    if json="$(fetch_serve_status_json)"; then
      report_host_state "$json"
    fi
  fi
}

cleanup() {
  unset ALLNIGHTER_SERVE_TEST_INJECT 2>/dev/null || true
  if [[ -n "${COLD_INSTALL_HOME:-}" ]]; then
    if [[ "$COLD_INSTALL_HOME" == "${COLD_INSTALL_HOME_PREFIX:-__never__}"* && -d "$COLD_INSTALL_HOME" ]]; then
      rm -rf "$COLD_INSTALL_HOME"
      log "cold-install: removed throwaway HOME $COLD_INSTALL_HOME"
    else
      log "cold-install: refusing to remove non-mktemp HOME ${COLD_INSTALL_HOME:-<empty>}"
    fi
  fi
  if [[ "$MUTATING" != true ]]; then
    return 0
  fi
  if wait_for_host_healthy "CLEANUP"; then
    return 0
  fi
  attempt_host_repair
}
trap cleanup EXIT

wait_for_replacement_pid() {
  local old_pid="$1"
  local signal_sent_at="$2"
  local deadline=$((signal_sent_at + RESPAWN_DEADLINE_SEC))
  local json new_pid

  while [[ $SECONDS -lt $deadline ]]; do
    if ! json="$(fetch_serve_status_json)"; then
      sleep "$POLL_INTERVAL_SEC"
      continue
    fi
    read_status_fields "$json"
    if [[ -n "$STATUS_DAEMON_PID" && "$STATUS_DAEMON_PID" != "$old_pid" ]]; then
      new_pid="$STATUS_DAEMON_PID"
      local respawn_sec=$((SECONDS - signal_sent_at))
      log "replacement daemon pid $new_pid appeared ${respawn_sec}s after signal (ThrottleInterval budget=${THROTTLE_INTERVAL_SEC}s)"
      if [[ "$respawn_sec" -le "$THROTTLE_INTERVAL_SEC" ]]; then
        pass "time-to-respawn ${respawn_sec}s is within ThrottleInterval (${THROTTLE_INTERVAL_SEC}s)"
      else
        log "time-to-respawn ${respawn_sec}s exceeded ThrottleInterval (${THROTTLE_INTERVAL_SEC}s) but replacement appeared — not failing on throttle alone"
      fi
      printf '%s\n%s\n' "$respawn_sec" "$json"
      return 0
    fi
    sleep "$POLL_INTERVAL_SEC"
  done

  fail "timed out after ${RESPAWN_DEADLINE_SEC}s waiting for replacement daemon pid (was $old_pid)"
  return 1
}

wait_for_active_health() {
  local expect_pid="$1"
  local respawn_seen_at="$2"
  local deadline=$((respawn_seen_at + HEALTH_AFTER_RESPAWN_DEADLINE_SEC))
  local json

  while [[ $SECONDS -lt $deadline ]]; do
    if ! json="$(fetch_serve_status_json)"; then
      sleep "$POLL_INTERVAL_SEC"
      continue
    fi
    read_status_fields "$json"
    if [[ "$STATUS_DAEMON_PID" == "$expect_pid" ]] \
      && [[ "$STATUS_STATE" == "healthy" ]] \
      && [[ -n "$STATUS_HEALTH_AT" ]]; then
      local health_sec=$((SECONDS - respawn_seen_at))
      log "active health for pid $expect_pid at ${health_sec}s after replacement appeared (budget=${HEALTH_BUDGET_SEC}s)"
      if [[ "$health_sec" -le "$HEALTH_BUDGET_SEC" ]]; then
        pass "time-to-health ${health_sec}s is within ${HEALTH_BUDGET_SEC}s budget"
      else
        fail "time-to-health ${health_sec}s exceeded ${HEALTH_BUDGET_SEC}s budget"
      fi
      printf '%s\n%s\n' "$health_sec" "$json"
      return 0
    fi
    sleep "$POLL_INTERVAL_SEC"
  done

  fail "timed out after ${HEALTH_AFTER_RESPAWN_DEADLINE_SEC}s waiting for active health on pid $expect_pid"
  return 1
}

run_signal_restart_half() {
  local signal_name="$1"
  local json before_pid before_daemon_id before_started_at before_loaded
  local signal_sent_at respawn_seen_at
  local wait_out respawn_sec health_sec new_pid

  log "=== $signal_name half: record before state ==="
  if ! json="$(ensure_healthy_or_fail "$signal_name before-state")"; then
    return 1
  fi
  read_status_fields "$json"
  before_pid="$STATUS_DAEMON_PID"
  before_daemon_id="$STATUS_DAEMON_ID"
  before_started_at="$STATUS_STARTED_AT"
  before_loaded="$STATUS_SUPERVISOR_LOADED"

  log "before: pid=$before_pid daemonId=$before_daemon_id startedAt=$before_started_at supervisor.loaded=$before_loaded"
  assert_singularity "$signal_name before-signal" "$json" || true

  if [[ -z "$before_pid" ]]; then
    fail "$signal_name: no daemon pid to signal"
    return 1
  fi

  log "=== $signal_name half: send $signal_name to pid $before_pid ==="
  signal_sent_at=$SECONDS
  if [[ "$signal_name" == "TERM" ]]; then
    if ! kill -TERM "$before_pid" 2>/dev/null; then
      fail "$signal_name: kill -TERM $before_pid failed"
      return 1
    fi
  elif [[ "$signal_name" == "KILL" ]]; then
    if ! kill -KILL "$before_pid" 2>/dev/null; then
      fail "$signal_name: kill -KILL $before_pid failed"
      return 1
    fi
  else
    fail "internal error: unknown signal $signal_name"
    return 1
  fi

  log "=== $signal_name half: wait for replacement pid ==="
  if ! wait_out="$(wait_for_replacement_pid "$before_pid" "$signal_sent_at")"; then
    return 1
  fi
  respawn_sec="$(printf '%s' "$wait_out" | sed -n '1p')"
  json="$(printf '%s' "$wait_out" | sed -n '2,$p')"
  read_status_fields "$json"
  new_pid="$STATUS_DAEMON_PID"
  respawn_seen_at=$SECONDS

  log "=== $signal_name half: wait for active health on pid $new_pid ==="
  if ! wait_out="$(wait_for_active_health "$new_pid" "$respawn_seen_at")"; then
    return 1
  fi
  health_sec="$(printf '%s' "$wait_out" | sed -n '1p')"
  json="$(printf '%s' "$wait_out" | sed -n '2,$p')"

  log "$signal_name summary: time-to-respawn=${respawn_sec}s time-to-health=${health_sec}s (health budget=${HEALTH_BUDGET_SEC}s throttle=${THROTTLE_INTERVAL_SEC}s)"
  pass "$signal_name produced replacement pid $before_pid -> $new_pid with active health"

  assert_singularity "$signal_name after-restart" "$json" || true
  printf '%s' "$json"
}

mutate_crash_restart() {
  MUTATING=true
  local json term_json kill_json kill_pid

  log "mutating mode: crash-restart (TERM then KILL)"

  if ! term_json="$(run_signal_restart_half "TERM")"; then
    fail "TERM half did not pass"
    return 1
  fi

  read_status_fields "$term_json"
  kill_pid="$STATUS_DAEMON_PID"
  log "=== KILL half: will signal new pid $kill_pid from TERM restart ==="

  if ! kill_json="$(run_signal_restart_half "KILL")"; then
    fail "KILL half did not pass"
    return 1
  fi

  if ! json="$(ensure_healthy_or_fail "final")"; then
    fail "host not healthy after both restart halves"
    return 1
  fi
  pass "host healthy after TERM and KILL restart halves"
  report_host_state "$json"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STAGED_COPY_PATH="$HOME/Library/Application Support/Allnighter/CLI/alln"
PATH_SYMLINK="$HOME/.local/bin/alln"
CANONICAL_INSTALL_DIR="$HOME/.local/share/allnighter/bin"
CANONICAL_BINARY="$CANONICAL_INSTALL_DIR/alln"
ROLLBACK_BINARY="${CANONICAL_BINARY}.rollback"
PLIST_PATH="$HOME/Library/LaunchAgents/com.allnighter.resident-coordinator.plist"
DOCK_APP_PATH="/Applications/Allnighter.app"

# §4.4 two-minute wake bound — ceiling for receipt observation, not a hardcoded guess.
# Must exceed capacityRefresh's cadence (~5 min) plus padding, or the gate's one
# load-bearing assertion is skipped every time and gate 5 becomes a proof that
# cannot fail. 120s was too small: every observed run skipped the check.
RECEIPT_MAX_WINDOW_SEC=480
# Grace after a declared nextWakeAt before calling a receipt stalled. Measured on
# this host: capacityRefresh with nextWakeAt 20:14:49 attempted at 20:15:05 (16s
# late — poll-loop tick plus jitter) and recorded success at 20:15:15 (26s late —
# the vendor CLI spawn itself takes ~10s). 15s failed a healthy scheduler. This
# is tolerance for tick lateness and work duration, NOT a §4.4 wake bound, which
# is 2 minutes and is gate 10's business.
RECEIPT_WAKE_PADDING_SEC=90

REQUIRED_SCHEDULER_IDS=(
  pendingWake
  pmTurnWake
  boostSeed
  vendorBackoff
  notifications
  capacityRefresh
  probeRecordRefresh
)

# Gate 5 vendor-PATH proof: only capacityRefresh must advance (spawns vendor CLIs).
ADVANCE_REQUIRED_SCHEDULER_IDS=(
  capacityRefresh
)

# Print cdhash on stdout only (for $(...) capture). Diagnostics on stderr.
binary_cdhash() {
  local path="$1"
  python3 - "$path" <<'PY'
import subprocess, sys
path = sys.argv[1]
try:
    out = subprocess.check_output(["codesign", "-dvvv", path], stderr=subprocess.STDOUT, text=True)
except subprocess.CalledProcessError as exc:
    print(f"codesign failed for {path}: {exc.output}", file=sys.stderr)
    sys.exit(1)
for line in out.splitlines():
    if line.startswith("CandidateCDHash sha256="):
        print(line.split("=", 1)[1])
        break
else:
    print(f"no CandidateCDHash in codesign output for {path}", file=sys.stderr)
    sys.exit(1)
PY
}

binary_sha256() {
  local path="$1"
  shasum -a 256 "$path" | awk '{print $1}'
}

# Gate 1 intentionally exercises only the serve-opt-out path.  The product
# LaunchAgent label belongs to this user, not to HOME, so registering it from a
# throwaway HOME would replace the founder's real coordinator.
COLD_INSTALL_HOME=""
COLD_INSTALL_HOME_PREFIX="${TMPDIR:-/tmp}/alln-cold-install."

snapshot_real_agent() {
  local label="com.allnighter.resident-coordinator"
  local output
  if output="$(launchctl print "gui/$(id -u)/$label" 2>&1)"; then
    printf 'loaded=1\n'
    printf 'program=%s\n' "$(printf '%s\n' "$output" | sed -n 's/^[[:space:]]*program = //p' | head -n 1)"
    printf 'pid=%s\n' "$(printf '%s\n' "$output" | sed -n 's/^[[:space:]]*pid = //p' | head -n 1)"
  else
    printf 'loaded=0\nprogram=\npid=\n'
  fi
}

snapshot_field() {
  local snapshot="$1" field="$2"
  printf '%s\n' "$snapshot" | sed -n "s/^${field}=//p" | head -n 1
}

assert_cold_install_bench_unchanged() {
  local before="$1" real_binary_sha="$2" temp_home="$3"
  local after before_loaded after_loaded before_program after_program before_pid after_pid after_sha print_output

  after="$(snapshot_real_agent)"
  before_loaded="$(snapshot_field "$before" loaded)"
  after_loaded="$(snapshot_field "$after" loaded)"
  before_program="$(snapshot_field "$before" program)"
  after_program="$(snapshot_field "$after" program)"
  before_pid="$(snapshot_field "$before" pid)"
  after_pid="$(snapshot_field "$after" pid)"
  after_sha="$(binary_sha256 "$CANONICAL_BINARY")"

  [[ "$after_loaded" == "$before_loaded" ]] || fail "cold-install bench protection: real agent loaded state changed ($before_loaded -> $after_loaded)"
  [[ "$after_program" == "$before_program" ]] || fail "cold-install bench protection: real agent program changed ($before_program -> $after_program)"
  [[ "$after_pid" == "$before_pid" ]] || fail "cold-install bench protection: real daemon pid changed ($before_pid -> $after_pid)"
  [[ "$after_sha" == "$real_binary_sha" ]] || fail "cold-install bench protection: real canonical binary sha256 changed ($real_binary_sha -> $after_sha)"

  if print_output="$(launchctl print "gui/$(id -u)/com.allnighter.resident-coordinator" 2>&1)" \
    && printf '%s' "$print_output" | grep -F -- "$temp_home" >/dev/null; then
    fail "cold-install bench protection: temp HOME appears in real LaunchAgent: $temp_home"
  else
    pass "cold-install bench protection: real LaunchAgent print contains no temp HOME"
  fi
}

assert_cold_install() {
  # This snapshot is deliberately first: nothing below may create the temp HOME
  # or invoke install-cli before the real per-user LaunchAgent is recorded.
  local real_agent_before real_binary_sha source_binary install_output install_ec
  local temp_canonical temp_symlink temp_desired temp_plist_dir desired_state
  real_agent_before="$(snapshot_real_agent)"
  real_binary_sha="$(binary_sha256 "$CANONICAL_BINARY")"
  source_binary="$(command -v alln)"

  log "cold-install bench protection before: $(printf '%s' "$real_agent_before" | tr '\n' ' ') canonicalSha256=$real_binary_sha"
  COLD_INSTALL_HOME="$(mktemp -d "${COLD_INSTALL_HOME_PREFIX}XXXXXX")" || {
    fail "cold-install: mktemp -d failed"
    return 1
  }
  temp_canonical="$COLD_INSTALL_HOME/.local/share/allnighter/bin/alln"
  temp_symlink="$COLD_INSTALL_HOME/.local/bin/alln"
  temp_desired="$COLD_INSTALL_HOME/Library/Application Support/Allnighter/serve-desired-state.json"
  temp_plist_dir="$COLD_INSTALL_HOME/Library/LaunchAgents"

  install_output="$(HOME="$COLD_INSTALL_HOME" "$source_binary" install-cli --no-serve 2>&1)"
  install_ec=$?
  log "cold-install: used documented --no-serve opt-out (not ALLN_NO_SERVE=1); install output follows verbatim:"
  printf '%s\n' "$install_output" >&2
  if [[ "$install_ec" -ne 0 ]]; then
    fail "cold-install: install-cli --no-serve failed (exit $install_ec)"
    assert_cold_install_bench_unchanged "$real_agent_before" "$real_binary_sha" "$COLD_INSTALL_HOME"
    return 1
  fi

  [[ -x "$temp_canonical" ]] || fail "cold-install: canonical binary missing or not executable at $temp_canonical"
  if cmp -s "$source_binary" "$temp_canonical"; then
    pass "cold-install: canonical binary is byte-identical to source binary"
  else
    fail "cold-install: canonical binary differs from source binary"
  fi
  if [[ "$(python3 - "$temp_symlink" "$temp_canonical" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]) == os.path.realpath(sys.argv[2]))
PY
)" == "True" ]]; then
    pass "cold-install: PATH symlink resolves to temp canonical binary"
  else
    fail "cold-install: PATH symlink does not resolve to $temp_canonical"
  fi
  [[ -f "$temp_desired" ]] || fail "cold-install: desired-state file missing at $temp_desired"
  desired_state="$(cat "$temp_desired" 2>/dev/null || true)"
  if printf '%s' "$desired_state" | grep -Eq '"enabled"[[:space:]]*:[[:space:]]*false|"state"[[:space:]]*:[[:space:]]*"disabled"'; then
    pass "cold-install: desired-state records disabled opt-out"
  else
    fail "cold-install: desired-state does not record disabled opt-out: $desired_state"
  fi
  if [[ ! -e "$temp_plist_dir/com.allnighter.resident-coordinator.plist" ]]; then
    pass "cold-install: no LaunchAgent plist was written in throwaway HOME"
  else
    fail "cold-install: LaunchAgent plist was written in throwaway HOME"
  fi
  if printf '%s' "$install_output" | grep -Eqi 'background scheduler.*not installed|not installed.*background scheduler' \
    && printf '%s' "$install_output" | grep -Eqi 'alln serve enable'; then
    pass "cold-install: opt-out disclosure says scheduler was not installed and how to enable it"
  else
    fail "cold-install: missing required opt-out scheduler disclosure"
  fi

  assert_cold_install_bench_unchanged "$real_agent_before" "$real_binary_sha" "$COLD_INSTALL_HOME"
}

assert_no_staged_copy() {
  local label="$1"
  if [[ -e "$STAGED_COPY_PATH" ]]; then
    fail "$label: staged copy must not exist at $STAGED_COPY_PATH (§2.1)"
  else
    pass "$label: no staged copy at $STAGED_COPY_PATH"
  fi
}

assert_no_orphan_serve() {
  local label="$1"
  local binary_path="$2"
  local supervisor_pid="$3"
  local orphans

  orphans="$(python3 - "$binary_path" "$supervisor_pid" <<'PY'
import subprocess, sys
path = sys.argv[1]
supervisor = int(sys.argv[2])
serve_cmd = f"{path} serve"
try:
    out = subprocess.check_output(["ps", "-axo", "pid=,ppid=,command="], text=True)
except subprocess.CalledProcessError:
    sys.exit(0)
found = []
for line in out.splitlines():
    parts = line.strip().split(None, 2)
    if len(parts) < 3:
        continue
    pid, ppid, cmd = int(parts[0]), int(parts[1]), parts[2]
    if cmd == serve_cmd and pid != supervisor:
        found.append(f"pid={pid} ppid={ppid}")
print("\n".join(found))
PY
)"

  if [[ -n "$orphans" ]]; then
    fail "$label: orphan alln serve process(es) (supervisor pid=$supervisor_pid): $orphans"
  else
    pass "$label: no orphan alln serve processes"
  fi
}

assert_path_symlink_canonical() {
  local label="$1"
  local canonical="$2"
  local resolved canonical_real

  if [[ ! -e "$PATH_SYMLINK" ]]; then
    fail "$label: PATH entry missing at $PATH_SYMLINK"
    return 1
  fi

  resolved="$(python3 - "$PATH_SYMLINK" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
)"
  canonical_real="$(python3 - "$canonical" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
)"

  if [[ "$resolved" != "$canonical_real" ]]; then
    fail "$label: PATH symlink resolves to $resolved, expected canonical $canonical_real"
  else
    pass "$label: PATH symlink resolves to canonical binary ($canonical_real)"
  fi
}

mutate_update() {
  MUTATING=true
  local json before_pid before_daemon_id before_sha before_cdhash before_head
  local expected_sha after_cdhash matches running_sha rebuild_log rebuild_ec after_head

  log "mutating mode: update (vA -> vB via rebuild_cli.sh)"

  if ! before_head="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"; then
    fail "update: could not resolve git HEAD from repo at $REPO_ROOT"
    return 1
  fi

  log "=== update: record before state ==="
  if ! json="$(ensure_healthy_or_fail "update before-state")"; then
    return 1
  fi
  read_status_fields "$json"
  before_pid="$STATUS_DAEMON_PID"
  before_daemon_id="$STATUS_DAEMON_ID"
  before_sha="$(json_field binary.runningGitSha "$json" 2>/dev/null || true)"

  if ! before_cdhash="$(binary_cdhash "$STATUS_BINARY_PATH")"; then
    fail "update: could not read cdhash for $STATUS_BINARY_PATH"
    return 1
  fi

  log "before: pid=$before_pid daemonId=$before_daemon_id runningGitSha=$before_sha cdhash=$before_cdhash repoHead=$before_head"
  assert_singularity "update before-rebuild" "$json" || true

  expected_sha="$before_head"
  log "expected runningGitSha after rebuild: $expected_sha"

  log "=== update: run rebuild_cli.sh ==="
  rebuild_log="$(mktemp "${TMPDIR:-/tmp}/rebuild-cli-log.XXXXXX")"
  rebuild_ec=0
  bash "$SCRIPT_DIR/rebuild_cli.sh" >"$rebuild_log" 2>&1 || rebuild_ec=$?
  log "rebuild_cli.sh exit status: $rebuild_ec"
  cat "$rebuild_log" >&2
  if [[ "$rebuild_ec" -ne 0 ]]; then
    fail "update: rebuild_cli.sh failed (exit $rebuild_ec)"
    rm -f "$rebuild_log"
    return 1
  fi
  rm -f "$rebuild_log"

  if ! after_head="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"; then
    fail "update: could not resolve git HEAD after rebuild"
    return 1
  fi

  log "=== update: wait for healthy host after rebuild ==="
  if ! wait_for_host_healthy "update after-rebuild"; then
    fail "update: host did not become healthy within bounded ceiling"
    return 1
  fi

  if ! json="$(fetch_serve_status_json)"; then
    fail "update: could not read status after rebuild"
    return 1
  fi

  read_status_fields "$json"
  matches="$(json_field binary.matches "$json" 2>/dev/null || true)"
  running_sha="$(json_field binary.runningGitSha "$json" 2>/dev/null || true)"

  if ! after_cdhash="$(binary_cdhash "$STATUS_BINARY_PATH")"; then
    fail "update: could not read cdhash after rebuild for $STATUS_BINARY_PATH"
    return 1
  fi

  log "after: pid=$STATUS_DAEMON_PID daemonId=$STATUS_DAEMON_ID runningGitSha=$running_sha cdhash=$after_cdhash binary.matches=$matches repoHead=$after_head"

  if [[ "$matches" != "true" ]]; then
    fail "update: binary.matches is not true after rebuild"
  else
    pass "update: binary.matches=true"
  fi

  if [[ "$running_sha" != "$expected_sha" ]]; then
    fail "update: runningGitSha ($running_sha) != expected ($expected_sha)"
  else
    pass "update: runningGitSha matches expected $expected_sha"
  fi

  if [[ "$before_head" == "$after_head" && "$before_sha" == "$after_head" ]]; then
    log "update: same-version reinstall — repo HEAD unchanged at $before_head; cdhash may move from rebuild timestamp alone"
    pass "update: same-version reinstall (not a vA -> vB proof)"
  elif [[ "$before_sha" != "$running_sha" ]]; then
    pass "update: version changed ($before_sha -> $running_sha)"
    if [[ "$after_cdhash" != "$before_cdhash" ]]; then
      pass "update: build identity changed ($before_cdhash -> $after_cdhash)"
    else
      log "update: cdhash unchanged despite version change — unexpected but not failing alone"
    fi
  else
    fail "update: runningGitSha did not change ($before_sha) but repo HEAD moved ($before_head -> $after_head)"
  fi

  assert_singularity "update after-rebuild" "$json" || true
  assert_no_staged_copy "update" || true
  assert_no_orphan_serve "update" "$STATUS_BINARY_PATH" "$STATUS_SUPERVISOR_PID" || true
  assert_path_symlink_canonical "update" "$STATUS_BINARY_PATH" || true

  pass "update host proof passed (gate 4 update half)"
  report_host_state "$json"
}

mutate_update_rollback() {
  MUTATING=true
  local failures_before=$FAILURES
  local json before_pid before_sha before_cdhash before_binary_sha before_plist_sha
  local rebuild_log rebuild_ec running_sha matches rollback_present

  log "mutating mode: update-rollback (injected bootstrap failure via ALLNIGHTER_SERVE_TEST_INJECT)"

  log "=== update-rollback: record before state ==="
  if ! json="$(ensure_healthy_or_fail "update-rollback before-state")"; then
    unset ALLNIGHTER_SERVE_TEST_INJECT 2>/dev/null || true
    return 1
  fi
  read_status_fields "$json"
  before_pid="$STATUS_DAEMON_PID"
  before_sha="$(json_field binary.runningGitSha "$json" 2>/dev/null || true)"

  if [[ ! -f "$CANONICAL_BINARY" ]]; then
    fail "update-rollback: canonical binary missing at $CANONICAL_BINARY"
    unset ALLNIGHTER_SERVE_TEST_INJECT 2>/dev/null || true
    return 1
  fi
  if [[ ! -f "$PLIST_PATH" ]]; then
    fail "update-rollback: plist missing at $PLIST_PATH"
    unset ALLNIGHTER_SERVE_TEST_INJECT 2>/dev/null || true
    return 1
  fi

  before_binary_sha="$(binary_sha256 "$CANONICAL_BINARY")"
  before_plist_sha="$(binary_sha256 "$PLIST_PATH")"

  if ! before_cdhash="$(binary_cdhash "$CANONICAL_BINARY")"; then
    fail "update-rollback: could not read cdhash for $CANONICAL_BINARY"
    unset ALLNIGHTER_SERVE_TEST_INJECT 2>/dev/null || true
    return 1
  fi

  log "before: pid=$before_pid runningGitSha=$before_sha cdhash=$before_cdhash binarySha256=$before_binary_sha plistSha256=$before_plist_sha"
  assert_singularity "update-rollback before-rebuild" "$json" || true

  log "=== update-rollback: run rebuild_cli.sh with bootstrap-failure injection ==="
  export ALLNIGHTER_SERVE_TEST_INJECT=bootstrap-failure
  rebuild_log="$(mktemp "${TMPDIR:-/tmp}/rebuild-cli-rollback-log.XXXXXX")"
  rebuild_ec=0
  bash "$SCRIPT_DIR/rebuild_cli.sh" >"$rebuild_log" 2>&1 || rebuild_ec=$?
  log "rebuild_cli.sh exit status (expected nonzero): $rebuild_ec"
  cat "$rebuild_log" >&2
  rm -f "$rebuild_log"
  unset ALLNIGHTER_SERVE_TEST_INJECT

  if [[ "$rebuild_ec" -eq 0 ]]; then
    fail "update-rollback: rebuild_cli.sh succeeded but bootstrap failure was injected"
    return 1
  else
    pass "update-rollback: install command exited nonzero ($rebuild_ec)"
  fi

  log "=== update-rollback: wait for healthy host on original build ==="
  if ! wait_for_host_healthy "update-rollback after failed install"; then
    fail "update-rollback: host did not return healthy on the original build"
    return 1
  fi

  if ! json="$(fetch_serve_status_json)"; then
    fail "update-rollback: could not read status after failed install"
    return 1
  fi

  read_status_fields "$json"
  running_sha="$(json_field binary.runningGitSha "$json" 2>/dev/null || true)"
  matches="$(json_field binary.matches "$json" 2>/dev/null || true)"

  local after_binary_sha after_plist_sha after_cdhash
  after_binary_sha="$(binary_sha256 "$CANONICAL_BINARY")"
  after_plist_sha="$(binary_sha256 "$PLIST_PATH")"
  if ! after_cdhash="$(binary_cdhash "$CANONICAL_BINARY")"; then
    fail "update-rollback: could not read cdhash after failed install"
    return 1
  fi

  log "after: pid=$STATUS_DAEMON_PID runningGitSha=$running_sha cdhash=$after_cdhash binarySha256=$after_binary_sha plistSha256=$after_plist_sha binary.matches=$matches"

  if [[ "$after_binary_sha" != "$before_binary_sha" ]]; then
    fail "update-rollback: canonical binary changed (before=$before_binary_sha after=$after_binary_sha)"
  else
    pass "update-rollback: canonical binary byte-identical to before state"
  fi

  if [[ "$after_plist_sha" != "$before_plist_sha" ]]; then
    fail "update-rollback: plist changed (before=$before_plist_sha after=$after_plist_sha)"
  else
    pass "update-rollback: plist restored to before bytes"
  fi

  if [[ "$running_sha" != "$before_sha" ]]; then
    fail "update-rollback: runningGitSha ($running_sha) != original ($before_sha)"
  else
    pass "update-rollback: host healthy on original runningGitSha $before_sha"
  fi

  if [[ "$before_cdhash" != "$after_cdhash" ]]; then
    fail "update-rollback: cdhash changed ($before_cdhash -> $after_cdhash)"
  else
    pass "update-rollback: cdhash unchanged on original build ($before_cdhash)"
  fi

  if launchctl print "gui/$(id -u)/$STATUS_SUPERVISOR_LABEL" >/dev/null 2>&1; then
    pass "update-rollback: prior LaunchAgent job is loaded again"
  else
    fail "update-rollback: LaunchAgent job is not loaded after restore"
  fi

  assert_singularity "update-rollback after-restore" "$json" || true
  assert_path_symlink_canonical "update-rollback" "$CANONICAL_BINARY" || true

  if [[ -f "$ROLLBACK_BINARY" ]]; then
    log "update-rollback: rollback bytes remain at $ROLLBACK_BINARY (§4.3 failed-rollback case — not deleted)"
  else
    pass "update-rollback: no $ROLLBACK_BINARY left behind after health confirmed"
  fi

  if [[ "$FAILURES" -eq "$failures_before" ]]; then
    pass "update-rollback host proof passed (gate 4 rollback half; §4.3 step 7)"
  fi
  report_host_state "$json"
}

launchctl_agent_program() {
  local label="$1"
  local listing
  listing="$(launchctl print "gui/$(id -u)/$label" 2>/dev/null)" || true
  python3 - "$listing" <<'PY'
import sys
for line in sys.argv[1].splitlines():
    trimmed = line.strip()
    if trimmed.startswith("program = "):
        print(trimmed.split(" = ", 1)[1])
        break
PY
}

read_plist_daemon_path() {
  python3 - "$PLIST_PATH" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    plist = plistlib.load(f)
print(plist.get("EnvironmentVariables", {}).get("PATH", ""))
PY
}

assert_identity_item2() {
  local label="$1"
  local json="$2"
  local matches expected_sha running_sha binary_path agent_program
  local canonical_real binary_real missing

  read_status_fields "$json"

  if [[ "$STATUS_STATE" != "healthy" ]]; then
    fail "$label: state must be healthy (saw $STATUS_STATE)"
  else
    pass "$label: state=healthy"
  fi

  matches="$(json_field binary.matches "$json" 2>/dev/null || true)"
  expected_sha="$(json_field binary.expectedGitSha "$json" 2>/dev/null || true)"
  running_sha="$(json_field binary.runningGitSha "$json" 2>/dev/null || true)"
  binary_path="$(json_field binary.path "$json" 2>/dev/null || true)"

  if [[ "$matches" != "true" ]]; then
    fail "$label: binary.matches must be true (saw $matches)"
  else
    pass "$label: binary.matches=true"
  fi

  if [[ -z "$expected_sha" || -z "$running_sha" ]]; then
    fail "$label: missing expectedGitSha or runningGitSha"
  elif [[ "$running_sha" != "$expected_sha" ]]; then
    fail "$label: runningGitSha ($running_sha) != expectedGitSha ($expected_sha)"
  else
    pass "$label: runningGitSha == expectedGitSha ($running_sha)"
  fi

  canonical_real="$(python3 - "$CANONICAL_BINARY" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
)"
  binary_real="$(python3 - "$binary_path" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
)"

  if [[ "$binary_real" != "$canonical_real" ]]; then
    fail "$label: binary.path ($binary_path -> $binary_real) != canonical ($CANONICAL_BINARY -> $canonical_real)"
  else
    pass "$label: binary.path matches canonical ($canonical_real)"
  fi

  if [[ -z "$STATUS_SUPERVISOR_LABEL" ]]; then
    fail "$label: missing supervisor.label in status JSON"
    return 1
  fi

  agent_program="$(launchctl_agent_program "$STATUS_SUPERVISOR_LABEL")"
  if [[ -z "$agent_program" ]]; then
    fail "$label: could not read program from launchctl print for $STATUS_SUPERVISOR_LABEL"
  else
    local agent_real
    agent_real="$(python3 - "$agent_program" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
)"
    if [[ "$agent_real" != "$canonical_real" ]]; then
      fail "$label: launchctl program ($agent_program -> $agent_real) != canonical ($canonical_real)"
    else
      pass "$label: launchctl program matches canonical binary ($agent_real)"
    fi
  fi

  if [[ -z "$STATUS_DAEMON_PID" || -z "$STATUS_SUPERVISOR_PID" ]]; then
    fail "$label: missing daemon or supervisor pid"
  elif [[ "$STATUS_DAEMON_PID" != "$STATUS_SUPERVISOR_PID" ]]; then
    fail "$label: daemon pid ($STATUS_DAEMON_PID) != supervisor pid ($STATUS_SUPERVISOR_PID)"
  else
    pass "$label: daemon pid == supervisor pid ($STATUS_DAEMON_PID)"
  fi

  missing="$(python3 - "$json" "${REQUIRED_SCHEDULER_IDS[@]}" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
required = sys.argv[2:]
present = {row.get("id") for row in data.get("schedulers", []) if isinstance(row, dict)}
missing = [sid for sid in required if sid not in present]
print(",".join(missing))
PY
)"
  if [[ -n "$missing" ]]; then
    fail "$label: missing required scheduler id(s): $missing"
  else
    pass "$label: all seven required scheduler ids present"
  fi

  local cloud_relay_state
  cloud_relay_state="$(python3 - "$json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
present = {row.get("id") for row in data.get("schedulers", []) if isinstance(row, dict)}
print("present" if "cloudRelay" in present else "absent")
PY
)"
  if [[ "$cloud_relay_state" == "present" ]]; then
    log "$label: optional scheduler cloudRelay is present"
  else
    log "$label: optional scheduler cloudRelay omitted (not a failure)"
  fi
}

assert_identity_item5_plist_path() {
  local label="$1"
  local plist_path daemon_path

  if [[ ! -f "$PLIST_PATH" ]]; then
    fail "$label: plist missing at $PLIST_PATH"
    return 1
  fi

  daemon_path="$(read_plist_daemon_path)"
  log "$label: plist EnvironmentVariables.PATH=$daemon_path"

  if [[ -z "$daemon_path" ]]; then
    fail "$label: plist EnvironmentVariables.PATH is missing"
    return 1
  fi

  if [[ ":$daemon_path:" != *":$CANONICAL_INSTALL_DIR:"* ]]; then
    fail "$label: plist PATH does not contain canonical install dir ($CANONICAL_INSTALL_DIR)"
  else
    pass "$label: plist PATH contains canonical install dir"
  fi

  if [[ ":$daemon_path:" == *":/opt/homebrew/bin:"* ]]; then
    fail "$label: plist PATH contains login-shell-only path /opt/homebrew/bin"
  else
    pass "$label: plist PATH does not contain /opt/homebrew/bin"
  fi
}

report_dock_app_state() {
  local label="$1"
  local dock_count app_exists

  dock_count="$(count_dock_allnighter_processes)"
  if [[ "$dock_count" -ne 0 ]]; then
    fail "$label: expected zero Allnighter.app processes, saw $dock_count"
  else
    pass "$label: zero Allnighter.app processes"
  fi

  if [[ -d "$DOCK_APP_PATH" ]]; then
    log "$label: $DOCK_APP_PATH exists on disk (reported only; not an assertion)"
  else
    log "$label: $DOCK_APP_PATH is absent on disk (reported only; not an assertion)"
  fi
}

observe_receipts_advance() {
  local label="$1"
  local initial_json="$2"
  local plan_json budget_sec final_json classify_json
  local advance_count=${#ADVANCE_REQUIRED_SCHEDULER_IDS[@]}

  plan_json="$(python3 - "$initial_json" "$RECEIPT_MAX_WINDOW_SEC" "$RECEIPT_WAKE_PADDING_SEC" "$advance_count" "${ADVANCE_REQUIRED_SCHEDULER_IDS[@]}" "${REQUIRED_SCHEDULER_IDS[@]}" <<'PY'
import json, sys, time
from datetime import datetime, timezone

data = json.loads(sys.argv[1])
max_window = float(sys.argv[2])
padding = float(sys.argv[3])
advance_count = int(sys.argv[4])
advance_ids = sys.argv[5:5 + advance_count]
required_ids = sys.argv[5 + advance_count:]
now = time.time()

def parse_iso(value):
    if not value:
        return None
    text = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(text).timestamp()
    except ValueError:
        return None

def scheduler_row(schedulers, sid):
    for row in schedulers:
        if isinstance(row, dict) and row.get("id") == sid:
            return row
    return None

def snapshot_row(row):
    if row is None:
        return None
    return {
        "lastAttemptAt": row.get("lastAttemptAt"),
        "lastSuccessAt": row.get("lastSuccessAt"),
        "nextWakeAt": row.get("nextWakeAt"),
    }

schedulers = data.get("schedulers", [])
plan = {
    "watch": [],
    "skip": [],
    "initial_success": {},
    "initial_snapshot": {},
    "required_ids": required_ids,
    "advance_ids": advance_ids,
    "observed_at": now,
    "max_window": max_window,
}

for sid in required_ids:
    row = scheduler_row(schedulers, sid)
    plan["initial_snapshot"][sid] = snapshot_row(row)

for sid in advance_ids:
    row = scheduler_row(schedulers, sid)
    if row is None:
        plan["skip"].append({"id": sid, "reason": "scheduler row missing"})
        continue
    initial = row.get("lastSuccessAt")
    plan["initial_success"][sid] = initial
    next_wake_raw = row.get("nextWakeAt")
    next_wake = parse_iso(next_wake_raw)
    if next_wake is None:
        plan["skip"].append({
            "id": sid,
            "reason": "no nextWakeAt",
            "lastSuccessAt": initial,
        })
        continue
    secs_until = next_wake - now
    if secs_until > max_window:
        plan["skip"].append({
            "id": sid,
            "reason": "nextWakeAt beyond window",
            "nextWakeAt": next_wake_raw,
            "secsUntil": round(secs_until, 1),
            "lastSuccessAt": initial,
        })
        continue
    required_budget = max(secs_until, 0) + padding
    if required_budget > max_window:
        plan["skip"].append({
            "id": sid,
            "reason": "nextWakeAt beyond window",
            "nextWakeAt": next_wake_raw,
            "secsUntil": round(max(secs_until, 0), 1),
            "requiredBudgetSec": round(required_budget, 1),
            "lastSuccessAt": initial,
        })
        continue
    wake_deadline_ts = next_wake + padding
    plan["watch"].append({
        "id": sid,
        "nextWakeAt": next_wake_raw,
        "secsUntil": round(max(secs_until, 0), 1),
        "wakeDeadlineTs": wake_deadline_ts,
        "requiredBudgetSec": round(required_budget, 1),
    })

if plan["watch"]:
    latest_deadline = max(item["wakeDeadlineTs"] for item in plan["watch"])
    budget = min(max_window, max(0.0, latest_deadline - now))
    plan["budgetSec"] = round(budget, 1)
    plan["waitUntilTs"] = latest_deadline
else:
    plan["budgetSec"] = 0
    plan["waitUntilTs"] = None

print(json.dumps(plan))
PY
)"

  if [[ -z "$plan_json" ]]; then
    fail "$label: could not derive receipt observation plan"
    return 1
  fi

  python3 - "$plan_json" "$RECEIPT_MAX_WINDOW_SEC" <<'PY' | while IFS= read -r line; do
import json, sys
plan = json.loads(sys.argv[1])
max_window = sys.argv[2]
for item in plan.get("skip", []):
    sid = item["id"]
    reason = item["reason"]
    if reason == "no nextWakeAt":
        print(f"SKIP {sid}: no nextWakeAt — capacityRefresh advance check skipped (lastSuccessAt={item.get('lastSuccessAt')})")
    elif reason == "nextWakeAt beyond window":
        required = item.get("requiredBudgetSec")
        if required is not None:
            print(
                f"SKIP {sid}: nextWakeAt {item.get('nextWakeAt')} needs {required}s budget "
                f"({item.get('secsUntil')}s until wake + padding), beyond {max_window}s window — capacityRefresh advance check skipped"
            )
        else:
            print(
                f"SKIP {sid}: nextWakeAt {item.get('nextWakeAt')} is {item.get('secsUntil')}s out, "
                f"beyond {max_window}s window — capacityRefresh advance check skipped"
            )
    else:
        print(f"SKIP {sid}: {reason}")
for item in plan.get("watch", []):
    print(f"WATCH {item['id']}: nextWakeAt={item.get('nextWakeAt')} secsUntil={item.get('secsUntil')} (must advance lastSuccessAt)")
if plan.get("budgetSec"):
    print(f"BUDGET {plan['budgetSec']}")
PY
    case "$line" in
      SKIP*)
        log "$label: ${line#SKIP }"
        ;;
      WATCH*)
        log "$label: ${line#WATCH }"
        ;;
      BUDGET*)
        log "$label: receipt wait budget=${line#BUDGET }s (derived from capacityRefresh nextWakeAt, max window=${RECEIPT_MAX_WINDOW_SEC}s)"
        ;;
    esac
  done

  budget_sec="$(python3 - "$plan_json" <<'PY'
import json, sys
plan = json.loads(sys.argv[1])
print(plan.get("budgetSec", 0))
PY
)"

  local watch_count capacity_advanced=false
  watch_count="$(python3 - "$plan_json" <<'PY'
import json, sys
plan = json.loads(sys.argv[1])
print(len(plan.get("watch", [])))
PY
)"

  if [[ "$watch_count" -gt 0 ]]; then
    local wait_until_ts json result_json
    wait_until_ts="$(python3 - "$plan_json" <<'PY'
import json, sys
plan = json.loads(sys.argv[1])
print(plan.get("waitUntilTs") or "")
PY
)"

    while :; do
      local now_ts done
      if ! json="$(fetch_serve_status_json)"; then
        sleep "$POLL_INTERVAL_SEC"
        continue
      fi
      result_json="$(python3 - "$json" "$plan_json" <<'PY'
import json, sys

status = json.loads(sys.argv[1])
plan = json.loads(sys.argv[2])

def scheduler_row(schedulers, sid):
    for row in schedulers:
        if isinstance(row, dict) and row.get("id") == sid:
            return row
    return None

schedulers = status.get("schedulers", [])
advanced = []
pending = []
for item in plan.get("watch", []):
    sid = item["id"]
    before = plan["initial_success"].get(sid)
    row = scheduler_row(schedulers, sid)
    after = row.get("lastSuccessAt") if row else None
    if after and after != before:
        advanced.append(sid)
    else:
        pending.append({
            "id": sid,
            "lastSuccessAt": after,
            "nextWakeAt": row.get("nextWakeAt") if row else None,
        })

print(json.dumps({"advanced": advanced, "pending": pending, "done": len(pending) == 0}))
PY
)"
      done="$(python3 - "$result_json" <<'PY'
import json, sys
print("true" if json.loads(sys.argv[1]).get("done") else "false")
PY
)"
      if [[ "$done" == "true" ]]; then
        capacity_advanced=true
        final_json="$json"
        pass "$label: capacityRefresh lastSuccessAt advanced before nextWakeAt+grace"
        break
      fi

      now_ts="$(python3 - <<'PY'
import time
print(time.time())
PY
)"
      if python3 - "$now_ts" "$wait_until_ts" <<'PY'
import sys
now = float(sys.argv[1])
target = sys.argv[2]
if not target:
    sys.exit(0)
sys.exit(0 if now >= float(target) else 1)
PY
      then
        break
      fi
      sleep "$POLL_INTERVAL_SEC"
    done

    if [[ "$capacity_advanced" != true ]]; then
      if [[ -z "${final_json:-}" ]]; then
        final_json="$json"
      fi
      result_json="$(python3 - "$final_json" "$plan_json" <<'PY'
import json, sys

status = json.loads(sys.argv[1])
plan = json.loads(sys.argv[2])

def scheduler_row(schedulers, sid):
    for row in schedulers:
        if isinstance(row, dict) and row.get("id") == sid:
            return row
    return None

schedulers = status.get("schedulers", [])
done = True
for item in plan.get("watch", []):
    sid = item["id"]
    before = plan["initial_success"].get(sid)
    row = scheduler_row(schedulers, sid)
    after = row.get("lastSuccessAt") if row else None
    if not (after and after != before):
        done = False
        break

print("true" if done else "false")
PY
)"
      if [[ "$result_json" == "true" ]]; then
        capacity_advanced=true
        pass "$label: capacityRefresh lastSuccessAt advanced by nextWakeAt+grace"
      elif ! final_json="$(fetch_serve_status_json)"; then
        fail "$label: timed out after ${budget_sec}s waiting for capacityRefresh advance and could not re-read status"
        return 1
      fi
    fi
  else
    # Not a pass. Gate 5's one load-bearing assertion did not run, so the gate
    # did not prove what it exists to prove. Report it as skipped and fail --
    # a green result here would be a proof that could not fail.
    final_json="$initial_json"
    fail "$label: capacityRefresh advance check did NOT RUN (nextWakeAt beyond ${RECEIPT_MAX_WINDOW_SEC}s window) — gate 5 unproven, not passed"
  fi

  classify_json="$(python3 - "$final_json" "$plan_json" "$capacity_advanced" "$RECEIPT_WAKE_PADDING_SEC" <<'PY'
import json, sys, time
from datetime import datetime, timezone

status = json.loads(sys.argv[1])
plan = json.loads(sys.argv[2])
capacity_advanced = sys.argv[3] == "true"
padding = float(sys.argv[4])
max_window = float(plan.get("max_window", 120))
observed_at = float(plan.get("observed_at", 0))
now_end = time.time()
required_ids = plan.get("required_ids", [])
advance_ids = set(plan.get("advance_ids", []))
initial_snapshot = plan.get("initial_snapshot", {})
skip_by_id = {item["id"]: item for item in plan.get("skip", [])}
watch_by_id = {item["id"]: item for item in plan.get("watch", [])}

def parse_iso(value):
    if not value:
        return None
    text = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(text).timestamp()
    except ValueError:
        return None

def scheduler_row(schedulers, sid):
    for row in schedulers:
        if isinstance(row, dict) and row.get("id") == sid:
            return row
    return None

def snapshot_row(row):
    if row is None:
        return None
    return {
        "lastAttemptAt": row.get("lastAttemptAt"),
        "lastSuccessAt": row.get("lastSuccessAt"),
        "nextWakeAt": row.get("nextWakeAt"),
    }

def classify(sid, initial, final):
    if initial is None and final is None:
        return "stuck", "scheduler row missing"

    init_attempt = initial.get("lastAttemptAt") if initial else None
    init_success = initial.get("lastSuccessAt") if initial else None
    init_wake = initial.get("nextWakeAt") if initial else None
    final_attempt = final.get("lastAttemptAt") if final else None
    final_success = final.get("lastSuccessAt") if final else None
    final_wake = final.get("nextWakeAt") if final else None
    any_attempt = init_attempt is not None or final_attempt is not None

    if final_success and final_success != init_success:
        return "advanced", f"lastSuccessAt advanced ({init_success!r} -> {final_success!r})"

    skip = skip_by_id.get(sid)
    if skip:
        reason = skip.get("reason")
        if reason == "no nextWakeAt":
            return "out-of-window", "no nextWakeAt — outside observation window"
        if reason == "nextWakeAt beyond window":
            required = skip.get("requiredBudgetSec")
            if required is not None:
                return (
                    "out-of-window",
                    f"nextWakeAt {skip.get('nextWakeAt')} needs {required}s budget, beyond {max_window}s window",
                )
            return (
                "out-of-window",
                f"nextWakeAt {skip.get('nextWakeAt')} is {skip.get('secsUntil')}s out, beyond {max_window}s window",
            )
        return "out-of-window", reason

    init_wake_ts = parse_iso(init_wake)
    final_wake_ts = parse_iso(final_wake)
    grace_deadline_ts = init_wake_ts + padding if init_wake_ts is not None else None

    if init_wake_ts is not None and observed_at:
        secs_until = init_wake_ts - observed_at
        if secs_until > max_window:
            return (
                "out-of-window",
                f"nextWakeAt {init_wake} is {round(secs_until, 1)}s out, beyond {max_window}s window",
            )

    if init_wake is None and final_wake is None:
        return "out-of-window", "no nextWakeAt — outside observation window"

    wake_advanced = (
        init_wake_ts is not None
        and final_wake_ts is not None
        and final_wake_ts > init_wake_ts
    )

    if wake_advanced and not any_attempt:
        return "idle", "no attempt recorded and deadline re-armed — idle"

    if grace_deadline_ts is not None and grace_deadline_ts > now_end:
        return (
            "out-of-window",
            f"nextWakeAt {init_wake} grace not yet elapsed during observation window",
        )

    if not wake_advanced and not any_attempt:
        if (now_end - observed_at) <= 1:
            return (
                "out-of-window",
                "no observation window — gate-5 receipt watch did not run",
            )
        return "stuck", "nextWakeAt did not advance and no attempt recorded — stuck"

    if any_attempt:
        return (
            "out-of-window",
            "attempt recorded; next wake not observed within window",
        )

    if (now_end - observed_at) <= 1:
        return (
            "out-of-window",
            "no observation window — gate-5 receipt watch did not run",
        )

    return "out-of-window", "no receipt advance observed within window"

schedulers = status.get("schedulers", [])
results = []
for sid in required_ids:
    initial = initial_snapshot.get(sid)
    row = scheduler_row(schedulers, sid)
    final = snapshot_row(row)
    kind, detail = classify(sid, initial, final)
    fail_kind = False
    watched = sid in watch_by_id
    if sid in advance_ids:
        if capacity_advanced or kind == "advanced":
            fail_kind = False
        elif watched and not capacity_advanced:
            fail_kind = True
            kind = "failed"
            detail = (
                f"capacityRefresh lastSuccessAt did not advance after "
                f"nextWakeAt {watch_by_id[sid].get('nextWakeAt')} + {padding}s grace"
            )
        elif kind == "out-of-window":
            fail_kind = False
        elif kind == "stuck":
            fail_kind = True
    elif sid == "probeRecordRefresh" and kind == "stuck":
        fail_kind = True
    results.append({
        "id": sid,
        "kind": kind,
        "detail": detail,
        "fail": fail_kind,
    })

print(json.dumps(results))
PY
)"

  python3 - "$classify_json" <<'PY' | while IFS= read -r line; do
import json, sys
for item in json.loads(sys.argv[1]):
    print(f"CLASS {item['id']}: {item['kind']} — {item['detail']}")
PY
    [[ -z "$line" ]] && continue
    log "$label: ${line#CLASS }"
  done

  local gate_failures
  gate_failures="$(python3 - "$classify_json" <<'PY'
import json, sys
for item in json.loads(sys.argv[1]):
    if item.get("fail"):
        print(f"{item['id']}: {item['detail']}")
PY
)"

  if [[ -n "$gate_failures" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      fail "$label: $line"
    done <<< "$gate_failures"
    return 1
  fi

  return 0
}

assert_identity_and_receipts() {
  local json

  log "inspect-only mode: identity-and-receipts (gates 2 and 5; no mutation)"

  if ! json="$(fetch_serve_status_json)"; then
    fail "identity-and-receipts: could not read serve status"
    return 1
  fi

  report_host_state "$json"
  assert_identity_item2 "gate-2" "$json" || true
  assert_identity_item5_plist_path "gate-5-path" || true
  report_dock_app_state "gate-5-dock" || true
  observe_receipts_advance "gate-5-receipts" "$json" || true
}

# --- argument parsing ---
SCENARIO=""
ASSERT_SCENARIO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --assert)
      shift
      if [[ $# -lt 1 ]]; then
        usage
      fi
      ASSERT_SCENARIO="$1"
      shift
      ;;
    --mutate-product-agent)
      shift
      if [[ $# -lt 1 ]]; then
        usage
      fi
      SCENARIO="$1"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      log "unknown argument: $1"
      usage
      ;;
  esac
done

if [[ -n "$ASSERT_SCENARIO" && "$ASSERT_SCENARIO" != "identity-and-receipts" && "$ASSERT_SCENARIO" != "cold-install" ]]; then
  log "unknown assert scenario: $ASSERT_SCENARIO"
  usage
fi

if [[ -n "$SCENARIO" && "$SCENARIO" != "crash-restart" && "$SCENARIO" != "update" && "$SCENARIO" != "update-rollback" ]]; then
  log "unknown scenario: $SCENARIO"
  usage
fi

if [[ -n "$ASSERT_SCENARIO" && -n "$SCENARIO" ]]; then
  log "cannot combine --assert and --mutate-product-agent"
  usage
fi

require_alln || true

if [[ -z "$SCENARIO" && -z "$ASSERT_SCENARIO" ]]; then
  inspect_only || true
elif [[ "$ASSERT_SCENARIO" == "identity-and-receipts" ]]; then
  assert_identity_and_receipts || true
elif [[ "$ASSERT_SCENARIO" == "cold-install" ]]; then
  assert_cold_install || true
elif [[ "$SCENARIO" == "crash-restart" ]]; then
  mutate_crash_restart || true
elif [[ "$SCENARIO" == "update" ]]; then
  mutate_update || true
elif [[ "$SCENARIO" == "update-rollback" ]]; then
  mutate_update_rollback || true
fi

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "works-test-serve-continuity: ALL PASS"
  exit 0
fi
echo "works-test-serve-continuity: $FAILURES FAILURE(S)" >&2
exit 1
