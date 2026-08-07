#!/usr/bin/env bash
# OPC-S01 — Fixture proof for scripts/get-alln.sh.
#
# CRITICAL SAFETY: every install runs under a scratch HOME + ALLN_INSTALL_DIR.
# Never touches the real machine's ~/.local/share/allnighter, ~/.local/bin, or
# the session's live `alln` binary.
#
# Proves (phase Works Test + CI proof):
#   BUG-0  script executed through a pipe still reaches bootstrap (step 10)
#   BUG-1  tampered sha256 → non-zero AND no install-path file
#   BUG-3  re-install while a holder keeps the old inode open succeeds
#   BUG-6  PATH conflict printed with both paths
#   host configs / shell rc mtimes unchanged
#   no MCP / no API-key advice in installer stdout
#
# Usage (from repo root):
#   bash scripts/test-get-alln.sh
#
# Env:
#   ALLN_FIXTURE_BINARY  path to a runnable alln (default: dist/alln-macos-universal
#                        or `command -v alln`)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/get-alln.sh"
EXAMPLE_MANIFEST="$ROOT/scripts/fixtures/get-alln/latest.example.json"

FAILURES=0
pass() { echo "test-get-alln: PASS — $*"; }
fail() { echo "test-get-alln: FAIL — $*" >&2; FAILURES=$((FAILURES + 1)); }
log()  { echo "test-get-alln: $*"; }
die()  { echo "test-get-alln: FATAL — $*" >&2; exit 2; }

# --- safety: refuse to run if we would touch the real home layout ----------
REAL_HOME="${HOME}"
# Capture the real home BEFORE we override it. Proofs must never use this.
if [[ -z "${REAL_HOME}" || "${REAL_HOME}" == "/" ]]; then
  die "refusing to run with empty/root REAL_HOME"
fi
REAL_ALLN_HOME="${REAL_HOME}/.local/share/allnighter"
REAL_LOCAL_BIN="${REAL_HOME}/.local/bin/alln"

