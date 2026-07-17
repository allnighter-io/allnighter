#!/usr/bin/env bash
# PO-S01 live works test: process A `team start`, process B polls `team status`
# every 2s and asserts status never becomes `interrupted` while the heartbeat
# is fresh. Exercises the real detached-runner path.
#
# Usage (from repo root, after building alln):
#   bash scripts/po_s01_async_run_works.sh
#
# Env:
#   ALLN          path to alln binary (default: debug product under Packages/AllnighterCore)
#   SUPPORT_DIR   isolated support root (default: mktemp)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALLN="${ALLN:-$ROOT/Packages/AllnighterCore/.build/debug/alln}"
if [[ ! -x "$ALLN" ]]; then
  ALLN="$ROOT/Packages/AllnighterCore/.build/arm64-apple-macosx/debug/alln"
fi
if [[ ! -x "$ALLN" ]]; then
  echo "FAIL: alln binary not found — build with: swift build --package-path Packages/AllnighterCore --product alln" >&2
  exit 2
fi

SUPPORT_DIR="${SUPPORT_DIR:-$(mktemp -d /tmp/po-s01-works-XXXXXX)}"
export ALLNIGHTER_SUPPORT_DIR="$SUPPORT_DIR"
echo "support: $SUPPORT_DIR"
echo "alln:    $ALLN"

parse_field() {
  local json="$1" field="$2"
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); v=d.get(sys.argv[2]); print("" if v is None else v)' "$json" "$field"
}

parse_worker_count() {
  local json="$1" want="$2"
  python3 -c '
import json,sys
d=json.loads(sys.argv[1])
want=sys.argv[2]
workers=d.get("workers") or []
if want=="running":
    print(sum(1 for w in workers if w.get("status")=="running"))
elif want=="done":
    print(sum(1 for w in workers if w.get("status") in ("completed","failed","timedOut","cancelled")))
else:
    print(0)
' "$json" "$want"
}

START_JSON="$("$ALLN" team start --json --lane code --effort low "PO-S01 works: say ok and stop" 2>/tmp/po-s01-start.err || true)"
if [[ -z "$START_JSON" ]]; then
  echo "FAIL: team start produced no JSON" >&2
  cat /tmp/po-s01-start.err >&2 || true
  exit 1
fi
echo "start: $START_JSON"

RUN_ID="$(parse_field "$START_JSON" runId)"
if [[ -z "$RUN_ID" ]]; then
  echo "FAIL: no runId in start envelope" >&2
  exit 1
fi
echo "runId: $RUN_ID"

SAW_RUNNING=0
SAW_DONE=0
STATUS=""
END_REASON=""
for i in $(seq 1 90); do
  STATUS_JSON="$("$ALLN" team status "$RUN_ID" --json 2>/tmp/po-s01-status.err || true)"
  if [[ -z "$STATUS_JSON" ]]; then
    echo "poll $i: empty status" >&2
    cat /tmp/po-s01-status.err >&2 || true
    sleep 2
    continue
  fi
  STATUS="$(parse_field "$STATUS_JSON" status)"
  END_REASON="$(parse_field "$STATUS_JSON" endReason)"
  RUNNING="$(parse_worker_count "$STATUS_JSON" running)"
  DONE_WORKERS="$(parse_worker_count "$STATUS_JSON" done)"
  echo "poll $i: status=$STATUS running=$RUNNING done_workers=$DONE_WORKERS endReason=${END_REASON:-}"

  if [[ "$STATUS" == "interrupted" ]]; then
    RUN_DIR="$SUPPORT_DIR/Runs/run_${RUN_ID}"
    HB="$RUN_DIR/heartbeat"
    if [[ -f "$HB" ]]; then
      HB_AGE=$(( $(date +%s) - $(stat -f %m "$HB") ))
      echo "FAIL: status became interrupted with heartbeat age ${HB_AGE}s (must never interrupt while fresh)" >&2
    else
      echo "FAIL: status became interrupted (no heartbeat file)" >&2
    fi
    exit 1
  fi

  if [[ "$RUNNING" -ge 1 ]]; then
    SAW_RUNNING=1
  fi
  case "$STATUS" in
    completed|failed|cancelled|timedOut)
      SAW_DONE=1
      break
      ;;
  esac
  sleep 2
done

if [[ "$SAW_DONE" -ne 1 ]]; then
  echo "FAIL: run did not reach a terminal status within timeout (saw_running=$SAW_RUNNING)" >&2
  exit 1
fi

if [[ -z "$END_REASON" ]]; then
  RESULT_JSON="$("$ALLN" team result "$RUN_ID" --json 2>/dev/null || true)"
  if [[ -n "$RESULT_JSON" ]]; then
    END_REASON="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print((d.get("teamRun") or {}).get("endReason") or "")' "$RESULT_JSON")"
  fi
fi
if [[ -z "$END_REASON" ]]; then
  echo "FAIL: terminal run missing endReason in status/result" >&2
  exit 1
fi

echo "PASS: run $RUN_ID finished status=$STATUS endReason=$END_REASON (never interrupted while live; saw_running=$SAW_RUNNING)"
exit 0
