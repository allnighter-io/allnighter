#!/usr/bin/env bash
# Start/stop the background Mac relay agent for `allios live`.
# Humans never run serve_remote.sh directly — ios_dev.sh calls this.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ALLNIGHTER_STATE_DIR="${ALLNIGHTER_STATE_DIR:-$HOME/Library/Developer/Allnighter}"
SERVE_PID_FILE="$ALLNIGHTER_STATE_DIR/ios-live-serve.pid"
SERVE_LOG="$ALLNIGHTER_STATE_DIR/ios-live-serve.log"

cmd="${1:-ensure}"

serve_pid() {
  if [[ -f "$SERVE_PID_FILE" ]]; then
    cat "$SERVE_PID_FILE"
  fi
}

serve_running() {
  local pid
  pid="$(serve_pid || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

case "$cmd" in
  ensure)
    mkdir -p "$ALLNIGHTER_STATE_DIR"
    if serve_running; then
      echo "✓ Mac relay agent already running (pid $(serve_pid))"
      exit 0
    fi

    echo "==> Starting Mac relay agent in background (~10s)"
    nohup bash "$ROOT/scripts/serve_remote.sh" >>"$SERVE_LOG" 2>&1 &
    echo $! >"$SERVE_PID_FILE"

    for _ in $(seq 1 20); do
      sleep 1
      if ! serve_running; then
        echo "✗ Mac relay agent exited early — see $SERVE_LOG" >&2
        tail -25 "$SERVE_LOG" >&2 || true
        exit 1
      fi
      if rg -q "remote agent: cloud relay enabled" "$SERVE_LOG" 2>/dev/null; then
        echo "✓ Mac relay agent ready (pid $(serve_pid), log: $SERVE_LOG)"
        exit 0
      fi
      if rg -q "remote agent disabled:" "$SERVE_LOG" 2>/dev/null; then
        echo "✗ Mac relay agent could not start — see $SERVE_LOG" >&2
        tail -25 "$SERVE_LOG" >&2 || true
        exit 1
      fi
    done

    echo "✓ Mac relay agent started (pid $(serve_pid)) — still warming up"
    echo "  log: $SERVE_LOG"
    ;;

  stop)
    if serve_running; then
      pid="$(serve_pid)"
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      rm -f "$SERVE_PID_FILE"
      echo "✓ Stopped Mac relay agent (pid $pid)"
    else
      rm -f "$SERVE_PID_FILE"
      echo "Mac relay agent not running"
    fi
    ;;

  status)
    if serve_running; then
      echo "running pid $(serve_pid) log $SERVE_LOG"
    else
      echo "not running"
      exit 1
    fi
    ;;

  *)
    echo "usage: ios_live_mac_agent.sh [ensure|stop|status]" >&2
    exit 1
    ;;
esac
