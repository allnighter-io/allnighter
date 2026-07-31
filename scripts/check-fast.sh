#!/usr/bin/env bash
# Cheap hygiene gates only — no compile suites, no package/app test runners,
# and no code_red_works_test. See docs/archive/phases/Test_Infrastructure_Upgrade.md (TIU-S01).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> check-fast: test guard liveness"
if ! bash "$ROOT/scripts/check-test-guard-liveness.sh"; then
  # Loud warning is required; do not silently pass. Hygiene still continues so
  # agents can fix other gates before install-test-guard lands in their shell.
  echo "check-fast: continuing after guard warning (install-test-guard.sh)" >&2
fi

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

echo "==> check-fast: OK"
