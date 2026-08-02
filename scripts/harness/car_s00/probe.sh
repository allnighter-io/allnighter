#!/bin/bash
# CAR-S00 caller-side probe. Identical script for both origins (outside Codex
# and inside a real default Codex session) so the two runs are comparable.
set -uo pipefail

BUNDLE_ID="com.happymoose.allnighter.harness"
SUPPORT_DIR="$HOME/Library/Application Support/AllnighterHarness"
NONCE_FILE="$SUPPORT_DIR/nonce.txt"
RECEIPT="$SUPPORT_DIR/receipt.json"
CONTROL_FILE="$SUPPORT_DIR/caller_control_write.txt"

echo "=== CAR-S00 probe ==="
echo "caller pid: $$  ppid: $PPID"
echo "caller CODEX_SANDBOX: ${CODEX_SANDBOX:-<absent>}"

# --- Sandbox-active control: one write outside any workspace ----------------
mkdir -p "$SUPPORT_DIR"
if (echo "caller-control-$(date +%s)" > "$CONTROL_FILE") 2>/dev/null; then
    echo "caller outside-workspace write: OK ($CONTROL_FILE)"
else
    echo "caller outside-workspace write: DENIED"
    # Bare retry so the shell's raw denial text lands on our stderr (captured by caller).
    echo "caller-control-$(date +%s)" > "$CONTROL_FILE"
fi

# --- Fresh nonce -------------------------------------------------------------
rm -f "$RECEIPT"
NONCE="$(uuidgen)"
printf '%s\n' "$NONCE" > "$NONCE_FILE" 2>/dev/null || {
    echo "PROBE INFRA FAILURE: could not write nonce file (caller sandboxed?)"
    echo "$NONCE" > "$NONCE_FILE"
}
echo "nonce: $NONCE"

# --- LaunchServices launch by bundle id --------------------------------------
echo "=== open -b $BUNDLE_ID ==="
OPEN_OUT="$(open -b "$BUNDLE_ID" 2>&1)"
OPEN_RC=$?
echo "open rc: $OPEN_RC"
[ -n "$OPEN_OUT" ] && echo "open output: $OPEN_OUT"

# --- Poll for receipt (30s) ---------------------------------------------------
echo "=== polling for receipt (up to 30s) ==="
FOUND=0
for i in $(seq 1 60); do
    [ -f "$RECEIPT" ] && { FOUND=1; break; }
    sleep 0.5
done

if [ "$FOUND" -eq 0 ]; then
    echo "VERDICT: NO RECEIPT within 30s"
    exit 2
fi

echo "=== receipt.json ==="
cat "$RECEIPT"

RECEIPT_NONCE="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("nonce"))' "$RECEIPT" 2>/dev/null || echo '<parse-failed>')"

echo "=== verdict ==="
if [ "$RECEIPT_NONCE" = "$NONCE" ]; then
    echo "VERDICT: FRESH RECEIPT (nonce match)"
else
    echo "VERDICT: STALE/MISMATCHED RECEIPT (expected $NONCE, got $RECEIPT_NONCE)"
    exit 3
fi
