#!/usr/bin/env bash
# Works Test for wall admission control (scripts/check.sh cooldown).
#
# Proves, without running the full wall (~0s refusal; probe for allow paths):
#   1. Two runs back to back → second REFUSES non-zero, runs zero tests.
#   2. With ALLNIGHTER_WALL_REASON set under cooldown → second is admitted
#      and the reason is logged to wall-runs.log.
#   3. With cooldown elapsed (stale timestamp) → admitted.
#   4. With CI=true → admitted regardless of cooldown.
#
# Uses ALLNIGHTER_WALL_ADMISSION_PROBE=1 so allow-paths never reach
# check-fast / swift-test / xcodebuild. Isolates state under a temp dir
# via ALLNIGHTER_WALL_STATE_DIR.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_SH="$ROOT/scripts/check.sh"

FAILURES=0
WORK_DIR=""

log()  { echo "works-test-wall: $*"; }
pass() { echo "works-test-wall: PASS — $*"; }
fail() { echo "works-test-wall: FAIL — $*" >&2; FAILURES=$((FAILURES + 1)); }

cleanup() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/alln-wall-cooldown.XXXXXX")"
export ALLNIGHTER_WALL_STATE_DIR="$WORK_DIR"
STATE_FILE="$WORK_DIR/wall-last-run.json"
LOG_FILE="$WORK_DIR/wall-runs.log"

# Unset ambient CI / reason / probe so scenarios start clean.
unset CI GITHUB_ACTIONS GITLAB_CI CIRCLECI BUILDKITE TF_BUILD JENKINS_URL CONTINUOUS_INTEGRATION
unset ALLNIGHTER_WALL_REASON ALLNIGHTER_WALL_ADMISSION_PROBE ALLNIGHTER_WALL_COOLDOWN_MINUTES

