#!/usr/bin/env bash
# Remove Allnighter Mac app(s), CLI installs, and product state so you can
# re-test cold install / first-run onboarding.
#
# Targets:
#   - Release app: /Applications/Allnighter.app, ~/Applications/Allnighter.app
#   - Dev app (allapp): ~/Library/Developer/Allnighter/Build/.../Allnighter.app
#   - CLI: get-alln home (~/.local/share/allnighter), PATH symlinks, dev scratch
#   - Background serve LaunchAgent (com.allnighter.resident-coordinator)
#   - Product state: ~/Library/Application Support/Allnighter (default)
#
# Usage:
#   bash scripts/uninstall-allnighter.sh              # interactive confirm
#   bash scripts/uninstall-allnighter.sh --yes        # no prompt
#   bash scripts/uninstall-allnighter.sh --keep-state # binaries only
#   bash scripts/uninstall-allnighter.sh --reset-tcc  # also reset TCC for com.allnighter.mac
#
# Does not touch the git checkout, vendor CLI logins, or unrelated `alln` on PATH.
set -euo pipefail

LABEL="com.allnighter.resident-coordinator"
BUNDLE_ID="com.allnighter.mac"
HOME_DIR="${HOME:?HOME is not set}"

YES=0
KEEP_STATE=0
RESET_TCC=0

usage() {
  cat <<'EOF'
usage: scripts/uninstall-allnighter.sh [--yes] [--keep-state] [--reset-tcc]

  --yes, -y       skip confirmation prompt
  --keep-state    remove apps/CLI/serve only; keep Application Support state
  --reset-tcc     run `tccutil reset All com.allnighter.mac` (dev only)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --keep-state) KEEP_STATE=1 ;;
    --reset-tcc) RESET_TCC=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "uninstall-allnighter: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

log() { printf 'uninstall-allnighter: %s\n' "$*"; }
warn() { printf 'uninstall-allnighter: warning: %s\n' "$*" >&2; }

# --- plan --------------------------------------------------------------------

PLAN=()

add_path() {
  local p="$1"
  if [[ -e "$p" || -L "$p" ]]; then
    PLAN+=("$p")
  fi
}

# Release + user Applications installs.
add_path "/Applications/Allnighter.app"
add_path "$HOME_DIR/Applications/Allnighter.app"

# Dev allapp build(s) under the standard derived-data root.
DEV_ROOT="${ALLNIGHTER_BUILD_DIR:-$HOME_DIR/Library/Developer/Allnighter/Build}"
for variant in Debug Release; do
  add_path "$DEV_ROOT/Build/Products/$variant/Allnighter.app"
done

# Any other Allnighter.app Launch Services knows about (e.g. dragged copies).
if command -v mdfind >/dev/null 2>&1; then
  while IFS= read -r found; do
    [[ -n "$found" ]] && add_path "$found"
  done < <(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null || true)
fi

# Cold-start CLI home (get-alln.sh).
add_path "$HOME_DIR/.local/share/allnighter"

# Dev CLI scratch + release build output (rebuild_cli.sh).
add_path "${ALLNIGHTER_CLI_SCRATCH:-$HOME_DIR/Library/Developer/Allnighter/CLI}"

# LaunchAgent plist.
add_path "$HOME_DIR/Library/LaunchAgents/${LABEL}.plist"

# Product state (onboarding, runs, setup cache, staged serve binary, etc.).
if [[ "$KEEP_STATE" -eq 0 ]]; then
  add_path "$HOME_DIR/Library/Application Support/Allnighter"
  add_path "$HOME_DIR/Library/Saved Application State/${BUNDLE_ID}.savedState"
  add_path "$HOME_DIR/Library/Preferences/${BUNDLE_ID}.plist"
  add_path "$HOME_DIR/Library/Caches/${BUNDLE_ID}"
fi

# PATH symlinks that resolve to an Allnighter-owned binary.
ALLN_SYMLINKS=()
is_allnighter_target() {
  local target="$1"
  case "$target" in
    *allnighter*|*Allnighter*) return 0 ;;
  esac
  return 1
}

