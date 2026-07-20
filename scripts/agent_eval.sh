#!/usr/bin/env bash
# Cold-agent evaluation harness.
#
# Suites:
#   menu-not-router (MR-S06) — pinned-binary mechanical menu-not-router matrix.
#   sharpening (SH-S09) — diversified quota-free pass/fail gate (no score — D5).
#
# Neither suite is a live frontier-LLM dogfood. Sharpening uses fixture drivers
# and isolated ALLNIGHTER_SUPPORT_DIR so no paid provider starts.
#
# Usage:
#   scripts/agent_eval.sh --suite menu-not-router --binary "$B"
#   scripts/agent_eval.sh --suite sharpening --binary "$B"
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
      sed -n '2,24p' "$0"
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

ensure_binary() {
  if [[ -z "$BINARY" ]]; then
    echo "building release alln…"
    swift build -c release --package-path Packages/AllnighterCore --product alln
    BINARY="$ROOT/Packages/AllnighterCore/.build/release/alln"
  fi
  test -x "$BINARY"
}

extra_flags() {
  EXTRA=()
  if [[ "$ALLOW_STALE_GITSHA" == "1" ]] || [[ "${ALLN_EVAL_ALLOW_STALE_GITSHA:-}" == "1" ]]; then
    EXTRA+=(--allow-stale-gitsha)
  fi
}

pin_suite_root() {
  local suite_dir="$1"
  cp "$suite_dir/pinned-binary.sha256" "$OUT_DIR/pinned-binary.sha256"
  cp "$suite_dir/version.json" "$OUT_DIR/version.json"
  cp "$suite_dir/workspace-HEAD.txt" "$OUT_DIR/workspace-HEAD.txt"
  cp "$suite_dir/transcript.txt" "$OUT_DIR/transcript.txt"
  echo "transcript: $OUT_DIR/transcript.txt"
}

case "$SUITE" in
  menu-not-router)
    echo "== MR-S06 menu-not-router (mechanical pinned-binary matrix) =="
    ensure_binary
    extra_flags
    /usr/bin/python3 "$ROOT/scripts/menu_not_router_eval.py" \
      --binary "$BINARY" \
      --out-dir "$OUT_DIR/menu-not-router" \
      ${EXTRA[@]+"${EXTRA[@]}"}
    pin_suite_root "$OUT_DIR/menu-not-router"
    ;;
  sharpening)
    echo "== SH-S09 sharpening (quota-free pass/fail gate, no score) =="
    ensure_binary
    extra_flags
    /usr/bin/python3 "$ROOT/scripts/sharpening_eval.py" \
      --binary "$BINARY" \
      --out-dir "$OUT_DIR/sharpening" \
      ${EXTRA[@]+"${EXTRA[@]}"}
    pin_suite_root "$OUT_DIR/sharpening"
    ;;
  *)
    echo "agent_eval: unknown suite '$SUITE' (known: menu-not-router, sharpening)" >&2
    exit 2
    ;;
esac
