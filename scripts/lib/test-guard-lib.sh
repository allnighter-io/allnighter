#!/usr/bin/env bash
# Shared helpers for the test-runner guard (swift-test.sh + kill-stale-tests.sh).
# Sourced, not executed. Every ps invocation forces LC_ALL=C so output format
# never depends on the caller's locale (this is what defect E was: a localized
# `lstart` string silently failed to parse and every age came back as 0).

# matches_pattern CMDLINE — true if CMDLINE looks like an AllnighterCore test
# runner and is NOT `alln serve` / `allnighter serve`. Never touch serve or
# unrelated work.
matches_pattern() {
  local cmdline="$1"
  if [[ "$cmdline" == *"alln serve"* ]] || [[ "$cmdline" == *"allnighter serve"* ]]; then
    return 1
  fi
  if [[ "$cmdline" == *"AllnighterCorePackageTests"* ]]; then
    return 0
  fi
  if [[ "$cmdline" == *"swift-test"* ]] && [[ "$cmdline" == *"AllnighterCore"* ]]; then
    return 0
  fi
  return 1
}

# list_matching_pids [EXCLUDE_PID] — echoes "pid cmdline" lines for every live
# process whose cmdline matches_pattern, one per line. Excludes EXCLUDE_PID
# (typically $$) if given.
list_matching_pids() {
  local exclude_pid="${1:-}"
  local pid cmdline
  # Plain `read` (default IFS) — NOT `${line%% *}` — because macOS `ps`
  # right-pads the numeric pid column with leading spaces for short pids,
  # which makes a manual `%%` split yield an empty pid. `read -r pid rest`
  # strips leading whitespace and captures everything else into cmdline
  # regardless of digit width.
  while read -r pid cmdline; do
    [[ -z "$pid" ]] && continue
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    [[ -n "$exclude_pid" ]] && [[ "$pid" -eq "$exclude_pid" ]] && continue
    matches_pattern "$cmdline" || continue
    kill -0 "$pid" 2>/dev/null || continue
    printf '%s %s\n' "$pid" "$cmdline"
  done < <(LC_ALL=C ps -axo pid=,command= 2>/dev/null || true)
}

# age_seconds PID — echoes elapsed seconds since PID started, parsed from
# `ps -o etime=` ([[dd-]hh:]mm:ss — locale-independent, unlike lstart).
# Returns non-zero (and prints nothing) if the probe fails; callers MUST NOT
# treat that as age=0 (that was defect E).
age_seconds() {
  local pid="$1"
  local etime
  etime="$(LC_ALL=C ps -p "$pid" -o etime= 2>/dev/null | tr -d '[:space:]')"
  [[ -n "$etime" ]] || return 1

  local dpart="0" rest="$etime"
  if [[ "$etime" == *-* ]]; then
    dpart="${etime%%-*}"
    rest="${etime#*-}"
  fi

  local a b c
  IFS=':' read -r a b c <<< "$rest"
  local hours="0" mins secs
  if [[ -n "$c" ]]; then
    hours="$a"; mins="$b"; secs="$c"
  elif [[ -n "$b" ]]; then
    mins="$a"; secs="$b"
  else
    return 1
  fi

  [[ "$dpart" =~ ^[0-9]+$ ]] || return 1
  [[ "$hours" =~ ^[0-9]+$ ]] || return 1
  [[ "$mins" =~ ^[0-9]+$ ]] || return 1
  [[ "$secs" =~ ^[0-9]+$ ]] || return 1

  echo $(( (10#$dpart) * 86400 + (10#$hours) * 3600 + (10#$mins) * 60 + (10#$secs) ))
}

# group_alive PGID — true if any live process reports this process group.
group_alive() {
  local pgid="$1"
  [[ -n "$pgid" ]] || return 1
  LC_ALL=C ps -axo pgid= 2>/dev/null | tr -d ' ' | grep -qx "$pgid"
}

# kill_pid_escalate PID — TERM, wait ~3s, KILL if still alive, verify.
# Echoes "killed" / "gone" / "survived" to stdout for the caller to log.
kill_pid_escalate() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null || { echo "gone"; return 0; }
  kill -TERM "$pid" 2>/dev/null || true
  local waited=0
  while [[ "$waited" -lt 3 ]] && kill -0 "$pid" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || true
    sleep 1
  fi
  if kill -0 "$pid" 2>/dev/null; then
    echo "survived"
    return 1
  fi
  echo "killed"
  return 0
}

# kill_process_group PGID — TERM the whole group, wait ~3s, KILL if any
# member survives. Used by swift-test.sh, which owns its runner's pgid.
kill_process_group() {
  local pgid="$1"
  [[ -n "$pgid" ]] || return 0
  kill -TERM -- "-$pgid" 2>/dev/null || true
  local waited=0
  while [[ "$waited" -lt 3 ]] && group_alive "$pgid"; do
    sleep 1
    waited=$((waited + 1))
  done
  if group_alive "$pgid"; then
    kill -KILL -- "-$pgid" 2>/dev/null || true
    sleep 1
  fi
  group_alive "$pgid" && return 1
  return 0
}

# sweep_matching_processes [EXCLUDE_PID] — unconditional TERM/wait/KILL sweep
# of every live process matching matches_pattern, regardless of age. Used as
# a preflight (defect A) and echoes any pid that survives KILL to stdout.
sweep_matching_processes() {
  local exclude_pid="${1:-}"
  local line pid cmdline
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    pid="${line%% *}"
    cmdline="${line#* }"
    echo "swift-test: preflight sweep — killing pid=$pid: $cmdline" >&2
    if ! kill_pid_escalate "$pid" >/dev/null; then
      echo "$pid"
    fi
  done < <(list_matching_pids "$exclude_pid")
}
