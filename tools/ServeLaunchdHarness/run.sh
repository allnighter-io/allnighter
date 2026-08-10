#!/usr/bin/env bash
# Disposable launchd code-identity + restart-contract harness.
# Touches only com.allnighter.serve-launchd-harness.
# Never invokes a vendor CLI. Never touches the product label.
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="${ALLN_SERVE_HARNESS_ROOT:-$HOME/Library/Developer/Allnighter/ServeLaunchdHarness}"
LABEL="com.allnighter.serve-launchd-harness"
USER_ID="$(id -u)"
MODE="${1:-same-session}"
MODULE_CACHE="$HARNESS_ROOT/.module-cache"

TRACKS=("adhoc" "apple-dev" "developer-id")
CASES=("case-a" "case-b")
SIGN_IDENTITIES=(
  "adhoc:-"
  "apple-dev:Apple Development: Michael Reining (7RU34H8XPD)"
  "developer-id:Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)"
)

RESULTS=()
FAILURES=0
PASSES=0
SKIPS=0

usage() {
  cat <<'USAGE'
Usage:
  bash tools/ServeLaunchdHarness/run.sh [same-session]

  same-session  Run the full identity + restart-contract matrix and print pass/fail.
USAGE
}

if [[ "$MODE" != "same-session" ]]; then
  echo "unknown mode: $MODE" >&2; usage >&2; exit 2
fi

# --- setup ----------------------------------------------------------------

mkdir -p "$HARNESS_ROOT/bin" "$HARNESS_ROOT/logs" "$HARNESS_ROOT/cwd" \
  "$HARNESS_ROOT/beats" "$HARNESS_ROOT/.build" "$MODULE_CACHE"

STAMP="$(date +%Y%m%d-%H%M%S)-$$"
LOG_DIR="$HARNESS_ROOT/logs/$STAMP"
mkdir -p "$LOG_DIR"

cleanup() {
  launchctl bootout "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || true
  /bin/rm -f "$HARNESS_ROOT/$LABEL.plist"
}
trap cleanup EXIT

record() {
  local cell="$1" verdict="$2" detail="$3"
  RESULTS+=("$cell|$verdict|$detail")
  case "$verdict" in
    PASS) ((PASSES++)) ;;
    FAIL) ((FAILURES++)) ;;
    SKIP) ((SKIPS++)) ;;
  esac
}

# --- plist builder --------------------------------------------------------

write_plist() {
  local bin_path="$1" heartbeat_path="$2" helper_mode="$3"
  local plist_path="$HARNESS_ROOT/$LABEL.plist"
  local stdout_log="$LOG_DIR/stdout-${helper_mode}.log"
  local stderr_log="$LOG_DIR/stderr-${helper_mode}.log"

  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$bin_path</string>
    <string>$heartbeat_path</string>
    <string>$helper_mode</string>
  </array>
  <key>WorkingDirectory</key><string>$HARNESS_ROOT/cwd</string>
  <key>StandardOutPath</key><string>$stdout_log</string>
  <key>StandardErrorPath</key><string>$stderr_log</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict>
    <key>SuccessfulExit</key><false/>
  </dict>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>ProcessType</key><string>Background</string>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>$HARNESS_ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict></plist>
PLIST
}

# --- bootstrap / bootout helpers ------------------------------------------

bootout() {
  launchctl bootout "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || true
  sleep 0.3
}

bootstrap() {
  launchctl bootstrap "gui/$USER_ID" "$HARNESS_ROOT/$LABEL.plist"
}

# --- heartbeat helpers ----------------------------------------------------

wait_for_beat() {
  local heartbeat_path="$1" timeout="${2:-20}"
  local deadline=$(($(date +%s) + timeout))
  while [[ ! -f "$heartbeat_path" ]]; do
    if [[ $(date +%s) -ge $deadline ]]; then
      return 1
    fi
    sleep 0.3
  done
  return 0
}

