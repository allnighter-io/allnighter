#!/usr/bin/env bash
# Cheap hygiene gates only — no compile suites, no package/app test runners,
# and no code_red_works_test. See docs/archive/phases/Test_Infrastructure_Upgrade.md (TIU-S01).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=ensure-test-guard-path.sh disable=SC1091
source "$ROOT/scripts/ensure-test-guard-path.sh"

echo "==> check-fast: test guard liveness"
bash "$ROOT/scripts/check-test-guard-liveness.sh"

echo "==> check AGENTS.md size budget"
# AGENTS.md is loaded into EVERY agent session via CLAUDE.md's @AGENTS.md.
# Every byte is a per-session tax on every agent, forever. It is a ROUTER:
# add paths, not prose, and remove a route when its packet is archived.
# Raising this ceiling is not the fix for a failing build — pruning is.
AGENTS_MD="$ROOT/AGENTS.md"
AGENTS_BUDGET_BYTES=18500
if [[ ! -f "$AGENTS_MD" ]]; then
  echo "check: missing AGENTS.md" >&2
  exit 1
fi
agents_bytes=$(wc -c < "$AGENTS_MD" | tr -d ' ')
if (( agents_bytes > AGENTS_BUDGET_BYTES )); then
  echo "check: AGENTS.md is ${agents_bytes} bytes, over the ${AGENTS_BUDGET_BYTES} budget." >&2
  echo "  It is a router loaded into every session. Prune before adding:" >&2
  echo "  - routes to archived packets belong in docs/archive/phases/README.md" >&2
  echo "  - ops detail belongs in docs/operations/Execution-Playbook.md" >&2
  echo "  - a law already enforced by code belongs in the code, not here" >&2
  echo "  Raising AGENTS_BUDGET_BYTES is a founder decision, not a build fix." >&2
  exit 1
fi
echo "    AGENTS.md ${agents_bytes}/${AGENTS_BUDGET_BYTES} bytes"

echo "==> check Code Red architecture policy"
bash "$ROOT/scripts/check_architecture_policy.sh"

echo "==> check Code Red architecture policy (negative self-test)"
bash "$ROOT/scripts/check_architecture_policy.sh" --self-test

echo "==> assert dev.sh build path is TCC-safe"
if grep -E '^DERIVED=' "$ROOT/scripts/dev.sh" | grep -qE '\$ROOT|\.build/'; then
  echo "check: scripts/dev.sh DERIVED points inside the repo — dev launch would" >&2
  echo "       run from ~/Documents and trigger TCC prompts. Keep it under" >&2
  echo "       ~/Library (see docs/archive/phases/Launch_Authority_TCC_Hotfix.md, slice H4)." >&2
  exit 1
fi
if [[ ! -f "$ROOT/scripts/rebuild_cli.sh" ]] \
  || ! grep -q 'ALLNIGHTER_CLI_SCRATCH:-\$HOME/Library/Developer/Allnighter/CLI' "$ROOT/scripts/rebuild_cli.sh"; then
  echo "check: rebuild_cli.sh must build alln outside the protected checkout" >&2
  exit 1
fi
if [[ ! -f "$ROOT/scripts/build-universal.sh" ]] \
  || ! grep -q 'ALLN_UNIVERSAL_SCRATCH:-\$HOME/Library/Developer/Allnighter/CLI-universal' "$ROOT/scripts/build-universal.sh"; then
  echo "check: build-universal.sh must scratch outside the Documents checkout" >&2
  echo "       (SPM Bundle.module bakes the scratch path; a repo scratch is a TCC prompt)." >&2
  exit 1
fi

echo "==> assert installed alln CLI on PATH is functional (auto-relinking if stale)"
if ! command -v alln >/dev/null 2>&1 || ! alln menu --json >/dev/null 2>&1; then
  echo "check: alln on PATH is missing or stale — auto-healing via scripts/rebuild_cli.sh..." >&2
  bash "$ROOT/scripts/rebuild_cli.sh"
fi

echo "==> check GUI visual proof gate"
bash "$ROOT/scripts/check_gui_proof.sh"

echo "==> check SwiftUI Observation state rules"
bash "$ROOT/scripts/check_swiftui_state.sh"

echo "==> check ThreadStore caller allowlist"
if rg -n '\.saveForImport\(' "$ROOT/Apps" --glob '*.swift' 2>/dev/null; then
  echo "check: Apps/ must not call ThreadStore.saveForImport (fixture/test gate only)" >&2
  exit 1
fi
if rg -n 'testPersistCursor' "$ROOT/Apps" --glob '*.swift' 2>/dev/null; then
  echo "check: Apps/ must not call ThreadStore test-only cursor hooks" >&2
  exit 1
fi

bash "$ROOT/scripts/check_spawn_policy.sh"

echo "==> check retired vocabulary in living docs (ASF-S08)"
VOCAB_SWIFT="$ROOT/Packages/AllnighterCore/Sources/AllnighterCore/RetiredVocabulary.swift"
if [[ ! -f "$VOCAB_SWIFT" ]]; then
  echo "check: missing RetiredVocabulary.swift" >&2
  exit 1
fi
LIVING_DOC_DENY=$(
  sed -n '/BEGIN livingDocDenyPatterns/,/END livingDocDenyPatterns/p' "$VOCAB_SWIFT" \
    | grep -o '"[^"]*"' \
    | tr -d '"'
)
if [[ -z "$LIVING_DOC_DENY" ]]; then
  echo "check: failed to extract livingDocDenyPatterns from RetiredVocabulary.swift" >&2
  exit 1
fi
living_doc_fail=0
while IFS= read -r pattern; do
  [[ -z "$pattern" ]] && continue
  hits=$(
    {
      rg -n -F -- "$pattern" "$ROOT"/docs/operations/*.md 2>/dev/null || true
      rg -n -F -- "$pattern" \
        "$ROOT/docs/phases/CLI_Product_Spine.md" \
        "$ROOT/docs/archive/phases/CLI_Implementation_Contract.md" 2>/dev/null || true
      rg -n -F -- "$pattern" "$ROOT/AGENTS.md" 2>/dev/null || true
      rg -n -F -- "$pattern" "$ROOT"/docs/workflows/*.md 2>/dev/null || true
      rg -n -F -- "$pattern" "$ROOT"/docs/phases/*.md 2>/dev/null || true
      rg -n -F -- "$pattern" \
        "$ROOT"/Packages/AllnighterCore/Sources/AllnighterCore/Resources/Recipes/*.md 2>/dev/null || true
    } || true
  )
  if [[ -n "$hits" ]]; then
    echo "check: retired instructional pattern found in living docs: '$pattern'" >&2
    echo "$hits" >&2
    living_doc_fail=1
  fi
done <<< "$LIVING_DOC_DENY"
if [[ "$living_doc_fail" -ne 0 ]]; then
  echo "check: ASF-S08 living-doc deny-list failed (see RetiredVocabulary.livingDocDenyPatterns)" >&2
  exit 1
fi

echo "==> check public floor docs match version identity"
bash "$ROOT/scripts/public-floor.sh" check

echo "==> check-fast: OK"
