#!/bin/bash
# Runs after every Cursor agent stop event.
# Processes the oldest pending item in .wmd/commit-queue.jsonl, if any.
# Exits 0 always (fail-open) so a queue error never blocks Cursor.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/commit_handoff_queue.py"

if [ ! -f "$SCRIPT" ]; then
  exit 0
fi

OUTPUT=$(python3 "$SCRIPT" process-next 2>&1)
RC=$?

# Suppress the idle message; surface everything else to the Hooks output channel
if [ "$OUTPUT" != "no pending commit handoff" ]; then
  printf '[commit-handoff] %s\n' "$OUTPUT" >&2
fi

exit 0