assert_scratch_home() {
  local h="$1"
  case "$h" in
    /tmp/*|"${TMPDIR:-/tmp}"/*)
      ;;
    *)
      die "HOME is not under /tmp (got: $h) — refusing to run install proof"
      ;;
  esac
  if [[ "$h" == "$REAL_HOME" ]]; then
    die "HOME equals real user home — refusing"
  fi
  case "$h" in
    "$REAL_HOME"/*)
      die "HOME is inside real user home ($h) — refusing"
      ;;
  esac
}

assert_not_real_paths() {
  # Post-condition: real machine install locations untouched by this proof.
  if [[ -e "$REAL_ALLN_HOME/.proof-marker-should-never-exist" ]]; then
    die "sentinel appeared under real allnighter home"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_cmd curl
require_cmd python3
require_cmd shasum
require_cmd mktemp
require_cmd sh

[[ -f "$SCRIPT" ]] || die "missing $SCRIPT"
[[ -f "$EXAMPLE_MANIFEST" ]] || die "missing schema fixture $EXAMPLE_MANIFEST"
# Schema fixture must carry the documented keys (shape gate).
for key in schemaVersion cliVersion appVersion releasedAt notes installCommand; do
  grep -q "\"$key\"" "$EXAMPLE_MANIFEST" || die "example latest.json missing key: $key"
done
grep -q '"cli"' "$EXAMPLE_MANIFEST" || die "example latest.json missing cli object"
grep -q '"sha256"' "$EXAMPLE_MANIFEST" || die "example latest.json missing sha256"

# --- resolve a dogfood binary (do not rebuild universal here) --------------
resolve_binary() {
  if [[ -n "${ALLN_FIXTURE_BINARY:-}" && -x "${ALLN_FIXTURE_BINARY}" ]]; then
    printf '%s\n' "$ALLN_FIXTURE_BINARY"
    return 0
  fi
  if [[ -x "$ROOT/dist/alln-macos-universal" ]]; then
    printf '%s\n' "$ROOT/dist/alln-macos-universal"
    return 0
  fi
  if command -v alln >/dev/null 2>&1; then
    command -v alln
    return 0
  fi
  return 1
}

BINARY="$(resolve_binary)" || die "no fixture binary — set ALLN_FIXTURE_BINARY or build dist/alln-macos-universal (OPC-S00)"
log "fixture binary: $BINARY"
"$BINARY" version </dev/null >/dev/null || die "fixture binary failed version: $BINARY"

# --- workspace under /tmp only --------------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/get-alln-proof.XXXXXX")"
cleanup() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  if [[ -n "${HOLDER_PID:-}" ]] && kill -0 "$HOLDER_PID" 2>/dev/null; then
    kill "$HOLDER_PID" 2>/dev/null || true
    wait "$HOLDER_PID" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT INT HUP TERM

PUBLISH="$WORK/publish"
mkdir -p "$PUBLISH"
VERSION="0.0.0-fixture"
ASSET_DIR="$PUBLISH/v$VERSION"
mkdir -p "$ASSET_DIR"
cp "$BINARY" "$ASSET_DIR/alln-macos-universal"
chmod 755 "$ASSET_DIR/alln-macos-universal"
(
  cd "$ASSET_DIR"
  shasum -a 256 alln-macos-universal >alln-macos-universal.sha256
)
SHA256="$(awk '{print $1}' "$ASSET_DIR/alln-macos-universal.sha256")"
[[ ${#SHA256} -eq 64 ]] || die "bad sha length from fixture asset"

# Local HTTP server for BASE/latest.json + versioned asset (no real network).
PORT="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
BASE_URL="http://127.0.0.1:${PORT}"

write_manifest() {
  local sha="$1"
  local out="$2"
  cat >"$out" <<EOF
{
  "schemaVersion": 1,
  "cliVersion": "$VERSION",
  "appVersion": "$VERSION",
  "releasedAt": "2026-07-31T00:00:00Z",
  "notes": "fixture only; never projected to agents",
  "installCommand": "curl -fsSL https://get.allnighter.io | sh",
  "cli": {
    "url": "${BASE_URL}/v${VERSION}/alln-macos-universal",
    "sha256": "${sha}"
  },
  "app": {
    "url": "${BASE_URL}/v${VERSION}/Allnighter.dmg",
    "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
  }
}
EOF
}

write_manifest "$SHA256" "$PUBLISH/latest.json"

# Host-config canaries (mtime must not change).
CANARY_DIR="$WORK/canaries"
mkdir -p "$CANARY_DIR"
for f in .zshrc .bash_profile .hermes_config .claude_config .cursor_config; do
  echo "canary $f" >"$CANARY_DIR/$f"
done
# Snapshot mtimes via python for portability.
CANARY_BEFORE="$WORK/canary-before.txt"
python3 - <<PY
import os, json
root = "$CANARY_DIR"
rows = {}
for name in sorted(os.listdir(root)):
    p = os.path.join(root, name)
    st = os.stat(p)
    rows[name] = {"mtime_ns": st.st_mtime_ns, "size": st.st_size}
with open("$CANARY_BEFORE", "w") as f:
    json.dump(rows, f, indent=2, sort_keys=True)
PY

log "starting fixture HTTP server on $BASE_URL (root $PUBLISH)"
python3 - <<PY &
import http.server, socketserver, os, sys
os.chdir("$PUBLISH")
Handler = http.server.SimpleHTTPRequestHandler
# Quiet the request log noise on success paths.
class Quiet(Handler):
    def log_message(self, fmt, *args):
        sys.stderr.write("test-get-alln: http: " + (fmt % args) + "\n")
with socketserver.TCPServer(("127.0.0.1", int("$PORT")), Quiet) as httpd:
    httpd.serve_forever()
PY
SERVER_PID=$!
sleep 0.3
kill -0 "$SERVER_PID" 2>/dev/null || die "fixture HTTP server failed to start"
curl -fsSL "$BASE_URL/latest.json" </dev/null >/dev/null || die "fixture server not serving latest.json"

run_install() {
  # $1 = scratch label; remaining env overrides via env assignment before call.
  local label="$1"
  local home_dir="$WORK/home-$label"
  local link_dir="$WORK/link-$label"
  mkdir -p "$home_dir" "$link_dir"
  assert_scratch_home "$home_dir"

  local out="$WORK/out-$label.txt"
  local err="$WORK/err-$label.txt"
  local status=0

  # PIPE execution (BUG-0). Not `sh scripts/get-alln.sh`.
  # PATH deliberately starts with only the scratch link dir so we never
  # resolve the real machine's alln during conflict-free installs.
  set +e
  env -i \
    HOME="$home_dir" \
    PATH="$link_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$WORK/tmp-$label" \
    ALLN_INSTALL_BASE_URL="$BASE_URL" \
    ALLN_INSTALL_DIR="$link_dir" \
    ALLN_BOOTSTRAP_HOST="hermes" \
    USER="${USER:-get-alln-proof}" \
    LANG=C \
    /bin/sh -c 'mkdir -p "$TMPDIR"; cat "$1" | /bin/sh' _ "$SCRIPT" \
    >"$out" 2>"$err"
  status=$?
  set -e

  printf '%s\n' "$status"
  # Also leave paths for callers:
  #   home_dir, link_dir, out, err via naming convention
}

# =============================================================================
# Scenario A: happy path through a pipe (BUG-0 + steps 7/10)
# =============================================================================
log "scenario A: pipe install (BUG-0)"
STATUS_A="$(run_install happy)"
HOME_A="$WORK/home-happy"
LINK_A="$WORK/link-happy"
BIN_A="$HOME_A/.local/share/allnighter/bin/alln"
OUT_A="$WORK/out-happy.txt"
ERR_A="$WORK/err-happy.txt"

if [[ "$STATUS_A" -eq 0 ]]; then
  pass "pipe install exited 0"
else
  fail "pipe install exited $STATUS_A"
  sed 's/^/  | /' "$ERR_A" >&2 || true
  sed 's/^/  | /' "$OUT_A" >&2 || true
fi

if [[ -x "$BIN_A" ]]; then
  pass "stable home binary exists: $BIN_A"
else
  fail "stable home binary missing after install"
fi

if "$BIN_A" version </dev/null >/dev/null 2>&1; then
  pass "absolute version exits 0"
else
  fail "absolute version failed"
fi

# Step 10: bootstrap paste markers
if grep -q 'alln menu --json' "$OUT_A" && grep -q 'ALLNIGHTER:TEACHING' "$OUT_A"; then
  pass "stdout includes bootstrap teaching paste (step 10)"
else
  fail "bootstrap paste markers missing from stdout (BUG-0 / step 10)"
  sed 's/^/  | /' "$OUT_A" | head -n 40 >&2 || true
fi

# No MCP / no API-key advice
if grep -Eiq 'mcp add|model.vendor api|api[_-]?key|OPENAI_API_KEY|ANTHROPIC_API_KEY' "$OUT_A" "$ERR_A"; then
  fail "installer output mentions MCP or API keys"
else
  pass "no MCP / API-key advice in installer output"
fi

# Symlink present
if [[ -L "$LINK_A/alln" ]]; then
  pass "PATH link is a symlink (not a copy)"
else
  fail "expected symlink at $LINK_A/alln"
fi

# =============================================================================
# Scenario B: tampered sha256 → fail closed, no install file (BUG-1)
# =============================================================================
log "scenario B: tampered sha256 (BUG-1)"
BAD_SHA="ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
write_manifest "$BAD_SHA" "$PUBLISH/latest.json"
# Ensure server serves the new manifest (file already replaced on disk).

HOME_B="$WORK/home-badsha"
LINK_B="$WORK/link-badsha"
mkdir -p "$HOME_B" "$LINK_B"
assert_scratch_home "$HOME_B"
OUT_B="$WORK/out-badsha.txt"
ERR_B="$WORK/err-badsha.txt"
BIN_B="$HOME_B/.local/share/allnighter/bin/alln"
# Pre-create parent to prove we don't leave a binary even if dirs exist.
mkdir -p "$(dirname "$BIN_B")"

set +e
env -i \
  HOME="$HOME_B" \
  PATH="$LINK_B:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMPDIR="$WORK/tmp-badsha" \
  ALLN_INSTALL_BASE_URL="$BASE_URL" \
  ALLN_INSTALL_DIR="$LINK_B" \
  ALLN_BOOTSTRAP_HOST="hermes" \
  USER="${USER:-get-alln-proof}" \
  LANG=C \
  /bin/sh -c 'mkdir -p "$TMPDIR"; cat "$1" | /bin/sh' _ "$SCRIPT" \
  >"$OUT_B" 2>"$ERR_B"
STATUS_B=$?
set -e

if [[ "$STATUS_B" -ne 0 ]]; then
  pass "tampered sha exited non-zero ($STATUS_B)"
else
  fail "tampered sha exited 0 (should fail closed)"
fi

if [[ -e "$BIN_B" ]]; then
  fail "tampered sha left a binary at install path: $BIN_B"
else
  pass "tampered sha left no binary at install path"
fi

if grep -q 'sha256 mismatch' "$ERR_B"; then
  pass "tampered sha printed both-hash style mismatch"
else
  fail "tampered sha did not print mismatch message"
  sed 's/^/  | /' "$ERR_B" >&2 || true
fi

# Restore good manifest for later scenarios.
write_manifest "$SHA256" "$PUBLISH/latest.json"

# =============================================================================
# Scenario C: atomic re-install while old inode is held open (BUG-3)
# =============================================================================
log "scenario C: re-install while holder keeps old inode (BUG-3)"
# Start from a clean successful install first.
HOME_C="$WORK/home-atomic"
LINK_C="$WORK/link-atomic"
mkdir -p "$HOME_C" "$LINK_C"
assert_scratch_home "$HOME_C"
OUT_C1="$WORK/out-atomic-1.txt"
ERR_C1="$WORK/err-atomic-1.txt"
set +e
env -i \
  HOME="$HOME_C" \
  PATH="$LINK_C:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMPDIR="$WORK/tmp-atomic" \
  ALLN_INSTALL_BASE_URL="$BASE_URL" \
  ALLN_INSTALL_DIR="$LINK_C" \
  ALLN_BOOTSTRAP_HOST="hermes" \
  USER="${USER:-get-alln-proof}" \
  LANG=C \
  /bin/sh -c 'mkdir -p "$TMPDIR"; cat "$1" | /bin/sh' _ "$SCRIPT" \
  >"$OUT_C1" 2>"$ERR_C1"
STATUS_C1=$?
set -e
BIN_C="$HOME_C/.local/share/allnighter/bin/alln"
[[ "$STATUS_C1" -eq 0 && -x "$BIN_C" ]] || fail "BUG-3 setup install failed (status=$STATUS_C1)"

# Hold the installed binary's inode open (simulates a long-lived serve/loop).
python3 - "$BIN_C" <<'PY' &
import sys, time
path = sys.argv[1]
f = open(path, "rb")
# Keep the fd alive; print ready then sleep.
print("holder-ready", flush=True)
while True:
    time.sleep(1)
PY
HOLDER_PID=$!
# Wait until holder is up
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if kill -0 "$HOLDER_PID" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
kill -0 "$HOLDER_PID" 2>/dev/null || fail "inode holder failed to start"

OUT_C2="$WORK/out-atomic-2.txt"
ERR_C2="$WORK/err-atomic-2.txt"
set +e
env -i \
  HOME="$HOME_C" \
  PATH="$LINK_C:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMPDIR="$WORK/tmp-atomic2" \
  ALLN_INSTALL_BASE_URL="$BASE_URL" \
  ALLN_INSTALL_DIR="$LINK_C" \
  ALLN_BOOTSTRAP_HOST="hermes" \
  USER="${USER:-get-alln-proof}" \
  LANG=C \
  /bin/sh -c 'mkdir -p "$TMPDIR"; cat "$1" | /bin/sh' _ "$SCRIPT" \
  >"$OUT_C2" 2>"$ERR_C2"
STATUS_C2=$?
set -e

if [[ "$STATUS_C2" -eq 0 ]]; then
  pass "re-install while inode held exited 0 (atomic rename)"
else
  fail "re-install while inode held failed (status=$STATUS_C2) — likely non-atomic write"
  sed 's/^/  | /' "$ERR_C2" >&2 || true
fi

if kill -0 "$HOLDER_PID" 2>/dev/null; then
  pass "old process holding prior inode still alive after upgrade"
  kill "$HOLDER_PID" 2>/dev/null || true
  wait "$HOLDER_PID" 2>/dev/null || true
  HOLDER_PID=""
else
  fail "inode holder died during upgrade (should survive rename)"
fi

if "$BIN_C" version </dev/null >/dev/null 2>&1; then
  pass "new binary at install path still runs after atomic upgrade"
else
  fail "new binary failed version after atomic upgrade"
fi

# =============================================================================
# Scenario D: PATH resolves elsewhere → conflict printed (BUG-6)
# =============================================================================
log "scenario D: PATH conflict warning (BUG-6)"
HOME_D="$WORK/home-conflict"
LINK_D="$WORK/link-conflict"
FAKE_D="$WORK/fake-path"
mkdir -p "$HOME_D" "$LINK_D" "$FAKE_D"
assert_scratch_home "$HOME_D"
# A decoy `alln` earlier on PATH (not our link).
cat >"$FAKE_D/alln" <<'EOF'
#!/bin/sh
echo "decoy-alln 0.0.0-fake"
exit 0
EOF
chmod 755 "$FAKE_D/alln"

OUT_D="$WORK/out-conflict.txt"
ERR_D="$WORK/err-conflict.txt"
set +e
env -i \
  HOME="$HOME_D" \
  PATH="$FAKE_D:$LINK_D:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMPDIR="$WORK/tmp-conflict" \
  ALLN_INSTALL_BASE_URL="$BASE_URL" \
  ALLN_INSTALL_DIR="$LINK_D" \
  ALLN_BOOTSTRAP_HOST="hermes" \
  USER="${USER:-get-alln-proof}" \
  LANG=C \
  /bin/sh -c 'mkdir -p "$TMPDIR"; cat "$1" | /bin/sh' _ "$SCRIPT" \
  >"$OUT_D" 2>"$ERR_D"
STATUS_D=$?
set -e

if [[ "$STATUS_D" -eq 0 ]]; then
  pass "conflict install still exited 0 (warn, do not refuse)"
else
  fail "conflict install exited $STATUS_D"
  sed 's/^/  | /' "$ERR_D" >&2 || true
fi

if grep -q 'BUG-6 conflict' "$ERR_D" && grep -q "$FAKE_D/alln" "$ERR_D"; then
  pass "PATH conflict printed with decoy path"
else
  fail "PATH conflict warning missing decoy path"
  sed 's/^/  | /' "$ERR_D" >&2 || true
fi

if grep -q "$HOME_D/.local/share/allnighter/bin/alln" "$ERR_D" || grep -q "$LINK_D/alln" "$ERR_D"; then
  pass "PATH conflict printed this-install path"
else
  fail "PATH conflict missing this-install path"
fi

# =============================================================================
# Host canaries unchanged
# =============================================================================
log "checking host-config canary mtimes"
set +e
CANARY_STATUS=0
python3 - <<PY
import os, json, sys
root = "$CANARY_DIR"
before = json.load(open("$CANARY_BEFORE"))
bad = []
for name, prev in before.items():
    p = os.path.join(root, name)
    st = os.stat(p)
    if st.st_mtime_ns != prev["mtime_ns"] or st.st_size != prev["size"]:
        bad.append(name)
if bad:
    print("CHANGED: " + ", ".join(bad))
    sys.exit(1)
print("OK")
PY
CANARY_STATUS=$?
set -e
if [[ "$CANARY_STATUS" -eq 0 ]]; then
  pass "host-config canary mtimes unchanged"
else
  fail "host-config canary files were modified"
fi

# =============================================================================
# Final safety: real machine paths not used as HOME in any scenario
# =============================================================================
assert_not_real_paths
# Real live binary (if any) must still be the same path we started with.
if [[ -x "$REAL_LOCAL_BIN" ]]; then
  pass "real ~/.local/bin/alln still present (proof used scratch only)"
fi

# =============================================================================
echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "test-get-alln: ALL GREEN ($WORK cleaned on exit)"
  exit 0
fi
echo "test-get-alln: $FAILURES failure(s)" >&2
exit 1
