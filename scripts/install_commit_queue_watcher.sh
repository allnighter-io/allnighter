#!/usr/bin/env bash
# =============================================================================
# Allnighter — Codex commit handoff processor (Cursor hooks + optional LaunchAgent)
# =============================================================================
#
# COPY-PASTE — install (run from repo root)
# -----------------------------------------------------------------------------
#   cd /path/to/Allnighter
#   bash scripts/install_commit_queue_watcher.sh
#
#   # Verify Cursor hooks (requires Cursor restart if hooks were new)
#   cat .cursor/hooks.json
#
#   # Optional: verify LaunchAgent (only when repo is outside protected folders
#   # or Full Disk Access is granted to /usr/bin/python3)
#   tail -20 .wmd/commit-queue-watcher.log
#   python3 scripts/commit_handoff_queue.py status
# -----------------------------------------------------------------------------
#
# PREREQUISITE (Codex agents)
#   bash scripts/install_codex_workspace_permissions.sh
#   Requires codex-cli >= 0.138.0. Fully quit Codex and start a new thread after.
#
# WHAT THIS DOES
#   0. (if present) Ensures the Codex workspace-git permission profile is merged
#      into ~/.codex/config.toml (strips legacy sandbox_mode / sandbox_workspace_write
#      that would block .git writes needed for handoff).
#   1. Installs Cursor hooks that start a repo-local poll watcher on sessionStart
#      (and drain once on stop). The watcher polls .wmd/commit-queue.jsonl every
#      2s so Codex --wait closeouts complete while Cursor is open.
#   2. Optionally installs a LaunchAgent watcher for headless waits when the repo
#      is outside macOS protected folders or Full Disk Access is granted.
#
# MANUAL FALLBACK
#   python3 scripts/commit_handoff_queue.py process-next
#
# UNINSTALL LaunchAgent
#   launchctl bootout gui/$(id -u)/com.allnighter.commit-queue-watcher
#   rm ~/Library/LaunchAgents/com.allnighter.commit-queue-watcher.plist
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.cursor/hooks"
HOOKS_JSON="$REPO_ROOT/.cursor/hooks.json"
HOOK_SRC="$REPO_ROOT/scripts/commit-handoff-hooks/process-pending.sh"
HOOK_DEST="$HOOKS_DIR/process-commit-handoff.sh"
HOOK_TEMPLATE="$REPO_ROOT/scripts/commit-handoff-hooks/cursor.hooks.json"
PLIST_DEST="$HOME/Library/LaunchAgents/com.allnighter.commit-queue-watcher.plist"
LABEL="com.allnighter.commit-queue-watcher"
LOG_DIR="$REPO_ROOT/.wmd"
LOG_PATH="$LOG_DIR/commit-queue-watcher.log"
WATCHER="$REPO_ROOT/scripts/commit_queue_watcher.py"
VENV_PYTHON="$REPO_ROOT/.venv/bin/python3"
SKIP_LAUNCHAGENT=false

for arg in "$@"; do
  case "$arg" in
    --skip-launchagent) SKIP_LAUNCHAGENT=true ;;
    -h|--help)
      sed -n '1,35p' "$0"
      exit 0
      ;;
    *)
      echo "error: unknown argument: $arg (try --skip-launchagent or --help)" >&2
      exit 2
      ;;
  esac
done

if [[ -x "$VENV_PYTHON" ]]; then
  PYTHON3="$VENV_PYTHON"
elif command -v python3 &>/dev/null; then
  PYTHON3="$(command -v python3)"
  echo "warning: ${VENV_PYTHON} not found; using ${PYTHON3}" >&2
else
  echo "error: python3 not found" >&2
  exit 1
fi

install_cursor_hooks() {
  mkdir -p "$HOOKS_DIR"
  install -m 755 "$HOOK_SRC" "$HOOK_DEST"
  if [[ -f "$REPO_ROOT/.cursor/hooks/process-commit-queue.sh" ]]; then
    chmod 755 "$REPO_ROOT/.cursor/hooks/process-commit-queue.sh"
  fi

  "$PYTHON3" - <<'PY' "$HOOKS_JSON" "$HOOK_TEMPLATE"
import json
import sys
from pathlib import Path

hooks_json = Path(sys.argv[1])
template_path = Path(sys.argv[2])
fragment = json.loads(template_path.read_text(encoding="utf-8"))

if hooks_json.exists():
    current = json.loads(hooks_json.read_text(encoding="utf-8"))
else:
    current = {"version": 1, "hooks": {}}

current.setdefault("version", 1)
current.setdefault("hooks", {})
for event, entries in fragment.get("hooks", {}).items():
    existing = current["hooks"].setdefault(event, [])
    commands = {entry.get("command") for entry in existing if isinstance(entry, dict)}
    for entry in entries:
        command = entry.get("command")
        if command not in commands:
            existing.append(entry)

hooks_json.parent.mkdir(parents=True, exist_ok=True)
hooks_json.write_text(json.dumps(current, indent=2) + "\n", encoding="utf-8")
PY

  echo "ok: installed Cursor commit handoff hooks"
  echo "  $HOOKS_JSON"
  echo "  $HOOK_DEST"
  echo "  Restart Cursor if hooks do not load immediately."
}

