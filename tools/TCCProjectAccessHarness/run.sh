#!/usr/bin/env bash
# Disposable launchd TCC harness. Run only from a normal macOS terminal.
# It never invokes a vendor CLI. It creates/removes only its own label and files.
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE=""
PROJECT=""
HARNESS_ROOT="${ALLN_TCC_HARNESS_ROOT:-$HOME/Library/Developer/Allnighter/TCCProjectAccessHarness}"
LABEL="com.allnighter.tcc-project-access-harness"

usage() {
  cat <<'USAGE'
Usage:
  bash tools/TCCProjectAccessHarness/run.sh --mode scratch
  bash tools/TCCProjectAccessHarness/run.sh --mode project --project /absolute/path/to/repo
  bash tools/TCCProjectAccessHarness/run.sh --mode snapshot --project /absolute/path/to/repo

Modes:
  scratch   launchd helper touches only Allnighter-owned Library scratch.
  project   launchd helper enumerates the supplied project root once.
  snapshot  this normal-terminal script creates a tracked-only snapshot with all
            .env* entries removed under Library, then the launchd helper touches it.

The script creates and removes only com.allnighter.tcc-project-access-harness.
It does not call tccutil, modify a project, or invoke a vendor CLI.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$MODE" in
  scratch) ;;
  project|snapshot)
    [[ -n "$PROJECT" && "$PROJECT" = /* && -d "$PROJECT" ]] || {
      echo "--project must be an existing absolute directory" >&2; exit 2;
    }
    ;;
  *) echo "--mode must be scratch, project, or snapshot" >&2; usage >&2; exit 2 ;;
esac

mkdir -p "$HARNESS_ROOT/bin" "$HARNESS_ROOT/logs" "$HARNESS_ROOT/snapshots" "$HARNESS_ROOT/owned-scratch"
printf 'owned scratch only\n' > "$HARNESS_ROOT/owned-scratch/probe.txt"

MODULE_CACHE="${ALLN_TCC_HARNESS_MODULE_CACHE:-/private/tmp/alln-tcc-project-access-module-cache}"
mkdir -p "$MODULE_CACHE"
HELPER="$HARNESS_ROOT/bin/tcc-project-access-helper"
xcrun swiftc -parse-as-library -module-cache-path "$MODULE_CACHE" "$SOURCE_DIR/main.swift" -o "$HELPER"

TARGET="$HARNESS_ROOT/owned-scratch"
if [[ "$MODE" == "project" ]]; then
  TARGET="$PROJECT"
elif [[ "$MODE" == "snapshot" ]]; then
  SNAPSHOT="$HARNESS_ROOT/snapshots/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$SNAPSHOT"
  # `git archive HEAD` supplies tracked bytes only. The explicit dotenv sweep
  # preserves the Panel snapshot policy even for a mistakenly tracked example.
  git -C "$PROJECT" archive --format=tar HEAD | tar -xf - -C "$SNAPSHOT"
  /usr/bin/find "$SNAPSHOT" -depth -name '.env*' -exec /bin/rm -rf {} +
  TARGET="$SNAPSHOT"
fi

STAMP="$(date +%Y%m%d-%H%M%S)-$$"
RECEIPT="$HARNESS_ROOT/logs/$STAMP.receipt.json"
STDOUT="$HARNESS_ROOT/logs/$STAMP.stdout.log"
STDERR="$HARNESS_ROOT/logs/$STAMP.stderr.log"
PLIST="$HARNESS_ROOT/$LABEL.plist"
USER_ID="$(id -u)"

cleanup() {
  launchctl bootout "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || true
  /bin/rm -f "$PLIST"
}
trap cleanup EXIT

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$HELPER</string>
    <string>$MODE</string>
    <string>$TARGET</string>
    <string>$RECEIPT</string>
  </array>
  <key>WorkingDirectory</key><string>$HARNESS_ROOT/owned-scratch</string>
  <key>StandardOutPath</key><string>$STDOUT</string>
  <key>StandardErrorPath</key><string>$STDERR</string>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST

launchctl bootout "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$USER_ID" "$PLIST"

for _ in {1..100}; do
  [[ -f "$RECEIPT" ]] && break
  sleep 0.1
done

if [[ ! -f "$RECEIPT" ]]; then
  echo "harness did not write a receipt; inspect $STDERR" >&2
  exit 1
fi

echo "receipt: $RECEIPT"
cat "$RECEIPT"
echo
echo "stdout: $STDOUT"
echo "stderr: $STDERR"
