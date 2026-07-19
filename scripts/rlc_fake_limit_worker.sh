#!/usr/bin/env bash
# RLC fake worker: emit a Claude-shaped session-limit error, then succeed on resume.
# Usage: put this on PATH as `claude` (or AGY) for a park→resume smoke.
set -euo pipefail
STATE_DIR="${TMPDIR:-/tmp}/rlc-fake-worker-state"
mkdir -p "$STATE_DIR"
MARKER="$STATE_DIR/hit-limit"

# Detect resume flags used by Claude / session-aware drivers.
is_resume=0
for arg in "$@"; do
  case "$arg" in
    --resume|--continue|-c) is_resume=1 ;;
  esac
done

if [[ "$is_resume" -eq 1 || -f "$MARKER" ]]; then
  rm -f "$MARKER"
  echo "OK: resumed after vendor wait"
  exit 0
fi

touch "$MARKER"
# Structured Claude rate_limit_error with short retry so wakes are testable.
echo '{"type":"error","error":{"type":"rate_limit_error","message":"Youve hit your session limit","retry_after":5}}' >&2
exit 1
