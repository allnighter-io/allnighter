#!/usr/bin/env bash
# Allnighter green wall — extend as Swift targets land.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ran_any=false

# Launch Authority TCC hotfix (H4/H6): the dev build/launch output must stay
# OUTSIDE the repo. The checkout lives under ~/Documents and macOS attributes a
# child's TCC prompts to the .app's location, so building/launching from the
# repo re-opens the launch-permission code red. Guard against a regression that
# points DERIVED back inside the repo (e.g. $ROOT/.build).
echo "==> assert dev.sh build path is TCC-safe"
if grep -E '^DERIVED=' "$ROOT/scripts/dev.sh" | grep -qE '\$ROOT|\.build/'; then
  echo "check: scripts/dev.sh DERIVED points inside the repo — dev launch would" >&2
  echo "       run from ~/Documents and trigger TCC prompts. Keep it under" >&2
  echo "       ~/Library (see docs/archive/phases/Launch_Authority_TCC_Hotfix.md, slice H4)." >&2
  exit 1
fi
ran_any=true

# GUI Visual Proof Gate (S05): a visible SwiftUI surface cannot land without a
# proof packet or an explicit waiver. Cheap (git + grep) so it runs first and
# fails fast. See docs/phases/GUI_Visual_Proof_Gate.md.
echo "==> check GUI visual proof gate"
bash "$ROOT/scripts/check_gui_proof.sh"
ran_any=true

echo "==> check SwiftUI Observation state rules"
bash "$ROOT/scripts/check_swiftui_state.sh"
ran_any=true

# ThreadStore hardening (TSH-S06): app runtime must use explicit mutation APIs,
# not fixture/import saves. See docs/archive/phases/05_ThreadStore_Hardening.md.
echo "==> check ThreadStore caller allowlist"
if rg -n '\.saveForImport\(' "$ROOT/Apps" --glob '*.swift' 2>/dev/null; then
  echo "check: Apps/ must not call ThreadStore.saveForImport (fixture/test gate only)" >&2
  exit 1
fi
if rg -n 'testPersistCursor' "$ROOT/Apps" --glob '*.swift' 2>/dev/null; then
  echo "check: Apps/ must not call ThreadStore test-only cursor hooks" >&2
  exit 1
fi
ran_any=true

bash "$ROOT/scripts/check_spawn_policy.sh"
ran_any=true

# ASF-S06: embed git SHA + build timestamp before compiling the CLI / running tests.
echo "==> generate BuildInfo (gitSha / buildTime)"
bash "$ROOT/scripts/generate_build_info.sh"
ran_any=true

# ASF-S08: living-doc deny-list — instructional retired grammar must not reappear
# in agent-facing living docs. Patterns are the SSOT in RetiredVocabulary.swift
# (livingDocDenyPatterns). Excludes docs/archive/ and docs/operations/debugger/
# (historical bug packets, not teaching surface).
echo "==> check retired vocabulary in living docs (ASF-S08)"
VOCAB_SWIFT="$ROOT/Packages/AllnighterCore/Sources/AllnighterCore/RetiredVocabulary.swift"
if [[ ! -f "$VOCAB_SWIFT" ]]; then
  echo "check: missing RetiredVocabulary.swift" >&2
  exit 1
fi
# Extract quoted string literals between the BEGIN/END markers (portable; no gawk/mapfile).
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
      # Top-level operations playbooks only (debugger/ packets are historical).
      rg -n -F -- "$pattern" "$ROOT"/docs/operations/*.md 2>/dev/null || true
      rg -n -F -- "$pattern" \
        "$ROOT/docs/phases/CLI_Product_Spine.md" \
        "$ROOT/docs/phases/CLI_Implementation_Contract.md" 2>/dev/null || true
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
ran_any=true

if [[ -f "$ROOT/Packages/AllnighterCore/Package.swift" ]]; then
  echo "==> swift test AllnighterCore"
  swift test --package-path "$ROOT/Packages/AllnighterCore"
  ran_any=true

  # ASF-S08: contract drift gate (same check StandingInvariants runs opportunistically).
  echo "==> alln dev export-contracts --check"
  ALLN_BIN=""
  if [[ -x "$ROOT/Packages/AllnighterCore/.build/debug/alln" ]]; then
    ALLN_BIN="$ROOT/Packages/AllnighterCore/.build/debug/alln"
  elif [[ -x "$ROOT/Packages/AllnighterCore/.build/release/alln" ]]; then
    ALLN_BIN="$ROOT/Packages/AllnighterCore/.build/release/alln"
  elif command -v alln >/dev/null 2>&1; then
    ALLN_BIN="$(command -v alln)"
  fi
  if [[ -n "$ALLN_BIN" ]]; then
    ( cd "$ROOT" && "$ALLN_BIN" dev export-contracts --check )
  else
    echo "check: no alln binary found after swift test; building product alln for export-contracts --check"
    swift build --package-path "$ROOT/Packages/AllnighterCore" --product alln
    ( cd "$ROOT" && "$ROOT/Packages/AllnighterCore/.build/debug/alln" dev export-contracts --check )
  fi
  ran_any=true
fi

# Mac app (XcodeGen-generated project; regenerate so .xcodeproj need not be committed).
MAC_APP="$ROOT/Apps/AllnighterMac"
if [[ -f "$MAC_APP/project.yml" ]] && command -v xcodegen >/dev/null 2>&1; then
  echo "==> xcodegen generate (AllnighterMac)"
  ( cd "$MAC_APP" && xcodegen generate >/dev/null )
  echo "==> xcodebuild test AllnighterMac"
  xcodebuild test \
    -project "$MAC_APP/AllnighterMac.xcodeproj" \
    -scheme AllnighterMac \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO | tail -3
  ran_any=true
elif [[ -f "$MAC_APP/project.yml" ]]; then
  echo "check: xcodegen not installed; skipping Mac app (run: brew install xcodegen)"
fi

if [[ "$ran_any" == false ]]; then
  echo "check: no Swift targets yet (docs-only bootstrap OK)"
fi
