#!/usr/bin/env bash
# PO-S01 v2 live works test: process A `team start`, process B polls `team status`
# every 2s and asserts status never becomes `interrupted` while the owner is
# identity-alive. Exercises the real detached-runner + truthful-accept path.
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
  # Scratch-path builds (PO proof discipline).
  ALLN="/tmp/po-slice-scratch/debug/alln"
fi
if [[ ! -x "$ALLN" ]]; then
  ALLN="/tmp/po-slice-scratch/arm64-apple-macosx/debug/alln"
fi
if [[ ! -x "$ALLN" ]]; then
  echo "FAIL: alln binary not found — build with: swift build --package-path Packages/AllnighterCore --product alln --scratch-path /tmp/po-slice-scratch" >&2
  exit 2
fi

SUPPORT_DIR="${SUPPORT_DIR:-$(mktemp -d /tmp/po-s01-works-XXXXXX)}"
export ALLNIGHTER_SUPPORT_DIR="$SUPPORT_DIR"
# Works script is a top-level probe — never inherit a host agent's team-depth.
unset ALLNIGHTER_TEAM_DEPTH
echo "support: $SUPPORT_DIR"
echo "alln:    $ALLN"

# Empty support roots have no probe cache — models stay "unknown" and every team
# refuses. Prefer seeding from the real Allnighter support root when present;
# otherwise run a full doctor probe (slower).
REAL_SUPPORT="${HOME}/Library/Application Support/Allnighter"
if [[ -d "$REAL_SUPPORT/ProjectReadiness" || -d "$REAL_SUPPORT/Config" ]]; then
  for leaf in Config Catalogs ProjectReadiness; do
    if [[ -d "$REAL_SUPPORT/$leaf" ]]; then
      mkdir -p "$SUPPORT_DIR/$leaf"
      cp -R "$REAL_SUPPORT/$leaf/." "$SUPPORT_DIR/$leaf/" 2>/dev/null || true
    fi
  done
  echo "seeded: Config/Catalogs/ProjectReadiness from real support (isolated Runs still empty)"
else
  echo "probe: warming model readiness under isolated support (doctor --full)…"
  "$ALLN" doctor --full --json >/dev/null || true
fi

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

# Truthful accept: must be a start envelope with runId, not a typed error.
RUN_ID="$(parse_field "$START_JSON" runId)"
if [[ -z "$RUN_ID" ]]; then
  CODE="$(parse_field "$START_JSON" code 2>/dev/null || true)"
  echo "FAIL: no runId in start envelope (code=${CODE:-}) — accepted envelope required after handshake" >&2
  exit 1
fi
echo "runId: $RUN_ID"

# Owner identity must exist after accept (detached runner claimed it).
OWNER_JSON="$SUPPORT_DIR/Runs/run_${RUN_ID}/owner.json"
if [[ ! -f "$OWNER_JSON" ]]; then
  # Give the runner a moment to claim.
  sleep 0.5
fi
if [[ -f "$OWNER_JSON" ]]; then
  echo "owner: $(cat "$OWNER_JSON")"
else
  echo "note: owner.json not yet visible (runner may still be claiming)"
fi

# Spec works test: poll until ≥1 worker reaches running then done, asserting
# status never becomes interrupted while the owner is identity-alive. Full-run
# terminal is nice-to-have (real code_core can take many minutes); ownership
# proof is the identity-alive/no-interrupt + progress path.
SAW_RUNNING=0
SAW_WORKER_DONE=0
STATUS=""
END_REASON=""
LAST_PROGRESS=""
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
  LAST_PROGRESS="$(parse_field "$STATUS_JSON" lastProgressAt)"
  RUNNING="$(parse_worker_count "$STATUS_JSON" running)"
  DONE_WORKERS="$(parse_worker_count "$STATUS_JSON" done)"
  echo "poll $i: status=$STATUS running=$RUNNING done_workers=$DONE_WORKERS endReason=${END_REASON:-} lastProgressAt=${LAST_PROGRESS:-}"

  if [[ "$STATUS" == "interrupted" ]]; then
    if [[ -f "$OWNER_JSON" ]]; then
      echo "FAIL: status became interrupted while owner.json present (must never interrupt while identity-alive)" >&2
      cat "$OWNER_JSON" >&2 || true
    else
      echo "FAIL: status became interrupted (no owner.json)" >&2
    fi
    # Best-effort cancel so a failed poll does not leave a live team burning.
    "$ALLN" team cancel "$RUN_ID" --json >/dev/null 2>&1 || true
    exit 1
  fi

  if [[ "$RUNNING" -ge 1 ]]; then
    SAW_RUNNING=1
  fi
  if [[ "$DONE_WORKERS" -ge 1 ]]; then
    SAW_WORKER_DONE=1
  fi
  # Ownership bar met: identity-alive never interrupted, ≥1 worker running then done.
  if [[ "$SAW_RUNNING" -eq 1 && "$SAW_WORKER_DONE" -eq 1 ]]; then
    echo "ownership bar met at poll $i (worker running→done; status still $STATUS)"
    break
  fi
  case "$STATUS" in
    completed|failed|cancelled|timedOut)
      break
      ;;
  esac
  sleep 2
done

if [[ "$SAW_RUNNING" -ne 1 || "$SAW_WORKER_DONE" -ne 1 ]]; then
  echo "FAIL: expected ≥1 worker running then done without interrupt (saw_running=$SAW_RUNNING saw_worker_done=$SAW_WORKER_DONE status=$STATUS)" >&2
  "$ALLN" team cancel "$RUN_ID" --json >/dev/null 2>&1 || true
  exit 1
fi

# Cancel the still-running team so the works probe does not leave a live tree.
case "$STATUS" in
  completed|failed|cancelled|timedOut|interrupted) ;;
  *)
    echo "cancel: stopping residual run $RUN_ID after ownership bar"
    CANCEL_JSON="$("$ALLN" team cancel "$RUN_ID" --json 2>/dev/null || true)"
    if [[ -n "$CANCEL_JSON" ]]; then
      STATUS="$(parse_field "$CANCEL_JSON" status)"
      END_REASON="cancelled"
    fi
    ;;
esac

if [[ -z "$END_REASON" ]]; then
  RESULT_JSON="$("$ALLN" team result "$RUN_ID" --json 2>/dev/null || true)"
  if [[ -n "$RESULT_JSON" ]]; then
    END_REASON="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print((d.get("teamRun") or {}).get("endReason") or d.get("endReason") or "")' "$RESULT_JSON" 2>/dev/null || true)"
  fi
fi

echo "PASS: run $RUN_ID ownership ok status=$STATUS endReason=${END_REASON:-n/a} lastProgressAt=${LAST_PROGRESS:-n/a} (never interrupted while identity-alive; saw_running=$SAW_RUNNING saw_worker_done=$SAW_WORKER_DONE)"
exit 0
