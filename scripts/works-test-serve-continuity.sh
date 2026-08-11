#!/usr/bin/env bash
# Works Test for alln serve host continuity (ASR-S06a gate 3, ASR-S06c gate 4 update half).
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
  echo "       $(basename "$0") --mutate-product-agent crash-restart" >&2
  echo "       $(basename "$0") --mutate-product-agent update" >&2
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
  local json before_pid before_daemon_id before_sha before_cdhash
  local expected_sha after_cdhash matches running_sha rebuild_log rebuild_ec

  log "mutating mode: update (vA -> vB via rebuild_cli.sh)"

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

  log "before: pid=$before_pid daemonId=$before_daemon_id runningGitSha=$before_sha cdhash=$before_cdhash"
  assert_singularity "update before-rebuild" "$json" || true

  if ! expected_sha="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"; then
    fail "update: could not resolve expected git sha from repo at $REPO_ROOT"
    return 1
  fi
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

  log "after: pid=$STATUS_DAEMON_PID daemonId=$STATUS_DAEMON_ID runningGitSha=$running_sha cdhash=$after_cdhash binary.matches=$matches"

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

  if [[ "$after_cdhash" == "$before_cdhash" ]]; then
    fail "update: build identity did not change (cdhash still $before_cdhash) — rebuild was a no-op because the tree was unchanged; an update proof that did not change the binary proves nothing"
  else
    pass "update: build identity changed ($before_cdhash -> $after_cdhash)"
  fi

  assert_singularity "update after-rebuild" "$json" || true
  assert_no_staged_copy "update" || true
  assert_no_orphan_serve "update" "$STATUS_BINARY_PATH" "$STATUS_SUPERVISOR_PID" || true
  assert_path_symlink_canonical "update" "$STATUS_BINARY_PATH" || true

  pass "update host proof passed (gate 4 update half; rollback half pending ASR-S06d)"
  report_host_state "$json"
}

# --- argument parsing ---
SCENARIO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [[ -n "$SCENARIO" && "$SCENARIO" != "crash-restart" && "$SCENARIO" != "update" ]]; then
  log "unknown scenario: $SCENARIO"
  usage
fi

require_alln || true

if [[ -z "$SCENARIO" ]]; then
  inspect_only || true
elif [[ "$SCENARIO" == "crash-restart" ]]; then
  mutate_crash_restart || true
elif [[ "$SCENARIO" == "update" ]]; then
  mutate_update || true
fi

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "works-test-serve-continuity: ALL PASS"
  exit 0
fi
echo "works-test-serve-continuity: $FAILURES FAILURE(S)" >&2
exit 1
