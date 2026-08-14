#!/usr/bin/env bash
# Post-upload proof: the published faucet, invoked the way a stranger
# invokes it, prints a live menu.
#
# Relocate-proof is the pre-upload gate on the signed artifact. This is the
# post-upload gate on the bytes get.allnighter.io actually serves. A
# `grep cliVersion` of latest.json is not proof (1.1.11 PATH trap).
#
# Usage:
#   scripts/faucet-smoke.sh <version> <gitSha>
#
# Safety: scratch HOME under TMPDIR, ALLN_NO_SERVE=1, PATH without
# /usr/local/bin. Never the founder's install or LaunchAgent.
#
# False greens this script refuses:
#   absolute-path menu, version-only, builder dist/, fixture BASE_URL,
#   real $HOME, omitting ALLN_NO_SERVE.
set -euo pipefail

die() { echo "faucet-smoke: $*" >&2; exit 1; }

[[ $# -eq 2 ]] || die "usage: scripts/faucet-smoke.sh <version> <gitSha>"
VERSION="$1"
GITSHA="$2"
[[ -n "$VERSION" && -n "$GITSHA" ]] || die "version and gitSha required"
[[ "$GITSHA" != "unknown" ]] || die "gitSha must not be unknown"

FAUCET="https://get.allnighter.io"

REAL_HOME="${HOME:-}"
[[ -n "$REAL_HOME" && "$REAL_HOME" != "/" ]] || die "refusing empty/root HOME"
REAL_ALLN_HOME="$REAL_HOME/.local/share/allnighter"

assert_scratch_home() {
  local h="$1"
  local tmp="${TMPDIR:-/tmp}"
  tmp="${tmp%/}"
  case "$h" in
    /tmp/*|"$tmp"/*) ;;
    *) die "HOME is not under TMPDIR (got: $h) — refusing" ;;
  esac
  if [[ "$h" == "$REAL_HOME" ]]; then
    die "HOME equals real user home — refusing"
  fi
  case "$h" in
    "$REAL_HOME"/*) die "HOME is inside real user home ($h) — refusing" ;;
  esac
}

command -v curl >/dev/null || die "missing curl"
command -v python3 >/dev/null || die "missing python3"
command -v mktemp >/dev/null || die "missing mktemp"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/alln-faucet-smoke.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT HUP TERM

HOME_DIR="$WORK/home"
LINK_DIR="$WORK/bin"
mkdir -p "$HOME_DIR" "$LINK_DIR" "$WORK/tmp"
assert_scratch_home "$HOME_DIR"

echo "faucet-smoke: wait for live latest.json cliVersion=$VERSION"
WAITED=0
while true; do
  LIVE_JSON="$(curl -fsSL "$FAUCET/latest.json" </dev/null)" || die "failed to fetch $FAUCET/latest.json"
  if ALLN_LIVE_JSON="$LIVE_JSON" ALLN_WANT="$VERSION" python3 - <<'PY'
import json, os, sys
doc = json.loads(os.environ["ALLN_LIVE_JSON"])
sys.exit(0 if doc.get("cliVersion") == os.environ["ALLN_WANT"] else 1)
PY
  then
    break
  fi
  WAITED=$((WAITED + 1))
  if [[ "$WAITED" -ge 12 ]]; then
    echo "faucet-smoke: live latest.json did not flip to $VERSION after 60s" >&2
    echo "$LIVE_JSON" >&2
    exit 1
  fi
  sleep 5
done

echo "faucet-smoke: curl | sh into scratch HOME (ALLN_NO_SERVE=1)"
# Stranger pipe. PATH omits /usr/local/bin so install-cli cannot pick a
# real writable prefix. ALLN_INSTALL_DIR pins the symlink into scratch.
set +e
env -i \
  HOME="$HOME_DIR" \
  PATH="$LINK_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMPDIR="$WORK/tmp" \
  ALLN_INSTALL_DIR="$LINK_DIR" \
  ALLN_NO_SERVE=1 \
  USER="${USER:-alln-ship-smoke}" \
  LANG=C \
  /bin/sh -c 'mkdir -p "$TMPDIR"; curl -fsSL https://get.allnighter.io | /bin/sh' \
  </dev/null
INSTALL_STATUS=$?
set -e
[[ "$INSTALL_STATUS" -eq 0 ]] || die "scratch curl|sh failed (exit $INSTALL_STATUS)"

if [[ -e "$REAL_ALLN_HOME/.faucet-smoke-should-never-exist" ]]; then
  die "sentinel appeared under real allnighter home"
fi

# Stranger use: cwd is scratch HOME (not the binary dir), bare name on PATH.
# Absolute "$HOME_DIR/.local/share/allnighter/bin/alln" is the 1.1.11 lie.
echo "faucet-smoke: bare alln version --json + menu --json from scratch HOME"
VERSION_JSON="$(
  cd "$HOME_DIR" && env -i \
    HOME="$HOME_DIR" \
    PATH="$LINK_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$WORK/tmp" \
    LANG=C \
    alln version --json </dev/null
)" || die "bare alln version --json failed (PATH invocation)"

ALLN_SHIP_JSON="$VERSION_JSON" python3 - "$VERSION" "$GITSHA" <<'PY' \
  || die "faucet binary identity mismatch (want version+gitSha)"
import json, os, sys
version, head = sys.argv[1], sys.argv[2]
doc = json.loads(os.environ["ALLN_SHIP_JSON"])
got_v = doc.get("binaryVersion")
got_sha = doc.get("gitSha")
if got_v != version:
    sys.stderr.write(f"binaryVersion {got_v!r} != {version!r}\n")
    sys.exit(1)
if got_sha != head:
    sys.stderr.write(f"gitSha {got_sha!r} != {head!r}\n")
    sys.exit(1)
PY

MENU_JSON="$(
  cd "$HOME_DIR" && env -i \
    HOME="$HOME_DIR" \
    PATH="$LINK_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="$WORK/tmp" \
    LANG=C \
    alln menu --json </dev/null
)" || die "bare alln menu --json failed (PATH invocation — 1.1.11 fingerprint)"

ALLN_MENU_JSON="$MENU_JSON" python3 - <<'PY' || die "menu --json is not a live menu"
import json, os, sys
doc = json.loads(os.environ["ALLN_MENU_JSON"])
if int(doc.get("schemaVersion") or 0) < 1:
    sys.stderr.write("schemaVersion missing or < 1\n")
    sys.exit(1)
commands = doc.get("commands")
if not isinstance(commands, list) or not commands:
    sys.stderr.write("commands missing or empty — catalog did not load\n")
    sys.exit(1)
PY

echo "faucet-smoke: OK — live faucet $VERSION ($GITSHA) prints a menu via PATH"