collect_alln_symlink() {
  local link="$1"
  [[ -L "$link" ]] || return 0
  local dest
  dest="$(readlink "$link" 2>/dev/null || true)"
  [[ -n "$dest" ]] || return 0
  if [[ "$dest" != /* ]]; then
    dest="$(cd "$(dirname "$link")" && pwd)/$dest"
  fi
  if command -v python3 >/dev/null 2>&1; then
    dest="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$dest" 2>/dev/null || printf '%s' "$dest")"
  fi
  if is_allnighter_target "$dest"; then
    ALLN_SYMLINKS+=("$link")
  fi
}

for dir in "$HOME_DIR/.local/bin" /usr/local/bin; do
  collect_alln_symlink "$dir/alln"
done

IFS=:
for dir in $PATH; do
  [[ -n "$dir" ]] || continue
  candidate="$dir/alln"
  if [[ -x "$candidate" && ! -L "$candidate" ]] && is_allnighter_target "$candidate"; then
    ALLN_SYMLINKS+=("$candidate")
  fi
done
unset IFS

# De-dupe PLAN + symlinks (bash 3.2 friendly).
dedupe_list() {
  printf '%s\n' "$@" | awk 'NF && !seen[$0]++'
}

TMP_PLAN=("${PLAN[@]+"${PLAN[@]}"}")
PLAN=()
while IFS= read -r line; do
  [[ -n "$line" ]] && PLAN+=("$line")
done <<EOF
$(dedupe_list ${TMP_PLAN[@]+"${TMP_PLAN[@]}"})
EOF

TMP_LINKS=("${ALLN_SYMLINKS[@]+"${ALLN_SYMLINKS[@]}"}")
ALLN_SYMLINKS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && ALLN_SYMLINKS+=("$line")
done <<EOF
$(dedupe_list ${TMP_LINKS[@]+"${TMP_LINKS[@]}"})
EOF

# --- confirm -----------------------------------------------------------------

if [[ ${#PLAN[@]} -eq 0 && ${#ALLN_SYMLINKS[@]} -eq 0 ]]; then
  log "nothing to remove — Allnighter does not appear to be installed on this Mac"
  exit 0
fi

echo "This will remove Allnighter apps, CLI installs, and the serve LaunchAgent."
if [[ "$KEEP_STATE" -eq 0 ]]; then
  echo "Product state under ~/Library/Application Support/Allnighter will be deleted."
else
  echo "Product state will be kept (--keep-state)."
fi
if [[ "$RESET_TCC" -eq 1 ]]; then
  echo "TCC permissions for ${BUNDLE_ID} will be reset."
fi
echo
if [[ ${#PLAN[@]} -gt 0 ]]; then
  echo "Paths:"
  printf '  - %s\n' ${PLAN[@]+"${PLAN[@]}"}
fi
if [[ ${#ALLN_SYMLINKS[@]} -gt 0 ]]; then
  echo "CLI symlinks / binaries:"
  printf '  - %s\n' ${ALLN_SYMLINKS[@]+"${ALLN_SYMLINKS[@]}"}
fi
echo

if [[ "$YES" -eq 0 ]]; then
  read -r -p "Type 'yes' to continue: " answer
  if [[ "$answer" != "yes" ]]; then
    log "aborted"
    exit 1
  fi
fi

# --- stop running processes --------------------------------------------------

quit_app() {
  if command -v osascript >/dev/null 2>&1; then
    osascript -e 'tell application "Allnighter" to quit' >/dev/null 2>&1 || true
  fi
  if pgrep -xq Allnighter 2>/dev/null; then
    pkill -x Allnighter 2>/dev/null || true
  fi
}

quit_app

# Leave Documents/Desktop/Downloads before any `alln` exec. Same belt as
# rebuild_cli.sh / get-alln.sh. ProtectedCWDEscape cannot avoid the first
# getcwd; a Documents checkout cwd is the ambient case for this script.
PROBE_SCRATCH="$HOME_DIR/Library/Application Support/Allnighter/ProbeScratch"
if mkdir -p "$PROBE_SCRATCH" 2>/dev/null; then
  cd "$PROBE_SCRATCH" || cd "$HOME_DIR"
else
  cd "$HOME_DIR"
fi

# Prefer the product command when available.
if command -v alln >/dev/null 2>&1; then
  alln serve disable >/dev/null 2>&1 || true
fi

UID_NUM="$(id -u)"
DOMAIN="gui/${UID_NUM}"
if launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
  launchctl bootout "$DOMAIN" "$HOME_DIR/Library/LaunchAgents/${LABEL}.plist" 2>/dev/null \
    || launchctl bootout "$DOMAIN/${LABEL}" 2>/dev/null \
    || true
fi

# Stop stray serve / worker processes owned by this product.
if pgrep -f '[/]alln serve' >/dev/null 2>&1; then
  pkill -f '[/]alln serve' 2>/dev/null || true
fi

sleep 0.5
quit_app

# --- remove ------------------------------------------------------------------

remove_item() {
  local item="$1"
  if [[ -e "$item" || -L "$item" ]]; then
    rm -rf "$item"
    log "removed $item"
  fi
}

for item in ${PLAN[@]+"${PLAN[@]}"}; do
  remove_item "$item"
done

for link in ${ALLN_SYMLINKS[@]+"${ALLN_SYMLINKS[@]}"}; do
  remove_item "$link"
done

if [[ "$RESET_TCC" -eq 1 ]]; then
  if command -v tccutil >/dev/null 2>&1; then
    if tccutil reset All "$BUNDLE_ID" 2>/dev/null; then
      log "reset TCC for $BUNDLE_ID"
    else
      warn "tccutil reset failed (may need Full Disk Access)"
    fi
  else
    warn "tccutil not found — skip TCC reset"
  fi
fi

log "done"
echo
echo "Re-install options:"
echo "  App:  curl -fsSL https://get.allnighter.io | sh   (CLI) + install Allnighter.dmg from get.allnighter.io"
echo "  Dev:  allapp   (from the repo checkout)"
echo "  CLI:  scripts/rebuild_cli.sh   or   curl -fsSL https://get.allnighter.io | sh"
