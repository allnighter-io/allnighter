#!/usr/bin/env bash
# Throwaway pair-programming hammer — Composer plans (packets), Gemini executes.
# Copies a sandbox template to /tmp, registers it as a project, runs the queue.
# Safe: never touches the Allnighter repo working tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$ROOT/docs/phases/sprint/pair/hammer/sandbox-template"
QUEUE="$ROOT/docs/phases/sprint/pair/hammer/queue"
SANDBOX="${PAIR_HAMMER_SANDBOX:-/tmp/alln-pair-hammer-$$}"

cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"
cp -R "$TEMPLATE/." "$SANDBOX/"
git -C "$SANDBOX" init -q
git -C "$SANDBOX" add hello.txt
git -C "$SANDBOX" -c user.email=hammer@test -c user.name=hammer commit -q -m "seed"

echo "sandbox: $SANDBOX"
PROJECT_JSON="$(swift run --package-path "$ROOT/Packages/AllnighterCore" alln project add "$SANDBOX" --name "pair-hammer" --json)"
PROJECT_ID="$(printf '%s' "$PROJECT_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["project"]["id"])')"
echo "project: $PROJECT_ID"

CMD=(
  swift run --package-path "$ROOT/Packages/AllnighterCore" alln pair run
  --queue "$QUEUE"
  --project "$PROJECT_ID"
  --executor default_chat
  --planner-worker model_cursor_composer_25
  --executor-worker model_gemini
  --max-retries 1
  --json
)
echo "running: ${CMD[*]}"
"${CMD[@]}"

if [[ "${PAIR_HAMMER_KEEP_SANDBOX:-}" == "1" ]]; then
  trap - EXIT
  echo "kept sandbox: $SANDBOX"
fi
