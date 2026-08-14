#!/bin/sh
# OPC-S01 — One-paste cold install / CLI upgrade faucet.
#
# Public shape (canonical; do not invent cousins):
#   curl -fsSL https://get.allnighter.io | sh
#
# Contract: docs/phases/One_Paste_Cold_Start.md
#   "Install script contract (scripts/get-alln.sh)" — download, verify, install.
#
# Env:
#   ALLN_INSTALL_BASE_URL   default https://get.allnighter.io (fixture/dogfood override)
#   ALLN_BOOTSTRAP_HOST     default hermes
#   ALLN_INSTALL_DIR        optional force install directory (passed as --path to install-cli)
#
# Downloads the latest CLI payload (Mach-O or tar.gz of binary + SPM
# resource bundles), verifies sha256, execs once as a liveness check,
# then delegates to install-cli for the canonical install layout (ASR-S01c).
#
# Body is wrapped in main(); only main "$@" at the bottom so a truncated
# curl|sh pipe never half-runs (law 2 / BUG-0).

# shellcheck shell=sh disable=SC2039,SC3043
# SC2039/SC3043: deliberately POSIX — no local, no [[.

main() {
  set -eu
  umask 022

  case "$(uname -s)" in
    Darwin) ;;
    *)
      echo "get-alln: Darwin (macOS) only; refusing on $(uname -s)" >&2
      exit 1
      ;;
  esac

  TMP_DIR=""
  cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
      rm -rf "$TMP_DIR"
    fi
  }
  trap cleanup EXIT INT HUP TERM

  require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
      echo "get-alln: missing required command: $1" >&2
      exit 1
    fi
  }

  require_cmd curl
  require_cmd shasum
  require_cmd mktemp
  require_cmd mkdir
  require_cmd chmod
  require_cmd sed
  require_cmd awk
  require_cmd head
  require_cmd tar
  require_cmd dd
  require_cmd od
  require_cmd tr

  # Progress on stderr when it is a human TTY. Piped installs, tests, and
  # NO_COLOR / TERM=dumb stay silent so agent captures stay clean.
  ALLN_TTY=0
  if [ -t 2 ] && [ -n "${TERM:-}" ] && [ "$TERM" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    ALLN_TTY=1
  fi
  paint_reset=""
  paint_amber=""
  paint_muted=""
  if [ "$ALLN_TTY" -eq 1 ]; then
    paint_reset="$(printf '\033[0m')"
    paint_amber="$(printf '\033[38;2;255;166;48m')"
    paint_muted="$(printf '\033[38;2;126;134;158m')"
  fi
  step() {
    if [ "$ALLN_TTY" -eq 1 ]; then
      printf '%s  %-11s%s  %s%s%s\n' "$paint_muted" "$1" "$paint_reset" "$paint_amber" "$2" "$paint_reset" >&2
    fi
  }

  # --- base URL ---------------------------------------------------------
  BASE="${ALLN_INSTALL_BASE_URL:-https://get.allnighter.io}"
  # Strip trailing slash so "$BASE/latest.json" is stable.
  case "$BASE" in
    */) BASE="${BASE%/}" ;;
  esac

  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/get-alln.XXXXXX")"
  MANIFEST="$TMP_DIR/latest.json"
  DOWNLOAD="$TMP_DIR/alln-macos-universal"

  # --- fetch latest.json ------------------------------------------------
  # Every child that might read stdin gets </dev/null so a curl|sh pipe is
  # not eaten by a child (BUG-0).
  step "fetching" "$BASE"
  if ! curl -fsSL "$BASE/latest.json" -o "$MANIFEST" </dev/null; then
    echo "get-alln: failed to fetch $BASE/latest.json" >&2
    exit 1
  fi

  # Fixed-shape extraction (no jq). First "url"/"sha256" are under "cli"
  # (schema puts cli before app). Fields must be on their own line in
  # published manifests; compact single-line JSON also works via .* match.
  extract_string() {
    _key="$1"
    _file="$2"
    sed -n 's/.*"'"$_key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_file" | head -n 1
  }

  CLI_URL="$(extract_string url "$MANIFEST")"
  CLI_SHA="$(extract_string sha256 "$MANIFEST")"

  if [ -z "$CLI_URL" ] || [ -z "$CLI_SHA" ]; then
    echo "get-alln: latest.json missing cli.url or cli.sha256" >&2
    exit 1
  fi
  if [ "${#CLI_SHA}" -ne 64 ]; then
    echo "get-alln: cli.sha256 is not 64 hex chars (got length ${#CLI_SHA})" >&2
    exit 1
  fi

  # --- download binary + verify SHA256 (fail closed) --------------------
  step "downloading" "alln"
  if ! curl -fsSL "$CLI_URL" -o "$DOWNLOAD" </dev/null; then
    echo "get-alln: failed to download CLI binary from $CLI_URL" >&2
    exit 1
  fi

  GOT_SHA="$(shasum -a 256 "$DOWNLOAD" | awk '{print $1}')"
  if [ "$GOT_SHA" != "$CLI_SHA" ]; then
    echo "get-alln: sha256 mismatch — refusing install (fail closed)" >&2
    echo "  expected: $CLI_SHA" >&2
    echo "  got:      $GOT_SHA" >&2
    exit 1
  fi

  chmod 755 "$DOWNLOAD"
  step "verified" "sha256"

  # gzip payload = binary + SPM resource bundles. A naked Mach-O is still
  # accepted so an in-flight faucet flip cannot wedge an old latest.json.
  is_gzip_payload() {
    _magic="$(dd if="$1" bs=1 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    [ "$_magic" = "1f8b" ]
  }
  if is_gzip_payload "$DOWNLOAD"; then
    PAYLOAD_DIR="$TMP_DIR/payload"
    mkdir -p "$PAYLOAD_DIR"
    if ! tar -xzf "$DOWNLOAD" -C "$PAYLOAD_DIR"; then
      echo "get-alln: failed to extract CLI payload" >&2
      exit 1
    fi
    if [ -x "$PAYLOAD_DIR/alln-macos-universal" ]; then
      DOWNLOAD="$PAYLOAD_DIR/alln-macos-universal"
    elif [ -x "$PAYLOAD_DIR/alln" ]; then
      DOWNLOAD="$PAYLOAD_DIR/alln"
    else
      echo "get-alln: archive missing alln binary" >&2
      exit 1
    fi
    chmod 755 "$DOWNLOAD"
  fi

  # Leave Documents/Desktop/Downloads before any alln exec. macOS TCC
  # attributes getcwd / inherited cwd to the CLI binary — Developer ID
  # does not skip the prompt; it only makes Allow stick. ProtectedCWDEscape
  # cannot avoid the first getcwd. Same belt as scripts/rebuild_cli.sh.
  # HOME is never a TCC-protected folder. Must run before `version` and
  # `install-cli` (2026-08-13: signed 1.1.3 from a Documents checkout
  # prompted on curl|sh).
  if ! cd "$HOME"; then
    echo "get-alln: failed to cd to HOME before running alln" >&2
    exit 1
  fi

  # --- liveness check (exec candidate once before installing) -----------
  # stdout is the identity dump — hide it; the install receipt is the
  # human surface. Failure still exits non-zero.
  if ! "$DOWNLOAD" version </dev/null >/dev/null; then
    echo "get-alln: downloaded binary failed liveness check: $DOWNLOAD version" >&2
    exit 1
  fi

  # --- delegate install to install-cli (ASR-S01c) -----------------------
  # Canonical install layout is owned by install-cli.
  # Pass --path through only when the caller supplied an explicit directory.
  INSTALL_ARGS="install-cli"
  if [ -n "${ALLN_INSTALL_DIR:-}" ]; then
    INSTALL_ARGS="install-cli --path $ALLN_INSTALL_DIR"
  fi

  step "installing" "alln"

  # shellcheck disable=SC2086
  exec "$DOWNLOAD" $INSTALL_ARGS
}

main "$@"
