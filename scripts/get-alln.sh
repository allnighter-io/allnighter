#!/bin/sh
# OPC-S01 — One-paste cold install / CLI upgrade faucet.
#
# Public shape (canonical; do not invent cousins):
#   curl -fsSL https://get.allnighter.app | sh
#
# Contract: docs/phases/One_Paste_Cold_Start.md
#   "Install script contract (scripts/get-alln.sh)" — 11-step main().
#
# Env:
#   ALLN_INSTALL_BASE_URL   default https://get.allnighter.app (fixture/dogfood override)
#   ALLN_BOOTSTRAP_HOST     default hermes
#   ALLN_INSTALL_DIR        optional force symlink directory
#
# Writes only under ~/.local/share/allnighter/, chosen link dir, and temp.
# Never edits shell rc, host configs, Keychain; never sudo.
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
  require_cmd mv
  require_cmd chmod
  require_cmd ln
  require_cmd sed
  require_cmd awk
  require_cmd head

  # --- 2. base URL ---------------------------------------------------------
  BASE="${ALLN_INSTALL_BASE_URL:-https://get.allnighter.app}"
  # Strip trailing slash so "$BASE/latest.json" is stable.
  case "$BASE" in
    */) BASE="${BASE%/}" ;;
  esac

  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/get-alln.XXXXXX")"
  MANIFEST="$TMP_DIR/latest.json"
  DOWNLOAD="$TMP_DIR/alln-macos-universal"

  # --- 3. fetch latest.json ------------------------------------------------
  # Every child that might read stdin gets </dev/null so a curl|sh pipe is
  # not eaten by a child (BUG-0).
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

  CLI_VERSION="$(extract_string cliVersion "$MANIFEST")"
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

  # --- 4. download binary + verify SHA256 (fail closed) --------------------
  if ! curl -fsSL "$CLI_URL" -o "$DOWNLOAD" </dev/null; then
    echo "get-alln: failed to download CLI binary from $CLI_URL" >&2
    exit 1
  fi

  GOT_SHA="$(shasum -a 256 "$DOWNLOAD" | awk '{print $1}')"
  if [ "$GOT_SHA" != "$CLI_SHA" ]; then
    echo "get-alln: sha256 mismatch — refusing install (fail closed)" >&2
    echo "  expected: $CLI_SHA" >&2
    echo "  got:      $GOT_SHA" >&2
    if [ -n "${CLI_VERSION:-}" ]; then
      echo "  cliVersion: $CLI_VERSION" >&2
    fi
    exit 1
  fi

  # --- 5. atomic install into stable home ----------------------------------
  # HOME is the only root we touch for the stable binary (fixture proofs
  # override HOME to a scratch dir — never write outside it).
  HOME_BIN="${HOME}/.local/share/allnighter/bin"
  mkdir -p "$HOME_BIN"
  BIN="${HOME_BIN}/alln"
  STAGE="${HOME_BIN}/.alln.tmp.$$"
  # Stage on the same filesystem as the destination, then rename (BUG-3:
  # never write in place over a running inode; never mv from TMPDIR across
  # devices into the final name without a same-fs stage).
  cp "$DOWNLOAD" "$STAGE"
  chmod 755 "$STAGE"
  mv -f "$STAGE" "$BIN"

  # --- 6. symlink onto a PATH-ish dir (law 1) ------------------------------
  choose_link_dir() {
    if [ -n "${ALLN_INSTALL_DIR:-}" ]; then
      printf '%s\n' "$ALLN_INSTALL_DIR"
      return 0
    fi
    # First directory already on $PATH that is writable without sudo.
    _old_ifs=$IFS
    IFS=:
    # shellcheck disable=SC2086
    for _d in $PATH; do
      IFS=$_old_ifs
      if [ -n "$_d" ] && [ -d "$_d" ] && [ -w "$_d" ]; then
        printf '%s\n' "$_d"
        return 0
      fi
    done
    IFS=$_old_ifs
    if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
      printf '%s\n' /usr/local/bin
      return 0
    fi
    printf '%s\n' "${HOME}/.local/bin"
  }

  LINK_DIR="$(choose_link_dir)"
  mkdir -p "$LINK_DIR"
  LINK_PATH="${LINK_DIR}/alln"
  # Symlink — never copy — so upgrades of the stable home need no re-link.
  ln -sfn "$BIN" "$LINK_PATH"

  link_on_path=0
  _old_ifs=$IFS
  IFS=:
  for _d in $PATH; do
    IFS=$_old_ifs
    if [ "$_d" = "$LINK_DIR" ]; then
      link_on_path=1
      break
    fi
  done
  IFS=$_old_ifs

  if [ "$link_on_path" -eq 0 ]; then
    echo "get-alln: $LINK_DIR is not on PATH in this shell."
    echo "  Add it for this session:"
    echo "    export PATH=\"${LINK_DIR}:\$PATH\""
    echo "  (We do not edit ~/.zshrc or ~/.bash_profile.)"
  fi

  # --- 7. absolute version proof (required success) ------------------------
  if ! "$BIN" version </dev/null; then
    echo "get-alln: installed binary failed: $BIN version" >&2
    echo "  If you see 'Code Signature Invalid', the public binary must be" >&2
    echo "  Developer ID signed (dogfood: ad-hoc is fine for private URLs)." >&2
    exit 1
  fi
  VERSION_OK=1

  # --- 8. PATH conflict warning (BUG-6) ------------------------------------
  resolved="$(command -v alln 2>/dev/null || true)"
  if [ -n "$resolved" ]; then
    # Compare symlink-resolved targets when possible.
    resolved_real="$resolved"
    link_real="$LINK_PATH"
    if command -v python3 >/dev/null 2>&1; then
      resolved_real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$resolved" </dev/null 2>/dev/null || printf '%s' "$resolved")"
      link_real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$LINK_PATH" </dev/null 2>/dev/null || printf '%s' "$LINK_PATH")"
    fi
    if [ "$resolved" != "$LINK_PATH" ] && [ "$resolved_real" != "$link_real" ] && [ "$resolved_real" != "$BIN" ]; then
      echo "get-alln: warning: 'alln' on PATH is not this install (BUG-6 conflict)" >&2
      echo "  PATH resolves to: $resolved" >&2
      if [ -x "$resolved" ]; then
        echo "  PATH version:     $("$resolved" version </dev/null 2>&1 | head -n 1)" >&2
      fi
      echo "  this install:     $LINK_PATH -> $BIN" >&2
      echo "  this version:     $("$BIN" version </dev/null 2>&1 | head -n 1)" >&2
      echo "  Fix: put $LINK_DIR first on PATH, or re-run install-cli from the binary you want." >&2
    fi
  fi

  # --- 9. in-flight / older serve warning (law 11) — announce only ---------
  # Never kill, never refuse install. Prefer upgrade between rounds.
  if inflight_ps="$("$BIN" ps </dev/null 2>/dev/null)"; then
    case "$inflight_ps" in
      *running*|*Running*)
        echo "get-alln: warning: processes still in flight (alln ps shows running)." >&2
        echo "  Prefer upgrading between rounds, not mid-loop (state-format cutovers can brick open loops)." >&2
        ;;
    esac
  fi
  if inflight_loops="$("$BIN" loop list </dev/null 2>/dev/null)"; then
    case "$inflight_loops" in
      *running*|*Running*)
        echo "get-alln: warning: a loop is still running (alln loop list)." >&2
        echo "  Finish or stop open loops before upgrading across a state-format cutover." >&2
        ;;
    esac
  fi
  if serve_health="$("$BIN" serve --health --json </dev/null 2>/dev/null)"; then
    case "$serve_health" in
      *'"state"'*available*|*'"state"'*:"available"*|*'"pid"'*)
        # Serve is up. Suggest restart so the daemon picks up the new binary.
        # (We do not parse binaryVersion in pure sh — restart advice is always
        # correct when a daemon is listening.)
        echo "get-alln: note: alln serve appears to be running an older process image." >&2
        echo "  Restart it to load this binary: stop the serve process, then \`alln serve\`." >&2
        ;;
    esac
  fi

  # --- 10. bootstrap paste (one teaching body; print only) -----------------
  HOST="${ALLN_BOOTSTRAP_HOST:-hermes}"
  echo ""
  echo "get-alln: install ok → $BIN"
  if [ -n "${CLI_VERSION:-}" ]; then
    echo "get-alln: cliVersion $CLI_VERSION"
  fi
  echo "get-alln: absolute fallback: $BIN"
  echo ""
  # Bootstrap is SSOT for host paste; script never hand-maintains a second manifesto.
  if ! "$BIN" bootstrap --host "$HOST" </dev/null; then
    echo "get-alln: warning: bootstrap --host $HOST failed (binary is still installed at $BIN)" >&2
    # Install itself succeeded (step 7); do not fail the faucet on paste issues.
  fi

  # --- 11. exit 0 only if version proof succeeded --------------------------
  if [ "${VERSION_OK:-0}" -eq 1 ]; then
    exit 0
  fi
  exit 1
}

main "$@"
