#!/usr/bin/env bash
# Cursor hook: keep a repo-local poll watcher alive and drain pending handoffs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PID_FILE="$ROOT/.wmd/commit-queue-watcher.pid"
LOG_FILE="$ROOT/.wmd/commit-queue-watcher.log"
WATCHER="$ROOT/scripts/commit_queue_watcher.py"

mkdir -p "$ROOT/.wmd"

watcher_running() {
  if [[ ! -f "$PID_FILE" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

ensure_watcher() {
  if watcher_running; then
    return 0
  fi
  if [[ ! -f "$WATCHER" ]]; then
    return 0
  fi
  nohup python3 "$WATCHER" >>"$LOG_FILE" 2>&1 &
  echo "$!" >"$PID_FILE"
}

ensure_watcher
python3 "$ROOT/scripts/commit_handoff_queue.py" process-next >/dev/null 2>&1 || true
exit 0