launchagent_usable() {
  local test_label="com.allnighter.commit-queue-selftest"
  local test_log="$LOG_DIR/commit-queue-selftest.log"
  local test_plist="/tmp/${test_label}.plist"

  mkdir -p "$LOG_DIR"
  : >"$test_log"

  cat >"$test_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${test_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${PYTHON3}</string>
    <string>${REPO_ROOT}/scripts/commit_handoff_queue.py</string>
    <string>status</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${REPO_ROOT}</string>
  <key>StandardOutPath</key>
  <string>${test_log}</string>
  <key>StandardErrorPath</key>
  <string>${test_log}</string>
</dict>
</plist>
PLIST

  launchctl bootout "gui/$(id -u)/$test_label" 2>/dev/null || true
  if ! launchctl bootstrap "gui/$(id -u)" "$test_plist" 2>/dev/null; then
    launchctl load "$test_plist" 2>/dev/null || true
  fi
  launchctl kickstart -k "gui/$(id -u)/$test_label" 2>/dev/null || true
  sleep 2
  launchctl bootout "gui/$(id -u)/$test_label" 2>/dev/null || true
  rm -f "$test_plist"

  if rg -q "Operation not permitted" "$test_log" 2>/dev/null; then
    return 1
  fi
  if ! rg -q '"status"' "$test_log" 2>/dev/null; then
    return 1
  fi
  return 0
}

install_launchagent() {
  if [[ ! -f "$WATCHER" ]]; then
    echo "error: watcher script missing: $WATCHER" >&2
    exit 1
  fi

  mkdir -p "$LOG_DIR"
  mkdir -p "$HOME/Library/LaunchAgents"

  if launchctl list "$LABEL" &>/dev/null 2>&1; then
    echo "Unloading existing $LABEL..."
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload "$PLIST_DEST" 2>/dev/null || true
  fi

  cat > "$PLIST_DEST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${PYTHON3}</string>
    <string>${WATCHER}</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key>
    <string>${HOME}</string>
  </dict>

  <key>WorkingDirectory</key>
  <string>${REPO_ROOT}</string>

  <key>StandardOutPath</key>
  <string>${LOG_PATH}</string>
  <key>StandardErrorPath</key>
  <string>${LOG_PATH}</string>

  <key>KeepAlive</key>
  <true/>

  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
PLIST

  launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST" 2>/dev/null || launchctl load "$PLIST_DEST"
  launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null || true

  echo ""
  echo "Installed LaunchAgent: $LABEL"
  echo "  Repo:     $REPO_ROOT"
  echo "  Python:   $PYTHON3"
  echo "  Log:      $LOG_PATH"
}

if [[ -f "$REPO_ROOT/scripts/install_codex_workspace_permissions.sh" ]]; then
  echo "==> Codex workspace permissions (workspace-git profile)"
  bash "$REPO_ROOT/scripts/install_codex_workspace_permissions.sh" || {
    echo "warning: Codex permissions install failed; commit handoff may not work in Codex threads" >&2
  }
  echo ""
fi

install_cursor_hooks

if [[ "$SKIP_LAUNCHAGENT" == true ]]; then
  echo ""
  echo "Skipped LaunchAgent (--skip-launchagent)."
  exit 0
fi

if launchagent_usable; then
  install_launchagent
else
  cat >&2 <<EOF

warning: LaunchAgent self-test failed for this repo path.
macOS often blocks background jobs from reading repos under ~/Documents unless
Full Disk Access is granted to ${PYTHON3}.

Cursor hooks were installed and will process pending handoffs while Cursor is
open (sessionStart + stop). For headless Codex waits, either:
  1. Grant Full Disk Access to ${PYTHON3}, then rerun:
       bash scripts/install_commit_queue_watcher.sh
  2. Move the clone outside ~/Documents, then rerun the installer
  3. Run manually when Codex is waiting:
       python3 scripts/commit_handoff_queue.py process-next

EOF
fi