write_recent_state() {
  # startedAt = now (within cooldown)
  python3 - "$STATE_FILE" <<'PY'
import json, sys
from datetime import datetime, timezone
path = sys.argv[1]
obj = {
    "startedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "headSha": "deadbeef",
    "reason": None,
    "result": "fail",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(obj, f, indent=2)
    f.write("\n")
PY
}

write_stale_state() {
  # startedAt = 2 hours ago (past default 45m cooldown)
  python3 - "$STATE_FILE" <<'PY'
import json, sys
from datetime import datetime, timezone, timedelta
path = sys.argv[1]
started = (datetime.now(timezone.utc) - timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ")
obj = {
    "startedAt": started,
    "headSha": "cafebabe",
    "reason": None,
    "result": "pass",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(obj, f, indent=2)
    f.write("\n")
PY
}

run_check() {
  # Usage: run_check <label> → sets OUT, EC, ELAPSED
  local label="$1"
  local out_file="$WORK_DIR/out-${label}.txt"
  local start end
  start=$SECONDS
  bash "$CHECK_SH" >"$out_file" 2>&1
  EC=$?
  end=$SECONDS
  ELAPSED=$((end - start))
  OUT="$(cat "$out_file")"
}

assert_no_wall_work() {
  local label="$1"
  if printf '%s' "$OUT" | grep -qE '==> (swift test|xcodegen|xcodebuild)|check-fast:|swift-test:'; then
    fail "$label: wall work started (should be admission-only)"
    printf '%s\n' "$OUT" | head -40 >&2
    return 1
  fi
  if printf '%s' "$OUT" | grep -q 'admission probe ok'; then
    # probe path is allow-path; not a failure here
    return 0
  fi
  return 0
}

# --- 1. Back-to-back: second REFUSES ---
log "scenario 1: back-to-back → second refuses"
write_recent_state
run_check "refuse"
assert_no_wall_work "1-refuse" || true
if [[ "$EC" -eq 0 ]]; then
  fail "1: expected non-zero exit under cooldown, got 0"
elif [[ "$EC" -ne 2 ]]; then
  # any non-zero is ok; prefer 2
  log "1: exit=$EC (expected 2; non-zero still counts as refuse)"
fi
if ! printf '%s' "$OUT" | grep -q 'REFUSED — wall cooldown active'; then
  fail "1: missing REFUSED message"
  printf '%s\n' "$OUT" | head -20 >&2
else
  pass "1: refused with cooldown message (exit=$EC, ${ELAPSED}s)"
fi
if ! printf '%s' "$OUT" | grep -q 'scripts/swift-test.sh --filter'; then
  fail "1: refusal must print cheap alternative (swift-test.sh --filter)"
else
  pass "1: printed cheap alternative"
fi
if ! printf '%s' "$OUT" | grep -q 'ALLNIGHTER_WALL_REASON='; then
  fail "1: refusal must print override form"
else
  pass "1: printed override form"
fi
if [[ "$ELAPSED" -gt 5 ]]; then
  fail "1: refusal took ${ELAPSED}s (expected ~0s / <5s)"
else
  pass "1: refusal was fast (${ELAPSED}s)"
fi
if printf '%s' "$OUT" | grep -qE '==> (swift test|xcodegen|xcodebuild)'; then
  fail "1: refusal path executed tests/build (ZERO required)"
else
  pass "1: refusal executed ZERO wall work"
fi

# --- 2. Override with reason → admitted + logged ---
log "scenario 2: ALLNIGHTER_WALL_REASON under cooldown → admits + logs"
write_recent_state
rm -f "$LOG_FILE"
export ALLNIGHTER_WALL_REASON="works-test closeout proof for wall cooldown"
export ALLNIGHTER_WALL_ADMISSION_PROBE=1
run_check "override"
unset ALLNIGHTER_WALL_REASON ALLNIGHTER_WALL_ADMISSION_PROBE
if [[ "$EC" -ne 0 ]]; then
  fail "2: expected admit under reason override, exit=$EC"
  printf '%s\n' "$OUT" | head -30 >&2
elif ! printf '%s' "$OUT" | grep -q 'admission probe ok'; then
  fail "2: expected admission probe ok"
  printf '%s\n' "$OUT" | head -30 >&2
else
  pass "2: admitted with reason (exit=$EC, ${ELAPSED}s)"
fi
if [[ ! -f "$LOG_FILE" ]] || ! grep -q 'works-test closeout proof for wall cooldown' "$LOG_FILE"; then
  fail "2: reason not logged to wall-runs.log"
  [[ -f "$LOG_FILE" ]] && cat "$LOG_FILE" >&2
else
  pass "2: reason logged to wall-runs.log"
fi
if printf '%s' "$OUT" | grep -qE '==> (swift test|xcodegen|xcodebuild)'; then
  fail "2: override path ran full wall (probe should stop early)"
else
  pass "2: override path ran no tests (probe)"
fi

# --- 3. Cooldown elapsed → admits ---
log "scenario 3: stale last-run → admits"
write_stale_state
export ALLNIGHTER_WALL_ADMISSION_PROBE=1
run_check "elapsed"
unset ALLNIGHTER_WALL_ADMISSION_PROBE
if [[ "$EC" -ne 0 ]] || ! printf '%s' "$OUT" | grep -q 'admission probe ok'; then
  fail "3: expected admit when cooldown elapsed, exit=$EC"
  printf '%s\n' "$OUT" | head -30 >&2
else
  pass "3: admitted after cooldown elapsed (exit=$EC, ${ELAPSED}s)"
fi

# --- 4. CI=true → admits regardless ---
log "scenario 4: CI=true → admits under fresh cooldown"
write_recent_state
export CI=true
export ALLNIGHTER_WALL_ADMISSION_PROBE=1
run_check "ci"
unset CI ALLNIGHTER_WALL_ADMISSION_PROBE
if [[ "$EC" -ne 0 ]] || ! printf '%s' "$OUT" | grep -q 'admission probe ok'; then
  fail "4: expected admit under CI=true, exit=$EC"
  printf '%s\n' "$OUT" | head -30 >&2
else
  pass "4: CI=true skips cooldown (exit=$EC, ${ELAPSED}s)"
fi
if printf '%s' "$OUT" | grep -q 'REFUSED'; then
  fail "4: CI path must never refuse"
fi

# Empty reason under cooldown still refuses
log "scenario 5 (bonus): empty ALLNIGHTER_WALL_REASON still refuses"
write_recent_state
export ALLNIGHTER_WALL_REASON=""
run_check "empty-reason"
unset ALLNIGHTER_WALL_REASON
if [[ "$EC" -eq 0 ]] || ! printf '%s' "$OUT" | grep -q 'REFUSED'; then
  fail "5: empty reason must still refuse under cooldown"
else
  pass "5: empty reason refused (exit=$EC)"
fi

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "works-test-wall: ALL PASS"
  exit 0
fi
echo "works-test-wall: $FAILURES FAILURE(S)" >&2
exit 1
