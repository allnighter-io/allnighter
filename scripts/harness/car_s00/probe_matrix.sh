#!/bin/bash
# CAR-S00b launch-primitive matrix probe.
#
# Runs each launch primitive in fixed order. For each: fresh nonce, delete
# stale receipt, launch, then poll up to 20s for a nonce-matching receipt.
# Identical script for both origins (leg A' outside Codex, leg C' inside a
# real default Codex session) so the two runs are comparable.
#
# Harness state (nonce/receipt) lives under the REAL product state root,
# which default Codex seatbelt lists as writable:
#   ~/Library/Application Support/Allnighter/car_s00_harness/
# The caller control write and the in-app fs authority probe deliberately
# target a genuinely non-writable path (the old S00 dir) — that write must
# FAIL for a sandboxed caller/inherited launch and SUCCEED for a detached
# LaunchServices launch. The asymmetry is the signal.
set -uo pipefail

BUNDLE_ID="com.happymoose.allnighter.harness"
APP_PATH="$HOME/Applications/AllnighterHarness.app"
EXE_PATH="$APP_PATH/Contents/MacOS/AllnighterHarness"
SUPPORT_DIR="$HOME/Library/Application Support/Allnighter/car_s00_harness"
NONCE_FILE="$SUPPORT_DIR/nonce.txt"
RECEIPT="$SUPPORT_DIR/receipt.json"
CONTROL_DIR="$HOME/Library/Application Support/AllnighterHarness"
CONTROL_FILE="$CONTROL_DIR/caller_control_write.txt"
POLL_SECONDS=20

echo "=== CAR-S00b launch-primitive matrix probe ==="
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "caller pid: $$  ppid: $PPID"
echo "caller CODEX_SANDBOX: ${CODEX_SANDBOX:-<absent>}"

# --- Sandbox-active control: one write to a genuinely non-writable path -----
mkdir -p "$SUPPORT_DIR"
mkdir -p "$CONTROL_DIR" 2>/dev/null || true
if (echo "caller-control-$(date +%s)" > "$CONTROL_FILE") 2>/dev/null; then
    echo "caller outside-workspace write: OK ($CONTROL_FILE)"
else
    echo "caller outside-workspace write: DENIED"
    # Bare retry so the shell's raw denial text lands on our stderr (captured by caller).
    echo "caller-control-$(date +%s)" > "$CONTROL_FILE"
fi

json_field() {
    /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    cur = d
    for k in sys.argv[2].split("."):
        cur = cur[k]
    print(cur)
except Exception:
    print("<parse-failed>")
' "$1" "$2"
}

GREEN_COUNT=0

# run_primitive <label> <cmd...>
run_primitive() {
    local label="$1"; shift
    echo ""
    echo "=== primitive: $label ==="
    echo "cmd: $*"

    rm -f "$RECEIPT" 2>/dev/null || true
    local NONCE
    NONCE="$(uuidgen)"
    if ! (printf '%s\n' "$NONCE" > "$NONCE_FILE") 2>/dev/null; then
        echo "PROBE INFRA FAILURE: could not write nonce file (caller sandboxed?)"
        printf '%s\n' "$NONCE" > "$NONCE_FILE"
    fi
    echo "nonce: $NONCE"

    local OUT RC
    OUT="$("$@" 2>&1)"
    RC=$?
    echo "rc: $RC"
    [ -n "$OUT" ] && echo "output: $OUT"

    echo "polling for receipt (up to ${POLL_SECONDS}s)"
    local FOUND=0 i
    for i in $(seq 1 $((POLL_SECONDS * 2))); do
        if [ -f "$RECEIPT" ] && [ "$(json_field "$RECEIPT" nonce)" = "$NONCE" ]; then
            FOUND=1
            break
        fi
        sleep 0.5
    done

    if [ "$FOUND" -eq 0 ]; then
        echo "PRIMITIVE VERDICT: NO FRESH RECEIPT within ${POLL_SECONDS}s"
        return
    fi

    echo "--- receipt.json ---"
    cat "$RECEIPT"
    echo "--- authority facts from receipt ---"
    local R_PID R_PPID R_SANDBOX R_KEYCHAIN R_FS
    R_PID="$(json_field "$RECEIPT" pid)"
    R_PPID="$(json_field "$RECEIPT" ppid)"
    R_SANDBOX="$(json_field "$RECEIPT" codex_sandbox)"
    R_KEYCHAIN="$(json_field "$RECEIPT" probes.keychain_status)"
    R_FS="$(json_field "$RECEIPT" probes.filesystem_write)"
    echo "receipt pid:            $R_PID"
    echo "receipt ppid:           $R_PPID"
    echo "receipt codex_sandbox:  $R_SANDBOX"
    echo "receipt keychain_status: $R_KEYCHAIN"
    echo "receipt fs write (non-writable path): $R_FS"

    if [ "$R_PPID" = "1" ] && [ "$R_SANDBOX" = "None" ] \
        && [ "$R_KEYCHAIN" = "-25300" ] && [ "$R_FS" = "ok" ]; then
        echo "PRIMITIVE VERDICT: DETACHED LAUNCH, INDEPENDENT AUTHORITY (GREEN-grade)"
        GREEN_COUNT=$((GREEN_COUNT + 1))
    else
        echo "PRIMITIVE VERDICT: RECEIPT SHOWS INHERITED/RESTRICTED AUTHORITY (not GREEN)"
    fi
}

run_primitive "1. open -b (LaunchServices db lookup)" open -b "$BUNDLE_ID"
run_primitive "2. open <path> (by path, no LS db lookup)" open "$APP_PATH"
run_primitive "3. open -a <path>" open -a "$APP_PATH"
run_primitive "4. direct spawn of bundle executable (control: inherits sandbox)" "$EXE_PATH"
run_primitive "5. osascript tell application id to launch" \
    osascript -e "tell application id \"$BUNDLE_ID\" to launch"

echo ""
echo "=== matrix summary ==="
echo "primitives with detached independent-authority receipt: $GREEN_COUNT / 5"
