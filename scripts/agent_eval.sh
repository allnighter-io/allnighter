#!/usr/bin/env bash
# Cold-agent evaluation harness.
#
# Primary suite (MR-S06): pinned-binary *mechanical* menu-not-router matrix.
# This is not a live frontier-LLM dogfood. It drives `alln` the way a cold
# agent must after reading `menu --json`: one discovery → exact ids → dry-run.
#
# Usage:
#   scripts/agent_eval.sh --suite menu-not-router --binary "$B"
#   scripts/agent_eval.sh --suite menu-not-router          # builds release alln first
#   scripts/agent_eval.sh                                  # defaults to menu-not-router
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SUITE="menu-not-router"
BINARY=""
ALLOW_STALE_GITSHA=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite)
      SUITE="${2:?}"
      shift 2
      ;;
    --binary)
      BINARY="${2:?}"
      shift 2
      ;;
    --allow-stale-gitsha)
      ALLOW_STALE_GITSHA=1
      shift
      ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "agent_eval: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

OUT_DIR="${ALLN_EVAL_OUT:-$ROOT/.build/agent-eval}"
mkdir -p "$OUT_DIR"

case "$SUITE" in
  menu-not-router)
    echo "== MR-S06 menu-not-router (mechanical pinned-binary matrix) =="
    if [[ -z "$BINARY" ]]; then
      echo "building release alln…"
      swift build -c release --package-path Packages/AllnighterCore --product alln
      BINARY="$ROOT/Packages/AllnighterCore/.build/release/alln"
    fi
    test -x "$BINARY"
    EXTRA=()
    if [[ "$ALLOW_STALE_GITSHA" == "1" ]] || [[ "${ALLN_EVAL_ALLOW_STALE_GITSHA:-}" == "1" ]]; then
      EXTRA+=(--allow-stale-gitsha)
    fi
    /usr/bin/python3 "$ROOT/scripts/menu_not_router_eval.py" \
      --binary "$BINARY" \
      --out-dir "$OUT_DIR/menu-not-router" \
      ${EXTRA[@]+"${EXTRA[@]}"}
    # Convenience pins at suite root (AE-S09 attribution habit).
    cp "$OUT_DIR/menu-not-router/pinned-binary.sha256" "$OUT_DIR/pinned-binary.sha256"
    cp "$OUT_DIR/menu-not-router/version.json" "$OUT_DIR/version.json"
    cp "$OUT_DIR/menu-not-router/workspace-HEAD.txt" "$OUT_DIR/workspace-HEAD.txt"
    cp "$OUT_DIR/menu-not-router/transcript.txt" "$OUT_DIR/transcript.txt"
    echo "transcript: $OUT_DIR/transcript.txt"
    ;;
  *)
    echo "agent_eval: unknown suite '$SUITE' (known: menu-not-router)" >&2
    exit 2
    ;;
esac