read_beat_field() {
  local heartbeat_path="$1" field="$2"
  if [[ -f "$heartbeat_path" ]]; then
    python3 -c "import json,sys; d=json.load(open('$heartbeat_path')); print(d.get('$field',''))" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

get_pid_from_beat() {
  read_beat_field "$1" pid
}

get_cdhash_from_beat() {
  read_beat_field "$1" cdhash
}

get_build_tag_from_beat() {
  read_beat_field "$1" buildTag
}

wait_for_new_pid() {
  local heartbeat_path="$1" old_pid="$2" timeout="${3:-30}"
  local deadline=$(($(date +%s) + timeout))
  while true; do
    local new_pid
    new_pid="$(get_pid_from_beat "$heartbeat_path")"
    if [[ -n "$new_pid" && "$new_pid" != "$old_pid" ]]; then
      echo "$new_pid"
      return 0
    fi
    if [[ $(date +%s) -ge $deadline ]]; then
      echo ""
      return 1
    fi
    sleep 0.3
  done
}

assert_no_new_pid() {
  local heartbeat_path="$1" old_pid="$2" timeout="${3:-30}"
  local deadline=$(($(date +%s) + timeout))
  while true; do
    local cur_pid
    cur_pid="$(get_pid_from_beat "$heartbeat_path")"
    if [[ -n "$cur_pid" && "$cur_pid" != "$old_pid" ]]; then
      return 1
    fi
    if [[ $(date +%s) -ge $deadline ]]; then
      return 0
    fi
    sleep 0.5
  done
}

get_last_exit_status() {
  launchctl print "gui/$USER_ID/$LABEL" 2>/dev/null \
    | grep "last exit code" | awk '{print $NF}' || echo "N/A"
}

collect_launchd_log() {
  log show --last 2m --predicate 'process == "launchd"' 2>/dev/null \
    | grep -iE 'LWCR|lightweight code requirement|Code Signature' || true
}

# --- build track ----------------------------------------------------------

build_track() {
  local track="$1"
  local bin_a="$HARNESS_ROOT/bin/harness-${track}-A"
  local bin_b="$HARNESS_ROOT/bin/harness-${track}-B"
  local src="$SOURCE_DIR/main.swift"
  local src_a="$HARNESS_ROOT/.build/main_${track}_A.swift"
  local src_b="$HARNESS_ROOT/.build/main_${track}_B.swift"

  cp "$src" "$src_a"
  cp "$src" "$src_b"
  echo "" >> "$src_a"
  echo 'let __harnessBuildTag = "A"' >> "$src_a"
  echo "" >> "$src_b"
  echo 'let __harnessBuildTag = "B"' >> "$src_b"

  xcrun swiftc -parse-as-library -module-cache-path "$MODULE_CACHE" "$src_a" -o "$bin_a"
  xcrun swiftc -parse-as-library -module-cache-path "$MODULE_CACHE" "$src_b" -o "$bin_b"

  local sign_identity=""
  for entry in "${SIGN_IDENTITIES[@]}"; do
    local key="${entry%%:*}"
    local val="${entry#*:}"
    if [[ "$key" == "$track" ]]; then
      sign_identity="$val"
      break
    fi
  done

  codesign --force --sign "$sign_identity" "$bin_a" 2>/dev/null
  codesign --force --sign "$sign_identity" "$bin_b" 2>/dev/null

  local cdhash_a cdhash_b
  cdhash_a="$(codesign -dvvv "$bin_a" 2>&1 | grep 'CDHash=' | sed 's/CDHash=//')"
  cdhash_b="$(codesign -dvvv "$bin_b" 2>&1 | grep 'CDHash=' | sed 's/CDHash=//')"

  if [[ -z "$cdhash_a" || -z "$cdhash_b" ]]; then
    echo "FATAL: could not extract cdhash for track $track. codesign may have failed." >&2
    exit 1
  fi

  if [[ "$cdhash_a" == "$cdhash_b" ]]; then
    echo "FATAL: cdhashes identical for track $track — build tags did not produce distinct bytes" >&2
    exit 1
  fi

  echo "$cdhash_a" > "$HARNESS_ROOT/beats/cdhash-${track}-A.txt"
  echo "$cdhash_b" > "$HARNESS_ROOT/beats/cdhash-${track}-B.txt"

  echo "$bin_a|$cdhash_a|$bin_b|$cdhash_b"
}

# --- case helpers ---------------------------------------------------------

deploy_bin() {
  local src="$1" dst="$2"
  local tmp="${dst}.deploy.$$"
  cp "$src" "$tmp" || { echo "deploy_bin: cp $src -> $tmp failed (errno $?)" >&2; return 1; }
  mv -f "$tmp" "$dst" || { echo "deploy_bin: mv $tmp -> $dst failed (errno $?)" >&2; rm -f "$tmp"; return 1; }
}

# --- run case (a): bootout, replace, bootstrap ----------------------------

run_case_a() {
  local track="$1" bin_a="$2" cdhash_a="$3" bin_b="$4" cdhash_b="$5"
  local cell="${track}-case-a"
  local bin_path="$HARNESS_ROOT/bin/harness-${track}-current"
  local heartbeat_path="$HARNESS_ROOT/beats/heartbeat-${track}-case-a.json"
  local log_file="$LOG_DIR/${cell}.log"

  rm -f "$heartbeat_path"
  bootout

  local deploy_err
  if ! deploy_err=$(deploy_bin "$bin_a" "$bin_path" 2>&1); then
    record "$cell" FAIL "deploy A failed: $deploy_err" "$log_file"
    return 1
  fi

  write_plist "$bin_path" "$heartbeat_path" "run"

  bootstrap

  if ! wait_for_beat "$heartbeat_path" 20; then
    record "$cell" FAIL "bootstrap with binary A did not produce heartbeat within 20s" "$log_file"
    return 1
  fi

  local pid_before cdhash_before build_tag_before
  pid_before="$(get_pid_from_beat "$heartbeat_path")"
  cdhash_before="$(get_cdhash_from_beat "$heartbeat_path")"
  build_tag_before="$(get_build_tag_from_beat "$heartbeat_path")"

  if [[ "$build_tag_before" != "A" ]]; then
    record "$cell" FAIL "buildTag before replacement: expected A, got $build_tag_before" "$log_file"
    return 1
  fi

  if [[ "$cdhash_before" != "$cdhash_a" ]]; then
    record "$cell" FAIL "cdhash (path-derived) before replacement: expected $cdhash_a, got $cdhash_before" "$log_file"
    return 1
  fi

  bootout
  rm -f "$heartbeat_path"

  deploy_err=""
  if ! deploy_err=$(deploy_bin "$bin_b" "$bin_path" 2>&1); then
    record "$cell" FAIL "deploy B failed: $deploy_err" "$log_file"
    return 1
  fi

  bootstrap

  if ! wait_for_beat "$heartbeat_path" 20; then
    record "$cell" FAIL "bootstrap after replacement did not produce heartbeat within 20s" "$log_file"
    return 1
  fi

  local pid_after cdhash_after build_tag_after
  pid_after="$(get_pid_from_beat "$heartbeat_path")"
  cdhash_after="$(get_cdhash_from_beat "$heartbeat_path")"
  build_tag_after="$(get_build_tag_from_beat "$heartbeat_path")"

  local last_exit
  last_exit="$(get_last_exit_status)"

  if [[ "$build_tag_after" != "B" ]]; then
    record "$cell" FAIL "buildTag after replacement: expected B, got $build_tag_after — new bytes NOT exec'd" "$log_file"
    return 1
  fi

  if [[ "$cdhash_after" != "$cdhash_b" ]]; then
    record "$cell" FAIL "cdhash (path-derived) after replacement: expected $cdhash_b, got $cdhash_after" "$log_file"
    return 1
  fi

  record "$cell" PASS "A buildTag:A cdhash:$cdhash_a B buildTag:B cdhash:$cdhash_b pid:$pid_before->$pid_after lastExit:$last_exit" "$log_file"
  return 0
}

# --- run case (b): replace underneath, kill TERM --------------------------

run_case_b() {
  local track="$1" bin_a="$2" cdhash_a="$3" bin_b="$4" cdhash_b="$5"
  local cell="${track}-case-b"
  local bin_path="$HARNESS_ROOT/bin/harness-${track}-current"
  local heartbeat_path="$HARNESS_ROOT/beats/heartbeat-${track}-case-b.json"
  local log_file="$LOG_DIR/${cell}.log"

  rm -f "$heartbeat_path"
  bootout

  local deploy_err
  if ! deploy_err=$(deploy_bin "$bin_a" "$bin_path" 2>&1); then
    record "$cell" FAIL "deploy A failed: $deploy_err" "$log_file"
    return 1
  fi

  write_plist "$bin_path" "$heartbeat_path" "run"

  bootstrap

  if ! wait_for_beat "$heartbeat_path" 20; then
    record "$cell" FAIL "bootstrap with binary A did not produce heartbeat within 20s" "$log_file"
    return 1
  fi

  local pid_before cdhash_before build_tag_before
  pid_before="$(get_pid_from_beat "$heartbeat_path")"
  cdhash_before="$(get_cdhash_from_beat "$heartbeat_path")"
  build_tag_before="$(get_build_tag_from_beat "$heartbeat_path")"

  if [[ "$build_tag_before" != "A" ]]; then
    record "$cell" FAIL "buildTag before kill: expected A, got $build_tag_before" "$log_file"
    return 1
  fi

  if [[ "$cdhash_before" != "$cdhash_a" ]]; then
    record "$cell" FAIL "cdhash (path-derived) before kill: expected $cdhash_a, got $cdhash_before" "$log_file"
    return 1
  fi

  deploy_err=""
  if ! deploy_err=$(deploy_bin "$bin_b" "$bin_path" 2>&1); then
    record "$cell" FAIL "deploy B failed: $deploy_err" "$log_file"
    return 1
  fi

  kill -TERM "$pid_before" 2>/dev/null || true

  sleep 2

  local pid_after
  pid_after="$(wait_for_new_pid "$heartbeat_path" "$pid_before" 30)"
  if [[ -z "$pid_after" ]]; then
    local last_exit
    last_exit="$(get_last_exit_status)"
    local lwcr
    lwcr="$(collect_launchd_log)"
    record "$cell" FAIL "no respawn after TERM within 30s — lastExit:$last_exit LWCR:${lwcr:-none}" "$log_file"
    return 1
  fi

  local cdhash_after build_tag_after
  cdhash_after="$(get_cdhash_from_beat "$heartbeat_path")"
  build_tag_after="$(get_build_tag_from_beat "$heartbeat_path")"
  local last_exit
  last_exit="$(get_last_exit_status)"

  if [[ "$build_tag_after" == "B" ]]; then
    record "$cell" PASS "Respawned with NEW bytes (buildTag:B, image-derived). cdhash(path-derived):$cdhash_after pid:$pid_before->$pid_after lastExit:$last_exit" "$log_file"
  elif [[ "$build_tag_after" == "A" ]]; then
    record "$cell" FAIL "Respawned but buildTag still A — launchd re-exec'd OLD image from old inode; new-bytes claim was wrong. cdhash(path-derived):$cdhash_after pid:$pid_before->$pid_after lastExit:$last_exit" "$log_file"
  else
    record "$cell" FAIL "Unknown buildTag after respawn: $build_tag_after cdhash(path-derived):$cdhash_after pid:$pid_before->$pid_after lastExit:$last_exit" "$log_file"
  fi
  return 0
}

# --- restart contract cases (adhoc only) ----------------------------------

run_restart_contracts() {
  local bin_path="$HARNESS_ROOT/bin/harness-adhoc-current"

  # --- exit-zero: should NOT respawn ---
  {
    local cell="restart-exit-zero"
    local hb_path="$HARNESS_ROOT/beats/heartbeat-restart-exit-zero.json"
    rm -f "$hb_path"
    bootout
    write_plist "$bin_path" "$hb_path" "exit-zero"
    bootstrap

    if ! wait_for_beat "$hb_path" 10; then
      record "$cell" FAIL "no initial beat" ""
      return 1
    fi

    local pid1
    pid1="$(get_pid_from_beat "$hb_path")"

    if assert_no_new_pid "$hb_path" "$pid1" 30; then
      record "$cell" PASS "exit(0) did NOT respawn (correct). pid:$pid1" ""
    else
      local pid2
      pid2="$(get_pid_from_beat "$hb_path")"
      record "$cell" FAIL "exit(0) UNEXPECTEDLY respawned. pid:$pid1->$pid2" ""
    fi
  }

  # --- exit-nonzero: SHOULD respawn ---
  {
    local cell="restart-exit-nonzero"
    local hb_path="$HARNESS_ROOT/beats/heartbeat-restart-exit-nonzero.json"
    rm -f "$hb_path"
    bootout
    write_plist "$bin_path" "$hb_path" "exit-nonzero"
    bootstrap

    if ! wait_for_beat "$hb_path" 10; then
      record "$cell" FAIL "no initial beat" ""
      return 1
    fi

    local pid1
    pid1="$(get_pid_from_beat "$hb_path")"

    local pid2
    pid2="$(wait_for_new_pid "$hb_path" "$pid1" 30)"
    if [[ -n "$pid2" ]]; then
      record "$cell" PASS "exit(3) respawned (correct). pid:$pid1->$pid2" ""
    else
      record "$cell" FAIL "exit(3) did NOT respawn. pid:$pid1" ""
    fi
  }

  # --- kill -KILL: SHOULD respawn ---
  {
    local cell="restart-kill-KILL"
    local hb_path="$HARNESS_ROOT/beats/heartbeat-restart-kill-KILL.json"
    rm -f "$hb_path"
    bootout
    write_plist "$bin_path" "$hb_path" "run"
    bootstrap

    if ! wait_for_beat "$hb_path" 10; then
      record "$cell" FAIL "no initial beat" ""
      return 1
    fi

    local pid1
    pid1="$(get_pid_from_beat "$hb_path")"

    kill -KILL "$pid1" 2>/dev/null || true

    local pid2
    pid2="$(wait_for_new_pid "$hb_path" "$pid1" 30)"
    if [[ -n "$pid2" ]]; then
      record "$cell" PASS "kill -KILL respawned (correct). pid:$pid1->$pid2" ""
    else
      record "$cell" FAIL "kill -KILL did NOT respawn. pid:$pid1" ""
    fi
  }
}

# --- baseline primitives (adhoc) ------------------------------------------

run_baselines() {
  local bin_path="$HARNESS_ROOT/bin/harness-adhoc-current"

  # bootstrap succeeds
  {
    local cell="baseline-bootstrap"
    local hb_path="$HARNESS_ROOT/beats/heartbeat-baseline-bootstrap.json"
    rm -f "$hb_path"
    bootout
    write_plist "$bin_path" "$hb_path" "run"
    bootstrap

    if wait_for_beat "$hb_path" 10; then
      record "$cell" PASS "bootstrap succeeded" ""
    else
      record "$cell" FAIL "bootstrap did not produce heartbeat" ""
      return 1
    fi
  }

  # active check reads fresh heartbeat
  {
    local cell="baseline-active-check"
    local hb_path="$HARNESS_ROOT/beats/heartbeat-baseline-bootstrap.json"
    local pid1 pid2
    pid1="$(get_pid_from_beat "$hb_path")"
    sleep 2
    pid2="$(get_pid_from_beat "$hb_path")"
    local count
    count="$(read_beat_field "$hb_path" beatCount)"
    if [[ "$pid1" == "$pid2" && "$count" -gt 1 ]]; then
      record "$cell" PASS "heartbeat alive, beatCount=$count" ""
    else
      record "$cell" FAIL "heartbeat not updating: pid $pid1->$pid2 count=$count" ""
    fi
  }

  # TERM restarts
  {
    local cell="baseline-TERM-restart"
    local hb_path="$HARNESS_ROOT/beats/heartbeat-baseline-bootstrap.json"
    local pid1
    pid1="$(get_pid_from_beat "$hb_path")"
    kill -TERM "$pid1" 2>/dev/null || true
    local pid2
    pid2="$(wait_for_new_pid "$hb_path" "$pid1" 20)"
    if [[ -n "$pid2" ]]; then
      record "$cell" PASS "TERM restarted. pid:$pid1->$pid2" ""
    else
      record "$cell" FAIL "TERM did NOT restart. pid:$pid1" ""
    fi
  }

  # KILL restarts
  {
    local cell="baseline-KILL-restart"
    local hb_path="$HARNESS_ROOT/beats/heartbeat-baseline-bootstrap.json"
    local pid1
    pid1="$(get_pid_from_beat "$hb_path")"
    kill -KILL "$pid1" 2>/dev/null || true
    local pid2
    pid2="$(wait_for_new_pid "$hb_path" "$pid1" 20)"
    if [[ -n "$pid2" ]]; then
      record "$cell" PASS "KILL restarted. pid:$pid1->$pid2" ""
    else
      record "$cell" FAIL "KILL did NOT restart. pid:$pid1" ""
    fi
  }

  # bootout leaves no process and no plist
  {
    local cell="baseline-bootout-clean"
    bootout
    sleep 1
    local still_there
    still_there="$(launchctl print "gui/$USER_ID/$LABEL" 2>/dev/null || true)"
    if [[ -z "$still_there" || "$still_there" == *"could not find"* ]]; then
      record "$cell" PASS "bootout removed job cleanly" ""
    else
      record "$cell" FAIL "job still present after bootout" ""
    fi
  }

  # PATH matches minimal plist PATH
  {
    local cell="baseline-PATH"
    local hb_path="$HARNESS_ROOT/beats/heartbeat-baseline-bootstrap.json"
    local recorded_path
    recorded_path="$(read_beat_field "$hb_path" path)"
    local expected_path="$HARNESS_ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    if [[ "$recorded_path" == "$expected_path" ]]; then
      record "$cell" PASS "PATH matches plist" ""
    else
      record "$cell" FAIL "PATH mismatch: expected='$expected_path' actual='$recorded_path'" ""
    fi
  }

  # CWD is neutral $ROOT/cwd
  {
    local cell="baseline-CWD"
    local hb_path="$HARNESS_ROOT/beats/heartbeat-baseline-bootstrap.json"
    local recorded_cwd
    recorded_cwd="$(read_beat_field "$hb_path" cwd)"
    local expected_cwd="$HARNESS_ROOT/cwd"
    if [[ "$recorded_cwd" == "$expected_cwd" ]]; then
      record "$cell" PASS "CWD matches neutral harness cwd" ""
    else
      record "$cell" FAIL "CWD mismatch: expected='$expected_cwd' actual='$recorded_cwd'" ""
    fi
  }
}

# ==== MAIN ================================================================

echo "=== ServeLaunchdHarness: code-identity + restart-contract matrix ==="
echo "Label: $LABEL"
echo "Root:  $HARNESS_ROOT"
echo "Logs:  $LOG_DIR"
echo ""

# --- build + run each track inline ---------------------------------------

for track in "${TRACKS[@]}"; do
  echo "--- Building track: $track ---"
  build_out="$(build_track "$track")"
  bin_a="${build_out%%|*}"
  rest="${build_out#*|}"
  cdhash_a="${rest%%|*}"
  rest="${rest#*|}"
  bin_b="${rest%%|*}"
  cdhash_b="${rest##*|}"

  echo "  A: $cdhash_a"
  echo "  B: $cdhash_b"
  echo "  cdhashes differ: YES"
  echo ""

  echo "=== Track: $track ==="

  echo "  --- Case A (bootout → replace → bootstrap) ---"
  run_case_a "$track" "$bin_a" "$cdhash_a" "$bin_b" "$cdhash_b" || true

  echo "  --- Case B (replace underneath → kill TERM) ---"
  run_case_b "$track" "$bin_a" "$cdhash_a" "$bin_b" "$cdhash_b" || true
  echo ""
done

# --- restart contract cases -----------------------------------------------

echo "=== Restart contract cases (adhoc) ==="
run_restart_contracts || true
echo ""

# --- baseline primitives --------------------------------------------------

echo "=== Baseline primitives (adhoc) ==="
run_baselines || true
echo ""

# --- final cleanup --------------------------------------------------------

bootout

# --- print results table --------------------------------------------------

echo ""
echo "============================================="
echo "  RESULTS"
echo "============================================="
printf "%-35s %-6s %s\n" "CELL" "VERDICT" "DETAIL"
echo "---------------------------------------------"
for entry in "${RESULTS[@]}"; do
  cell="${entry%%|*}"
  rest="${entry#*|}"
  verdict="${rest%%|*}"
  detail="${rest#*|}"
  printf "%-35s %-6s %s\n" "$cell" "$verdict" "$detail"
done
echo "---------------------------------------------"
echo "PASS: $PASSES  FAIL: $FAILURES  SKIP: $SKIPS"
echo ""

if [[ "$FAILURES" -gt 0 ]]; then
  echo "SOME CHECKS FAILED. Review $LOG_DIR"
  exit 1
else
  echo "All checks passed."
fi
